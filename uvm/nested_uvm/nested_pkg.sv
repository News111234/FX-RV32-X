// nested_uvm/nested_pkg.sv — 论文10项测试的UVM验证包
`timescale 1ns/1ps

package nested_uvm_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // ===== Driver: 加载hex, 驱动中断 =====
    class nested_driver extends uvm_driver #(uvm_sequence_item);
        `uvm_component_utils(nested_driver)
        virtual cpu_if vif;

        function new(string name = "nested_driver", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db #(virtual cpu_if)::get(this, "", "vif", vif))
                `uvm_fatal("DRV", "Virtual interface not found")
        endfunction

        // 加载 hex 文件到指令ROM (通过soc_top内部inst_rom后门)
        task load_program(string hex_file);
            int fd, addr;
            string line;
            logic [31:0] instr;

            fd = $fopen(hex_file, "r");
            if (fd == 0) begin
                `uvm_fatal("DRV", $sformatf("Cannot open: %s", hex_file))
            end

            // 先填充NOP
            for (int i = 0; i < 4096; i++)
                $root.tb_top.u_soc_top.gen_inst_rom.u_inst_rom.rom[i] = 32'h00000013;

            addr = 0;
            while (!$feof(fd)) begin
                void'($fgets(line, fd));
                line = line.substr(0, line.len()-2);
                if (line.len() >= 8) begin
                    instr = line.atohex();
                    $root.tb_top.u_soc_top.gen_inst_rom.u_inst_rom.rom[addr] = instr;
                    addr++;
                end
            end
            $fclose(fd);
            `uvm_info("DRV", $sformatf("Loaded %0d instructions from %s", addr, hex_file), UVM_LOW)
        endtask

        // 触发GPIO上升沿脉冲
        task trigger_gpio();
            @(vif.drv_cb);
            vif.drv_cb.gpio_pin0 <= 1'b1;
            @(vif.drv_cb);
            vif.drv_cb.gpio_pin0 <= 1'b0;
        endtask
    endclass

    // ===== Monitor: 监控tohost和marker =====
    class nested_monitor extends uvm_monitor;
        `uvm_component_utils(nested_monitor)
        virtual cpu_if vif;

        function new(string name = "nested_monitor", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db #(virtual cpu_if)::get(this, "", "vif", vif))
                `uvm_fatal("MON", "Virtual interface not found")
        endfunction
    endclass

    // ===== Scoreboard: 结果比对 =====
    class nested_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(nested_scoreboard)

        int pass_cnt, fail_cnt;

        function new(string name = "nested_scoreboard", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void check_marker(string test_name, int index, logic [31:0] expected);
            logic [31:0] actual;
            actual = $root.tb_top.u_soc_top.u_data_ram.mem[index];
            if (actual === expected) begin
                `uvm_info("SB", $sformatf("[PASS] %s: mem[%0d]=0x%08h", test_name, index, actual), UVM_NONE)
                pass_cnt++;
            end else begin
                `uvm_error("SB", $sformatf("[FAIL] %s: mem[%0d]=0x%08h, expected 0x%08h",
                                          test_name, index, actual, expected))
                fail_cnt++;
            end
        endfunction

        function void check_tohost(string test_name, logic [31:0] expected);
            check_marker(test_name, 63, expected);
        endfunction

        function void report_phase(uvm_phase phase);
            `uvm_info("SB", $sformatf("Total: %0d passed, %0d failed", pass_cnt, fail_cnt), UVM_NONE)
        endfunction
    endclass

    // ===== Agent =====
    class nested_agent extends uvm_agent;
        `uvm_component_utils(nested_agent)
        nested_driver    driver;
        nested_monitor   monitor;

        function new(string name = "nested_agent", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            driver  = nested_driver::type_id::create("driver", this);
            monitor = nested_monitor::type_id::create("monitor", this);
        endfunction
    endclass

    // ===== Env =====
    class nested_env extends uvm_env;
        `uvm_component_utils(nested_env)
        nested_agent      agent;
        nested_scoreboard scoreboard;

        function new(string name = "nested_env", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent      = nested_agent::type_id::create("agent", this);
            scoreboard = nested_scoreboard::type_id::create("scoreboard", this);
        endfunction
    endclass

    // ===== Base Test =====
    class nested_test_base extends uvm_test;
        nested_env env;

        function new(string name = "nested_test_base", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = nested_env::type_id::create("env", this);
        endfunction

        // 等待 tohost != 0 或超时
        task wait_tohost_or_timeout(int timeout_ns = 10000000);
            int waited = 0;
            while (waited < timeout_ns) begin
                if ($root.tb_top.u_soc_top.u_data_ram.mem[63] !== 32'h0) begin
                    `uvm_info("TEST", $sformatf("tohost=0x%08h at %0t ns",
                             $root.tb_top.u_soc_top.u_data_ram.mem[63], $time), UVM_LOW)
                    return;
                end
                #100;
                waited += 100;
            end
            `uvm_warning("TEST", $sformatf("Timeout after %0d ns", timeout_ns))
        endtask
    endclass

    // ========================================================================
    // 10个测试类
    // ========================================================================

    // Test 1: 单次Timer中断
    class test_single_intr extends nested_test_base;
        `uvm_component_utils(test_single_intr)
        function new(string name = "test_single_intr", uvm_component parent = null);
            super.new(name, parent);
        endfunction
        task run_phase(uvm_phase phase);
            nested_driver drv;
            phase.raise_objection(this);
            $cast(drv, env.agent.driver);
            drv.load_program("single_intr_test.hex");
            repeat(20) @(posedge $root.tb_top.clk);
            $root.tb_top.rst_n = 1;
            wait_tohost_or_timeout();
            env.scoreboard.check_tohost("single_intr", 0);
            phase.drop_objection(this);
        endtask
    endclass

    // Test 2: 最小中断
    class test_ultra_min extends nested_test_base;
        `uvm_component_utils(test_ultra_min)
        function new(string name = "test_ultra_min", uvm_component parent = null);
            super.new(name, parent);
        endfunction
        task run_phase(uvm_phase phase);
            nested_driver drv;
            phase.raise_objection(this);
            $cast(drv, env.agent.driver);
            drv.load_program("ultra_min_test.hex");
            repeat(20) @(posedge $root.tb_top.clk);
            $root.tb_top.rst_n = 1;
            wait_tohost_or_timeout();
            env.scoreboard.check_marker("ultra_min", 64, 32'h42);
            phase.drop_objection(this);
        endtask
    endclass

    // Test 3: 无中断
    class test_no_intr extends nested_test_base;
        `uvm_component_utils(test_no_intr)
        function new(string name = "test_no_intr", uvm_component parent = null);
            super.new(name, parent);
        endfunction
        task run_phase(uvm_phase phase);
            nested_driver drv;
            phase.raise_objection(this);
            $cast(drv, env.agent.driver);
            drv.load_program("no_intr_test.hex");
            repeat(20) @(posedge $root.tb_top.clk);
            $root.tb_top.rst_n = 1;
            wait_tohost_or_timeout();
            env.scoreboard.check_marker("no_intr", 64, 32'h42);
            phase.drop_objection(this);
        endtask
    endclass

    // Test 4: 两级嵌套 (Timer→GPIO)
    class test_nested extends nested_test_base;
        `uvm_component_utils(test_nested)
        function new(string name = "test_nested", uvm_component parent = null);
            super.new(name, parent);
        endfunction
        task run_phase(uvm_phase phase);
            nested_driver drv;
            phase.raise_objection(this);
            $cast(drv, env.agent.driver);
            drv.load_program("nested_test.hex");
            repeat(20) @(posedge $root.tb_top.clk);
            $root.tb_top.rst_n = 1;
            // GPIO在约1.6μs触发 (Timer ISR执行中)
            repeat(300) @(posedge $root.tb_top.clk);
            drv.trigger_gpio();
            wait_tohost_or_timeout();
            env.scoreboard.check_marker("nested", 64, 32'hDEAD0001);
            env.scoreboard.check_marker("nested", 65, 32'hBEEF0001);
            phase.drop_objection(this);
        endtask
    endclass

    // Test 5: Bank溢出 (BANKS=1, POL=0)
    class test_overflow extends nested_test_base;
        `uvm_component_utils(test_overflow)
        function new(string name = "test_overflow", uvm_component parent = null);
            super.new(name, parent);
        endfunction
        task run_phase(uvm_phase phase);
            nested_driver drv;
            phase.raise_objection(this);
            $cast(drv, env.agent.driver);
            drv.load_program("overflow_test.hex");
            repeat(20) @(posedge $root.tb_top.clk);
            $root.tb_top.rst_n = 1;
            repeat(250) @(posedge $root.tb_top.clk);
            drv.trigger_gpio();
            wait_tohost_or_timeout();
            env.scoreboard.check_marker("overflow", 64, 32'hDEAD0001);
            env.scoreboard.check_marker("overflow", 65, 32'hBEEF0002);
            phase.drop_objection(this);
        endtask
    endclass

    // Test 6: 溢出最小测试
    class test_overflow_min extends nested_test_base;
        `uvm_component_utils(test_overflow_min)
        function new(string name = "test_overflow_min", uvm_component parent = null);
            super.new(name, parent);
        endfunction
        task run_phase(uvm_phase phase);
            nested_driver drv;
            phase.raise_objection(this);
            $cast(drv, env.agent.driver);
            drv.load_program("overflow_minimal.hex");
            repeat(20) @(posedge $root.tb_top.clk);
            $root.tb_top.rst_n = 1;
            wait_tohost_or_timeout();
            env.scoreboard.check_marker("overflow_min", 64, 32'h42);
            phase.drop_objection(this);
        endtask
    endclass

    // Test 7: 上下文完整性
    class test_context extends nested_test_base;
        `uvm_component_utils(test_context)
        function new(string name = "test_context", uvm_component parent = null);
            super.new(name, parent);
        endfunction
        task run_phase(uvm_phase phase);
            nested_driver drv;
            phase.raise_objection(this);
            $cast(drv, env.agent.driver);
            drv.load_program("context_integrity_test.hex");
            repeat(20) @(posedge $root.tb_top.clk);
            $root.tb_top.rst_n = 1;
            repeat(300) @(posedge $root.tb_top.clk);
            drv.trigger_gpio();
            wait_tohost_or_timeout();
            env.scoreboard.check_tohost("context", 0);
            phase.drop_objection(this);
        endtask
    endclass

    // Test 8: 降级复用 (BANKS=1, POL=1)
    class test_degradation extends nested_test_base;
        `uvm_component_utils(test_degradation)
        function new(string name = "test_degradation", uvm_component parent = null);
            super.new(name, parent);
        endfunction
        task run_phase(uvm_phase phase);
            nested_driver drv;
            phase.raise_objection(this);
            $cast(drv, env.agent.driver);
            drv.load_program("degradation_test.hex");
            repeat(20) @(posedge $root.tb_top.clk);
            $root.tb_top.rst_n = 1;
            repeat(250) @(posedge $root.tb_top.clk);
            drv.trigger_gpio();
            wait_tohost_or_timeout();
            env.scoreboard.check_marker("degradation", 65, 32'hBEEF0003);
            phase.drop_objection(this);
        endtask
    endclass

    // Test 9: 尾链优化
    class test_tailchain extends nested_test_base;
        `uvm_component_utils(test_tailchain)
        function new(string name = "test_tailchain", uvm_component parent = null);
            super.new(name, parent);
        endfunction
        task run_phase(uvm_phase phase);
            nested_driver drv;
            phase.raise_objection(this);
            $cast(drv, env.agent.driver);
            drv.load_program("tail_chain_test.hex");
            repeat(20) @(posedge $root.tb_top.clk);
            $root.tb_top.rst_n = 1;
            repeat(350) @(posedge $root.tb_top.clk);
            drv.trigger_gpio();
            wait_tohost_or_timeout();
            env.scoreboard.check_marker("tailchain", 64, 32'h1);
            phase.drop_objection(this);
        endtask
    endclass

    // Test 10: 三级嵌套
    class test_triple extends nested_test_base;
        `uvm_component_utils(test_triple)
        function new(string name = "test_triple", uvm_component parent = null);
            super.new(name, parent);
        endfunction
        task run_phase(uvm_phase phase);
            nested_driver drv;
            phase.raise_objection(this);
            $cast(drv, env.agent.driver);
            drv.load_program("triple_nested_test.hex");
            repeat(20) @(posedge $root.tb_top.clk);
            $root.tb_top.rst_n = 1;
            // SW中断: testbench在400ns后触发
            repeat(70) @(posedge $root.tb_top.clk);
            $root.tb_top.vif.intr_software = 1;
            repeat(20) @(posedge $root.tb_top.clk);
            $root.tb_top.vif.intr_software = 0;
            // GPIO在Timer ISR期间触发
            repeat(220) @(posedge $root.tb_top.clk);
            drv.trigger_gpio();
            wait_tohost_or_timeout();
            env.scoreboard.check_marker("triple", 64, 32'hCAFE0003);
            env.scoreboard.check_marker("triple", 65, 32'hDEAD0007);
            env.scoreboard.check_marker("triple", 66, 32'hBEEF000B);
            phase.drop_objection(this);
        endtask
    endclass

endpackage
