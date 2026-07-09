// soc/periph/uart_rx.v — UART 接收器
// ============================================================================
// 功能: UART 接收器，实现异步串行接收
//
// 协议: 8N1 (1 start bit, 8 data bits, no parity, 1 stop bit)
// 过采样: 16× 波特率, 在每位中间点采样
//   分频 = CLK_FREQ / (BAUD_RATE * 16)
//   200MHz / (115200 * 16) ≈ 108
//
// 状态机: IDLE → START → DATA[0..7] → STOP → IDLE
//
// 输出接口:
//   rx_data_o:  接收到的 8-bit 数据 (在 rx_valid_o 有效时有效)
//   rx_valid_o: 接收完成脉冲 (单周期高电平)
// ============================================================================
`timescale 1ns/1ps

module uart_rx #(
    parameter CLK_FREQ   = 200_000_000,
    parameter BAUD_RATE  = 115200
) (
    // ========== 系统接口 ==========
    input  wire        clk_i,
    input  wire        rst_n_i,

    // ========== 外部引脚 ==========
    input  wire        rx_pin_i,           // UART RX 引脚

    // ========== 数据输出 ==========
    output reg  [7:0]  rx_data_o,          // 接收到的字节
    output reg         rx_valid_o,         // 接收完成脉冲 (1 周期)

    // ========== 调试输出 ==========
    output wire [1:0]  debug_state_o,
    output wire [15:0] debug_sample_cnt_o,
    output wire [3:0]  debug_bit_cnt_o
);

    // 16× 过采样分频系数
    // 200MHz / (115200 * 16) = 108.5 → 108 (误差 0.46%)
    localparam SAMPLE_DIV = CLK_FREQ / (BAUD_RATE * 16);  // ≈ 108
    localparam SAMPLE_HALF = SAMPLE_DIV / 2;               // ≈ 54 (半位中心)

    // 状态机
    localparam RX_IDLE  = 2'b00;
    localparam RX_START = 2'b01;
    localparam RX_DATA  = 2'b10;
    localparam RX_STOP  = 2'b11;

    reg [1:0]  state;
    reg [15:0] sample_cnt;      // 过采样计数器 (0 ~ SAMPLE_DIV-1)
    reg [3:0]  bit_cnt;         // 已接收位数 (0 ~ 7)
    reg [7:0]  shift_reg;       // 移位寄存器

    // RX 引脚同步 (两级同步器消除亚稳态)
    reg rx_sync1, rx_sync2;
    always @(posedge clk_i) begin
        rx_sync1 <= rx_pin_i;
        rx_sync2 <= rx_sync1;
    end
    wire rx_synced = rx_sync2;

    // 下降沿检测 (用于检测 START bit)
    reg rx_prev;
    always @(posedge clk_i) begin
        if (!rst_n_i)
            rx_prev <= 1'b1;
        else
            rx_prev <= rx_synced;
    end
    wire rx_falling = rx_prev && !rx_synced;

    // ========================================================================
    // 接收状态机
    // ========================================================================
    always @(posedge clk_i) begin
        if (!rst_n_i) begin
            state       <= RX_IDLE;
            sample_cnt  <= 16'b0;
            bit_cnt     <= 4'b0;
            shift_reg   <= 8'b0;
            rx_data_o   <= 8'b0;
            rx_valid_o  <= 1'b0;
        end else begin
            // 默认值
            rx_valid_o <= 1'b0;

            case (state)
                RX_IDLE: begin
                    sample_cnt <= 16'b0;
                    bit_cnt    <= 4'b0;

                    if (rx_falling) begin
                        state <= RX_START;
                    end
                end

                RX_START: begin
                    // 等待半个位周期 (8 个采样周期), 对准数据位中心
                    if (sample_cnt == SAMPLE_HALF - 1) begin
                        sample_cnt <= 16'b0;
                        // 确认 START bit 仍为低 (防毛刺)
                        if (!rx_synced) begin
                            state <= RX_DATA;
                        end else begin
                            state <= RX_IDLE;   // 假起始位, 回到 IDLE
                        end
                    end else begin
                        sample_cnt <= sample_cnt + 1;
                    end
                end

                RX_DATA: begin
                    if (sample_cnt == SAMPLE_DIV - 1) begin
                        sample_cnt <= 16'b0;
                        // 在每一位的中心点采样 (已在 START 阶段对准)
                        shift_reg <= {rx_synced, shift_reg[7:1]};  // LSB 先收
                        bit_cnt   <= bit_cnt + 1;

                        if (bit_cnt == 7) begin  // 已收到 8 个数据位
                            state <= RX_STOP;
                        end
                    end else begin
                        sample_cnt <= sample_cnt + 1;
                    end
                end

                RX_STOP: begin
                    // 等待 1 个位周期 (16 个采样周期) 完成停止位
                    if (sample_cnt == SAMPLE_DIV - 1) begin
                        sample_cnt <= 16'b0;
                        state      <= RX_IDLE;
                        rx_data_o  <= shift_reg;
                        rx_valid_o <= 1'b1;     // 单周期脉冲
                    end else begin
                        sample_cnt <= sample_cnt + 1;
                    end
                end

                default: state <= RX_IDLE;
            endcase
        end
    end

    // ========================================================================
    // 调试输出
    // ========================================================================
    assign debug_state_o      = state;
    assign debug_sample_cnt_o = sample_cnt;
    assign debug_bit_cnt_o    = bit_cnt;

endmodule
