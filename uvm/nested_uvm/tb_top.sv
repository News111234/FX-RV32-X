// nested_uvm/tb_top.sv — UVM顶层 (soc_top DUT, 论文测试专用)
`timescale 1ns/1ps

module tb_top #(
    parameter USE_INST_ROM    = 1,
    parameter SHADOW_BANKS    = 4,
    parameter OVERFLOW_POLICY = 0
);

    import uvm_pkg::*;
    import nested_uvm_pkg::*;

    // 时钟与复位 (200MHz)
    reg clk = 0;
    reg rst_n = 0;
    always #2.5 clk = ~clk;

    // 接口
    cpu_if vif (.clk(clk), .rst_n(rst_n));

    // ===== DUT: soc_top =====
    wire        uart_tx;
    wire [31:0] gpio_io, gpio_out, gpio_oe;
    wire [31:0] gpio_in;
    wire        spi_sclk, spi_mosi, spi_cs;
    wire        i2c_sda, i2c_scl;

    assign gpio_in = {31'b0, vif.gpio_pin0};
    assign gpio_io[0] = gpio_oe[0] ? gpio_out[0] : 1'bz;
    assign gpio_io[31:1] = 31'bz;

    soc_top #(
        .USE_INST_ROM(USE_INST_ROM),
        .SHADOW_BANKS(SHADOW_BANKS),
        .OVERFLOW_POLICY(OVERFLOW_POLICY)
    ) u_soc_top (
        .clk_i(clk),
        .rst_n_i(rst_n),
        .uart_tx_o(uart_tx),
        .uart_rx_i(1'b1),
        .gpio_io(gpio_io),
        .gpio_in(gpio_in),
        .gpio_out(gpio_out),
        .gpio_oe(gpio_oe),
        .spi_sclk_o(spi_sclk),
        .spi_mosi_o(spi_mosi),
        .spi_miso_i(1'b0),
        .spi_cs_o(spi_cs),
        .i2c_sda_io(i2c_sda),
        .i2c_scl_io(i2c_scl),
        .intr_software_i(vif.intr_software)
    );

    // ===== hex程序加载到inst_rom =====
    // 经由soc_top内部的inst_rom后门写入
    // (UVM driver负责此操作)

    // ===== 启动UVM =====
    initial begin
        uvm_config_db #(virtual cpu_if)::set(null, "*", "vif", vif);
        run_test();
    end

endmodule
