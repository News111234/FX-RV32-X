// tb/tb_nested_intr.v — 多Bank影子寄存器嵌套中断验证测试平台
`timescale 1ns/1ps

module tb_nested_intr;

    // ========================================================================
    // 时钟和复位
    // ========================================================================
    reg         clk;
    reg         rst_n;

    // 200MHz 时钟 (周期 5ns)
    initial clk = 0;
    always #2.5 clk = ~clk;

    // ========================================================================
    // 指令ROM和数据RAM
    // ========================================================================
    reg  [31:0] inst_rom [0:4095];
    reg  [31:0] data_ram [0:1023];  // 4KB

    // ========================================================================
    // core_top接口
    // ========================================================================
    wire [31:0] if_pc;
    wire [31:0] if_instr;
    wire        bus_re;
    wire        bus_we;
    wire [31:0] bus_addr;
    wire [31:0] bus_wdata;
    wire [2:0]  bus_width;
    wire [31:0] bus_rdata;
    wire        bus_ready;

    reg         intr_timer;
    reg         intr_software;
    reg         intr_external;
    reg         intr_spi;
    reg         intr_i2c;

    // 中断源
    reg         gpio_intr_req;      // GPIO中断请求 (模拟外部中断)
    reg         timer_intr_req;     // 定时器中断请求

    wire        gpio_interrupt;
    wire        timer_interrupt;
    wire        core_if_pc;

    // ========================================================================
    // DUT: core_top (多Bank版本)
    // ========================================================================
    core_top u_core_top (
        .clk_i          (clk),
        .rst_n_i        (rst_n),
        .if_pc_o        (if_pc),
        .if_instr_i     (if_instr),
        .bus_re_o       (bus_re),
        .bus_we_o       (bus_we),
        .bus_addr_o     (bus_addr),
        .bus_wdata_o    (bus_wdata),
        .bus_width_o    (bus_width),
        .bus_rdata_i    (bus_rdata),
        .bus_ready_i    (bus_ready),
        .intr_timer_i   (intr_timer),
        .intr_software_i(intr_software),
        .intr_external_i(intr_external),
        .intr_spi_i     (intr_spi),
        .intr_i2c_i     (intr_i2c)
    );

    // ========================================================================
    // 指令ROM (组合逻辑读)
    // ========================================================================
    assign if_instr = inst_rom[if_pc[31:2]];

    // ========================================================================
    // 数据RAM和总线响应
    // ========================================================================
    assign bus_ready = 1'b1;  // 单周期响应

    wire [31:2] ram_word_addr = bus_addr[31:2];

    // 读数据MUX: RAM范围 或 tohost
    reg [31:0] bus_rdata_reg;
    always @(*) begin
        if (bus_addr >= 32'h0000_0000 && bus_addr < 32'h0000_1000) begin
            bus_rdata_reg = data_ram[ram_word_addr];
        end else if (bus_addr == 32'h0000_00FC) begin
            // tohost: 读回0
            bus_rdata_reg = 32'h0;
        end else begin
            bus_rdata_reg = 32'h0;
        end
    end
    assign bus_rdata = bus_rdata_reg;

    // 写数据RAM
    always @(posedge clk) begin
        if (bus_we && bus_addr < 32'h0000_1000) begin
            case (bus_width)
                3'b000: begin  // SB
                    case (bus_addr[1:0])
                        2'b00: data_ram[ram_word_addr][7:0]   <= bus_wdata[7:0];
                        2'b01: data_ram[ram_word_addr][15:8]  <= bus_wdata[7:0];
                        2'b10: data_ram[ram_word_addr][23:16] <= bus_wdata[7:0];
                        2'b11: data_ram[ram_word_addr][31:24] <= bus_wdata[7:0];
                    endcase
                end
                3'b001: begin  // SH
                    if (bus_addr[1])  // 半字对齐
                        data_ram[ram_word_addr][31:16] <= bus_wdata[15:0];
                    else
                        data_ram[ram_word_addr][15:0]  <= bus_wdata[15:0];
                end
                3'b010: begin  // SW
                    data_ram[ram_word_addr] <= bus_wdata;
                end
                default: ;
            endcase
        end
    end

    // ========================================================================
    // 中断信号生成
    // ========================================================================
    // GPIO中断 (连到external)
    assign gpio_interrupt  = gpio_intr_req;
    // 定时器中断
    assign timer_interrupt = timer_intr_req;

    // 中断连接
    always @(*) begin
        intr_external = gpio_interrupt;
        intr_timer    = timer_interrupt;
        intr_software = 1'b0;
        intr_spi      = 1'b0;
        intr_i2c      = 1'b0;
    end

    // ========================================================================
    // 测试程序加载 (从hex文件)
    // ========================================================================
    integer fd, i, status;
    reg [31:0] hex_word;

    initial begin
        // 初始化
        clk           = 0;
        rst_n         = 0;
        gpio_intr_req = 0;
        timer_intr_req = 0;

        // 清零存储器
        for (i = 0; i < 4096; i = i + 1) inst_rom[i] = 32'h00000013; // NOP
        for (i = 0; i < 1024; i = i + 1) data_ram[i]  = 32'h0;

        // 加载hex程序
        fd = $fopen("nested_intr_test.hex", "r");
        if (fd) begin
            i = 0;
            while (!$feof(fd) && i < 4096) begin
                status = $fscanf(fd, "%h\n", hex_word);
                if (status == 1) begin
                    inst_rom[i] = hex_word;
                    i = i + 1;
                end
            end
            $fclose(fd);
            $display("[TB] Loaded %0d instructions from nested_intr_test.hex", i);
        end else begin
            $display("[TB] ERROR: Cannot open nested_intr_test.hex");
            $finish;
        end

        // 释放复位
        #100;
        rst_n = 1;
        $display("[TB] Reset released at t=%0t", $time);

        // ---- 中断刺激序列 ----
        // 1. 先触发定时器中断 (优先级7, 较低)
        #500;
        $display("[TB] t=%0t: Triggering Timer interrupt (priority 7)...", $time);
        timer_intr_req = 1;
        #50;
        timer_intr_req = 0;

        // 2. 在定时器ISR执行期间, 触发GPIO中断 (优先级11, 更高) → 抢占
        #200;
        $display("[TB] t=%0t: Triggering GPIO interrupt (priority 11) → should PREEMPT Timer ISR", $time);
        gpio_intr_req = 1;
        #50;
        gpio_intr_req = 0;

        // 3. 等待一段时间后触发第二次定时器中断 (验证返回)
        #2000;
        $display("[TB] t=%0t: Triggering second Timer interrupt...", $time);
        timer_intr_req = 1;
        #50;
        timer_intr_req = 0;

        // 4. 再触发GPIO抢占
        #300;
        $display("[TB] t=%0t: Triggering second GPIO interrupt → should PREEMPT again", $time);
        gpio_intr_req = 1;
        #50;
        gpio_intr_req = 0;

        // 等待完成
        #5000;
        $display("[TB] Simulation timeout. Checking results...");
        check_results;
        $finish;
    end

    // ========================================================================
    // 结果检查
    // ========================================================================
    task check_results;
        begin
            $display("============================================");
            $display("  Test Results");
            $display("============================================");
            // tohost at 0xFC (word address 63)
            if (data_ram[63] == 32'h0)
                $display("  PASS: tohost = 0x%08h", data_ram[63]);
            else
                $display("  FAIL: tohost = 0x%08h", data_ram[63]);

            // 检查嵌套标志
            $display("  nest_count  (addr 0x80) = %0d", data_ram[32]);
            $display("  preempt_flag(addr 0x84) = 0x%08h", data_ram[33]);
            $display("  timer_count (addr 0x88) = %0d", data_ram[34]);
            $display("  gpio_count  (addr 0x8C) = %0d", data_ram[35]);
            $display("============================================");
        end
    endtask

    // ========================================================================
    // 波形输出
    // ========================================================================
    initial begin
        $dumpfile("nested_intr_wave.vcd");
        $dumpvars(0, tb_nested_intr);
        $dumpvars(1, u_core_top.if_pc);
        $dumpvars(1, u_core_top.if_instr_i);
        $dumpvars(1, u_core_top.bank_ptr);
        $dumpvars(1, u_core_top.shadow_save);
        $dumpvars(1, u_core_top.shadow_restore);
        $dumpvars(1, u_core_top.interrupt_taken_pipe);
        $dumpvars(1, u_core_top.intr_take_now);
        $dumpvars(1, u_core_top.intr_pending);
        $dumpvars(1, u_core_top.allow_nesting);
        $dumpvars(1, u_core_top.bank_full);
    end

    // ========================================================================
    // 仿真监控
    // ========================================================================
    integer cycle_count;
    always @(posedge clk) begin
        if (rst_n)
            cycle_count <= cycle_count + 1;
        else
            cycle_count <= 0;
    end

    // 监控Bank状态变化
    always @(posedge clk) begin
        if (rst_n && u_core_top.bank_ptr != 4'd0)
            $display("[%0t] Cycle %0d: bank_ptr=%0d, shadow_save=%b, shadow_restore=%b",
                     $time, cycle_count,
                     u_core_top.bank_ptr,
                     u_core_top.shadow_save,
                     u_core_top.shadow_restore);
    end

    // 监控中断进入
    always @(posedge clk) begin
        if (rst_n && u_core_top.interrupt_taken_pipe)
            $display("[%0t] Cycle %0d: *** INTERRUPT TAKEN *** PC=%h, bank_ptr=%0d",
                     $time, cycle_count, if_pc, u_core_top.bank_ptr);
    end

endmodule
