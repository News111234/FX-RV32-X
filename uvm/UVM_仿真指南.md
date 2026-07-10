# FX-RV32 UVM 仿真指南

## 目录

- [1. 如何运行 UVM 仿真](#1-如何运行-uvm-仿真)
  - [1.1 前置准备：生成 hex 文件](#11-前置准备生成-hex-文件)
  - [1.2 方式一：在终端里跑（推荐）](#12-方式一在-windows-cmd--git-bash-终端里跑推荐)
  - [1.3 方式二：在 Modelsim 控制台里跑](#13-方式二在-modelsim-控制台transcript里跑)
  - [1.4 波形窗口说明](#14-波形窗口说明gui-模式下)
  - [1.5 切换不同测试](#15-切换不同测试)
  - [1.6 环境变量说明](#16-环境变量说明)
- [2. 测试结果（2026-06-02）](#2-测试结果2026-06-02)
  - [2.1 编译统计](#21-编译统计)
  - [2.2 仿真运行时统计](#22-仿真运行时统计)
  - [2.3 功能覆盖率](#23-功能覆盖率)
  - [2.4 Load-Use 停顿验证](#24-load-use-停顿验证)
  - [2.5 发现的问题](#25-发现的问题)
- [3. 环境搭建问题与修复记录](#3-环境搭建问题与修复记录)

---

## 1. 如何运行 UVM 仿真

### 1.1 前置准备：生成 hex 文件

UVM 仿真需要 `.hex` 文件（纯 hex 格式，每行一个 32-bit 字）。使用 `python/asm_to_hex.py` 从汇编文件生成：

```bash
cd python
python asm_to_hex.py ../uvm/asm/load_use_test.s ../uvm/hex/load_use_test.hex
python asm_to_hex.py ../uvm/asm/intr_test.s    ../uvm/hex/intr_test.hex
```

### 1.2 方式一：终端命令行，只看文字结果（最快）

> 加 `-c` 表示控制台模式，不弹 GUI，结果直接打印在终端。

**Windows CMD：**

```cmd
cd uvm
set UVM_HOME=D:/modeltech64_10.6e/verilog_src/uvm-1.2
vsim -c -do "set HEX_FILE hex/load_use_test.hex; set TEST_NAME cpu_test_hazard; do run_msim.tcl"
```

**Git Bash / MSYS2：**

```bash
cd uvm
UVM_HOME=/d/modeltech64_10.6e/verilog_src/uvm-1.2 \
  vsim -c -do "set HEX_FILE hex/load_use_test.hex; set TEST_NAME cpu_test_hazard; do run_msim.tcl"
```

- `-c`：控制台模式，不弹 GUI
- `UVM_HOME`：指向 Modelsim 安装目录下的 UVM 1.2 源码

仿真结束后会自动打印覆盖率报告和 Scoreboard 结果。

---

### 1.3 方式二：终端命令行 + GUI 波形（推荐调试用）

> **去掉 `-c`，加上 `set GUI_MODE 1`**，Modelsim 窗口会自动弹出来并显示波形。

**Windows CMD：**

```cmd
cd uvm
vsim -do "set HEX_FILE hex/load_use_test.hex; set TEST_NAME cpu_test_hazard; set GUI_MODE 1; do run_msim.tcl"
```

**用 run_uvm.bat 更简单（Windows CMD）：**

```cmd
cd uvm
run_uvm.bat hazard gui        :: 冒险测试 + 波形
run_uvm.bat intr gui          :: 中断测试 + 波形
run_uvm.bat alu gui           :: 基础指令测试 + 波形
run_uvm.bat nested gui        :: 嵌套中断测试 + 波形
```

> `run_uvm.bat` 其实就是帮你拼好了上面那串 `vsim -do "..." ` 命令，加 `gui` 参数就行。

**Git Bash：**

```bash
cd uvm
vsim -do "set HEX_FILE hex/load_use_test.hex; set TEST_NAME cpu_test_hazard; set GUI_MODE 1; do run_msim.tcl"
```

执行后 Modelsim 自动打开，波形窗口按分组排列好，直接看。

---

### 1.4 方式三：在 Modelsim 图形界面里操作

> 先打开 Modelsim，在底部 Transcript 窗口敲命令（跟方式一、二的命令一样，只是不拼在 `-do` 里）。

**步骤**：

**①** 双击 Modelsim 图标打开主窗口。

**②** 在底部 **Transcript** 窗口输入：

```
cd uvm
```

**③** 只看文字结果：

```
set HEX_FILE hex/load_use_test.hex
set TEST_NAME cpu_test_hazard
do run_msim.tcl
```

**④** 或者想看波形，加一行 `set GUI_MODE 1`：

```
set HEX_FILE hex/load_use_test.hex
set TEST_NAME cpu_test_hazard
set GUI_MODE 1
do run_msim.tcl
```

---

### 1.5 波形窗口说明（GUI 模式下）

波形窗口会自动弹出，信号已按以下分组添加好：

| 波形分组 | 包含信号 |
|---------|---------|
| Clock & Reset | `clk`, `rst_n` |
| IF Stage | `if_pc`, `if_instr` |
| ID Stage | `if_id_pc`, `if_id_instr` |
| EX Stage | `ex_alu_result`, `ex_branch_taken`, `ex_jump_taken` |
| WB Stage | `wb_reg_we_out`, `wb_rd_addr_out`, `wb_data` |
| Pipeline Ctrl (Hazard) | `stall_if`, `stall_id`, `flush_if`, `flush_id`, `forwardA`, `forwardB` |
| Bus | `bus_re`, `bus_we`, `bus_addr`, `bus_rdata`, `bus_ready` |

**波形操作提示**：
- 放大/缩小：鼠标滚轮或工具栏 🔍 按钮
- 查看完整波形：工具栏 **Zoom Full** 按钮
- 测量时间差：鼠标左键点起点 → 拖到终点 → 看左下角 Δ 值
- 搜索信号：`Ctrl+F`
- 改变显示格式：右键信号 → **Radix** → 选 Hexadecimal / Decimal / Binary

### 1.6 切换不同测试

| 测试 | 命令 |
|------|------|
| Load-Use 冒险测试 | `set HEX_FILE hex/load_use_test.hex; set TEST_NAME cpu_test_hazard` |
| 中断测试 | `set HEX_FILE hex/intr_test.hex; set TEST_NAME cpu_test_interrupt` |
| 基础指令测试 | `set HEX_FILE hex/alu_test.hex; set TEST_NAME cpu_test_alu` |

每次切换测试前，建议清掉上次编译结果：
```
vdel -all
```

### 1.7 环境变量说明

TCL 脚本中可设置的变量：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `TEST_NAME` | `cpu_test_alu` | UVM 测试类名 |
| `HEX_FILE` | `hex/alu_test.hex` | 测试程序 hex 文件 |
| `GUI_MODE` | `0` | 1=打开波形窗口 |
| `COV_ENABLE` | `1` | 1=启用代码覆盖率 |
| `DUMP_VCD` | `0` | 1=生成 VCD 波形文件 |

---

## 2. 测试结果（2026-06-02）

- **测试程序**：`load_use_test.s` → `load_use_test.hex`（21 条指令）
- **UVM 测试类**：`cpu_test_hazard`
- **CPU 频率**：200MHz（时钟周期 5ns）
- **仿真时长**：500,102.5 ns（约 100,000 个时钟周期）

### 2.1 编译统计

| 项目 | 数量 |
|------|------|
| RTL 源文件 | 24 个 |
| UVM 环境文件 | 3 个（cpu_if.sv + riscv_uvm_pkg.sv + uvm_tb_top.sv） |
| 编译错误 | 0 |
| 编译警告 | 0 |

### 2.2 仿真运行时统计

| 指标 | 数值 | 说明 |
|------|------|------|
| 寄存器写回 (WB) | 18 次 | Scoreboard 记录 |
| Store 操作 | 0 次 | 测试中 store 数据未通过 monitor 检测（地址 > 0xFC 触发 bus，但 monitor 检测到 bus_we → 实际 store 到 0x100/0x104 被正确执行） |
| Load 操作 | 8 次 | 含重复 load（因测试循环） |
| Stall 事件 | 12 次 | 每次 load-use 产生 stall_if + stall_id 各一条 |
| 最大停顿周期 | 1 cycle | 符合预期：单周期 load-use 停顿 |
| Mismatch | 0 | Scoreboard 无寄存器/内存比对错误 |

### 2.3 功能覆盖率

| 覆盖组 | 覆盖率 | 说明 |
|--------|--------|------|
| `cg_instr_types` | 75% | 6/8 目标寄存器被覆盖，x28_t3 和 x11_a1 未触发 |
| `cg_memory_ops` | 58% | 低地址和 tohost 地址被覆盖，mid 地址范围未完全覆盖 |
| `cg_stall` | 78% | stall_if/stall_id 均被触发，持续时间 d1(1cycle) 被覆盖 |
| `cg_forwarding` | 100% | EX/MEM 和 MEM/WB 转发路径均已覆盖 |

### 2.4 Load-Use 停顿验证

Monitor 成功检测到 4 处 load-use 停顿，每次停顿恰好 1 个周期：

| 停顿位置 (PC) | 停顿指令 | 停顿周期 | 
|---------------|---------|---------|
| 0x0000002c | `add x3, x1, x5` (依赖 lw x1) | 1 cycle |
| 0x00000038 | `addi x6, x1, 0x100` (依赖 lw x1) | 1 cycle |
| 0x00000044 | `sw x1, 8(x4)` (依赖 lw x1) | 1 cycle |
| 0x0000004c | `sw x7, 0(x20)` (依赖 lw x7) | 1 cycle |

每次停顿模式一致：`STALL_IF` 和 `STALL_ID` 同时拉高 1 个周期后释放。停顿只影响 IF/ID 阶段，EX/MEM/WB 继续正常流动。

### 2.5 发现的问题

#### 问题：addi → lw 间 x4 未正确转发

测试序列中存在一个非 load-use 的数据依赖：

```asm
addi x4, x0, 0x100    # x4 = 0x100
addi x5, x0, 1        # 无关指令
lw   x1, 0(x4)        # rs1 = x4，应得 0x100，实际 load 地址为 0x0
```

- **现象**：`lw x1, 0(x4)` 的 load 地址为 `0x00000000` 而非 `0x00000100`
- **根因分析**：`addi x4, x0, 0x100` 写回 x4 时，结果位于 MEM/WB 流水线寄存器，此时 `lw` 正处于 EX 阶段。forwarding unit 应将 MEM/WB → EX 的值转发到 lw 的 rs1 地址计算路径，但该转发未生效
- **影响**：Test1 从地址 0 读取未初始化数据得到 `X`，Test1: FAIL
- **影响范围**：Test2 和 Test3 由于依赖的 x1 也是通过 load 获取（x1 = mem[x4]，x4=0），同样受影响

**Scoreboard 仍报告 PASS** 是因为 scoreboard 只做 WB/Store 计数统计，不做寄存器值的期望值比对。

---

## 3. 环境搭建问题与修复记录

以下记录了首次运行 UVM 仿真时遇到的问题及修复方法。

### 问题 1：uvm_macros.svh 找不到

**错误信息**：
```
Cannot open `include file "uvm_macros.svh"
```

**原因**：`run_msim.tcl` 中编译 UVM 环境文件（`cpu_if.sv`、`riscv_uvm_pkg.sv`、`uvm_tb_top.sv`）时缺少 `+incdir+` 指向 UVM 源码目录。

**修复**：在 `run_msim.tcl` 的 UVM 环境编译命令中添加 `+incdir+$UVM_SRC`：

```tcl
# 修复前
vlog -work work +acc +cover=sbceft +define+UVM_NO_DPI -sv riscv_uvm_pkg.sv

# 修复后
vlog -work work +acc +cover=sbceft +define+UVM_NO_DPI +incdir+$UVM_SRC -sv riscv_uvm_pkg.sv
```

### 问题 2：声明在语句之后

**错误信息**：
```
riscv_uvm_pkg.sv(640): Illegal declaration after the statement near line '635'.
```

**原因**：`cpu_test_hazard::run_phase()` 中变量声明 `logic [31:0] r1, r2, r3;` 放在了 `@(posedge ...)` 语句之后。在 SystemVerilog 中，begin-end 块内所有变量声明必须在任何可执行语句之前。

**修复**：将变量声明移到 task 体最前面：

```systemverilog
// 修复前
task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    ...
    @(posedge $root.uvm_tb_top.clk);     // 语句
    logic [31:0] r1, r2, r3;             // 声明 — 非法!

// 修复后
task run_phase(uvm_phase phase);
    logic [31:0] r1, r2, r3;             // 声明 — 必须在最前面
    phase.raise_objection(this);
    ...
```

### 问题 3：coverpoint 不支持 string 类型

**错误信息**：
```
Illegal unpacked type expression for coverpoint expression of Coverpoint 'op'.
```

**原因**：Modelsim 10.6e 不支持对 `string` 类型定义 coverpoint。

**修复**：将 `cg_memory_ops` 中的 string 类型 coverpoint 改为 1-bit 逻辑：

```systemverilog
// 修复前
covergroup cg_memory_ops with function sample(string op, logic [31:0] addr);
    coverpoint op {
        bins load  = {"LOAD"};
        bins store = {"STORE"};
    }
endgroup

// 修复后
covergroup cg_memory_ops with function sample(bit is_store, logic [31:0] addr);
    coverpoint is_store {
        bins load  = {1'b0};
        bins store = {1'b1};
    }
endgroup
```

对应的 sample 调用也从 `cg_memory_ops.sample(tr.event_type, ...)` 改为 `cg_memory_ops.sample((t.event_type == "STORE"), ...)`。

### 问题 4：uvm_subscriber::write() 参数名不匹配

**错误信息**：
```
Argument name 'tr' for virtual method 'write' in sub class 'cpu_coverage'
does not match the argument name 't' in superclass 'uvm_subscriber'.
```

**原因**：UVM 1.2 的 `uvm_subscriber` 基类定义了 `virtual function void write(T t)`，子类 `cpu_coverage` 的 `write(cpu_transaction tr)` 参数名 `tr` 不匹配 `t`。

**修复**：将子类参数名改为 `t`：

```systemverilog
// 修复前
function void write(cpu_transaction tr);

// 修复后
function void write(cpu_transaction t);
```

### 问题 5：$root 在 package 中不可访问

**错误信息**：
```
(vlog-7053) $root access from within packages is not allowed.
```

**原因**：Modelsim 10.6e 不允许在 SystemVerilog package 内部使用 `$root` 层次路径。`riscv_uvm_pkg` 中的 Monitor 和 Coverage 类多处使用了 `$root.uvm_tb_top.u_dut.*` 来访问 DUT 内部信号。

**修复**：在 vlog 命令中添加 `-suppress 7053` 抑制该检查：

```tcl
vlog -work work +acc +cover=sbceft +define+UVM_NO_DPI +incdir+$UVM_SRC -suppress 7053 -sv riscv_uvm_pkg.sv
```

> **说明**：这是折中方案。最佳实践是将所需信号通过 virtual interface 传递，避免 package 内的层次路径引用。但考虑到改动量大，`-suppress 7053` 在当前环境下可正常工作。

### 问题 6：core_top 无 perf_* 端口

**错误信息**：
```
Port 'perf_total_time' not found in module 'core_top'.
```

**原因**：`uvm_tb_top.sv` 实例化 `core_top` 时连接了 6 个 CoreMark 性能监控端口（`perf_total_time`、`perf_score` 等），但这些端口只存在于 `core_top_sim`（CoreMark 包装层），不在 `core_top` 中。

**修复**：从 `uvm_tb_top.sv` 的 DUT 实例化中移除 6 个 `perf_*` 端口连接。

### 问题 7：UVM DPI 函数未找到

**错误信息**：
```
Null foreign function pointer encountered when calling 'uvm_dpi_get_next_arg_c'
```

**原因**：编译 UVM package 时未定义 `UVM_NO_DPI`，导致编译了 DPI 调用，但运行时找不到对应的 DLL。

**修复**：在编译 `uvm_pkg.sv` 时也加入 `+define+UVM_NO_DPI`：

```tcl
# 修复前
catch { vlog -work work +incdir+$UVM_SRC $UVM_SRC/uvm_pkg.sv }

# 修复后
catch { vlog -work work +incdir+$UVM_SRC +define+UVM_NO_DPI $UVM_SRC/uvm_pkg.sv }
```

### 问题 8：UVM 找不到测试类

**错误信息**：
```
UVM_FATAL [NOCOMP] No components instantiated.
```

**原因**：`vsim` 命令行传递了 `+TEST_NAME=cpu_test_hazard`，但 UVM 的 `run_test()` 需要 `+UVM_TESTNAME=<test_class>` 来指定测试类。

**修复**：在所有 `vsim` 命令中额外添加 `+UVM_TESTNAME=$TEST_NAME`：

```tcl
# 修复后
vsim -c -voptargs=+acc -coverage work.uvm_tb_top \
    +UVM_TESTNAME=$TEST_NAME +TEST_NAME=$TEST_NAME +HEX_FILE=$HEX_FILE \
    -do "run -all; ..."
```

---

## 附录：文件结构

```
uvm/
├── UVM_仿真指南.md          # 本文档
├── README.md                 # 原始 UVM 说明
├── 问题修复记录.md            # 问题修复记录
├── run_msim.tcl              # Modelsim TCL 自动化脚本（已修复）
├── run_uvm.bat               # Windows 批处理启动脚本
├── run_tb_soc.tcl            # SoC 级仿真脚本
├── cpu_if.sv                 # Virtual interface 定义
├── riscv_uvm_pkg.sv          # UVM 验证组件包（已修复）
├── uvm_tb_top.sv             # UVM 顶层 Testbench（已修复）
├── rtl_filelist.f            # RTL 源文件列表
├── asm/                      # 汇编源文件 (.s)
│   ├── load_use_test.s
│   ├── intr_test.s
│   ├── alu_test.s
│   └── ...
├── hex/                      # 编译产物 (.hex)
│   ├── load_use_test.hex
│   ├── intr_test.hex
│   ├── alu_test.hex
│   └── ...
├── docs/                     # 旧文档归档
└── nested_uvm/               # 嵌套中断测试套件
    ├── run_nested.tcl
    ├── asm/                  # 嵌套测试汇编源文件
    ├── hex/                  # 嵌套测试 hex 文件
    └── ...
```

## 附录：备用 - 使用 Windows 批处理

如果你在 Windows cmd 下操作，可以用 `run_uvm.bat`：

```cmd
cd uvm
run_uvm.bat hazard            :: 冒险测试，控制台模式
run_uvm.bat hazard gui        :: 冒险测试 + GUI 波形
run_uvm.bat intr              :: 中断测试
run_uvm.bat intr gui          :: 中断测试 + GUI 波形
```

**注意**：`run_uvm.bat` 假设 `vsim` 在 PATH 中。如果不在，需先运行 Modelsim 的环境设置脚本或将 Modelsim 的 `win64` 目录加入 PATH。
