// soc/periph/i2c_master.v — I2C 主控制器 (Master Only)
// 支持标准模式 (100kHz) 和快速模式 (400kHz), 7 位寻址, 中断驱动
//
// ======================= I2C 协议概述 ======================================
// I2C 总线使用两根线: SCL (时钟线) 和 SDA (数据线), 均为开漏, 需要上拉电阻。
//
// 1. START 条件: SCL 高电平时, SDA 从高变低
// 2. STOP  条件: SCL 高电平时, SDA 从低变高
// 3. 数据位传输: SCL 高电平时 SDA 必须稳定; SDA 只能在 SCL 低电平时变化
// 4. 应答 (ACK/NACK): 每字节后第 9 个时钟周期, 发送方释放 SDA, 接收方拉低 = ACK
// 5. 写操作: START → 从设备地址(W) → ACK → 写数据 → ACK → ... → STOP
// 6. 读操作: START → 从设备地址(R) → ACK → 读数据 → ACK/NACK → ... → STOP
//
// ======================= 内部状态机 ========================================
//   IDLE → START → SEND_ADDR → RECV_ACK → SEND_DATA/RECV_DATA → SEND_ACK/RECV_ACK → STOP → IDLE
//
// ======================= 寄存器映射 ========================================
//   0x00: CTRL     控制 (en, irq_en, start, stop, rw, ack_en)
//   0x04: CLK_DIV  时钟分频 (低16位); I2C时钟 = 系统时钟 / (2*(clk_divider+1))
//   0x08: TX_DATA  发送数据 (写模式)
//   0x0C: RX_DATA  接收数据 (读模式)
//   0x10: STATUS   状态 (只读: tx_busy, tx_ready, rx_ready, ack_status)
//   0x14: ADDR     从设备地址 (低7位)
//   0x18: IRQ_FLAG 中断标志 (写1清除: tx_done, rx_done, nack)
//
// ======================= 时钟分频计算 ======================================
//   clk_divider = (f_sys / (2 * f_i2c)) - 1
//   例: f_sys=200MHz, f_i2c=100kHz → clk_divider = 999
// ============================================================================

`timescale 1ns/1ps

module i2c_master (
    input  wire        clk_i,
    input  wire        rst_n_i,

    // ========== 总线接口 ==========
    input  wire        we_i,
    input  wire        re_i,
    input  wire [31:0] addr_i,
    input  wire [31:0] wdata_i,
    output reg  [31:0] rdata_o,

    // ========== I2C 外部接口 ==========
    inout  wire        sda_io,
    inout  wire        scl_io,

    // ========== 中断输出 ==========
    output reg         interrupt_o

);

// ========== 寄存器地址定义 ==========
localparam REG_CTRL     = 8'h00;
localparam REG_CLK_DIV  = 8'h04;
localparam REG_TX_DATA  = 8'h08;
localparam REG_RX_DATA  = 8'h0C;
localparam REG_STATUS   = 8'h10;
localparam REG_ADDR     = 8'h14;
localparam REG_IRQ_FLAG = 8'h18;

// ========== 内部寄存器 ==========
reg         i2c_enable;
reg         irq_enable;
reg         start_cmd;
reg         stop_cmd;
reg         rw_cmd;
reg         ack_enable;

reg  [15:0] clk_divider;
reg  [7:0]  tx_data;
reg  [7:0]  rx_data;
reg  [6:0]  slave_addr;

reg         tx_busy;
reg         rx_ready;
reg         tx_ready;
reg         ack_status;

reg         irq_flag_tx;
reg         irq_flag_rx;
reg         irq_flag_nack;

// I2C 状态机
localparam I2C_IDLE      = 3'b000;
localparam I2C_START     = 3'b001;
localparam I2C_SEND_ADDR = 3'b010;
localparam I2C_SEND_DATA = 3'b011;
localparam I2C_RECV_DATA = 3'b100;
localparam I2C_SEND_ACK  = 3'b101;
localparam I2C_RECV_ACK  = 3'b110;
localparam I2C_STOP      = 3'b111;

reg [2:0]  i2c_state;
reg [3:0]  bit_counter;
reg        scl_reg;
reg        sda_out_reg;
reg        sda_oe_reg;
reg        scl_oe_reg;
reg        scl_in;
reg        sda_in;

reg [15:0] clk_counter;
reg        clk_tick;

// ========== 三态缓冲器控制 ==========
assign sda_io = sda_oe_reg ? sda_out_reg : 1'bz;
assign scl_io = scl_oe_reg ? scl_reg     : 1'bz;

// 输入同步
always @(posedge clk_i) begin
    scl_in <= scl_io;
    sda_in <= sda_io;
end

// ========== 时钟分频 (clk_tick 为波特率节拍) ==========
always @(posedge clk_i) begin
    if (!rst_n_i) begin
        clk_counter <= 16'b0;
        clk_tick    <= 1'b0;
    end else if (i2c_enable && (i2c_state != I2C_IDLE)) begin
        if (clk_counter >= clk_divider) begin
            clk_counter <= 16'b0;
            clk_tick    <= 1'b1;
        end else begin
            clk_counter <= clk_counter + 1;
            clk_tick    <= 1'b0;
        end
    end else begin
        clk_counter <= 16'b0;
        clk_tick    <= 1'b0;
    end
end

// ========== I2C 时钟 (SCL) 生成 ==========
always @(posedge clk_i) begin
    if (!rst_n_i) begin
        scl_reg    <= 1'b1;
        scl_oe_reg <= 1'b0;
    end else if (i2c_enable && (i2c_state != I2C_IDLE) && (i2c_state != I2C_STOP)) begin
        scl_oe_reg <= 1'b1;          // 主动驱动 SCL
        if (clk_tick)
            scl_reg <= ~scl_reg;     // 每个节拍翻转
    end else begin
        scl_reg    <= 1'b1;          // 释放 SCL (上拉为高)
        scl_oe_reg <= 1'b0;
    end
end

// ========== I2C 状态机 (含数据收发和中断标志) ==========
always @(posedge clk_i) begin
    if (!rst_n_i) begin
        i2c_state    <= I2C_IDLE;
        tx_busy      <= 1'b0;
        rx_ready     <= 1'b0;
        tx_ready     <= 1'b1;
        bit_counter  <= 4'b0;
        sda_out_reg  <= 1'b1;
        sda_oe_reg   <= 1'b0;
        ack_status   <= 1'b0;
        rx_data      <= 8'b0;
    end else begin
        tx_ready <= 1'b0;

        case (i2c_state)
            I2C_IDLE: begin
                sda_oe_reg  <= 1'b0;
                sda_out_reg <= 1'b1;
                tx_busy     <= 1'b0;
                bit_counter <= 4'b0;

                if (i2c_enable && start_cmd) begin
                    i2c_state   <= I2C_START;
                    tx_busy     <= 1'b1;
                    sda_oe_reg  <= 1'b1;       // 主动驱动 SDA
                    sda_out_reg <= 1'b1;        // SDA 先保持高电平
                end else begin
                    tx_ready <= 1'b1;
                end
            end

            I2C_START: begin
                if (scl_reg) begin
                    // SCL 高电平时拉低 SDA → START 条件
                    sda_out_reg <= 1'b0;
                end
                // 等待 SCL 变低 (START 保持时间满足后再进入地址发送)
                if (!scl_reg)
                    i2c_state <= I2C_SEND_ADDR;
            end

            I2C_SEND_ADDR: begin
                if (clk_tick && scl_reg) begin
                    if (bit_counter < 7) begin
                        // 发送 7 位地址 (MSB 先)
                        sda_out_reg <= slave_addr[6 - bit_counter];
                        bit_counter <= bit_counter + 1;
                    end else if (bit_counter == 7) begin
                        // 发送 R/W 位
                        sda_out_reg <= rw_cmd;
                        bit_counter <= bit_counter + 1;
                    end else if (bit_counter == 8) begin
                        // 释放 SDA, 等待从设备应答
                        sda_oe_reg <= 1'b0;
                        i2c_state  <= I2C_RECV_ACK;
                    end
                end
            end

            I2C_SEND_DATA: begin
                if (clk_tick && scl_reg) begin
                    if (bit_counter < 8) begin
                        // 发送 8 位数据 (MSB 先)
                        sda_out_reg <= tx_data[7 - bit_counter];
                        bit_counter <= bit_counter + 1;
                    end else if (bit_counter == 8) begin
                        // 释放 SDA, 等待应答
                        sda_oe_reg  <= 1'b0;
                        bit_counter <= bit_counter + 1;
                        i2c_state   <= I2C_RECV_ACK;
                    end
                end
            end

            I2C_RECV_DATA: begin
                if (clk_tick && scl_reg) begin
                    if (bit_counter < 8) begin
                        // 接收 8 位数据 (MSB 先)
                        rx_data[7 - bit_counter] <= sda_in;
                        bit_counter <= bit_counter + 1;
                    end else if (bit_counter == 8) begin
                        // 发送 ACK/NACK
                        sda_oe_reg  <= 1'b1;
                        sda_out_reg <= ~ack_enable;  // ack_enable=1 → ACK(拉低); 0 → NACK(拉高)
                        bit_counter <= bit_counter + 1;
                        i2c_state   <= I2C_SEND_ACK;
                    end
                end
            end

            I2C_RECV_ACK: begin
                if (clk_tick && scl_reg) begin
                    ack_status  <= sda_in;   // 记录应答状态
                    bit_counter <= 4'b0;

                    if (sda_in == 1'b1) begin  // NACK
                        if (stop_cmd) begin
                            sda_oe_reg  <= 1'b1;
                            sda_out_reg <= 1'b0;
                            i2c_state   <= I2C_STOP;
                        end else begin
                            i2c_state <= I2C_IDLE;
                        end
                    end else begin  // ACK
                        if (rw_cmd) begin  // 读模式
                            if (stop_cmd) begin
                                sda_oe_reg  <= 1'b1;
                                sda_out_reg <= 1'b0;
                                i2c_state   <= I2C_STOP;
                                rx_ready    <= 1'b1;
                            end else begin
                                i2c_state   <= I2C_RECV_DATA;
                                bit_counter <= 4'b0;
                            end
                        end else if (bit_counter == 9) begin  // 写模式单字节完成
                            sda_oe_reg  <= 1'b1;
                            sda_out_reg <= 1'b0;
                            i2c_state   <= I2C_STOP;
                            bit_counter <= 4'b0;
                        end else begin  // 写模式继续
                            if (stop_cmd) begin
                                sda_oe_reg  <= 1'b1;
                                sda_out_reg <= 1'b0;
                                i2c_state   <= I2C_STOP;
                            end else begin
                                i2c_state   <= I2C_SEND_DATA;
                                bit_counter <= 4'b0;
                                tx_ready    <= 1'b1;
                            end
                        end
                    end
                end
            end

            I2C_SEND_ACK: begin
                if (clk_tick && scl_reg) begin
                    if (stop_cmd) begin
                        sda_oe_reg  <= 1'b1;
                        sda_out_reg <= 1'b0;
                        i2c_state   <= I2C_STOP;
                        rx_ready    <= 1'b1;
                    end else begin
                        i2c_state   <= I2C_RECV_DATA;
                        bit_counter <= 4'b0;
                    end
                end
            end

            I2C_STOP: begin
                if (scl_reg) begin
                    sda_oe_reg  <= 1'b1;
                    sda_out_reg <= 1'b1;  // SCL 高时 SDA 从低变高 → STOP 条件
                end
                // 等待 SCL 变低 (STOP 保持时间满足后再回到 IDLE)
                if (!scl_reg) begin
                    i2c_state <= I2C_IDLE;
                    tx_busy   <= 1'b0;
                end
            end
        endcase
    end
end

// ========== 寄存器写操作 ==========
always @(posedge clk_i) begin
    if (!rst_n_i) begin
        i2c_enable  <= 1'b0;
        irq_enable  <= 1'b0;
        start_cmd   <= 1'b0;
        stop_cmd    <= 1'b0;
        rw_cmd      <= 1'b0;
        ack_enable  <= 1'b1;
        clk_divider <= 16'd1000;
        tx_data     <= 8'b0;
        slave_addr  <= 7'b0;
    end else if (we_i) begin
        case (addr_i[7:0])
            REG_CTRL: begin
                i2c_enable <= wdata_i[0];
                irq_enable <= wdata_i[1];            // 直接读写，写0可关闭中断
                if (wdata_i[2]) start_cmd <= 1'b1;   // 写1启动 START
                if (wdata_i[3]) stop_cmd  <= 1'b1;   // 写1启动 STOP
                rw_cmd     <= wdata_i[4];
                ack_enable <= wdata_i[5];
            end

            REG_CLK_DIV: begin
                clk_divider <= wdata_i[15:0];
            end

            REG_TX_DATA: begin
                tx_data <= wdata_i[7:0];
            end

            REG_ADDR: begin
                slave_addr <= wdata_i[6:0];
            end

            REG_IRQ_FLAG: begin
                // 中断标志清除在统一模块中处理
            end
        endcase
    end else begin
        start_cmd <= 1'b0;  // 自动清零
        stop_cmd  <= 1'b0;
    end
end

// ========== 中断标志统一管理 (含清除和置位) ==========
always @(posedge clk_i) begin
    if (!rst_n_i) begin
        irq_flag_tx   <= 1'b0;
        irq_flag_rx   <= 1'b0;
        irq_flag_nack <= 1'b0;
    end else begin
        // 优先级1: 写 IRQ_FLAG 寄存器时清除
        if (we_i && (addr_i[7:0] == REG_IRQ_FLAG)) begin
            if (wdata_i[0]) irq_flag_tx   <= 1'b0;
            if (wdata_i[1]) irq_flag_rx   <= 1'b0;
            if (wdata_i[2]) irq_flag_nack <= 1'b0;
        end
        // 优先级2: 状态机事件产生中断
        else begin
            // NACK 中断
            if (i2c_state == I2C_RECV_ACK && sda_in == 1'b1)
                irq_flag_nack <= 1'b1;
            // 接收完成中断 (读模式 stop_cmd)
            else if (i2c_state == I2C_RECV_ACK && rw_cmd && stop_cmd)
                irq_flag_rx <= 1'b1;
            // 接收完成中断 (SEND_ACK 状态)
            else if (i2c_state == I2C_SEND_ACK && stop_cmd)
                irq_flag_rx <= 1'b1;
            // 发送完成中断 (写模式 bit_counter == 9)
            else if (i2c_state == I2C_RECV_ACK && !rw_cmd && bit_counter == 9)
                irq_flag_tx <= 1'b1;
            // 发送完成中断 (写模式 stop_cmd)
            else if (i2c_state == I2C_RECV_ACK && !rw_cmd && stop_cmd)
                irq_flag_tx <= 1'b1;
        end
    end
end

// ========== 寄存器读操作 ==========
always @(*) begin
    case (addr_i[7:0])
        REG_CTRL:     rdata_o = {26'b0, ack_enable, rw_cmd, stop_cmd, start_cmd, irq_enable, i2c_enable};
        REG_CLK_DIV:  rdata_o = {16'b0, clk_divider};
        REG_TX_DATA:  rdata_o = {24'b0, tx_data};
        REG_RX_DATA:  rdata_o = {24'b0, rx_data};
        REG_STATUS:   rdata_o = {28'b0, ack_status, rx_ready, tx_ready, tx_busy};
        REG_ADDR:     rdata_o = {25'b0, slave_addr};
        REG_IRQ_FLAG: rdata_o = {29'b0, irq_flag_nack, irq_flag_rx, irq_flag_tx};
        default:      rdata_o = 32'b0;
    endcase
end

// ========== 中断输出 ==========
always @(posedge clk_i) begin
    interrupt_o <= (irq_enable) && (irq_flag_tx || irq_flag_rx || irq_flag_nack);
end

endmodule
