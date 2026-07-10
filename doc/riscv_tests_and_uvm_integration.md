# RISC-V 官方测试集与 UVM 验证环境的集成

> 日期：2026-06-08 | 作者：Yi Fengxin, Beihang University

本文档说明 riscv-tests 官方测试集的原始设计、为什么需要反复修改才能用于 FX-RV32 裸机 CPU 测试、以及测试程序如何与 UVM 验证环境协同工作。

---

## 0. 仿真软件环境

**UVM 验证环境和 RISC-V 测试集均使用 Mentor Graphics Modelsim/Questa 运行**，不支持 Verilator。

| 组件 | 仿真器 | 说明 |
|------|--------|------|
| UVM 验证 (uvm/) | **Modelsim/Questa** | `vsim -c -do "set HEX_FILE ...; do run_msim.tcl"` |
| RISC-V 测试集批量运行 | **Modelsim/Questa** | `batch_run.py` 调用 `run_test_fast.tcl` → `vsim` |
| CoreMark Verilator 仿真 (sim/) | **Verilator** | `cd sim && make run`，仅用于 CoreMark 基准测试 |
| 简单指令测试 (smoke test 等) | **Verilator** | 可在 WSL/Linux 命令行快速验证 |

**为什么 UVM 不能用 Verilator 替代：**

1. **UVM 库依赖**：UVM 1.2 是 SystemVerilog 库，Verilator 不支持 UVM 框架（Verilator 主要支持可综合的 Verilog/SystemVerilog）
2. **MMIO 外设访问**：当前 Verilator 仿真环境（`core_top_sim`）对 0x10000000+ 地址的 MMIO 读写存在已知问题，timer/GPIO/UART 等外设无法通过总线正常访问
3. **中断注入**：UVM Driver 可以通过 SystemVerilog 接口直接控制中断信号，Verilator 的 C++ testbench 缺乏等效机制

**运行环境要求：**

- **Modelsim/Questa**：Windows 环境（开发板所在机器），需在 PATH 中可用 `vsim` 命令
- **Verilator**：Linux/WSL 环境，`sim/` 目录下执行 `make run`
- **Python 脚本**（`clean_adapt.py`, `batch_run.py`, `asm_to_hex.py`）：跨平台，Python 3.6+

---

## 1. riscv-tests 是什么

[riscv-tests](https://github.com/riscv-software-src/riscv-tests) 是 RISC-V 基金会维护的官方指令集测试套件。我们使用的是 `isa` 目录下的 **rv32ui** 测试集（RV32 User-level ISA），共 42 个测试，每个测试覆盖一条或一类指令：

| 类别 | 测试名称 | 数量 |
|------|----------|------|
| 算术逻辑 | add, addi, sub, and, andi, or, ori, xor, xori | 9 |
| 移位 | sll, slli, srl, srli, sra, srai | 6 |
| 比较 | slt, slti, sltu, sltiu | 4 |
| 分支 | beq, bne, blt, bltu, bge, bgeu | 6 |
| 跳转 | jal, jalr | 2 |
| 高位立即数 | lui, auipc | 2 |
| 内存访问 | lb, lbu, lh, lhu, lw, sb, sh, sw | 8 |
| 内存交互 | ld_st, st_ld, ma_data | 3 |
| 杂项 | simple, fence_i | 2 |

### 1.1 原始设计：为 Spike/Proxy Kernel 设计

riscv-tests 的原始目标运行环境是 **Spike ISA 模拟器 + Proxy Kernel (pk)**，这个环境提供了：

- **完整特权级支持**：Machine/Supervisor/User 模式
- **tohost 机制**：地址 0x80001000（约）写入非零值 = 测试失败，写入 0 = 测试通过。Spike 监控该地址并在测试结束时终止仿真
- **trap 处理**：非法指令、ECALL 等异常有标准处理流程
- **地址空间**：代码从 0x80000000 开始（Spike 默认 DRAM 基址）

每个测试的汇编源码遵循统一模板：

```asm
RVTEST_CODE_BEGIN         # 代码段起始宏（展开为跳转 + 对齐指令）
  # ... 测试逻辑 ...
  bne xA, xB, fail        # 如果结果不匹配，跳转到 fail
  # ... 更多测试 ...
  j pass                  # 全部通过，跳转到 pass
RVTEST_CODE_END           # 代码段结束

RVTEST_PASS               # 展开为: fence.i; li TESTNUM,0; li x17,93; li x10,0; ECALL
RVTEST_FAIL               # 展开为: fence.i; li x17,93; mv x10,TESTNUM; ECALL
RVTEST_DATA_BEGIN / END   # 测试数据段
```

### 1.2 ECALL 的三重角色

原始测试中，ECALL 指令出现 **三次**，各有不同用途：

| 出现顺序 | 位置 | 原始用途 | 我们的处理 |
|----------|------|----------|------------|
| 第1个 | trap_vector（地址 0x50 附近） | 环境检查：初始化 mtvec、测试数据指针等 | → **NOP**（跳过 trap 设置，我们的 CPU 已在 RTL 中初始化 CSR） |
| 第2个 | fail 标签 | 测试失败时到达，触发 Spike 的 tohost 机制 | → **J_SELF（死循环）**，CPU 停在此处不会写入 0x3F4 |
| 第3个 | pass 标签 | 测试通过时到达，触发 Spike 退出 | → **JAL → finalizer**（读取 mcycle 并写入 0x3F4） |

> **注意**：有些测试（如 simple）只有 2 个 ECALL（trap_vector + pass），没有独立的 fail handler。还有个别测试（如 ma_data）PASS/FAIL handler 在二进制中的顺序可能与"倒数第二=FAIL"的假设不同，需要 `classify_ecalls()` 自动检测。

---

## 2. 为什么需要反复修改才能测试

### 2.1 根本原因：目标环境不同

```
  riscv-tests 设计的运行环境          FX-RV32 实际运行环境
  ┌─────────────────────────┐        ┌──────────────────────────┐
  │  Spike ISA Simulator    │        │  FX-RV32 CPU (Verilog)   │
  │  + Proxy Kernel (pk)    │        │  5-stage pipeline        │
  │  + 完整特权级           │        │  RV32I only (no M/A/F/D) │
  │  + tohost 监控机制      │        │  裸机运行，无 OS         │
  │  + 地址 0x80000000 起步 │        │  地址 0x00000000 起步    │
  └─────────────────────────┘        └──────────────────────────┘
```

这种差异导致了需要多层适配，每一层都可能引入问题：

### 2.2 地址空间重定位：0x80000000 → 0x00000000

riscv-tests 编译时 ELF 入口地址为 `0x80000000`，而 FX-RV32 的指令 ROM 从 `0x00000000` 开始。

```bash
# clean_adapt.py 使用 objcopy 进行地址平移
riscv32-unknown-elf-objcopy --change-addresses=-0x80000000 <输入> <输出>
```

所有绝对地址引用（JAL 目标、LUI/AUIPC 立即数等）自动减 0x80000000。

### 2.3 ECALL 语义替换：从"通知 Spike"到"测量 mcycle"

这是最核心的修改。原始 ECALL 在 Spike 环境中会触发 trap 并最终通知 Spike 测试结束。FX-RV32 没有操作系统，ECALL 只会触发 trap 进入未定义的 handler。

修改方案（`clean_adapt.py` 的 `adapt_hex()` 函数）：

```
原始 hex 结构:                         适配后 hex 结构:
┌──────────────────────┐              ┌──────────────────────┐
│ line 0: j reset_vector│              │ line 0: JAL → startup │ ← 劫持入口
│ ... test code ...    │              │ ... test code ...    │
│ ECALL #1 (trap)      │ → NOP        │ NOP                   │ ← 跳过 trap 设置
│ ... test code ...    │              │ ... test code ...    │
│ ECALL #2 (fail)      │ → J_SELF     │ J_SELF                │ ← 失败=死循环
│ ECALL #3 (pass)      │ → JAL fin    │ JAL → finalizer       │ ← 通过=写mcycle
│ ... data ...         │              │ ... data ...         │
└──────────────────────┘              ├──────────────────────┤
                                      │ csrrs mcycle          │ ← 启动代码
                                      │ sw 0x3F0(x0)          │    记录开始时间
                                      │ JAL test_entry        │    跳转到测试
                                      ├──────────────────────┤
                                      │ csrrs mcycle          │ ← 终止代码
                                      │ sw 0x3F4(x0)          │    记录结束时间
                                      │ J_SELF                │    停止
                                      └──────────────────────┘
```

`mcycle` 差值 = 测试净执行周期数。`batch_run.py` 解析 transcript 中的 `STORE: [0x000003f0]` 和 `STORE: [0x000003f4]` 来计算。

### 2.4 PASS/FAIL handler 顺序的不确定性

**关键坑点**：`clean_adapt.py` 原生假设"最后一个 ECALL = PASS，倒数第二个 = FAIL"，但这不总是成立。

**反例**：ma_data 测试中：
- BNE 条件分支 → line 444（FAIL handler）
- JAL 无条件跳转... 实际没有直接跳转到 PASS handler 的 JAL
- 控制流在 PASS 情况下通过 `BNE x0, x3 → line 445` 到达 PASS 区域

`classify_ecalls()` 函数通过扫描所有分支/跳转指令的目标地址来自动区分：

```
分支(BEQ/BNE/...) → ECALL位置 的次数 > 0  → FAIL handler
JAL → ECALL位置 的次数 > 0                → PASS handler
```

但仍有边界情况（如 ma_data 中 BNE 目标不是 ECALL 本身而是 handler 的前几条指令），需要手动干预。

### 2.5 fence.i 指令的不兼容

`fence.i` 是 RV32I Zifencei 扩展指令（`0x0000100F`），FX-RV32 不支持该扩展。测试中的 `RVTEST_PASS` 和 `RVTEST_FAIL` 宏展开后会在 ECALL 之前包含 `fence.i` 指令。

执行 `fence.i` 会触发非法指令异常 → CPU trap → 测试无法正常结束。**当前状态**：fence_i 测试预期失败（标记为已知不支持的扩展），但其他 40 个测试的 fence.i 指令被保留（它们仅出现在 ECALL 之前的 pass/fail handler 中——如果测试走到 pass handler，JAL 已经将 ECALL 替换为跳转，fence.i 之前的代码路径已经被 NOP/JAL 覆盖）。

### 2.6 test_entry 的自动检测

原始 hex 的 line 0 是 `j reset_vector`（JAL 指令）。`get_reset_vector_line()` 解码该 JAL 的立即数偏移来定位 test_entry：

```python
# 示例: 0x0500006f = JAL x0, offset=0x50
# offset=0x50 → target line = 0x50 / 4 = 20
```

早期版本硬编码 `test_entry_line = 1`（即地址 0x4 = trap_vector），导致所有测试直接从 trap handler 开始执行，跳过了正常的 reset 初始化流程。

---

## 3. UVM 验证环境的配合

### 3.1 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                     UVM Testbench (uvm_tb_top.sv)           │
│                                                             │
│  ┌─────────────┐   ┌──────────┐   ┌──────────────────────┐ │
│  │ cpu_if (接口) │   │ core_top │   │ inst_rom / data_ram │ │
│  │ clk/rst_n    │◄─►│ (DUT)    │◄─►│ (仿真内存)          │ │
│  │ bus_re/we    │   │ 5-stage  │   │ inst_rom: 4096×32bit│ │
│  │ bus_addr     │   │ pipeline │   │ data_ram: 64KB      │ │
│  │ bus_rdata    │   └──────────┘   └──────────────────────┘ │
│  │ bus_ready    │                                            │
│  └──────┬───────┘                                            │
│         │ monitor 采样                                       │
│  ┌──────▼──────────────────────────────────────────────────┐ │
│  │              UVM 环境                                    │ │
│  │  ┌────────┐  ┌──────────┐  ┌────────────┐              │ │
│  │  │ Driver │  │ Monitor  │  │ Reference  │              │ │
│  │  │ 加载   │  │ 采样总线 │  │ Model      │              │ │
│  │  │ hex→ROM│  │ 事务     │  │ 期望值生成 │              │ │
│  │  └────────┘  └────┬─────┘  └─────┬──────┘              │ │
│  │                   │              │                      │ │
│  │              ┌────▼──────────────▼──────┐               │ │
│  │              │     Scoreboard           │               │ │
│  │              │  DUT 结果 vs 参考模型     │               │ │
│  │              │  Mismatch 检测           │               │ │
│  │              └──────────────────────────┘               │ │
│  └─────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 hex 文件加载流程

```
clean_adapt.py 生成的 hex 文件
         │
         │ (由 batch_run.py 复制到 test.hex)
         ▼
┌─────────────────────┐
│ uvm_tb_top.sv       │
│ load_program()      │
│  读取 test.hex      │
│  每行 = 32-bit 指令  │
│  写入 inst_rom[i]   │
│  同时复制到          │
│  data_ram[i]        │  ← 为 load/store 测试准备
└─────────────────────┘
         │
         ▼
   UVM Driver 释放复位
         │
         ▼
   core_top 从 inst_rom[0] 取第一条指令（JAL → startup）
         │
         ▼
   startup 代码执行：
     csrrs mcycle → sw 0x3F0
     JAL test_entry → 测试代码
```

### 3.3 UVM Monitor 采样与 Scoreboard 比对

Monitor 在每个时钟上升沿采样 core_top 的内部信号，生成 `cpu_transaction`：

```systemverilog
// 事务类型
typedef enum { WB, STORE, LOAD, STALL } trans_type_t;

// WB 事务：寄存器写回
//   记录 rd_addr, rd_data（供 Scoreboard 比对）
// STORE 事务：内存写入
//   记录 bus_addr, bus_wdata（更新参考内存模型）
// LOAD 事务：内存读取
//   记录 bus_addr（用于覆盖率统计）
// STALL 事务：流水线停顿
//   记录 stall_duration（用于性能分析）
```

**参考模型**：Scoreboard 维护一个软件级寄存器堆 (`ref_regs[32]`) 和内存模型 (`ref_mem[...]`)。每次收到 WB 事务时，比对 DUT 的写回数据与参考模型的预期值：

```
DUT: x5 <= 0x0FF00FF0     (实际硬件结果)
REF: x5 <= 0x0FF00FF0     (参考模型预期)
     ↓ 相等 = match，不等 = mismatch++
```

参考模型按照 RISC-V ISA 语义执行"完美"的指令模拟——它不受流水线冒险、转发路径、时序问题的影响。任何硬件 bug（如转发错误、符号扩展缺失）都会体现为 DUT 与参考模型的 mismatch。

### 3.4 总线简化（关键优化）

UVM testbench 中的总线逻辑经过简化：

```systemverilog
// 简化后: 总线读直接从 data_ram 获取
// data_ram 在 load_program() 时已预装载 hex 文件的所有内容
if (vif.bus_re && !vif.bus_we) begin
    if (vif.bus_addr[31:2] < 16384) begin
        bus_rdata_mux = data_ram[vif.bus_addr[31:2]];
        bus_ready_mux = 1'b1;  // 单周期响应
    end
end
```

**简化内容**：
- data_ram 读取为组合逻辑（0 周期延迟），而非真实的 1 周期 SRAM 延迟
- 写操作直接写入 data_ram，下一个周期即可读取（write-through 语义）
- 移除了 `data_ram_written` 追踪机制——不再区分"初始化数据"和"运行时写入数据"

这使得 load-use 停顿分析更清晰——停顿仅由 RAW hazard 的流水线时序决定，不受外部存储器延迟影响。

### 3.5 UVM 报告与 batch_run.py 的协作

UVM Scoreboard 在 `report_phase` 输出：

```
# UVM_INFO [SBD]   Register writes (WB):  368
# UVM_INFO [SBD]   Store operations:      2      ← 包括 0x3F0 和 0x3F4
# UVM_INFO [SBD]   Load operations:       24
# UVM_INFO [SBD]   Stall events:          3
# UVM_INFO [SBD]   Max stall duration:    2 cycles
# UVM_INFO [SBD]   Mismatches:            0      ← 0=硬件与参考模型完全一致
# UVM_INFO [SBD] *** LOAD-USE HAZARD TEST PASSED ***
```

`batch_run.py` 独立解析 transcript 中的 STORE 行：

```python
# 搜索 STORE: [0x000003f0] → 提取启动时的 mcycle 值
sv = int(line.split('<= ')[-1].strip(), 16)  # startup value
# 搜索 STORE: [0x000003f4] → 提取结束时的 mcycle 值
ev = int(line.split('<= ')[-1].strip(), 16)  # end value
cycles = ev - sv  # 净测试周期数
```

两个检查维度互补：
- **UVM Scoreboard**：硬件行为是否正确（寄存器值、内存内容匹配参考模型）
- **batch_run mcycle**：执行时间是否确定（5 次重复周期数完全相同）

---

## 4. 完整数据流

```
riscv-tests/isa/rv32ui-p-add  (ELF, 0x80000000 起步)
        │
        ▼ clean_adapt.py step 1: objcopy --change-addresses=-0x80000000
/tmp/rv32ui-p-add_clean.elf   (ELF, 0x00000000 起步)
        │
        ▼ clean_adapt.py step 2: objcopy -O binary → hex
2144 lines of hex             (原始机器码)
        │
        ▼ clean_adapt.py step 3: adapt_hex()
        │   · find_ecalls()          → [86, 417, 422]
        │   · classify_ecalls()      → PASS=422, FAIL=417
        │   · get_reset_vector_line() → test_entry_line=20
        │   · ECALL[86]  → NOP
        │   · ECALL[417] → J_SELF
        │   · ECALL[422] → JAL → finalizer
        │   · 前面添加 JAL → startup
        │   · 末尾添加 startup 代码 + finalizer
        ▼
riscv_tests/hex/add.hex       (2150 lines, 适配后的机器码)
        │
        ▼ batch_run.py: cp add.hex → test.hex
/mnt/d/FX-RV32_Tests/uvm/test.hex
        │
        ▼ Modelsim: vsim -c -do run_test_fast.tcl
        │   · load_program() 加载 test.hex → inst_rom + data_ram
        │   · 释放复位，CPU 开始执行
        │   · Monitor 采样 → Scoreboard 比对
        ▼
transcript                    (仿真日志)
        │
        ▼ batch_run.py: 解析 STORE 事件
        │   sv = 0x00000005 (mcycle 启动值)
        │   ev = 0x0000021F (mcycle 终止值)
        │   cycles = 544
        │
        ▼ (5次重复结果完全相同)
add: 544 cycles (det=YES, σ=0.0)  ✅
```

---

## 5. 常见问题与调试技巧

### 5.1 测试 FAILED (0/5)——完全没有 STORE 事件

**原因**：测试程序从未执行到 PASS 或 FAIL handler。

常见子原因：
1. **ECALL 补丁错误**：PASS handler 的 JAL 目标计算错误，跳转到非预期地址
2. **trap_vector 未正确处理**：ECALL #1 (trap) 应该是 NOP，但如果其他 ECALL 也被误打成 NOP...
3. **非法指令**：CPU 遇到不支持的指令（如 fence.i）触发 trap 后无法恢复
4. **死循环**：测试逻辑错误或转发 bug 导致无限循环

**调试方法**：
```bash
# 运行单测试，查看 transcript 中的 UVM 日志
grep -E "STORE|Mismatches|PASS|FAIL|trap" transcript
```

### 5.2 测试 FAILED (3/5)——部分迭代失败

**原因**：非确定性行为。常见于：
1. **未初始化的信号**：某次运行中偶然为 0，另一次为 1
2. **时序竞争**：跨时钟域信号未同步
3. **流水线控制信号的竞态**：flush/stall 在不同迭代中的时序略有不同

FX-RV32 当前设计中所有通过测试的 σ=0.0，证明不存在此类问题。

### 5.3 Mismatches ≠ 0 但 STORE 存在

**原因**：硬件执行了测试代码但某些指令结果与参考模型不一致。

**调试方法**：Scoreboard 在 mismatch 发生时打印详细日志（DUT 值 vs 期望值）。第一个 mismatch 通常是根因——后续 mismatch 可能是级联错误。

### 5.4 快速测试 vs 完整编译

| 模式 | TCL 脚本 | 每测试耗时 | 适用场景 |
|------|----------|-----------|----------|
| 完整编译 | `run_test.tcl` → `run_msim.tcl` | ~2 分钟 | RTL 修改后首次验证 |
| 快速模式 | `run_test_fast.tcl` → `run_msim_fast.tcl` | ~5 秒 | RTL 不变，仅换 hex 文件 |

**前提**：快速模式需要先执行 `compile_once.tcl` 完成一次性编译。

---

## 6. 总结

riscv-tests 是为 Spike 模拟器设计的，用于 FX-RV32 裸机 CPU 需要经过多层适配：

| 适配层 | 问题 | 解决方案 |
|--------|------|----------|
| 地址空间 | ELF 入口 0x80000000 | objcopy 重定位到 0x00000000 |
| 测试结束机制 | ECALL 通知 Spike | ECALL→NOP/J_SELF/JAL finalizer |
| mcycle 测量 | 原始测试不测量周期 | 附加 startup/finalizer 代码 |
| PASS/FAIL 顺序 | 不确定哪个 ECALL 是 pass | classify_ecalls() 自动分析分支目标 |
| fence.i 指令 | FX-RV32 不支持 Zifencei | 标记 fence_i 测试为预期失败 |

UVM 环境提供两层验证：Scoreboard 比对硬件行为正确性 + mcycle 测量验证时序确定性。
