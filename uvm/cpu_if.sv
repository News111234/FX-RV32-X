// cpu_if.sv — UVM 接口定义
// 连接 DUT (core_top) 与 UVM 验证组件
// 含两个时钟块: drv_cb (驱动侧) 和 mon_cb (监控侧, 延迟3ns采样以避免毛刺)
`timescale 1ns/1ps

interface cpu_if (
    input wire clk,
    input wire rst_n
);
    // ========== 指令取指接口 ==========
    logic [31:0] if_pc;
    logic [31:0] if_instr;

    // ========== 总线访存接口 ==========
    logic        bus_re;
    logic        bus_we;
    logic [31:0] bus_addr;
    logic [31:0] bus_wdata;
    logic [2:0]  bus_width;
    logic [31:0] bus_rdata;
    logic        bus_ready;

    // ========== 中断接口 ==========
    logic        intr_timer;
    logic        intr_software;
    logic        intr_external;
    logic        intr_spi;
    logic        intr_i2c;

    // ========== 驱动侧时钟块 ==========
    clocking drv_cb @(posedge clk);
        default input #1ns output #1ns;
        output intr_timer, intr_software, intr_external, intr_spi, intr_i2c;
        input  if_pc, bus_re, bus_we, bus_addr, bus_wdata, bus_width;
    endclocking

    // ========== 监控侧时钟块 (延迟采样避免毛刺) ==========
    clocking mon_cb @(posedge clk);
        default input #3ns;
        input if_pc, if_instr, bus_re, bus_we, bus_addr, bus_wdata,
              bus_width, bus_rdata, bus_ready,
              intr_timer, intr_software, intr_external, intr_spi, intr_i2c;
    endclocking

    // ========== 通用端口 ==========
    modport dut (
        input  clk, rst_n,
        output if_pc,
        input  if_instr,
        output bus_re, bus_we, bus_addr, bus_wdata, bus_width,
        input  bus_rdata, bus_ready,
        input  intr_timer, intr_software, intr_external, intr_spi, intr_i2c
    );

    modport tb (
        input  clk, rst_n,
        output if_instr,
        input  if_pc,
        input  bus_re, bus_we, bus_addr, bus_wdata, bus_width,
        output bus_rdata, bus_ready,
        output intr_timer, intr_software, intr_external, intr_spi, intr_i2c
    );

endinterface
