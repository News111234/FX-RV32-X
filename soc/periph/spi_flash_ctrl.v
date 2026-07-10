// soc/periph/spi_flash_ctrl.v — SPI Flash 专用读控制器
//
// 功能: 封装 S25FL256S SPI Flash 的读取协议，对外暴露类似存储器的读接口。
//   CPU 通过总线读地址 0x3000_XXXX → 控制器自动执行 SPI READ 命令 →
//   返回 32-bit 数据。
//
// SPI Flash READ 命令 (0x03):
//   CS低 → 发 0x03 → 发 24-bit 地址 → 读 4 字节 → CS高 → 拼接成 32-bit word
//
// SPI 参数 (Mode 0: CPOL=0, CPHA=0):
//   系统时钟 200MHz, SPI 时钟 10MHz → clk_div = 9
//   每次读: 8+24+32 = 64 bit × 20 周期/bit = 1280 周期 ≈ 6.4μs
//
// 地址映射:
//   总线地址 0x3000_0000 → Flash 内部地址 FLASH_BASE + 0x000
//   总线地址 0x3000_0004 → Flash 内部地址 FLASH_BASE + 0x004
// ============================================================================
`timescale 1ns/1ps

module spi_flash_ctrl #(
    parameter CLK_FREQ    = 200_000_000,
    parameter SPI_FREQ    = 10_000_000,        // SPI 时钟 10MHz
    parameter FLASH_BASE  = 24'h01_00_00       // Flash 内程序起始地址 (16MB 偏移)
) (
    // ===== 系统接口 =====
    input  wire        clk_i,
    input  wire        rst_n_i,

    // ===== 总线读接口 =====
    input  wire        re_i,                   // 读请求
    input  wire [23:0] addr_i,                 // 读地址 (word address, 最大 16MB)
    output reg  [31:0] rdata_o,                // 读数据
    output reg         ready_o,                // 数据就绪 (busy=0 时可用)

    // ===== SPI Flash 物理接口 =====
    output reg         flash_sclk_o,           // SPI 时钟
    output reg         flash_mosi_o,           // 主发从收 (SDI)
    input  wire        flash_miso_i,           // 主收从发 (SDO)
    output reg         flash_cs_o              // 片选 (低有效)
);

    // ========================================================================
    // SPI 时钟分频
    // f_spi = f_sys / (2 * (clk_div + 1))
    // 10MHz = 200MHz / (2 * 10) → clk_div = 9
    // ========================================================================
    localparam CLK_DIV = (CLK_FREQ / (2 * SPI_FREQ)) - 1;  // = 9
    localparam CLK_HALF = CLK_DIV;                           // 半周期计数值

    // ========================================================================
    // 状态机
    // ========================================================================
    localparam ST_IDLE   = 3'd0;    // 等待读请求
    localparam ST_CMD    = 3'd1;    // 发送 READ 命令 0x03
    localparam ST_ADDR2  = 3'd2;    // 发送地址[23:16]
    localparam ST_ADDR1  = 3'd3;    // 发送地址[15:8]
    localparam ST_ADDR0  = 3'd4;    // 发送地址[7:0]
    localparam ST_READ3  = 3'd5;    // 读数据 byte3 [31:24]
    localparam ST_READ2  = 3'd6;    // 读数据 byte2 [23:16]
    localparam ST_READ1  = 3'd7;    // 读数据 byte1 [15:8]
    localparam ST_READ0  = 3'd8;    // 读数据 byte0 [7:0]
    localparam ST_DONE   = 3'd9;    // 完成, 返回数据
    // 注: 3'd10-3'd15 为无效状态, case default 回到 IDLE

    reg [3:0]  state;
    reg [3:0]  next_state;

    // ========================================================================
    // SPI 位传输控制
    // ========================================================================
    reg [7:0]  clk_cnt;             // 半周期计数器 (0 ~ CLK_DIV)
    reg [3:0]  bit_cnt;             // 位计数器 (0 ~ 7)

    reg        sclk_en;             // SCLK 使能 (开始翻转)
    wire       sclk_tick;           // 半周期到达
    wire       sclk_rise;           // SCLK 上升沿 (采样 MISO)
    wire       sclk_fall;           // SCLK 下降沿 (更新 MOSI)

    assign sclk_tick = (clk_cnt == CLK_HALF);
    assign sclk_rise = sclk_en && sclk_tick && (flash_sclk_o == 1'b0);
    assign sclk_fall = sclk_en && sclk_tick && (flash_sclk_o == 1'b1);

    // ========================================================================
    // 数据寄存器
    // ========================================================================
    reg [23:0] flash_addr;          // Flash 内部地址 (BASE + bus_addr)
    reg [7:0]  shift_out;           // MOSI 移位寄存器
    reg [31:0] shift_in;            // MISO 接收移位寄存器
    reg        start_req;           // 读请求锁存

    // ========================================================================
    // 从总线地址计算 Flash 内部地址
    // addr_i 是相对于 Flash 窗口 (0x3000_0000) 的字节偏移
    // flash_byte_addr = FLASH_BASE + addr_i
    // ========================================================================
    wire [23:0] flash_byte_addr;
    assign flash_byte_addr = FLASH_BASE + addr_i;

    // ========================================================================
    // SCLK 生成
    // ========================================================================
    always @(posedge clk_i) begin
        if (!rst_n_i) begin
            clk_cnt <= 8'b0;
        end else if (sclk_en) begin
            if (sclk_tick)
                clk_cnt <= 8'b0;
            else
                clk_cnt <= clk_cnt + 1;
        end else begin
            clk_cnt <= 8'b0;
        end
    end

    // SCLK 输出 (Mode 0: 空闲=0, 数据在上升沿采样)
    always @(posedge clk_i) begin
        if (!rst_n_i) begin
            flash_sclk_o <= 1'b0;
        end else if (sclk_en && sclk_tick) begin
            flash_sclk_o <= ~flash_sclk_o;
        end else if (!sclk_en) begin
            flash_sclk_o <= 1'b0;   // 空闲低电平 (CPOL=0)
        end
    end

    // ========================================================================
    // 主状态机
    // ========================================================================
    always @(posedge clk_i) begin
        if (!rst_n_i) begin
            state        <= ST_IDLE;
            flash_cs_o   <= 1'b1;       // CS 高 (不选中)
            flash_mosi_o <= 1'b0;
            sclk_en      <= 1'b0;
            bit_cnt      <= 4'b0;
            shift_out    <= 8'b0;
            shift_in     <= 32'b0;
            flash_addr   <= 24'b0;
            start_req    <= 1'b0;
            rdata_o      <= 32'b0;
            ready_o      <= 1'b1;       // 空闲时 ready
        end else begin
            case (state)
                // ------------------------------------------------------------
                // IDLE: 等待总线读请求
                // ------------------------------------------------------------
                ST_IDLE: begin
                    flash_cs_o  <= 1'b1;
                    sclk_en     <= 1'b0;
                    bit_cnt     <= 4'b0;
                    ready_o     <= 1'b1;

                    if (re_i && !start_req) begin
                        start_req  <= 1'b1;
                        flash_addr <= flash_byte_addr;
                        ready_o    <= 1'b0;
                        state      <= ST_CMD;
                    end
                end

                // ------------------------------------------------------------
                // CMD: 发送 READ 命令 (0x03)
                // ------------------------------------------------------------
                ST_CMD: begin
                    flash_cs_o <= 1'b0;                 // CS 低
                    sclk_en    <= 1'b1;                 // 启动 SCLK
                    shift_out  <= 8'h03;                // READ command

                    if (sclk_rise) begin
                        if (bit_cnt == 4'd7) begin
                            bit_cnt   <= 4'b0;
                            shift_out <= flash_addr[23:16];
                            state     <= ST_ADDR2;
                        end else begin
                            bit_cnt <= bit_cnt + 1;
                            // 在下个下降沿更新 MOSI
                        end
                    end

                    if (sclk_fall && bit_cnt < 4'd7) begin
                        flash_mosi_o <= shift_out[7 - bit_cnt];
                    end
                end

                // ------------------------------------------------------------
                // ADDR2: 发送地址[23:16]
                // ------------------------------------------------------------
                ST_ADDR2: begin
                    if (sclk_rise) begin
                        if (bit_cnt == 4'd7) begin
                            bit_cnt   <= 4'b0;
                            shift_out <= flash_addr[15:8];
                            state     <= ST_ADDR1;
                        end else begin
                            bit_cnt <= bit_cnt + 1;
                        end
                    end

                    if (sclk_fall && bit_cnt < 4'd7) begin
                        flash_mosi_o <= shift_out[7 - bit_cnt];
                    end
                end

                // ------------------------------------------------------------
                // ADDR1: 发送地址[15:8]
                // ------------------------------------------------------------
                ST_ADDR1: begin
                    if (sclk_rise) begin
                        if (bit_cnt == 4'd7) begin
                            bit_cnt   <= 4'b0;
                            shift_out <= flash_addr[7:0];
                            state     <= ST_ADDR0;
                        end else begin
                            bit_cnt <= bit_cnt + 1;
                        end
                    end

                    if (sclk_fall && bit_cnt < 4'd7) begin
                        flash_mosi_o <= shift_out[7 - bit_cnt];
                    end
                end

                // ------------------------------------------------------------
                // ADDR0: 发送地址[7:0]
                // ------------------------------------------------------------
                ST_ADDR0: begin
                    if (sclk_rise) begin
                        // 采样 MISO (虽然 ADDR0 阶段 MISO 通常无效)
                        shift_in <= {shift_in[30:0], flash_miso_i};

                        if (bit_cnt == 4'd7) begin
                            bit_cnt <= 4'b0;
                            state   <= ST_READ3;
                        end else begin
                            bit_cnt <= bit_cnt + 1;
                        end
                    end

                    if (sclk_fall && bit_cnt < 4'd7) begin
                        flash_mosi_o <= shift_out[7 - bit_cnt];
                    end
                end

                // ------------------------------------------------------------
                // READ3-0: 接收 4 字节数据 (MSB first → byte3, byte2, byte1, byte0)
                // ------------------------------------------------------------
                ST_READ3, ST_READ2, ST_READ1, ST_READ0: begin
                    // MOSI 发 dummy (don't care)
                    flash_mosi_o <= 1'b0;

                    if (sclk_rise) begin
                        shift_in <= {shift_in[30:0], flash_miso_i};

                        if (bit_cnt == 4'd7) begin
                            bit_cnt <= 4'b0;
                            // 进入下一阶段
                            case (state)
                                ST_READ3: state <= ST_READ2;
                                ST_READ2: state <= ST_READ1;
                                ST_READ1: state <= ST_READ0;
                                ST_READ0: state <= ST_DONE;
                                default:  state <= ST_IDLE;
                            endcase
                        end else begin
                            bit_cnt <= bit_cnt + 1;
                        end
                    end
                end

                // ------------------------------------------------------------
                // DONE: 返回数据, 拉高 CS
                // ------------------------------------------------------------
                ST_DONE: begin
                    sclk_en    <= 1'b0;
                    flash_cs_o <= 1'b1;
                    start_req  <= 1'b0;
                    rdata_o    <= shift_in;   // 锁存最终数据
                    ready_o    <= 1'b1;
                    state      <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule
