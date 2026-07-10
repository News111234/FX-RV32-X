// soc/periph/spi_master.v — SPI 主控制器 (Master Only)
//
// 功能: 实现 SPI 总线的主机协议，支持:
//   - 4 种 SPI 模式 (CPOL/CPHA 可配置)
//   - 可配置时钟分频 (SPI 时钟 = 系统时钟 / (2 * (clk_divider+1)))
//   - 8 位 / 16 位数据传输
//   - MSB 优先 / LSB 优先可配置
//   - 中断支持 (发送完成 / 接收完成)
//
// ======================= SPI 协议概述 ======================================
// SPI 使用 4 根线: SCLK(时钟), MOSI(主发从收), MISO(主收从发), CS(片选,低有效)
//
// CPOL (Clock Polarity): 空闲时 SCLK 的电平, 0=低, 1=高
// CPHA (Clock Phase):    数据采样时机, 0=第一个边沿采样(前沿), 1=第二个边沿采样(后沿)
//
// 四种 SPI 模式: Mode0(0,0), Mode1(0,1), Mode2(1,0), Mode3(1,1)
// sample_edge: 该边沿读取 MISO 上的数据
// setup_edge:  该边沿更新 MOSI 上的数据
//
// ======================= 内部状态机 ========================================
//   SPI_IDLE  → SPI_START → SPI_TRANS → SPI_STOP → SPI_IDLE
//
// ======================= 寄存器映射 ========================================
//   0x00: CTRL     控制寄存器 (enable, irq_en, cpol, cpha, lsb_first, data_16bit, start_tx)
//   0x04: CLK_DIV  时钟分频寄存器 (低16位有效)
//   0x08: DATA     数据寄存器 (写=发送数据, 读=接收数据)
//   0x0C: STATUS   状态寄存器 (只读: tx_busy, rx_ready, tx_ready)
//   0x10: IRQ_FLAG 中断标志寄存器 (写1清除)
//
// ======================= 时钟分频计算 ======================================
//   clk_divider = (f_sys / (2 * f_spi)) - 1
//   例: f_sys=200MHz, f_spi=10MHz → clk_divider = 9
// ============================================================================

`timescale 1ns/1ps

module spi_master (
    // ========== 系统接口 ==========
    input  wire        clk_i,          // 系统时钟 (200MHz, 周期 5ns)
    input  wire        rst_n_i,        // 复位信号 (低电平有效)

    // ========== CPU 总线接口 ==========
    input  wire        we_i,           // 写使能: 1=CPU 正在写寄存器
    input  wire        re_i,           // 读使能: 1=CPU 正在读寄存器
    input  wire [31:0] addr_i,         // 地址总线 (低 8 位用于寄存器选择)
    input  wire [31:0] wdata_i,        // CPU 写数据总线
    output reg  [31:0] rdata_o,        // CPU 读数据总线

    // ========== SPI 外部接口 ==========
    output wire        sclk_o,         // SPI 时钟输出 (连接到从设备 SCLK)
    output wire        mosi_o,         // 主发从收 (连接到从设备 MOSI)
    input  wire        miso_i,         // 主收从发 (连接到从设备 MISO)
    output wire        cs_o,           // 片选输出 (低电平有效)

    // ========== 中断输出 ==========
    output reg         interrupt_o     // 中断信号 (连接到中断控制器)

);

// ========== 1. 寄存器地址定义 ==========
localparam REG_CTRL     = 8'h00;
localparam REG_CLK_DIV  = 8'h04;
localparam REG_DATA     = 8'h08;
localparam REG_STATUS   = 8'h0C;
localparam REG_IRQ_FLAG = 8'h10;

// ========== 2. 内部控制寄存器 ==========
reg         spi_enable;
reg         irq_enable;
reg         cpol;
reg         cpha;
reg         lsb_first;
reg         data_16bit;
reg         start_tx;

reg  [15:0] clk_divider;
reg  [15:0] tx_data;

reg  [15:0] clk_counter;
reg  [15:0] rx_data;
reg         tx_busy;
reg         rx_ready;
reg         tx_ready;

reg         irq_flag_tx;
reg         irq_flag_rx;

// ========== 3. SPI 状态机定义 ==========
localparam SPI_IDLE   = 2'b00;
localparam SPI_START  = 2'b01;
localparam SPI_TRANS  = 2'b10;
localparam SPI_STOP   = 2'b11;

reg [1:0]  spi_state;
reg [4:0]  bit_counter;

reg        sclk_reg;
reg        mosi_reg;
reg        cs_reg;
reg        sample_edge;
reg        setup_edge;

wire       sclk_tick;
wire [15:0] bits_to_send;
wire [4:0]  max_bits;

// SCLK 前一拍寄存 (用于边沿检测)
reg        sclk_o_d1;

// ========== 4. 辅助信号赋值 ==========
assign max_bits    = data_16bit ? 5'd16 : 5'd8;
assign bits_to_send = data_16bit ? tx_data : {8'b0, tx_data[7:0]};

// ========== 5. 时钟分频计数器 ==========
assign sclk_tick = (clk_counter >= clk_divider) && spi_enable;

always @(posedge clk_i) begin
    if (!rst_n_i) begin
        clk_counter <= 16'b0;
    end else if (sclk_tick) begin
        clk_counter <= 16'b0;
    end else if (spi_enable && (spi_state != SPI_IDLE)) begin
        clk_counter <= clk_counter + 1;
    end else begin
        clk_counter <= 16'b0;
    end
end

// ========== 6. SPI 时钟 (SCLK) 生成 ==========
always @(posedge clk_i) begin
    if (!rst_n_i) begin
        sclk_reg <= 1'b0;
    end else if (spi_enable && (spi_state == SPI_START || spi_state == SPI_TRANS)) begin
        if (sclk_tick) begin
            sclk_reg <= ~sclk_reg;
        end
    end else begin
        sclk_reg <= cpol;   // 空闲时保持 CPOL 指定的电平
    end
end

// ========== 7. 采样边沿和设置边沿检测 ==========
always @(posedge clk_i) begin
    sclk_o_d1 <= sclk_reg;
end

wire sclk_rising  = sclk_reg && ~sclk_o_d1;
wire sclk_falling = ~sclk_reg && sclk_o_d1;

always @(*) begin
    if (cpha) begin
        sample_edge = sclk_falling;  // CPHA=1: 后沿采样
        setup_edge  = sclk_rising;   // CPHA=1: 前沿设置
    end else begin
        sample_edge = sclk_rising;   // CPHA=0: 前沿采样
        setup_edge  = sclk_falling;  // CPHA=0: 后沿设置
    end
end

// ========== 8. SPI 状态机 (含数据收发和中断标志) ==========
always @(posedge clk_i) begin
    if (!rst_n_i) begin
        spi_state   <= SPI_IDLE;
        tx_busy     <= 1'b0;
        rx_ready    <= 1'b0;
        tx_ready    <= 1'b1;
        bit_counter <= 5'b0;
        mosi_reg    <= 1'b0;
        cs_reg      <= 1'b1;
        rx_data     <= 16'b0;
    end else begin
        tx_ready <= 1'b0;

        case (spi_state)
            SPI_IDLE: begin
                cs_reg      <= 1'b1;    // CS 拉高
                tx_busy     <= 1'b0;
                bit_counter <= 5'b0;

                if (spi_enable && start_tx) begin
                    spi_state <= SPI_START;
                    tx_busy   <= 1'b1;
                end else begin
                    tx_ready <= 1'b1;
                end
            end

            SPI_START: begin
                cs_reg      <= 1'b0;    // CS 拉低, 开始传输
                bit_counter <= 5'b0;

                if (cpha) begin
                    // CPHA=1: 在 setup_edge 发送第一位数据, 然后进入 TRANS
                    if (setup_edge) begin
                        if (lsb_first)
                            mosi_reg <= bits_to_send[0];
                        else
                            mosi_reg <= bits_to_send[max_bits-1];
                        spi_state <= SPI_TRANS;
                    end
                end else begin
                    // CPHA=0: 立即输出第一位数据, 然后进入 TRANS 等待 sample_edge 采样
                    if (lsb_first)
                        mosi_reg <= bits_to_send[0];
                    else
                        mosi_reg <= bits_to_send[max_bits-1];
                    spi_state <= SPI_TRANS;
                end
            end

            SPI_TRANS: begin
                // setup_edge: 更新 MOSI 上的下一位数据
                // CPHA=0 且 bit=0 时跳过 (第一位已在 START 阶段发送)
                if (setup_edge && (bit_counter < max_bits)) begin
                    if (cpha == 1'b0 && bit_counter == 5'd0) begin
                        // CPHA=0: 第一位已在 START 发送, 此处跳过
                    end else begin
                        if (lsb_first)
                            mosi_reg <= bits_to_send[bit_counter];
                        else
                            mosi_reg <= bits_to_send[max_bits - 1 - bit_counter];
                    end
                end

                // sample_edge: 采样 MISO 上的数据
                if (sample_edge && (bit_counter < max_bits)) begin
                    if (lsb_first)
                        rx_data[bit_counter] <= miso_i;
                    else
                        rx_data[max_bits - 1 - bit_counter] <= miso_i;
                    bit_counter <= bit_counter + 1;
                end

                // 所有位发送完成 (bit_counter 在 sample_edge 递增后到达 max_bits)
                if (sample_edge && (bit_counter == max_bits - 1)) begin
                    spi_state <= SPI_STOP;
                    rx_ready  <= 1'b1;
                end
            end

            SPI_STOP: begin
                cs_reg    <= 1'b1;       // CS 拉高, 结束传输
                spi_state <= SPI_IDLE;
                tx_busy   <= 1'b0;
                tx_ready  <= 1'b1;
            end
        endcase
    end
end

// ========== 9. 寄存器写操作 ==========
always @(posedge clk_i) begin
    if (!rst_n_i) begin
        spi_enable   <= 1'b0;
        irq_enable   <= 1'b0;
        cpol         <= 1'b0;
        cpha         <= 1'b0;
        lsb_first    <= 1'b0;
        data_16bit   <= 1'b0;
        start_tx     <= 1'b0;
        clk_divider  <= 16'd100;
        tx_data      <= 16'b0;
    end else if (we_i) begin
        case (addr_i[7:0])
            REG_CTRL: begin
                spi_enable  <= wdata_i[0];
                irq_enable  <= wdata_i[1];
                cpol        <= wdata_i[2];
                cpha        <= wdata_i[3];
                lsb_first   <= wdata_i[4];
                data_16bit  <= wdata_i[5];
                if (wdata_i[6])
                    start_tx <= 1'b1;   // start_tx 写 1 启动传输
            end

            REG_CLK_DIV: begin
                clk_divider <= wdata_i[15:0];
            end

            REG_DATA: begin
                tx_data <= data_16bit ? wdata_i[15:0] : {8'b0, wdata_i[7:0]};
            end

            REG_IRQ_FLAG: begin
                // 中断标志清除在统一模块中处理
                // 此处只记录写操作
            end
        endcase
    end else begin
        start_tx <= 1'b0;  // 自动清零
    end
end

// ========== 10. 中断标志统一管理 (含清除和置位) ==========
always @(posedge clk_i) begin
    if (!rst_n_i) begin
        irq_flag_tx <= 1'b0;
        irq_flag_rx <= 1'b0;
    end else begin
        // 优先级1: 写 IRQ_FLAG 寄存器时清除
        if (we_i && (addr_i[7:0] == REG_IRQ_FLAG)) begin
            if (wdata_i[0]) irq_flag_tx <= 1'b0;
            if (wdata_i[1]) irq_flag_rx <= 1'b0;
        end
        // 优先级2: 状态机事件产生中断
        else begin
            // 发送完成中断 (STOP 状态)
            if (spi_state == SPI_STOP)
                irq_flag_tx <= 1'b1;
            // 接收完成中断 (TRANS 结束)
            else if (spi_state == SPI_TRANS && bit_counter == max_bits)
                irq_flag_rx <= 1'b1;
        end
    end
end

// ========== 11. 寄存器读操作 ==========
always @(*) begin
    case (addr_i[7:0])
        REG_CTRL:     rdata_o = {26'b0, data_16bit, lsb_first, cpha, cpol, irq_enable, spi_enable};
        REG_CLK_DIV:  rdata_o = {16'b0, clk_divider};
        REG_DATA:     rdata_o = data_16bit ? {16'b0, rx_data} : {24'b0, rx_data[7:0]};
        REG_STATUS:   rdata_o = {29'b0, tx_busy, rx_ready, tx_ready};
        REG_IRQ_FLAG: rdata_o = {30'b0, irq_flag_rx, irq_flag_tx};
        default:      rdata_o = 32'b0;
    endcase
end

// ========== 12. 中断输出 ==========
always @(posedge clk_i) begin
    interrupt_o <= (irq_enable) && ((irq_flag_tx) || (irq_flag_rx));
end

// ========== 13. 输出引脚赋值 ==========
assign sclk_o = sclk_reg;
assign mosi_o = mosi_reg;
assign cs_o   = cs_reg;

endmodule
