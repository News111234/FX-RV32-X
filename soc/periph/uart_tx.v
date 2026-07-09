// soc/periph/uart_tx.v — UART 发送器
`timescale 1ns/1ps

// ============================================================================
// 模块: uart_tx
// 功能: UART 发送器，实现异步串行发送
// 描述:
//   本模块实现 UART 发送器底层发送协议:
//   1. 空闲时 TX 线为高电平
//   2. 起始位: 1 个低电平位
//   3. 数据位: 8 个数据位，LSB 先发
//   4. 停止位: 1 个高电平位
//   5. 发送完毕返回空闲
//   状态机: IDLE -> START -> DATA[0..7] -> STOP -> IDLE
//   波特率通过分频系数 BAUD_DIV = CLK_FREQ / BAUD_RATE 控制。
// ============================================================================
module uart_tx #(
    parameter CLK_FREQ  = 200_000_000,     // 时钟频率 (Hz)
    parameter BAUD_RATE = 115200           // 波特率
) (
    // ========== 系统接口 ==========
    input  wire        clk_i,              // 时钟信号
    input  wire        rst_n_i,            // 复位信号 (低电平有效)

    // ========== 数据接口 ==========
    input  wire [7:0]  tx_data_i,          // 要发送的数据
    input  wire        tx_valid_i,         // 数据有效信号
    output reg         tx_ready_o,         // 发送器就绪 (可以接收新数据)

    // ========== 输出引脚 ==========
    output wire        tx_pin_o,           // UART TX 引脚

    // ========== 调试输出 ==========
    output wire [1:0]  debug_state_o,      // 调试: 状态机状态
    output wire [31:0] debug_baud_cnt_o,   // 调试: 波特率计数器
    output wire [3:0]  debug_bit_cnt_o,    // 调试: 位计数器
    output wire [7:0]  debug_shift_reg_o   // 调试: 移位寄存器
);

// 计算波特率分频系数
localparam BAUD_DIV = CLK_FREQ / BAUD_RATE;

// 状态机定义
localparam IDLE  = 2'b00;
localparam START = 2'b01;
localparam DATA  = 2'b10;
localparam STOP  = 2'b11;

// 内部寄存器
reg [1:0]   state;          // 当前状态
reg [7:0]   shift_reg;      // 移位寄存器
reg [3:0]   bit_cnt;        // 已发送位数
reg [31:0]  baud_cnt;       // 波特率计数器
reg         tx_reg;         // TX 输出寄存器

// 状态机
always @(posedge clk_i) begin
    if (!rst_n_i) begin
        state      <= IDLE;
        shift_reg  <= 8'b0;
        bit_cnt    <= 4'b0;
        baud_cnt   <= 32'b0;
        tx_reg     <= 1'b1;      // 空闲时为高电平
        tx_ready_o <= 1'b1;
    end else begin
        case (state)
            IDLE: begin
                tx_reg     <= 1'b1;          // 保持高电平
                tx_ready_o <= 1'b1;          // 准备接收
                bit_cnt    <= 4'b0;
                baud_cnt   <= 32'b0;

                if (tx_valid_i) begin
                    state     <= START;
                    shift_reg <= tx_data_i;  // 锁存数据
                    baud_cnt  <= 32'b0;      // 重置计数器，START 时开始计时
                end
            end

            START: begin
                tx_reg     <= 1'b0;          // 起始位 (低电平)
                tx_ready_o <= 1'b0;          // 忙，不再接收
                if (baud_cnt >= BAUD_DIV - 1) begin
                    baud_cnt <= 32'b0;
                    state    <= DATA;
                end else begin
                    baud_cnt <= baud_cnt + 1;
                end
            end

            DATA: begin
                tx_reg <= shift_reg[0];      // 发送 LSB

                if (baud_cnt == BAUD_DIV - 1) begin
                    baud_cnt  <= 32'b0;
                    shift_reg <= {1'b0, shift_reg[7:1]};  // 右移
                    bit_cnt   <= bit_cnt + 1;

                    if (bit_cnt == 7) begin  // 已发送 8 个数据位
                        state   <= STOP;
                        bit_cnt <= 4'b0;     // 重置位计数器
                    end
                end else begin
                    baud_cnt <= baud_cnt + 1;
                end
            end

            STOP: begin
                tx_reg <= 1'b1;              // 停止位 (高电平)

                if (baud_cnt >= BAUD_DIV - 1) begin
                    baud_cnt   <= 32'b0;
                    state      <= IDLE;
                    tx_ready_o <= 1'b1;      // 回到 IDLE 时恢复 ready
                end else begin
                    baud_cnt <= baud_cnt + 1;
                end
            end

            default: state <= IDLE;
        endcase
    end
end

assign tx_pin_o = tx_reg;

// 调试输出
assign debug_state_o    = state;
assign debug_baud_cnt_o = baud_cnt;
assign debug_bit_cnt_o  = bit_cnt;
assign debug_shift_reg_o = shift_reg;

endmodule
