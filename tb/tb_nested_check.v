// tb_nested_check.v — 嵌套中断验证 + 详细结果
//
// 参数 USE_INST_ROM:
//   1 (默认) = inst_rom (组合读, 2周期中断延迟)
//   0        = inst_bram (同步读, 3周期中断延迟, FPGA上板用)
//
// 切换方式 (不改代码):
//   vsim -gUSE_INST_ROM=1 work.tb_nested_check    # ROM模式
//   vsim -gUSE_INST_ROM=0 work.tb_nested_check    # BRAM模式
//
`timescale 1ns/1ps
module tb_nested_check #(
    parameter USE_INST_ROM    = 1,   // 1=inst_rom, 0=inst_bram
    parameter SHADOW_BANKS    = 4,   // 影子Bank数量
    parameter OVERFLOW_POLICY = 0    // Bank溢出策略: 0=硬限制, 1=降级复用
);

    reg clk, rst_n;
    initial clk = 0; always #2.5 clk = ~clk;
    wire uart_tx, spi_sclk, spi_mosi, spi_cs, i2c_sda, i2c_scl;
    wire [31:0] gpio_io, gpio_out_s, gpio_oe_s;
    reg [31:0] gpio_in; reg gpio_pin0;
    reg sw_intr;  // 软件中断 (用于三级嵌套测试)

    soc_top #(
        .USE_INST_ROM(USE_INST_ROM),
        .SHADOW_BANKS(SHADOW_BANKS),
        .OVERFLOW_POLICY(OVERFLOW_POLICY)
    ) u_soc_top (
        .clk_i(clk), .rst_n_i(rst_n), .uart_tx_o(uart_tx), .uart_rx_i(1'b1),
        .gpio_io(gpio_io), .gpio_in(gpio_in),
        .gpio_out(gpio_out_s), .gpio_oe(gpio_oe_s),
        .spi_sclk_o(spi_sclk), .spi_mosi_o(spi_mosi),
        .spi_miso_i(1'b0), .spi_cs_o(spi_cs),
        .i2c_sda_io(i2c_sda), .i2c_scl_io(i2c_scl),
        .intr_software_i(sw_intr)
    );
    always @(*) begin gpio_in = 32'b0; gpio_in[0] = gpio_pin0; end
    assign gpio_io[0] = gpio_oe_s[0] ? gpio_out_s[0] : 1'bz;
    assign gpio_io[31:1] = 31'bz;

    // ========================================================================
    // 程序加载: $readmemh → 后门写入 (ROM 或 BRAM, 由 generate 选择路径)
    // ========================================================================
    reg [31:0] hex[0:4095]; integer i, n;
    integer log_file;

    generate
        if (USE_INST_ROM) begin : gen_mem_init
            initial begin
                #1;  // 等待所有模块 initial 块完成, 再后门写入覆盖
                $readmemh("nested_test.hex", hex);
                n = 0; while (hex[n] !== 32'hx && n < 4096) n = n + 1;
                for (i = 0; i < n; i = i + 1)
                    u_soc_top.gen_inst_rom.u_inst_rom.rom[i] = hex[i];
                for (i = n; i < 4096; i = i + 1)
                    u_soc_top.gen_inst_rom.u_inst_rom.rom[i] = 32'h00000013;
            end
        end else begin : gen_mem_init
            initial begin
                #1;  // 等待所有模块 initial 块完成 (inst_bram 的 bootloader), 再覆盖
                $readmemh("nested_test.hex", hex);
                n = 0; while (hex[n] !== 32'hx && n < 4096) n = n + 1;
                for (i = 0; i < n; i = i + 1)
                    u_soc_top.gen_inst_bram.u_inst_bram.mem[i] = hex[i];
                for (i = n; i < 4096; i = i + 1)
                    u_soc_top.gen_inst_bram.u_inst_bram.mem[i] = 32'h00000013;
            end
        end
    endgenerate

    // ========================================================================
    // 主仿真流程
    // ========================================================================
    initial begin
        clk = 0; rst_n = 0; gpio_pin0 = 0; sw_intr = 0;
        // ---- 打开日志文件 (diary/) ----
        log_file = $fopen("diary/nested_test_result.log", "w");
        if (log_file) begin
            $fwrite(log_file, "==== FX-RV32 Nested Interrupt Test Log ====\n");
            $fwrite(log_file, "  inst_mem = %s\n",
                    USE_INST_ROM ? "inst_rom (combinational, 2-cycle latency)" :
                                   "inst_bram (synchronous, 3-cycle latency)");
        end

        #100; rst_n = 1;

        // SW中断触发 (~400ns后, 程序已完成中断配置)
        // 仅 triple_nested_test 使用 (mie[3]=1), 其他测试 mie[3]=0 不受影响
        #400;
        sw_intr = 1; #100; sw_intr = 0;

        // Timer 约在 ~1300ns 触发 (LOAD=200, 配置完成 ~300ns)
        // GPIO 在 ~1600ns 触发 → Timer ISR 的延迟循环中抢占
        #1000;
        $display("[TB] t=%0t: GPIO rise → preempt Timer ISR", $time);
        if (log_file) $fwrite(log_file, "[TB] t=%0t: GPIO rise → preempt Timer ISR\n", $time);
        gpio_pin0 = 1; #50; gpio_pin0 = 0;

        #5000;
        $display("============================================");
        $display("  inst_mem      = %s",
                 USE_INST_ROM ? "inst_rom" : "inst_bram");
        $display("  tohost        = %08h", u_soc_top.u_data_ram.mem[63]);
        $display("  timer_count   = %0d", u_soc_top.u_data_ram.mem[64]);
        $display("  gpio_count    = %0d", u_soc_top.u_data_ram.mem[65]);
        $display("  preempted     = %0d", u_soc_top.u_data_ram.mem[66]);
        $display("  %s", u_soc_top.u_data_ram.mem[63] == 0 ? "PASS" : "FAIL");
        $display("============================================");
        if (log_file) begin
            $fwrite(log_file, "============================================\n");
            $fwrite(log_file, "  inst_mem      = %s\n",
                    USE_INST_ROM ? "inst_rom" : "inst_bram");
            $fwrite(log_file, "  tohost        = %08h\n", u_soc_top.u_data_ram.mem[63]);
            $fwrite(log_file, "  timer_count   = %0d\n", u_soc_top.u_data_ram.mem[64]);
            $fwrite(log_file, "  gpio_count    = %0d\n", u_soc_top.u_data_ram.mem[65]);
            $fwrite(log_file, "  preempted     = %0d\n", u_soc_top.u_data_ram.mem[66]);
            $fwrite(log_file, "  %s\n", u_soc_top.u_data_ram.mem[63] == 0 ? "PASS" : "FAIL");
            $fwrite(log_file, "============================================\n");
        end
        if (log_file) $fclose(log_file);
        $finish;
    end

    initial begin $dumpfile("diary/nested_wave.vcd"); $dumpvars(0, tb_nested_check); end

    integer cyc;
    always @(posedge clk) cyc <= rst_n ? cyc + 1 : 0;
    always @(posedge clk)
        if (rst_n && u_soc_top.u_core.bank_ptr != 0) begin
            $display("[%0t] C%0d: bank_ptr=%0d save=%b restore=%b",
                     $time, cyc, u_soc_top.u_core.bank_ptr,
                     u_soc_top.u_core.shadow_save,
                     u_soc_top.u_core.shadow_restore);
            if (log_file)
                $fwrite(log_file, "[%0t] C%0d: bank_ptr=%0d save=%b restore=%b\n",
                        $time, cyc, u_soc_top.u_core.bank_ptr,
                        u_soc_top.u_core.shadow_save,
                        u_soc_top.u_core.shadow_restore);
        end
    always @(posedge clk)
        if (rst_n && u_soc_top.u_core.interrupt_taken_pipe) begin
            $display("[%0t] C%0d: *** INTR TAKEN *** bank_ptr=%0d",
                     $time, cyc, u_soc_top.u_core.bank_ptr);
            if (log_file)
                $fwrite(log_file, "[%0t] C%0d: *** INTR TAKEN *** bank_ptr=%0d\n",
                        $time, cyc, u_soc_top.u_core.bank_ptr);
        end

    // MRET 检测 (id_ex_mret 持续一拍)
    always @(posedge clk)
        if (rst_n && u_soc_top.u_core.id_ex_mret) begin
            $display("[%0t] C%0d: *** MRET *** bank_ptr=%0d restore=%b",
                     $time, cyc, u_soc_top.u_core.bank_ptr,
                     u_soc_top.u_core.shadow_restore);
            if (log_file)
                $fwrite(log_file, "[%0t] C%0d: *** MRET *** bank_ptr=%0d restore=%b\n",
                        $time, cyc, u_soc_top.u_core.bank_ptr,
                        u_soc_top.u_core.shadow_restore);
        end

    // data_ram 写入监视 (地址 0x100, 0x104, 0x108 = mem[64,65,66])
    always @(posedge clk)
        if (rst_n && u_soc_top.u_data_ram.we_i) begin
            $display("[%0t] C%0d: RAM_WR addr=%08h data=%08h (mem[%0d])",
                     $time, cyc, u_soc_top.u_data_ram.addr_i,
                     u_soc_top.u_data_ram.wdata_i,
                     u_soc_top.u_data_ram.addr_i[11:2]);
            if (log_file)
                $fwrite(log_file, "[%0t] C%0d: RAM_WR addr=%08h data=%08h (mem[%0d])\n",
                        $time, cyc, u_soc_top.u_data_ram.addr_i,
                        u_soc_top.u_data_ram.wdata_i,
                        u_soc_top.u_data_ram.addr_i[11:2]);
        end

    // CPU 总线输出 + RAM 仲裁监视
    always @(posedge clk)
        if (rst_n && u_soc_top.core_bus_we) begin
            $display("[%0t] C%0d: CPU_WR busaddr=%08h wdata=%08h ram_we=%b",
                     $time, cyc, u_soc_top.core_bus_addr,
                     u_soc_top.core_bus_wdata, u_soc_top.bus_ram_we);
            if (log_file)
                $fwrite(log_file, "[%0t] C%0d: CPU_WR busaddr=%08h wdata=%08h ram_we=%b\n",
                        $time, cyc, u_soc_top.core_bus_addr,
                        u_soc_top.core_bus_wdata, u_soc_top.bus_ram_we);
        end

    // IF PC + 当前指令监视 + 关键流水线信号
    always @(posedge clk)
        if (rst_n && (cyc < 50 || u_soc_top.u_core.interrupt_taken_pipe || u_soc_top.u_core.id_ex_mret)) begin
            $display("[%0t] C%0d: PC=%08h INSTR=%08h IFID={pc=%08h instr=%08h} IDEX={pc=%08h br=%b jmp=%b} EX={bt=%b jt=%b} FWD={A=%0d B=%0d} FLUSH={if=%b id=%b}",
                     $time, cyc,
                     u_soc_top.u_core.if_pc,
                     u_soc_top.u_core.if_instr_i,
                     u_soc_top.u_core.if_id_pc,
                     u_soc_top.u_core.if_id_instr,
                     u_soc_top.u_core.id_ex_pc,
                     u_soc_top.u_core.id_ex_branch,
                     u_soc_top.u_core.id_ex_jump,
                     u_soc_top.u_core.ex_branch_taken,
                     u_soc_top.u_core.ex_jump_taken,
                     u_soc_top.u_core.forwardA,
                     u_soc_top.u_core.forwardB,
                     u_soc_top.u_core.flush_if,
                     u_soc_top.u_core.flush_id);
            if (log_file)
                $fwrite(log_file, "[%0t] C%0d: PC=%08h INSTR=%08h IFID={pc=%08h instr=%08h} IDEX={pc=%08h br=%b jmp=%b} EX={bt=%b jt=%b} FWD={A=%0d B=%0d} FLUSH={if=%b id=%b}\n",
                        $time, cyc,
                        u_soc_top.u_core.if_pc,
                        u_soc_top.u_core.if_instr_i,
                        u_soc_top.u_core.if_id_pc,
                        u_soc_top.u_core.if_id_instr,
                        u_soc_top.u_core.id_ex_pc,
                        u_soc_top.u_core.id_ex_branch,
                        u_soc_top.u_core.id_ex_jump,
                        u_soc_top.u_core.ex_branch_taken,
                        u_soc_top.u_core.ex_jump_taken,
                        u_soc_top.u_core.forwardA,
                        u_soc_top.u_core.forwardB,
                        u_soc_top.u_core.flush_if,
                        u_soc_top.u_core.flush_id);
        end

endmodule
