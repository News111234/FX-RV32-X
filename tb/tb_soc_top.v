// tb/tb_soc_top.v - SoC 顶层仿真测试平台
`timescale 1ns/1ps

module tb_soc_top;

// 时钟和复位
reg clk;
reg rst_n;

// 顶层端口连接
wire        uart_tx;
wire [31:0] gpio_io;
reg  [31:0] gpio_in;          // GPIO 外部输入 (驱动给 DUT)
wire [31:0] gpio_out;         // GPIO 输出 (来自 DUT)
wire [31:0] gpio_oe;          // GPIO 方向 (来自 DUT)
wire        spi_sclk;
wire        spi_mosi;
reg         spi_miso;         // SPI 外部输入 (驱动给 DUT)
wire        spi_cs;
wire        i2c_sda;
wire        i2c_scl;

// 实例化 SoC 顶层
soc_top u_soc_top (
    .clk_i          (clk),
    .rst_n_i        (rst_n),

    .uart_tx_o      (uart_tx),

    .gpio_io        (gpio_io),
    .gpio_in        (gpio_in),
    .gpio_out       (gpio_out),
    .gpio_oe        (gpio_oe),

    .spi_sclk_o     (spi_sclk),
    .spi_mosi_o     (spi_mosi),
    .spi_miso_i     (spi_miso),
    .spi_cs_o       (spi_cs),

    .i2c_sda_io     (i2c_sda),
    .i2c_scl_io     (i2c_scl)

);

// 时钟生成 (200MHz)
initial begin
    clk = 0;
    forever #2.5 clk = ~clk;
end

// 复位控制
initial begin
    rst_n = 0;
    #100;
    rst_n = 1;
end

// =========================================================================
// GPIO 外部输入激励 — 产生中断测试信号
// =========================================================================
// GPIO 中断机制 (见 soc/periph/gpio.v):
//   边沿触发 (EDGE=1): rising_edge | falling_edge → 置位 IF
//   电平触发 (EDGE=0): gpio_in_sync[i] == 1  → 持续触发
//   中断输出: interrupt_o = |(gpio_if & gpio_ie)
//
// 测试程序需提前配置:
//   GPIO_IE[0]   = 1   (使能 pin0 中断)
//   GPIO_EDGE[0] = 1   (边沿触发) 或 0 (电平触发)
// =========================================================================

initial begin
    gpio_in = 32'h0;
    // ---- 阶段1: 400ns 前保持低电平 ----
    #400;

    // ---- 阶段2: 400ns 时产生上升沿 (pin0 0→1) ----
    gpio_in[0] = 1'b1;
    $display("[TB] %t: gpio_in[0] = 1 (rising edge)", $time);
    #80;

    // ---- 阶段3: 再产生下降沿 (pin0 1→0) ----
    gpio_in[0] = 1'b0;
    $display("[TB] %t: gpio_in[0] = 0 (falling edge)", $time);
    #200;

    // ---- 阶段4: 再次上升沿 + 保持高电平 (测试电平触发) ----
    gpio_in[0] = 1'b1;
    $display("[TB] %t: gpio_in[0] = 1 (level high)", $time);
    #500;

    // ---- 阶段5: 恢复低电平 ----
    gpio_in[0] = 1'b0;
    $display("[TB] %t: gpio_in[0] = 0 (idle)", $time);
end

// =========================================================================
// SPI 外部输入默认
// =========================================================================
initial begin
    spi_miso = 1'b0;
end

// =========================================================================
// I2C 上拉 (弱上拉模拟)
// =========================================================================
pullup(i2c_sda);
pullup(i2c_scl);

// =========================================================================
// 运行时监控 — 测试结果检查
// =========================================================================
reg [31:0] cycle_cnt;
reg        result_done;

initial begin
    cycle_cnt   = 0;
    result_done = 0;
end

always @(posedge clk) begin
    if (!rst_n) begin
        cycle_cnt   <= 0;
        result_done <= 0;
    end else if (!result_done) begin
        cycle_cnt <= cycle_cnt + 1;
    end
end

// 监控 tohost 地址 (0x000000FC) — 测试通过/失败
always @(posedge clk) begin
    if (u_soc_top.core_bus_we &&
        u_soc_top.core_bus_addr == 32'h000000FC) begin
        if (u_soc_top.core_bus_wdata == 32'h0)
            $display("=== TEST PASSED at cycle %0d ===", cycle_cnt);
        else
            $display("=== TEST FAILED code=%0d at cycle %0d ===",
                     u_soc_top.core_bus_wdata, cycle_cnt);
        $finish;
    end
end

// 监控 results 区域 (0x300~0x3EF) — 每轮3 words: duration/entry_mcycle/timer_count
always @(posedge clk) begin
    if (u_soc_top.core_bus_we &&
        (u_soc_top.core_bus_addr >= 32'h00000300) &&
        (u_soc_top.core_bus_addr <= 32'h000003EF)) begin
        case ((u_soc_top.core_bus_addr - 32'h00000300) % 12)
            0: $display("  [%0d] ISR_duration = %0d",
                        ((u_soc_top.core_bus_addr - 32'h00000300) / 12),
                        u_soc_top.core_bus_wdata);
            4: $display("  [%0d] entry_mcycle = %0d",
                        ((u_soc_top.core_bus_addr - 32'h00000300) / 12),
                        u_soc_top.core_bus_wdata);
            8: $display("  [%0d] timer_count = %0d",
                        ((u_soc_top.core_bus_addr - 32'h00000300) / 12),
                        u_soc_top.core_bus_wdata);
        endcase
    end
end

// =========================================================================
// GPIO 中断监控 — 观察中断相关信号
// =========================================================================
always @(posedge clk) begin
    if (u_soc_top.u_gpio.interrupt_o)
        $display("[TB] %t: GPIO interrupt asserted, IF=%08h",
                 $time, u_soc_top.u_gpio.debug_gpio_if);
end

endmodule


//   GPIO 中断激励时序

//   400ns       480ns      680ns      1180ns
//     │           │          │          │
//   ──┘───────────┐──────────┘──────────┐──────────
//                 │  ↑上升沿   │  ↓下降沿  │  ↑上升沿+保持高
//                 │  (边沿触发) │  (边沿触发)│  (电平触发)

//   - 400ns: pin0 上升沿 → 边沿触发型中断
//   - 480ns: pin0 下降沿 → 又一次边沿触发
//   - 680ns: pin0 再次上升沿并保持 → 电平触发型中断
//   - 1180ns: pin0 回到低电平

//   GPIO 中断的触发链路

//   tb_soc_top.gpio_in[0]
//       → soc_top.gpio_in[0]
//       → gpio.gpio_in_i[0] (2级同步)
//       → 边沿检测/电平检测
//       → gpio_if[0] 置位
//       → interrupt_o = |(gpio_if & gpio_ie)
//       → gpio_interrupt
//       → intr_external_i (与 SPI/I2C 或)
//       → CPU 外部中断 cause=11

//   你的测试程序只需要提前配好 GPIO_IE[0]=1、GPIO_EDGE[0]=1（边沿），然后 400ns 后 gpio_in[0]
//   自动产生上升沿，中断就进来了。