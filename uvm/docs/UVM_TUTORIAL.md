# UVM 从零入门教程 —— 以 FX-RV32 UVM 验证环境为例

本教程面向零 UVM 基础读者，以 FX-RV32 现有的 UVM 验证环境为实例，从概念到实操逐步讲解。读完你可以自行搭建类似验证环境。

---

## 目录

1. [UVM 是什么](#1-uvm-是什么)
2. [核心概念：类、层次、Phase](#2-核心概念)
3. [环境拆解：8 个文件逐个讲](#3-环境拆解)
4. [动手搭建：从空文件夹到能跑仿真](#4-动手搭建)
5. [添加新测试：以嵌套中断为例](#5-添加新测试)
6. [调试技巧](#6-调试技巧)

---

## 1. UVM 是什么

UVM（Universal Verification Methodology）是一套基于 SystemVerilog 的**验证方法学库**。你把它理解成一个"验证框架"——它提供了一套标准组件（Driver、Monitor、Scoreboard 等），你只需要往里面填自己的逻辑。

**UVM 解决的核心问题**：
- 激励生成与施加（Driver）
- 信号监控与收集（Monitor）
- 结果比对与判定（Scoreboard）
- 测试用例管理（Test / Sequence）
- 仿真阶段控制（Phase）
- 日志与报告（Report）

**和你手写 testbench 的区别**：
- 手写 testbench：一个 `initial` 块搞定全部。简单但不可复用。
- UVM：组件化、可复用、标准化。每个组件职责单一。但学习曲线陡。

---

## 2. 核心概念

### 2.1 类的继承关系

```
uvm_component (UVM 内置)
  ├── uvm_driver      → 驱动 DUT 输入信号
  ├── uvm_monitor     → 监控 DUT 输出信号
  ├── uvm_scoreboard  → 比对期望值和实际值
  ├── uvm_agent       → 封装 driver + monitor
  ├── uvm_env         → 封装 agent + scoreboard
  └── uvm_test        → 顶级测试用例


uvm_object (UVM 内置)
  └── uvm_sequence_item → Transaction: 在组件间传递的数据包
```

### 2.2 层次结构（树）

UVM 环境是一个树形结构：

```
uvm_test_top (uvm_test)
  └── uvm_tb_env (uvm_env)
        ├── cpu_agent (uvm_agent)
        │     ├── cpu_driver (uvm_driver)
        │     └── cpu_monitor (uvm_monitor)
        └── cpu_scoreboard (uvm_scoreboard)
```

每个节点通过 `build_phase` 创建子节点。顶层 test 由 `run_test("test_name")` 启动。

### 2.3 Phase 机制

UVM 仿真按 Phase 顺序执行。最常用的三个：

| Phase | 执行顺序 | 用途 |
|-------|:---:|------|
| `build_phase` | ① 自顶向下 | 创建子组件、获取配置 |
| `connect_phase` | ② 自底向上 | 连接组件间的 TLM 端口 |
| `main_phase` | ③ 并行执行 | 真正的仿真激励与检查 |

理解 Phase 的关键：**build_phase 只做创建和配置，main_phase 才做实际工作**。

### 2.4 TLM 通信

组件之间通过 TLM（Transaction Level Modeling）端口通信：

```
Monitor ──(analysis_port)──→ Scoreboard
Driver  ←──(seq_item_port)──→ Sequencer → Sequence
```

- `uvm_analysis_port`：广播端口，一对多。Monitor 用这个把收集到的 transaction 发给 Scoreboard。
- `uvm_seq_item_port`：点对点端口。Driver 通过这个从 Sequencer 获取下一个 transaction。

### 2.5 Factory 与 Config DB

**Factory（工厂）**：UVM 通过 factory 创建对象。写 `type_id::create("name", parent)` 而不是 `new()`。这样可以在不修改代码的情况下替换组件（override）。

**Config DB（配置数据库）**：组件间传递配置的全局键值存储。最常见的用法——把 virtual interface 从顶层传给 Driver：

```systemverilog
// 在顶层 testbench (module) 中:
uvm_config_db #(virtual cpu_if)::set(null, "*", "vif", vif);

// 在 Driver 中:
uvm_config_db #(virtual cpu_if)::get(this, "", "vif", vif);
```

---

## 3. 环境拆解

FX-RV32 的 UVM 环境由 8 个文件组成。下面逐个解读。

### 3.1 `cpu_if.sv` — Virtual Interface

```systemverilog
interface cpu_if(input logic clk, input logic rst_n);
    // Driver 驱动的信号
    logic intr_timer;
    logic intr_external;

    // Monitor 观察的信号（来自 DUT 内部）
    logic        interrupt_taken;
    logic [3:0]  bank_ptr;
    logic [31:0] if_pc;
    logic [31:0] if_instr;
    // ... 更多信号 ...

    // Clocking block: 确保信号在正确的时钟沿被采样/驱动
    clocking drv_cb @(posedge clk);
        output intr_timer, intr_external;
    endclocking

    clocking mon_cb @(posedge clk);
        input interrupt_taken, bank_ptr, if_pc, if_instr /* ... */;
    endclocking
endinterface
```

**要点**：interface 把 DUT 和 testbench 隔离开。所有信号都通过 interface 连接，testbench 不直接碰 DUT 的内部信号。

`clocking block` 的作用：指定信号在哪个时钟沿被驱动（output）或采样（input），避免竞争条件。

### 3.2 `riscv_uvm_pkg.sv` — UVM 组件包

所有 UVM 类都定义在这个 package 里。包含：

**Transaction（数据包）**：
```systemverilog
class cpu_transaction extends uvm_sequence_item;
    string      event_type;     // "WB" / "STORE" / "STALL" 等
    int         cycle;
    logic [31:0] rd_data;       // WB 数据
    logic [31:0] bus_addr;      // 访存地址
    // ...
endclass
```

**Driver（激励驱动）**：
```systemverilog
class cpu_driver extends uvm_driver #(cpu_transaction);
    task load_program(string hex_file);  // 加载 hex 到 inst_rom
    task trigger_timer_interrupt();      // 触发 Timer 中断
    task trigger_gpio_interrupt();       // 触发 GPIO 中断
endclass
```

**Monitor（信号监控）**：
```systemverilog
class cpu_monitor extends uvm_monitor;
    // 每个时钟沿采样 pipeline 信号
    // 检测 stall、前递、WB、中断等事件
    // 创建 transaction 并通过 analysis_port 发给 Scoreboard
endclass
```

**Scoreboard（结果比对）**：
```systemverilog
class cpu_scoreboard extends uvm_scoreboard;
    // 接收 Monitor 发来的 transaction
    // 根据 event_type 判断是对比 WB 数据还是检查中断 marker
    // 打印 PASS/FAIL
endclass
```

**Test（测试用例）**：
```systemverilog
class cpu_test_alu extends uvm_test;
    function void build_phase(uvm_phase phase);
        // 创建 env
        env = cpu_env::type_id::create("env", this);
    endfunction

    task main_phase(uvm_phase phase);
        // 1. 设置超时
        // 2. 通过 driver 加载 hex
        // 3. 释放复位
        // 4. 等待测试结束（轮询 tohost 或超时）
        // 5. 比对结果
    endtask
endclass
```

### 3.3 `uvm_tb_top.sv` — 顶层 testbench（module）

这是最顶层——非 UVM 的 `module`。它：
1. 实例化 DUT（core_top_sim）+ inst_rom + data_ram
2. 实例化 interface (`cpu_if`)
3. 连接 interface 信号到 DUT
4. 将 interface 写入 Config DB

```systemverilog
module uvm_tb_top;
    reg clk, rst_n;
    cpu_if vif(clk, rst_n);

    // DUT 实例化
    core_top_sim u_dut(.clk_i(clk), .rst_n_i(rst_n), /* 端口连接 */);

    // 连接 interface 信号到 DUT 内部
    assign vif.if_pc = u_dut.if_pc;

    // 将 interface 注册到 Config DB
    initial begin
        uvm_config_db #(virtual cpu_if)::set(null, "*", "vif", vif);
        run_test();  // 启动 UVM
    end
endmodule
```

### 3.4 `run_msim.tcl` — Modelsim 启动脚本

自动完成：建库 → 编译 RTL → 编译 UVM → 启动仿真。

```tcl
vlib work
vlog +acc +cover ../core/ifu/*.v ../core/id/*.v ...  ;# 编译 RTL
vlog +acc +cover cpu_if.sv uvm_tb_top.sv              ;# 编译 UVM
vsim -c -coverage uvm_tb_top -do "run -all"           ;# 启动
```

---

## 4. 动手搭建

### 4.1 从空文件夹开始

假设你要为一个新 DUT 搭建 UVM 环境，需要以下文件：

```
my_uvm/
├── dut_if.sv          # ① interface 定义
├── my_pkg.sv          # ② UVM 组件包 (transaction, driver, monitor, scoreboard, tests)
├── tb_top.sv          # ③ 顶层 module
├── run.tcl            # ④ 启动脚本
└── test_program.hex   # ⑤ 测试程序
```

### 4.2 步骤一：写 interface

```systemverilog
interface dut_if(input logic clk, input logic rst_n);
    logic [31:0] addr;
    logic [31:0] wdata;
    logic [31:0] rdata;
    logic        we;

    clocking drv_cb @(posedge clk);
        output addr, wdata, we;
    endclocking

    clocking mon_cb @(posedge clk);
        input rdata;
    endclocking
endinterface
```

### 4.3 步骤二：写 package（组件包）

**最小 Transaction**：
```systemverilog
class my_transaction extends uvm_sequence_item;
    `uvm_object_utils(my_transaction)
    int         cycle;
    logic [31:0] addr, data;
    function new(string name = "my_transaction");
        super.new(name);
    endfunction
endclass
```

**最小 Driver**：
```systemverilog
class my_driver extends uvm_driver #(my_transaction);
    `uvm_component_utils(my_driver)
    virtual dut_if vif;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db #(virtual dut_if)::get(this, "", "vif", vif);
    endfunction

    task main_phase(uvm_phase phase);
        // 在这里驱动 DUT 信号
        @(vif.drv_cb);
        vif.drv_cb.addr  <= 32'h100;
        vif.drv_cb.wdata <= 32'hDEADBEEF;
        vif.drv_cb.we    <= 1'b1;
    endtask
endclass
```

**最小 Monitor**：
```systemverilog
class my_monitor extends uvm_monitor;
    `uvm_component_utils(my_monitor)
    virtual dut_if vif;
    uvm_analysis_port #(my_transaction) ap;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db #(virtual dut_if)::get(this, "", "vif", vif);
        ap = new("ap", this);
    endfunction

    task main_phase(uvm_phase phase);
        forever begin
            @(vif.mon_cb);  // 每个时钟沿
            my_transaction tr = my_transaction::type_id::create("tr");
            tr.cycle = $time;
            tr.data  = vif.mon_cb.rdata;
            ap.write(tr);  // 发给 Scoreboard
        end
    endtask
endclass
```

**最小 Scoreboard**：
```systemverilog
class my_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(my_scoreboard)
    uvm_analysis_imp #(my_transaction, my_scoreboard) ap_imp;
    logic [31:0] expected = 32'hDEADBEEF;

    function void write(my_transaction tr);
        if (tr.data == expected)
            `uvm_info("SB", $sformatf("[PASS] cycle=%0d data=0x%08h", tr.cycle, tr.data), UVM_LOW)
        else
            `uvm_error("SB", $sformatf("[FAIL] got=0x%08h expected=0x%08h", tr.data, expected))
    endfunction
endclass
```

**最小 Test**：
```systemverilog
class my_test extends uvm_test;
    `uvm_component_utils(my_test)
    my_env env;

    function void build_phase(uvm_phase phase);
        env = my_env::type_id::create("env", this);
    endfunction

    task main_phase(uvm_phase phase);
        phase.phase_done.set_drain_time(this, 1000);  // 最多跑 1μs
    endtask
endclass
```

### 4.4 步骤三：写顶层 module

```systemverilog
module tb_top;
    reg clk = 0; always #5 clk = ~clk;
    reg rst_n = 0;
    dut_if vif(clk, rst_n);

    my_dut u_dut(.clk(clk), .rst_n(rst_n),
                 .addr(vif.addr), .wdata(vif.wdata), .rdata(vif.rdata), .we(vif.we));

    initial begin
        uvm_config_db #(virtual dut_if)::set(null, "*", "vif", vif);
        #20 rst_n = 1;
        run_test("my_test");
    end
endmodule
```

### 4.5 步骤四：写 TCL 脚本

```tcl
vlib work
vlog +acc dut_if.sv my_dut.v my_pkg.sv tb_top.sv
vsim -c tb_top -do "run -all"
```

### 4.6 步骤五：运行

```bash
vsim -c -do run.tcl
```

---

## 5. 添加新测试

以 FX-RV32 添加 `cpu_test_nested`（嵌套中断测试）为例：

### 5.1 在 package 中新增 Test 类

```systemverilog
class cpu_test_nested extends uvm_test;
    `uvm_component_utils(cpu_test_nested)
    cpu_env env;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = cpu_env::type_id::create("env", this);
    endfunction

    task main_phase(uvm_phase phase);
        cpu_driver drv;
        int timeout = 1000000;  // 1ms 超时

        phase.raise_objection(this);

        // ① 获取 driver 句柄
        $cast(drv, env.agent.driver);

        // ② 加载 hex 程序
        drv.load_program("nested_test.hex");

        // ③ 设置超时
        phase.phase_done.set_drain_time(this, timeout);

        // ④ 释放复位
        repeat(20) @(posedge vif.clk);
        vif.rst_n = 1;

        // ⑤ 在指定时间触发 GPIO
        repeat(300) @(posedge vif.clk);
        vif.gpio_pin0 = 1;
        repeat(10) @(posedge vif.clk);
        vif.gpio_pin0 = 0;

        // ⑥ 等待 tohost 或超时
        fork
            begin
                while ($root.uvm_tb_top.data_ram.mem[63] === 32'h0 &&
                       $time < timeout)
                    @(posedge vif.clk);
            end
        join

        // ⑦ 比对 marker 值
        if ($root.uvm_tb_top.data_ram.mem[64] == 32'hDEAD0001 &&
            $root.uvm_tb_top.data_ram.mem[65] == 32'hBEEF0001)
            `uvm_info("TEST", "=> PASS", UVM_NONE)
        else
            `uvm_error("TEST", "=> FAIL")

        phase.drop_objection(this);
    endtask
endclass
```

### 5.2 运行

```tcl
set HEX_FILE nested_test.hex
set TEST_NAME cpu_test_nested
do run_msim.tcl
```

---

## 6. 调试技巧

### 6.1 打印信号值

```systemverilog
`uvm_info("DEBUG", $sformatf("cycle=%0d PC=0x%08h bank_ptr=%0d",
         $time, vif.mon_cb.if_pc, vif.mon_cb.bank_ptr), UVM_NONE)
```

### 6.2 用 Transcript 交互

仿真运行中（或暂停时），在 Transcript 输入：
```tcl
exam /uvm_tb_top/u_dut/u_csr_regfile/mstatus_o   # 读 CSR 值
force /uvm_tb_top/intr_timer 1                     # 强制触发中断
```

### 6.3 UVM 日志级别

| 宏 | 级别 | 何时用 |
|----|------|--------|
| `uvm_info("ID", "msg", UVM_NONE)` | 始终打印 | 测试结论 |
| `uvm_info("ID", "msg", UVM_LOW)` | 低 | 关键事件（中断进入）|
| `uvm_info("ID", "msg", UVM_MEDIUM)` | 中 | 常规事件（WB 写回）|
| `uvm_info("ID", "msg", UVM_HIGH)` | 高 | 调试信息（每周期 PC）|
| `uvm_error("ID", "msg")` | — | 比对失败 |
| `uvm_fatal("ID", "msg")` | — | 无法继续（仿真终止）|

控制日志级别：`vsim +UVM_VERBOSITY=UVM_LOW`

### 6.4 常见错误排查

| 错误 | 原因 | 解决 |
|------|------|------|
| `UVM_FATAL: Null object reference` | 忘记 `create()` 直接用了 `new()` | 改用 `type_id::create()` |
| `Virtual interface not found` | config_db 的 set 和 get 路径不匹配 | 检查 `set(null, "*", ...)` 和 `get(this, "", ...)` |
| `Cannot open hex file` | hex 文件路径不对 | 检查相对路径，uvm/ 下确认文件存在 |
| Phase 不结束 | 忘记 `drop_objection` 或 drain_time 太短 | 检查 main_phase 的 objection 管理 |
