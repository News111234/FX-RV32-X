// tb/tb_gpio_basic.v — GPIO 中断测试
`timescale 1ns/1ps
module tb_gpio_basic;

    reg clk, rst_n;
    initial clk = 0;
    always #2.5 clk = ~clk;

    wire uart_tx, spi_sclk, spi_mosi, spi_cs, i2c_sda, i2c_scl;
    wire [31:0] gpio_io, gpio_out_s, gpio_oe_s;
    reg  [31:0] gpio_in;
    reg  gpio_pin0;

    // DUT
    soc_top u_soc_top (
        .clk_i(clk), .rst_n_i(rst_n),
        .uart_tx_o(uart_tx), .uart_rx_i(1'b1),
        .gpio_io(gpio_io), .gpio_in(gpio_in),
        .gpio_out(gpio_out_s), .gpio_oe(gpio_oe_s),
        .spi_sclk_o(spi_sclk), .spi_mosi_o(spi_mosi),
        .spi_miso_i(1'b0), .spi_cs_o(spi_cs),
        .i2c_sda_io(i2c_sda), .i2c_scl_io(i2c_scl)
    );

    always @(*) begin gpio_in = 32'b0; gpio_in[0] = gpio_pin0; end
    assign gpio_io[0] = gpio_oe_s[0] ? gpio_out_s[0] : 1'bz;
    assign gpio_io[31:1] = 31'bz;

    // 程序加载 & 测试主流程
    reg [31:0] hex[0:4095]; integer i, n; reg [31:0] tohost_val;
    initial begin
        clk = 0; rst_n = 0; gpio_pin0 = 0;
        $readmemh("gpio_basic_test.hex", hex);
        n = 0; while (hex[n] !== 32'hx && n < 4096) n = n + 1;
        for (i = 0; i < n; i = i + 1) u_soc_top.u_inst_bram.mem[i] = hex[i];
        for (i = n; i < 4096; i = i + 1) u_soc_top.u_inst_bram.mem[i] = 32'h00000013;
        $display("[TB] Loaded %0d words", n);

        #100; rst_n = 1; $display("[TB] Reset released");

        // GPIO 中断 1
        #600; $display("[TB] t=%0t: GPIO0 rise #1", $time);
        gpio_pin0 = 1; #50; gpio_pin0 = 0;

        // 等 ISR 处理完
        #800; tohost_val = u_soc_top.u_data_ram.mem[63];
        $display("[TB] After IRQ1: tohost=%08h", tohost_val);

        // GPIO 中断 2
        $display("[TB] t=%0t: GPIO0 rise #2", $time);
        gpio_pin0 = 1; #50; gpio_pin0 = 0;

        #800; tohost_val = u_soc_top.u_data_ram.mem[63];
        $display("[TB] After IRQ2: tohost=%08h", tohost_val);

        $display("============================================");
        $display("  tohost=%08h  %s", tohost_val, tohost_val == 32'h0 ? "PASS" : "FAIL");
        $display("============================================");
        $finish;
    end

    // 波形
    initial begin $dumpfile("gpio_test.vcd"); $dumpvars(0, tb_gpio_basic); end

    // 监控
    integer cyc;
    always @(posedge clk) cyc <= rst_n ? cyc + 1 : 0;
    always @(posedge clk)
        if (rst_n && u_soc_top.u_core.interrupt_taken_pipe)
            $display("[%0t] C%0d: INTR bank_ptr=%0d PC=%h",
                     $time, cyc, u_soc_top.u_core.bank_ptr, u_soc_top.u_core.if_pc_o);

endmodule
