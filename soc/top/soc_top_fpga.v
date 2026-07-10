// soc/top/soc_top_fpga.v — FPGA 专用顶层
// Target FPGA: Xilinx Kintex-7 xc7k325tffg900-2
// Clock: 200 MHz LVDS 差分时钟 → 单端 clk_i
`timescale 1ns/1ps

module soc_top_fpga #(
    parameter SHADOW_BANKS    = 4,   // 影子Bank数量 (默认4, 支持3级嵌套)
    parameter OVERFLOW_POLICY = 0    // Bank溢出策略: 0=硬限制, 1=降级复用
) (
    // 差分系统时钟输入
    input  wire        clk_p_i,
    input  wire        clk_n_i,

    // UART 输出
    output wire        uart_tx_o,
    input  wire        uart_rx_i,

    // SPI 接口
    output wire        spi_sclk_o,
    output wire        spi_mosi_o,
    input  wire        spi_miso_i,
    output wire        spi_cs_o,

    // I2C 接口
    inout  wire        i2c_sda_io,
    inout  wire        i2c_scl_io,

    // GPIO 接口 (双向)
    inout  wire [31:0] gpio_io,

    // LED 指示灯 (8 个)
    output wire        led0_o,
    output wire        led1_o,
    output wire        led2_o,
    output wire        led3_o,
    output wire        led4_o,
    output wire        led5_o,
    output wire        led6_o,
    output wire        led7_o
);

// ----------------------------------------------------------------------
// 时钟与复位
// ----------------------------------------------------------------------
wire clk_200m;                  // 内部 200MHz 时钟
IBUFDS u_ibufds_clk (
    .I  (clk_p_i),
    .IB (clk_n_i),
    .O  (clk_200m)
);

// 上电复位计数器 (产生内部复位)
reg [24:0] rst_counter = 0;
wire rst_n_internal;
always @(posedge clk_200m) begin
    if (!rst_n_internal)
        rst_counter <= rst_counter + 1;
end
assign rst_n_internal = &rst_counter;   // 所有位为 1 时释放复位

// ----------------------------------------------------------------------
// SoC 实例化
// ----------------------------------------------------------------------
wire [31:0] gpio_out;
wire [31:0] gpio_oe;
wire [31:0] gpio_in;

soc_top #(
    .SHADOW_BANKS(SHADOW_BANKS),
    .OVERFLOW_POLICY(OVERFLOW_POLICY)
) u_soc_top (
    .clk_i            (clk_200m),
    .rst_n_i          (rst_n_internal),

    .uart_tx_o        (uart_tx_o),
    .uart_rx_i        (uart_rx_i),

    .gpio_io          (),                // 不使用顶层直连, 由 GPIO IOBUF 处理
    .spi_sclk_o       (spi_sclk_o),
    .spi_mosi_o       (spi_mosi_o),
    .spi_miso_i       (spi_miso_i),
    .spi_cs_o         (spi_cs_o),

    .i2c_sda_io       (i2c_sda_io),
    .i2c_scl_io       (i2c_scl_io),

    // GPIO 三态分解端口
    .gpio_out         (gpio_out),
    .gpio_oe          (gpio_oe),
    .gpio_in          (gpio_in),

    // 软件中断 (FPGA 上无外部软件中断源, 固定为 0)
    .intr_software_i  (1'b0)
);

// ----------------------------------------------------------------------
// GPIO 三态缓冲器
// ----------------------------------------------------------------------
genvar g;
generate
    for (g = 0; g < 32; g = g + 1) begin : gpio_tristate
        IOBUF u_gpio_iobuf (
            .I(gpio_out[g]),
            .O(gpio_in[g]),
            .IO(gpio_io[g]),
            .T(~gpio_oe[g])
        );
    end
endgenerate

// ----------------------------------------------------------------------
// LED 指示灯
// ----------------------------------------------------------------------
reg [27:0] led_counter;
always @(posedge clk_200m) begin
    if (!rst_n_internal)
        led_counter <= 28'h0;
    else
        led_counter <= led_counter + 1;
end

assign led0_o = rst_n_internal;         // 复位状态指示 (复位时灭, 释放后亮)
assign led1_o = led_counter[26];        // 系统心跳 (~0.75 Hz @200MHz)
assign led2_o = led_counter[25];        // 心跳快闪 (~1.5 Hz)
assign led3_o = led_counter[24];        // 心跳快闪 (~3 Hz)
assign led4_o = led_counter[23];        // 心跳快闪 (~6 Hz)
assign led5_o = led_counter[22];        // 心跳快闪 (~12 Hz)
assign led6_o = led_counter[21];        // 心跳快闪 (~24 Hz)
assign led7_o = 1'b1;                   // 系统运行指示 (常亮)

// ==========================================================================
// 注: 如需恢复内部信号指示 (综合需将对应信号引出为顶层端口):
//   led2_o = |if_instr       — 指令有效
//   led3_o = uart_we         — UART 写使能
//   led4_o = |if_pc          — PC 非零
//   led5_o = ex_branch_taken — 分支跳转
//   led6_o = ex_jump_taken   — 跳转
//   这些信号来自 core_top/uart_ctrl 内部, 需修改对应模块引出端口.
// ==========================================================================

endmodule
