// tb/tb_nested_soc.v — SoC级嵌套中断验证 (使用 soc_top)
`timescale 1ns/1ps

module tb_nested_soc;

    reg         clk;
    reg         rst_n;

    initial clk = 0;
    always #2.5 clk = ~clk;    // 200MHz

    // DUT: soc_top
    wire        uart_tx;
    wire        spi_sclk, spi_mosi, spi_cs;
    wire        i2c_sda, i2c_scl;
    wire [31:0] gpio_io;

    // GPIO 接口信号 (必须在 soc_top 实例化之前声明)
    wire [31:0] gpio_out_from_soc;
    wire [31:0] gpio_oe_from_soc;
    reg  [31:0] gpio_in_drive;
    reg         gpio_ext_0;

    soc_top u_soc_top (
        .clk_i          (clk),
        .rst_n_i        (rst_n),
        .uart_tx_o      (uart_tx),
        .uart_rx_i      (1'b1),
        .gpio_io        (gpio_io),
        .gpio_in        (gpio_in_drive),
        .gpio_out       (gpio_out_from_soc),
        .gpio_oe        (gpio_oe_from_soc),
        .spi_sclk_o     (spi_sclk),
        .spi_mosi_o     (spi_mosi),
        .spi_miso_i     (1'b0),
        .spi_cs_o       (spi_cs),
        .i2c_sda_io     (i2c_sda),
        .i2c_scl_io     (i2c_scl)
    );

    // 只处理 pin0：外部输入驱动 → GPIO 输入
    always @(*) begin
        gpio_in_drive = 32'b0;
        gpio_in_drive[0] = gpio_ext_0;
    end

    // pin0 双向：SoC输出时驱动 pin，否则外部驱动
    assign gpio_io[0] = gpio_oe_from_soc[0] ? gpio_out_from_soc[0] : 1'bz;
    // 其余 pin 悬空
    assign gpio_io[31:1] = 31'bz;

    // ========================================================================
    // 加载程序到 inst_bram（覆写 bootloader 区域）
    // ========================================================================
    reg [31:0] hex_mem [0:4095];
    integer fd, i, status, nwords;
    reg [31:0] word;

    initial begin
        clk = 0;
        rst_n = 0;
        gpio_ext_0 = 1'b0;

        // 加载 hex
        fd = $fopen("nested_intr_test.hex", "r");
        if (!fd) begin
            $display("[TB] ERROR: Cannot open nested_intr_test.hex");
            $finish;
        end
        nwords = 0;
        while (!$feof(fd) && nwords < 4096) begin
            status = $fscanf(fd, "%h\n", word);
            if (status == 1) begin
                hex_mem[nwords] = word;
                nwords = nwords + 1;
            end
        end
        $fclose(fd);
        $display("[TB] Loaded %0d words from nested_intr_test.hex", nwords);

        // 覆写 inst_bram: 地址 0 开始 = 测试程序
        for (i = 0; i < nwords; i = i + 1)
            u_soc_top.u_inst_bram.mem[i] = hex_mem[i];

        // 剩余填充 NOP
        for (i = nwords; i < 4096; i = i + 1)
            u_soc_top.u_inst_bram.mem[i] = 32'h00000013;

        $display("[TB] Program loaded: %0d words at inst_bram[0:%0d]", nwords, nwords-1);
        $display("[TB] First 4 words: %08h %08h %08h %08h",
                 hex_mem[0], hex_mem[1], hex_mem[2], hex_mem[3]);

        // 复位
        #100;
        rst_n = 1;
        $display("[TB] Reset released at t=%0t", $time);

        // ---- 中断刺激 ----
        // 1. GPIO pin0 上升沿 → 外部中断 (ID=11)
        #800;
        $display("[TB] t=%0t: GPIO0 rising edge → trigger MEI", $time);
        gpio_ext_0 = 1'b1;
        #50;
        gpio_ext_0 = 1'b0;

        // 2. 等待 ISR 执行, 再发第二个中断
        #5000;
        $display("[TB] t=%0t: GPIO0 second rising edge", $time);
        gpio_ext_0 = 1'b1;
        #50;
        gpio_ext_0 = 1'b0;

        // 等待
        #15000;
        $display("[TB] Timeout. Checking results...");
        check_results;
        $finish;
    end

    // ========================================================================
    // 结果检查
    // ========================================================================
    task check_results;
        reg [31:0] tohost_val;
        reg [31:0] nest_count, preempt_flag, timer_count, gpio_count;
        begin
            tohost_val  = u_soc_top.u_data_ram.mem[63];   // 0xFC
            nest_count  = u_soc_top.u_data_ram.mem[64];   // 0x100
            preempt_flag= u_soc_top.u_data_ram.mem[65];   // 0x104
            timer_count = u_soc_top.u_data_ram.mem[66];   // 0x108
            gpio_count  = u_soc_top.u_data_ram.mem[67];   // 0x10C

            $display("============================================");
            $display("  Test Results");
            $display("============================================");
            if (tohost_val == 32'h0)
                $display("  PASS: tohost = 0x%08h", tohost_val);
            else
                $display("  FAIL: tohost = 0x%08h (expected 0)", tohost_val);
            $display("  nest_count   = %0d", nest_count);
            $display("  preempt_flag = 0x%08h", preempt_flag);
            $display("  timer_count  = %0d", timer_count);
            $display("  gpio_count   = %0d", gpio_count);
            $display("============================================");
        end
    endtask

    // ========================================================================
    // VCD 波形
    // ========================================================================
    initial begin
        $dumpfile("nested_soc_wave.vcd");
        $dumpvars(0, tb_nested_soc);
    end

    // ========================================================================
    // 监控
    // ========================================================================
    integer cycle_count;

    always @(posedge clk) begin
        if (rst_n)
            cycle_count <= cycle_count + 1;
        else
            cycle_count <= 0;
    end

    always @(posedge clk) begin
        if (rst_n && (u_soc_top.u_core.bank_ptr != 4'd0 ||
                      u_soc_top.u_core.shadow_save ||
                      u_soc_top.u_core.shadow_restore))
            $display("[%0t] C%0d: bank_ptr=%0d save=%b restore=%b pending=%b",
                     $time, cycle_count,
                     u_soc_top.u_core.bank_ptr,
                     u_soc_top.u_core.shadow_save,
                     u_soc_top.u_core.shadow_restore,
                     u_soc_top.u_core.intr_pending);
    end

    always @(posedge clk) begin
        if (rst_n && u_soc_top.u_core.interrupt_taken_pipe)
            $display("[%0t] C%0d: *** INTR *** PC=%h bank_ptr=%0d",
                     $time, cycle_count,
                     u_soc_top.u_core.if_pc_o,
                     u_soc_top.u_core.bank_ptr);
    end

    // 监控 GPIO 寄存器写
    always @(posedge clk) begin
        if (rst_n && u_soc_top.u_gpio.we_i)
            $display("[%0t] C%0d: GPIO write addr=%h data=%08h",
                     $time, cycle_count,
                     u_soc_top.u_gpio.addr_i,
                     u_soc_top.u_gpio.wdata_i);
    end

endmodule
