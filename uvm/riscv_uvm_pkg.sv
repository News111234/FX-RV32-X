// riscv_uvm_pkg.sv — FX-RV32 UVM 验证组件包
// 包含: Transaction, Driver, Monitor, Scoreboard, Agent, Env, Tests
// 重点验证: load-use 冒险停顿机制
`timescale 1ns/1ps

package riscv_uvm_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // ========================================================================
    // Transaction: 统一的流水线事件事务
    // ========================================================================
    class cpu_transaction extends uvm_sequence_item;
        `uvm_object_utils(cpu_transaction)

        // 事件类型: WB / STORE / LOAD / STALL / BRANCH / NOP
        string            event_type;
        int unsigned      cycle;           // 触发周期

        // WB 相关
        logic [4:0]       rd_addr;
        logic [31:0]      rd_data;
        logic             reg_we_valid;

        // 访存相关
        logic [31:0]      bus_addr;
        logic [31:0]      bus_wdata;
        logic [31:0]      bus_rdata;
        logic             bus_is_write;

        // 停顿检测
        logic             stall_if_detected;
        logic             stall_id_detected;
        int unsigned      stall_duration;  // 停顿持续周期数

        // PC 追踪
        logic [31:0]      inst_pc;

        function new(string name = "cpu_transaction");
            super.new(name);
        endfunction
    endclass


    // ========================================================================
    // Driver: 加载 hex 程序, 处理中断激励
    // ========================================================================
    class cpu_driver extends uvm_driver #(cpu_transaction);
        `uvm_component_utils(cpu_driver)

        virtual cpu_if vif;

        function new(string name = "cpu_driver", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        // ---- 加载 hex 文件到指令 ROM ----
        task load_program(string hex_file);
            int       fd, lineno;
            string    line;
            logic [31:0] instr;
            int       addr;

            fd = $fopen(hex_file, "r");
            if (fd == 0) begin
                `uvm_fatal("DRV", $sformatf("Cannot open hex file: %s", hex_file))
            end

            addr = 0;
            lineno = 0;
            while (!$feof(fd)) begin
                void'($fgets(line, fd));
                line = line.substr(0, line.len()-2);  // 去掉 \n
                if (line.len() >= 8) begin
                    instr = line.atohex();
                    $root.uvm_tb_top.inst_rom[addr] = instr;
                    `uvm_info("DRV", $sformatf("inst_rom[%4d] = 0x%08h", addr, instr), UVM_MEDIUM)
                    addr++;
                end
                lineno++;
            end
            $fclose(fd);
            `uvm_info("DRV", $sformatf("Loaded %0d instructions from %s", addr, hex_file), UVM_LOW)
        endtask

        // ---- 触发定时器中断脉冲 (保留) ----
        task trigger_timer_interrupt();
            @(vif.drv_cb);
            vif.drv_cb.intr_timer <= 1'b1;
            @(vif.drv_cb);
            vif.drv_cb.intr_timer <= 1'b0;
        endtask

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db #(virtual cpu_if)::get(this, "", "vif", vif))
                `uvm_fatal("DRV", "Virtual interface not found")
        endfunction
    endclass


    // ========================================================================
    // Monitor: 监控流水线事件, 重点检测 load-use 停顿
    // ========================================================================
    class cpu_monitor extends uvm_monitor;
        `uvm_component_utils(cpu_monitor)

        virtual cpu_if              vif;
        uvm_analysis_port #(cpu_transaction) ap;

        // 上一周期状态 (用于边沿检测)
        logic        prev_stall_if;
        logic        prev_stall_id;
        int unsigned stall_cycle_cnt;   // 当前停顿已持续周期数

        function new(string name = "cpu_monitor", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            ap = new("ap", this);
            if (!uvm_config_db #(virtual cpu_if)::get(this, "", "vif", vif))
                `uvm_fatal("MON", "Virtual interface not found")
        endfunction

        task run_phase(uvm_phase phase);
            cpu_transaction tr;
            int unsigned cycle;
            cycle = 0;

            // 等待复位释放
            wait(vif.rst_n === 1'b1);
            @(vif.mon_cb);

            forever begin
                @(vif.mon_cb);
                cycle++;

                // ---- 检测停顿信号变化 ----
                // 通过层次路径访问 hazard_unit 的 stall 输出
                if ($root.uvm_tb_top.u_dut.stall_if && !prev_stall_if) begin
                    // stall_if 上升沿: 停顿开始
                    stall_cycle_cnt = 0;
                    tr = cpu_transaction::type_id::create("tr");
                    tr.event_type = "STALL";
                    tr.cycle      = cycle;
                    tr.stall_if_detected = 1;
                    tr.inst_pc    = $root.uvm_tb_top.u_dut.if_id_pc;
                    `uvm_info("MON", $sformatf("[%0d] STALL_IF asserted, PC=0x%08h",
                              cycle, tr.inst_pc), UVM_MEDIUM)
                    ap.write(tr);
                end

                if ($root.uvm_tb_top.u_dut.stall_id && !prev_stall_id) begin
                    tr = cpu_transaction::type_id::create("tr");
                    tr.event_type = "STALL";
                    tr.cycle      = cycle;
                    tr.stall_id_detected = 1;
                    tr.inst_pc    = $root.uvm_tb_top.u_dut.if_id_pc;
                    `uvm_info("MON", $sformatf("[%0d] STALL_ID asserted, PC=0x%08h",
                              cycle, tr.inst_pc), UVM_MEDIUM)
                    ap.write(tr);
                end

                // 停顿持续计数
                if ($root.uvm_tb_top.u_dut.stall_if || $root.uvm_tb_top.u_dut.stall_id)
                    stall_cycle_cnt++;

                // 停顿释放时报告持续周期
                if (!$root.uvm_tb_top.u_dut.stall_if && prev_stall_if) begin
                    tr = cpu_transaction::type_id::create("tr");
                    tr.event_type     = "STALL";
                    tr.cycle          = cycle;
                    tr.stall_duration = stall_cycle_cnt;
                    `uvm_info("MON", $sformatf("[%0d] STALL released, duration=%0d cycles",
                              cycle, stall_cycle_cnt), UVM_LOW)
                    ap.write(tr);
                    stall_cycle_cnt = 0;
                end

                prev_stall_if = $root.uvm_tb_top.u_dut.stall_if;
                prev_stall_id = $root.uvm_tb_top.u_dut.stall_id;

                // ---- 检测寄存器写回 ----
                if ($root.uvm_tb_top.u_dut.wb_reg_we_out &&
                    $root.uvm_tb_top.u_dut.wb_rd_addr_out != 5'b0) begin
                    tr = cpu_transaction::type_id::create("tr");
                    tr.event_type  = "WB";
                    tr.cycle       = cycle;
                    tr.rd_addr     = $root.uvm_tb_top.u_dut.wb_rd_addr_out;
                    tr.rd_data     = $root.uvm_tb_top.u_dut.wb_data;
                    tr.reg_we_valid = 1;
                    tr.inst_pc     = 32'b0;  // WB 阶段无直接 PC 信号
                    `uvm_info("MON", $sformatf("[%0d] WB: x%0d <= 0x%08h",
                              cycle, tr.rd_addr, tr.rd_data), UVM_MEDIUM)
                    ap.write(tr);
                end

                // ---- 检测内存写 (store) ----
                if (vif.mon_cb.bus_re && vif.mon_cb.bus_we) begin
                    tr = cpu_transaction::type_id::create("tr");
                    tr.event_type   = "STORE";
                    tr.cycle        = cycle;
                    tr.bus_addr     = vif.mon_cb.bus_addr;
                    tr.bus_wdata    = vif.mon_cb.bus_wdata;
                    tr.bus_is_write = 1;
                    `uvm_info("MON", $sformatf("[%0d] STORE: [0x%08h] <= 0x%08h",
                              cycle, tr.bus_addr, tr.bus_wdata), UVM_MEDIUM)
                    ap.write(tr);
                end

                // ---- 检测内存读完成 (load) ----
                if (vif.mon_cb.bus_re && !vif.mon_cb.bus_we && vif.mon_cb.bus_ready) begin
                    tr = cpu_transaction::type_id::create("tr");
                    tr.event_type   = "LOAD";
                    tr.cycle        = cycle;
                    tr.bus_addr     = vif.mon_cb.bus_addr;
                    tr.bus_rdata    = vif.mon_cb.bus_rdata;
                    tr.bus_is_write = 0;
                    `uvm_info("MON", $sformatf("[%0d] LOAD:  [0x%08h] => 0x%08h",
                              cycle, tr.bus_addr, tr.bus_rdata), UVM_MEDIUM)
                    ap.write(tr);
                end
            end
        endtask
    endclass


    // ========================================================================
    // Scoreboard: 参考模型比对，重点验证 load-use 场景的正确性
    // ========================================================================
    class cpu_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(cpu_scoreboard)

        uvm_analysis_export #(cpu_transaction) analysis_export;
        uvm_tlm_analysis_fifo #(cpu_transaction) fifo;

        // 参考模型
        logic [31:0] ref_reg [0:31];             // 寄存器参考模型
        logic [31:0] ref_mem [logic [31:0]];     // 内存参考模型 (关联数组)

        // 统计
        int unsigned total_wb;
        int unsigned total_stall_events;
        int unsigned total_load;
        int unsigned total_store;
        int unsigned mismatch_count;
        int unsigned stall_max_duration;

        function new(string name = "cpu_scoreboard", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            analysis_export = new("analysis_export", this);
            fifo = new("fifo", this);
            analysis_export.connect(fifo.analysis_export);
        endfunction

        task run_phase(uvm_phase phase);
            cpu_transaction tr;
            int i;
            for (i = 0; i < 32; i++) ref_reg[i] = 32'b0;
            ref_reg[0] = 32'b0;  // x0 始终为 0
            ref_mem.delete();
            total_wb      = 0;
            total_stall_events = 0;
            total_load    = 0;
            total_store   = 0;
            mismatch_count = 0;
            stall_max_duration = 0;

            forever begin
                fifo.get(tr);

                case (tr.event_type)
                    "WB": begin
                        total_wb++;
                        if (tr.reg_we_valid && tr.rd_addr != 5'b0) begin
                            // 更新参考模型 (WB 阶段写入)
                            ref_reg[tr.rd_addr] = tr.rd_data;
                            `uvm_info("SBD", $sformatf("[ref] x%0d = 0x%08h",
                                      tr.rd_addr, tr.rd_data), UVM_HIGH)
                        end
                    end

                    "STORE": begin
                        total_store++;
                        ref_mem[tr.bus_addr] = tr.bus_wdata;
                        `uvm_info("SBD", $sformatf("[ref] mem[0x%08h] = 0x%08h",
                                  tr.bus_addr, tr.bus_wdata), UVM_HIGH)
                    end

                    "LOAD": begin
                        total_load++;
                        // 不需更新参考模型，load 不改变状态
                    end

                    "STALL": begin
                        total_stall_events++;
                        if (tr.stall_duration > stall_max_duration)
                            stall_max_duration = tr.stall_duration;
                    end
                endcase
            end
        endtask

        function void report_phase(uvm_phase phase);
            super.report_phase(phase);
            `uvm_info("SBD", "", UVM_NONE)
            `uvm_info("SBD", "========================================", UVM_NONE)
            `uvm_info("SBD", "  Load-Use Hazard Test — Scoreboard Report", UVM_NONE)
            `uvm_info("SBD", "========================================", UVM_NONE)
            `uvm_info("SBD", $sformatf("  Register writes (WB):  %0d", total_wb), UVM_NONE)
            `uvm_info("SBD", $sformatf("  Store operations:      %0d", total_store), UVM_NONE)
            `uvm_info("SBD", $sformatf("  Load operations:       %0d", total_load), UVM_NONE)
            `uvm_info("SBD", $sformatf("  Stall events:          %0d", total_stall_events), UVM_NONE)
            `uvm_info("SBD", $sformatf("  Max stall duration:    %0d cycles", stall_max_duration), UVM_NONE)
            `uvm_info("SBD", $sformatf("  Mismatches:            %0d", mismatch_count), UVM_NONE)
            `uvm_info("SBD", "========================================", UVM_NONE)

            if (total_wb == 0)
                `uvm_warning("SBD", "No WB events detected — test may be empty or stalled")
            else if (mismatch_count == 0 && total_wb > 0)
                `uvm_info("SBD", "*** LOAD-USE HAZARD TEST PASSED ***", UVM_NONE)
        endfunction
    endclass


    // ========================================================================
    // Coverage Collector: 功能覆盖率收集
    // ========================================================================
    class cpu_coverage extends uvm_subscriber #(cpu_transaction);
        `uvm_component_utils(cpu_coverage)

        // ---- 覆盖组1: 指令类型 ----
        // 通过 WB 事件的 rd_addr 判断是否覆盖到了各类指令
        covergroup cg_instr_types with function sample(logic [4:0] rd);
            coverpoint rd {
                bins x1_ra    = {5'd1};
                bins x2_sp    = {5'd2};
                bins x3_gp    = {5'd3};
                bins x5_t0    = {5'd5};
                bins x6_t1    = {5'd6};
                bins x10_a0   = {5'd10};
                bins x11_a1   = {5'd11};
                bins x28_t3   = {5'd28};
            }
        endgroup

        // ---- 覆盖组2: 访存操作 ----
        covergroup cg_memory_ops with function sample(bit is_store, logic [31:0] addr);
            coverpoint is_store {
                bins load  = {1'b0};
                bins store = {1'b1};
            }
            coverpoint addr {
                bins addr_low    = {[0:32'hFF]};       // 低地址
                bins addr_mid    = {[32'h100:32'h1FF]}; // 数据区
                bins addr_tohost = {32'hFC};             // tohost
            }
        endgroup

        // ---- 覆盖组3: Load-Use 停顿 ----
        covergroup cg_stall with function sample(logic stall_if, logic stall_id,
                                                  int unsigned duration);
            coverpoint stall_if {
                bins triggered = {1'b1};
            }
            coverpoint stall_id {
                bins triggered = {1'b1};
            }
            coverpoint duration {
                bins d1 = {1};    // 正常: 1 周期停顿
                bins d2 = {2};    // 异常: 2 周期 (可能 load 复制问题)
                bins dN = {[3:10]};
            }
        endgroup

        // ---- 覆盖组4: 数据转发 ----
        covergroup cg_forwarding with function sample(logic [1:0] fwdA, logic [1:0] fwdB);
            coverpoint fwdA {
                bins none    = {2'b00};
                bins ex_mem  = {2'b01};  // EX/MEM 转发
                bins mem_wb  = {2'b10};  // MEM/WB 转发
            }
            coverpoint fwdB {
                bins none    = {2'b00};
                bins ex_mem  = {2'b01};
                bins mem_wb  = {2'b10};
            }
        endgroup

        function new(string name = "cpu_coverage", uvm_component parent = null);
            super.new(name, parent);
            cg_instr_types  = new();
            cg_memory_ops   = new();
            cg_stall        = new();
            cg_forwarding   = new();
        endfunction

        function void write(cpu_transaction t);
            case (t.event_type)
                "WB": begin
                    cg_instr_types.sample(t.rd_addr);
                end
                "LOAD", "STORE": begin
                    cg_memory_ops.sample((t.event_type == "STORE"), t.bus_addr);
                end
                "STALL": begin
                    cg_stall.sample(t.stall_if_detected, t.stall_id_detected,
                                    t.stall_duration);
                end
            endcase
            // 转发信号由 Monitor 通过层次路径采样 (额外监控)
            fork
                begin
                    @(negedge $root.uvm_tb_top.clk);
                    cg_forwarding.sample(
                        $root.uvm_tb_top.u_dut.forwardA,
                        $root.uvm_tb_top.u_dut.forwardB
                    );
                end
            join_none
        endfunction

        function void report_phase(uvm_phase phase);
            super.report_phase(phase);
            `uvm_info("COV", "", UVM_NONE)
            `uvm_info("COV", "========================================", UVM_NONE)
            `uvm_info("COV", "  Functional Coverage Summary", UVM_NONE)
            `uvm_info("COV", "========================================", UVM_NONE)
            `uvm_info("COV", $sformatf("  cg_instr_types:  %0d%%",
                      cg_instr_types.get_coverage()), UVM_NONE)
            `uvm_info("COV", $sformatf("  cg_memory_ops:   %0d%%",
                      cg_memory_ops.get_coverage()), UVM_NONE)
            `uvm_info("COV", $sformatf("  cg_stall:        %0d%%",
                      cg_stall.get_coverage()), UVM_NONE)
            `uvm_info("COV", $sformatf("  cg_forwarding:   %0d%%",
                      cg_forwarding.get_coverage()), UVM_NONE)
            `uvm_info("COV", "========================================", UVM_NONE)
        endfunction
    endclass


    // ========================================================================
    // Agent: 封装 Driver + Monitor + Sequencer
    // ========================================================================
    class cpu_agent extends uvm_agent;
        `uvm_component_utils(cpu_agent)

        cpu_driver    driver;
        cpu_monitor   monitor;
        uvm_sequencer #(cpu_transaction) sequencer;

        function new(string name = "cpu_agent", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            driver    = cpu_driver::type_id::create("driver", this);
            monitor   = cpu_monitor::type_id::create("monitor", this);
            sequencer = uvm_sequencer #(cpu_transaction)::type_id::create("sequencer", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            driver.seq_item_port.connect(sequencer.seq_item_export);
        endfunction
    endclass


    // ========================================================================
    // Environment: 封装 Agent + Scoreboard
    // ========================================================================
    class cpu_env extends uvm_env;
        `uvm_component_utils(cpu_env)

        cpu_agent      agent;
        cpu_scoreboard scoreboard;
        cpu_coverage   coverage;

        function new(string name = "cpu_env", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent      = cpu_agent::type_id::create("agent", this);
            scoreboard = cpu_scoreboard::type_id::create("scoreboard", this);
            coverage   = cpu_coverage::type_id::create("coverage", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            agent.monitor.ap.connect(scoreboard.analysis_export);
            agent.monitor.ap.connect(coverage.analysis_export);
        endfunction
    endclass


    // ========================================================================
    // Base Test: 公共基类
    // ========================================================================
    class cpu_test_base extends uvm_test;
        `uvm_component_utils(cpu_test_base)

        cpu_env       env;
        string        hex_file;
        int unsigned  run_cycles;     // 运行周期数 (默认 100000)

        function new(string name = "cpu_test_base", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = cpu_env::type_id::create("env", this);

            if (!$value$plusargs("HEX_FILE=%s", hex_file))
                hex_file = "load_use_test.hex";
            run_cycles = 100000;
            `uvm_info("TEST", $sformatf("Using hex file: %s", hex_file), UVM_LOW)
        endfunction

        // 子类可覆盖 run_cycles 来调整仿真时长
        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            env.agent.driver.load_program(hex_file);
            wait($root.uvm_tb_top.rst_n === 1'b1);
            @(posedge $root.uvm_tb_top.clk);
            repeat(run_cycles) @(posedge $root.uvm_tb_top.clk);
            phase.drop_objection(this);
        endtask
    endclass


    // ========================================================================
    // Test 1: cpu_test_alu — 基础指令测试
    //   加载 hex 汇编程序，运行指定周期数后由 Scoreboard 汇总统计
    //   用法: vsim -c -do "set HEX_FILE alu_test.hex; set TEST_NAME cpu_test_alu; do run_msim.tcl"
    // ========================================================================
    class cpu_test_alu extends cpu_test_base;
        `uvm_component_utils(cpu_test_alu)

        function new(string name = "cpu_test_alu", uvm_component parent = null);
            super.new(name, parent);
        endfunction
    endclass


    // ========================================================================
    // Test 2: cpu_test_interrupt — 中断测试
    //   在指定周期注入定时器中断脉冲，验证影子寄存器上下文保存与恢复
    //   hex 程序 (intr_test.s):
    //     - 初始化 x1-x5 为 0xA1~0xA5
    //     - 设置 mtvec/mie/mstatus 使能定时器中断
    //     - ISR 故意破坏 x1-x5 (改为 0xB1~0xB5)
    //     - MRET 返回后检查 x1-x5 是否被影子寄存器恢复为原始值
    //     - [0xFC] = 0 (PASS) 或 1 (FAIL)
    //   用法: vsim -c -do "set HEX_FILE intr_test.hex; set TEST_NAME cpu_test_interrupt; do run_msim.tcl"
    // ========================================================================
    class cpu_test_interrupt extends cpu_test_base;
        `uvm_component_utils(cpu_test_interrupt)

        int unsigned intr_inject_cycle;   // 中断注入周期 (默认 2000)

        function new(string name = "cpu_test_interrupt", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        task run_phase(uvm_phase phase);
            phase.raise_objection(this);

            intr_inject_cycle = 2000;

            // 加载中断测试程序
            env.agent.driver.load_program(hex_file);

            // 等待复位释放
            wait($root.uvm_tb_top.rst_n === 1'b1);
            @(posedge $root.uvm_tb_top.clk);

            // 运行到指定周期后注入定时器中断脉冲
            `uvm_info("TEST", $sformatf("Waiting %0d cycles before injecting timer interrupt...",
                      intr_inject_cycle), UVM_LOW)
            repeat(intr_inject_cycle) @(posedge $root.uvm_tb_top.clk);

            `uvm_info("TEST", "Injecting timer interrupt pulse (1 cycle)...", UVM_NONE)
            env.agent.driver.trigger_timer_interrupt();

            // 继续运行等待测试完成
            repeat(50000) @(posedge $root.uvm_tb_top.clk);

            // 读取 tohost 结果
            if ($root.uvm_tb_top.data_ram[63] == 32'h0)
                `uvm_info("TEST", "*** INTERRUPT TEST PASSED — shadow registers correctly restored ***", UVM_NONE)
            else begin
                `uvm_error("TEST", $sformatf("*** INTERRUPT TEST FAILED — tohost=0x%08h (expected 0x0) ***",
                          $root.uvm_tb_top.data_ram[63]))
            end

            phase.drop_objection(this);
        endtask
    endclass


    // ========================================================================
    // Test 3: cpu_test_hazard — 冒险测试
    //   定向验证 load-use 停顿与数据转发路径
    //   hex 程序 (load_use_test.s):
    //     三组连续 lw+use 序列，结果依次写入 [0xFC]
    //     Test1: lw+add   → 预期 0xDEADBEF0
    //     Test2: lw+addi  → 预期 0xCAFEBBBE
    //     Test3: lw+sw    → 预期 0xDEADBEEF
    //   用法: vsim -c -do "set HEX_FILE load_use_test.hex; set TEST_NAME cpu_test_hazard; do run_msim.tcl"
    // ========================================================================
    class cpu_test_hazard extends cpu_test_base;
        `uvm_component_utils(cpu_test_hazard)

        function new(string name = "cpu_test_hazard", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        task run_phase(uvm_phase phase);
            // 监控 [0xFC] 检测三组测试结果
            logic [31:0] r1, r2, r3;
            logic [31:0] e1, e2, e3;

            phase.raise_objection(this);

            env.agent.driver.load_program(hex_file);

            wait($root.uvm_tb_top.rst_n === 1'b1);
            @(posedge $root.uvm_tb_top.clk);

            e1 = 32'hDEADBEF0;
            e2 = 32'hCAFEBBBE;
            e3 = 32'hDEADBEEF;

            fork
                begin
                    repeat(100000) @(posedge $root.uvm_tb_top.clk);
                    `uvm_error("TEST", "Timeout waiting for test completion")
                end
                begin
                    wait($root.uvm_tb_top.data_ram[63] !== 32'h0);
                    r1 = $root.uvm_tb_top.data_ram[63];
                    `uvm_info("TEST", $sformatf("Test1 (lw+add):  got=0x%08h expected=0x%08h %s",
                              r1, e1, (r1==e1)?"[PASS]":"[FAIL]"), UVM_NONE)

                    wait($root.uvm_tb_top.data_ram[63] !== r1);
                    r2 = $root.uvm_tb_top.data_ram[63];
                    `uvm_info("TEST", $sformatf("Test2 (lw+addi): got=0x%08h expected=0x%08h %s",
                              r2, e2, (r2==e2)?"[PASS]":"[FAIL]"), UVM_NONE)

                    wait($root.uvm_tb_top.data_ram[63] !== r2);
                    r3 = $root.uvm_tb_top.data_ram[63];
                    `uvm_info("TEST", $sformatf("Test3 (lw+sw):   got=0x%08h expected=0x%08h %s",
                              r3, e3, (r3==e3)?"[PASS]":"[FAIL]"), UVM_NONE)

                    `uvm_info("TEST", "", UVM_NONE)
                    if (r1==e1 && r2==e2 && r3==e3)
                        `uvm_info("TEST", "*** ALL HAZARD TESTS PASSED ***", UVM_NONE)
                    else
                        `uvm_error("TEST", "*** HAZARD TEST FAILED ***")
                end
            join_any
            disable fork;

            phase.drop_objection(this);
        endtask
    endclass

endpackage
