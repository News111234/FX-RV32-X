# ISR 修复验证测试报告

**日期**: 2026-06-30（更新 2026-07-01）  
**测试目的**: 验证 `ifu_top.v` + `hazard_unit.v` 中断相关 bug 修复 + 多 Bank 影子寄存器扩展功能  
**测试平台**: ModelSim SE-64 10.6e  
**指令存储器**: **inst_rom**（组合读，`USE_INST_ROM=1`, `SYNC_INST_MEM=0`）  
**中断延迟**: **2 周期**（inst_rom 模式）  
**测试范围**: 10 个测试程序，覆盖基本 ISR、嵌套中断、Bank 溢出/排队、寄存器完整性、降级复用、尾链优化

---

## 1. RTL Bug 修复摘要

### Bug 1: `ifu_top.v` — interrupt_taken_i 期间 PC hold 导致 ISR 停滞

**文件**: `core/ifu/ifu_top.v` + `sim/rtl/core/ifu/ifu_top.v`

| | 修复前（错误）| 修复后（正确）|
|---|---|---|
| `next_pc` | `(interrupt_taken_i) ? pc_value` | `(interrupt_taken_i) ? pc_value + 32'h4` |

**根因**: `interrupt_taken_i` 在 T2-T3 期间仅需挡住旧 EX 分支/跳转信号（优先级排在 `branch_taken_i`/`jump_taken_i` 前面），PC 应正常递增 `pc+4`。写成 `pc_value`（hold）导致 ISR 停滞一周期。

### Bug 2: `hazard_unit.v` — control_hazard_r 在中断期间抑制（BRAM 保护）

**文件**: `core/hazard/hazard_unit.v` + `sim/rtl/core/hazard/hazard_unit.v`

BRAM 模式（`SYNC_INST_MEM=1`）下，旧分支的 `control_hazard_r` 寄存器残留在中断 T2-T3 期间会导致 IF/ID 被错误冲刷。ROM 模式（`SYNC_INST_MEM=0`）不受影响。

修复：`control_hazard_r_active = control_hazard_r && !interrupt_taken_i`。

### Bug 3: `hazard_unit.v` — 旧分支的 flush_if/flush_id 冲掉 ISR 第一条指令

**文件**: `core/hazard/hazard_unit.v` + `sim/rtl/core/hazard/hazard_unit.v`

**根因**: `intr_flush_id_o = 0` 保证中断路径不冲刷 IF/ID，但旧分支/跳转产生的 `flush_if_o = control_hazard` 通过 `if_id_reg` 的 `flush_i \|\| intr_flush_i` OR 逻辑仍会冲刷 IF/ID。当 main loop 里有 `j` 指令且中断恰好在 `j` 处于 EX 时触发，第一条中断向量入口指令（如 `j isr_timer`）被冲掉，PC 顺序递增到下一向量表项（`j spin`），进入死循环。

修复: `flush_if_o = control_hazard_extended && !interrupt_taken_i` 和 `flush_id_o` 同理。中断期间抑制来自旧分支的冲刷，让第一条 ISR 指令通过 IF/ID。

---

## 2. 测试程序

### 2.1 single_intr_test — 单次 Timer 中断

**验证目标**: 基本的 Timer 中断触发、ISR 执行、MRET 返回。

**测试流程**:
1. 配置 mtvec = 0x201（vectored 模式，base=0x200）
2. 使能 Timer 中断（mie[7]=1），开启全局中断（mstatus.MIE=1）
3. 设置 Timer: one-shot, LOAD=100
4. 主循环轮询 mem[64]（初始值 0），等待 ISR 将其改为非零值
5. Timer 触发 → ISR 将 DEAD0001 写入 mem[64] → 清除 Timer 中断 → MRET
6. 主循环检测到 mem[64] ≠ 0 → 写 tohost=0（PASS）

**检查点**: mem[64] = 32'hDEAD0001, tohost = 0

**预期中断行为**: 
- Timer 触发 → intr_take_now → PC 跳转到 handler（2 周期延迟）
- shadow_save 单周期脉冲（bank_ptr 0→1）
- ISR 执行 → shadow_restore 单周期脉冲（MRET, bank_ptr 1→0）

### 2.2 ultra_min_test — 最小中断

**验证目标**: 最精简的中断场景——ISR 仅一条 `addi` + `sw`，验证核心中断通路。

**测试流程**:
1. 配置 mtvec = 0x201, 使能 Timer 中断（mie[7]=1）
2. 设置 Timer: one-shot, LOAD=40
3. 软件延迟循环等待 Timer 触发
4. ISR: `addi t0, x0, 0x42` → `sw t0, 0x100(x0)` → 清除 Timer → MRET
5. 主程序检查 mem[64] == 0x42 → tohost=0（PASS）

**检查点**: mem[64] = 32'h00000042, tohost = 0

### 2.3 no_intr_test — 无中断

**验证目标**: 确认在中断未使能时，程序正常执行不会被误触发的中断打断。

**测试流程**:
1. 不配置 mtvec，不使能任何中断（mie=0, mstatus.MIE=0）
2. 直接写 mem[64] = 0x42, mem[65] = 0xDEADBEEF
3. 写 tohost=0（PASS）后进入死循环

**检查点**: mem[64] = 32'h00000042, mem[65] = 32'hDEADBEEF

**预期中断行为**: 全程无 INTR TAKEN，bank_ptr 保持为 0

### 2.4 nested_test — 嵌套中断（GPIO 抢占 Timer）

**验证目标**: 高优先级 GPIO 中断在 Timer ISR 执行期间抢占，验证嵌套中断的 bank_ptr 切换和影子寄存器。

**测试流程**:
1. 配置 mtvec = 0x201, 使能 Timer（mie[7]）+ GPIO（mie[11]）中断
2. 设置 GPIO: 输入模式、上升沿触发、pin0 中断使能
3. 设置 Timer: one-shot, LOAD=200（约 1μs 后触发）
4. Testbench 在 ~1.6μs 时拉高 GPIO pin0，模拟外部 GPIO 中断
5. Timer 先触发 → ISR 写 DEAD0001 → 清除 Timer → 重开 MIE → 延迟循环
6. GPIO 在延迟循环期间触发 → **嵌套进入**（bank_ptr 1→2）→ ISR 写 BEEF0001 → 清除 GPIO → MRET
7. 回到 Timer ISR 延迟循环 → 清除 preempted 标志 → MRET
8. 主循环检测 gpio_count ≠ 0 → tohost=0（PASS）

**检查点**: mem[64] = 32'hDEAD0001（Timer）, mem[65] = 32'hBEEF0001（GPIO）

**预期中断行为**:
- bank_ptr: 0 → 1（Timer 进入）→ 2（GPIO 嵌套抢占）→ 1（GPIO MRET）→ 0（Timer MRET）
- shadow_save: 两次（Timer 进入 + GPIO 嵌套进入）
- shadow_restore: 两次（GPIO MRET + Timer MRET）

### 2.5 overflow_minimal — 单 Bank 基本 ISR

**验证目标**: SHADOW_BANKS=1 时最基本的 Timer ISR 能正常运行。

**测试流程**: 同 ultra_min_test，但 SHADOW_BANKS=1

**检查点**: mem[64] = 32'h00000042, tohost = 0

**预期中断行为**: bank_ptr 0→1→0，单影子 Bank 工作正常

### 2.6 overflow_test — Bank 溢出/排队

**验证目标**: SHADOW_BANKS=1 + OVERFLOW_POLICY=0（硬限制）时，Bank 满后新中断排队等待。

**测试流程**:
1. 配置 mtvec = 0x201, 使能 Timer（mie[7]）+ GPIO（mie[11]）
2. 设置 GPIO: 输入模式、上升沿触发、pin0 中断使能
3. 设置 Timer: one-shot, LOAD=50
4. Testbench 在 Timer ISR 执行期间拉高 GPIO pin0
5. Timer 触发 → ISR 写 DEAD0001 → 清除 Timer → 重开 MIE → 延迟循环（300 次）
6. GPIO 尝试进入但 **bank_full=1** 阻塞 → GPIO 保持 pending
7. Timer ISR MRET → **GPIO 作为新中断立即进入** → ISR 写 BEEF0002 → MRET
8. 主循环检查 timer=DEAD0001, gpio=BEEF0002 → tohost=0（PASS）

**检查点**: mem[64] = 32'hDEAD0001（Timer）, mem[65] = 32'hBEEF0002（GPIO, 排队标记）

**预期中断行为**:
- Timer 进入: bank_ptr 0→1
- GPIO 尝试嵌套: 被 bank_full 阻塞，保持 pending
- Timer MRET: bank_ptr 1→0
- GPIO 作为新中断进入: bank_ptr 0→1（非嵌套，是全新的中断）
- GPIO MRET: bank_ptr 1→0

### 2.7 context_integrity_test — 嵌套后寄存器完整性

**验证目标**: 两级嵌套（Timer→GPIO）返回后，x1-x31 全部 31 个通用寄存器恢复为中断前的值，验证影子寄存器在嵌套场景下无寄存器覆盖或错位。

**测试流程**:
1. 主程序预加载 x1=1, x2=2, ..., x31=31
2. 配置 Timer + GPIO 两级嵌套（同 nested_test）
3. Timer ISR 故意篡改 x1-x5 为错误值（0xAA-0xEE）
4. GPIO ISR 故意篡改 x6-x10 为错误值（0x11-0x55）
5. 两级嵌套返回后，逐条比对 x1-x31 是否恢复为原始值
6. 任一寄存器不匹配 → 写 tohost=1（FAIL）；全部匹配 → tohost=0（PASS）

**检查点**: tohost = 0（31 个寄存器全部正确恢复）

**预期中断行为**: 同 nested_test，额外验证 shadow_restore 的正确性不受 ISR 内部寄存器篡改影响。

### 2.8 degradation_test — 降级复用策略（BANKS=1, POL=1）

**验证目标**: Bank 满时 OVERFLOW_POLICY=1（降级复用），高优先级中断直接抢占并覆盖最深嵌套层 Bank。

**测试流程**:
1. BANKS=1, OVERFLOW_POLICY=1
2. Timer 先触发 → ISR 写 DEAD0001 → 重开 MIE → 延迟循环
3. GPIO 在延迟循环期间到达 → Bank 满但 POL=1 → **直接抢占覆盖 Bank[0]**
4. GPIO ISR 写 BEEF0003（降级标记，区别于正常嵌套的 BEEF0001）→ MRET
5. 主循环检测 gpio marker → tohost=0

**检查点**: mem[64]=DEAD0001, mem[65]=BEEF0003

**预期中断行为**: Timer 上下文被 GPIO 覆盖丢失。Timer MRET 后将恢复到被覆盖的上下文（行为未定义）。

**与 overflow_test 的区别**:
| | overflow_test (POL=0) | degradation_test (POL=1) |
|---|---|---|
| GPIO 进入时机 | Timer ISR 完成后（排队）| Timer ISR 执行中（抢占覆盖）|
| GPIO marker | BEEF0002（排队标记）| BEEF0003（降级覆盖标记）|
| Timer 上下文 | 完整保留 | 被覆盖丢失 |

### 2.9 tail_chain_test — 尾链优化

**验证目标**: MRET 时刻若有中断 pending，跳过 shadow_restore，Bank 指针不变，新中断直接复用当前 Bank。

**测试流程**:
1. 配置 Timer（one-shot）+ GPIO 中断
2. GPIO ISR 末尾：置 tail_chain flag=1，重新使能 Timer（LOAD=1，极短计数）→ MRET
3. MRET 时 Timer 已 pending → tail_chain_detect=1 → 跳过 shadow_restore
4. Timer ISR 立即进入，记录 mcycle 值

**检查点**: mem[64]=1（tail_chain flag）, mem[65]≥1（timer_count）, mem[66]≥1（gpio_count）, mem[67]=GPIO 进入时的 mcycle, mem[68]=尾链后 Timer 进入时的 mcycle

**预期中断行为**: GPIO MRET 不触发 shadow_restore（bank_ptr 不变），Timer 以 2 周期延迟直接进入。

### 2.10 triple_nested_test — 三级嵌套（SW→Timer→GPIO）

**验证目标**: 三级中断嵌套，bank_ptr 0→1→2→3→2→1→0，每级延迟均为 2 周期。

**测试流程**:
1. 配置 SW（mie[3]）+ Timer（mie[7]）+ GPIO（mie[11]）三级中断
2. Testbench 在程序配置完成后脉冲 sw_intr → SW ISR 进入（bank_ptr 0→1）
3. SW ISR 写 CAFE0003 → 重开 MIE → 延迟循环
4. Timer 到期 → 抢占 SW ISR（bank_ptr 1→2）→ 写 DEAD0007 → 延迟循环
5. GPIO 上升沿 → 抢占 Timer ISR（bank_ptr 2→3）→ 写 BEEF000B → MRET
6. 三级逐级返回：GPIO→Timer→SW→主程序

**检查点**: mem[64]=CAFE0003（SW）, mem[65]=DEAD0007（Timer）, mem[66]=BEEF000B（GPIO）

**预期中断行为**: bank_ptr 0→1→2→3→2→1→0，每级进入延迟 2 周期，shadow_save 三次，shadow_restore 三次。

**RTL 依赖**: 需 `soc_top.v` 暴露 `intr_software_i` 端口，`tb_nested_check.v` 添加 `sw_intr` 驱动。

**与 nested_test 的区别**:
| | nested_test (BANKS=4) | overflow_test (BANKS=1) |
|---|---|---|
| GPIO 进入时机 | Timer ISR 执行中（嵌套）| Timer ISR 完成后（排队）|
| GPIO marker | BEEF0001（嵌套标记）| BEEF0002（排队标记）|
| bank_ptr | 0→1→2→1→0 | 0→1→0→1→0 |
| shadow_save 次数 | 2 次 | 2 次（分两次独立中断）|

---

## 3. 命令行测试（CLI）

### 3.1 汇编程序（使用修复后的汇编器）

```bash
cd python
python asm_to_hex.py ../sim/single_intr_test.s ../sim/single_intr_test.hex
python asm_to_hex.py ../sim/ultra_min_test.s ../sim/ultra_min_test.hex
python asm_to_hex.py ../sim/no_intr_test.s ../sim/no_intr_test.hex
python asm_to_hex.py ../sim/nested_test.s ../sim/nested_test.hex
python asm_to_hex.py ../sim/overflow_minimal.s ../sim/overflow_minimal.hex
python asm_to_hex.py ../sim/overflow_test.s ../sim/overflow_test.hex
```

### 3.2 一键 CLI 测试（推荐）

```bash
cd sim
bash run_all_tests.sh
# 输出:
#   1.single_intr           PASS
#   2.ultra_min             PASS
#   3.no_intr               PASS
#   4.nested                PASS
#   5.overflow_min          PASS
#   6.overflow              PASS
#   TOTAL: 6  PASS: 6  FAIL: 0
```

### 3.3 CLI 单测脚本（每个测试一个 DO 文件，自动编译+运行）

```bash
cd sim

# 基本 ISR (BANKS=4)
vsim -c -do run_cli_single_intr.do       # 单次 Timer ISR, DEAD0001
vsim -c -do run_cli_ultra_min.do         # 最小中断, 0x42
vsim -c -do run_cli_no_intr.do           # 无中断, 0x42

# 嵌套中断 (BANKS=4)
vsim -c -do run_cli_nested.do            # Timer→GPIO 嵌套, DEAD0001+BEEF0001

# Bank 溢出 (BANKS=1)
vsim -c -do run_cli_overflow_min.do      # 单 Bank, 0x42
vsim -c -do run_cli_overflow.do          # Bank 满排队, DEAD0001+BEEF0002
```

每个脚本独立完成：删除旧编译库 → 编译 RTL → 加载 → 运行 → 输出结果和 PASS/FAIL → 退出。

### 3.4 CLI 测试结果

| # | 测试 | BANKS | mem[64] | mem[65] | 中断行为 | 结果 |
|---|------|-------|---------|---------|---------|------|
| 1 | single_intr | 4 | DEAD0001 | — | C119 进入, C127 写 marker, C130 MRET | **PASS** ✅ |
| 2 | ultra_min | 4 | 0x42 | — | C51 进入, C56 写结果, C59 MRET | **PASS** ✅ |
| 3 | no_intr | 4 | 0x42 | — | 无中断触发（正确）| **PASS** ✅ |
| 4 | nested | 4 | DEAD0001 | BEEF0001 | bank_ptr 0→1→2→1→0, 嵌套成功 | **PASS** ✅ |
| 5 | overflow_min | 1 | 0x42 | — | 单 Bank Timer ISR 正常 | **PASS** ✅ |
| 6 | overflow | 1 | DEAD0001 | BEEF0002 | Bank 满排队, GPIO 等 Timer MRET 后进入 | **PASS** ✅ |

**中断延迟验证**（single_intr_test，200MHz 时钟，ROM 模式）：
- Timer 配置: LOAD=100（约 500ns）
- 中断接受: C119（698ns）— `bank_ptr=1 save=1` 单周期完成
- ISR 写结果: C127（738ns）— `mem[64] = DEAD0001`
- MRET: C130（753ns）
- 主程序检测到结果: C141（808ns）— `tohost = 0`（PASS）
- **中断延迟 = 2 周期**（intr_take_now → ISR 第一条指令执行），符合设计目标

**嵌套中断验证**（nested_test）：
- C225: Timer ISR 进入, bank_ptr=1, save=1
- C304: GPIO 抢占 Timer ISR, bank_ptr=2, save=1 ← 嵌套成功
- C315: GPIO ISR MRET, bank_ptr=2→1
- C340: Timer ISR MRET, bank_ptr=1→0
- 结果: timer_count=DEAD0001, gpio_count=BEEF0001 ✓

**Bank 溢出/排队验证**（overflow_test, BANKS=1, 硬限制）：
- Timer ISR 进入, bank_ptr=1. GPIO 尝试嵌套被 bank_full 阻塞.
- Timer ISR MRET 后 GPIO 立即作为新中断进入.
- 结果: timer_count=DEAD0001, gpio_count=BEEF0002（排队标记）✓

---

## 4. GUI 波形测试

### 4.1 GUI 测试脚本

| 脚本 | 测试程序 | 参数 | 用途 |
|------|---------|------|------|
| `run_gui_single_intr.do` | single_intr_test | BANKS=4 | 单次中断，li+sw ISR，验证转发+shadow |
| `run_gui.do` | ultra_min_test | BANKS=4 | 最小中断，论文截图用 |
| `run_gui_no_intr.do` | no_intr_test | BANKS=4 | 无中断，mem[64]=0x42 |
| `run_gui_nested.do` | nested_test | BANKS=4 | 嵌套中断波形，bank_ptr 0→1→2→1→0 |
| `run_gui_overflow.do` | overflow_test | BANKS=1 | Bank 溢出排队波形 |
| `run_gui_overflow_minimal.do` | overflow_minimal | BANKS=1 | 单 Bank 基本 ISR |
| `run_gui_overflow_banks4.do` | overflow_test | BANKS=4 | 4 Bank 模式溢出 |

### 4.2 运行 GUI 测试

```bash
cd sim

# 基本 ISR 验证
vsim -do run_gui_single_intr.do

# 最小中断验证（论文截图用）
vsim -do run_gui.do

# 无中断验证
vsim -do run_gui_no_intr.do

# 嵌套中断验证
vsim -do run_gui_nested.do

# Bank 溢出验证
vsim -do run_gui_overflow.do

# Bank 溢出最小测试
vsim -do run_gui_overflow_minimal.do
```

CLI 和 GUI 用法一致：CLI 加 `-c` 出文字结果，GUI 不加 `-c` 打开波形窗口。```

### 4.3 GUI 波形关键观察点

| 信号组 | 关键信号 | 观察要点 |
|--------|---------|---------|
| 时钟与复位 | clk, rst_n | 200MHz (2.5ns 半周期) |
| IF/ID 流水线 | PC, IF_instr, IFID_instr | 中断时 PC 跳转到 handler，flush_if 在中断期间为 0 |
| 中断系统 | intr_taken, bank_ptr, shadow_save/restore | bank_ptr 变化、save/restore 单周期脉冲 |
| 转发 | fwdA, fwdB, op2_selected | ISR 中 li+sw 转发路径 |
| 总线与存储 | bus_we, bus_wdata, mem[64] | sw 写 marker 到 data_ram |
| 流水线控制 | flush_if, stall_if, flush_id | **中断期间 flush_if=0**，不被旧分支误冲刷 |

**核心验证点**（以 single_intr_test 为例）：
1. `intr_taken` 上升沿 → `bank_ptr` 从 0 变为 1（同一时钟沿）
2. `shadow_save` = 1（单周期脉冲，保存 x1-x31）
3. ISR 第一条指令进入 IF → ID → EX（无多余 stall/flush）
4. `flush_if` = 0 在中断接受期间（不受旧分支 `j` 指令影响）
5. `bus_wdata` = 0xDEAD0001 出现在总线上（sw 指令执行）
6. MRET 执行 → `shadow_restore` = 1（单周期脉冲）

---

## 5. BRAM 模式（inst_bram）测试

### 6.1 当前状态

⚠️ **BRAM 模式暂不可靠，仅供调试。** ISR 本身能正确执行并写入结果，但 MRET 返回主程序后会跑飞（反复 MRET + 写 mem[0]），原因是 `control_hazard_r` 2 周期扩展逻辑在 BRAM 同步读延迟下 PC 未正确对齐。

### 6.2 ROM vs BRAM 对比

| | ROM (inst_rom) | BRAM (inst_bram) |
|---|---|---|
| 参数 | `USE_INST_ROM=1, SYNC_INST_MEM=0` | `USE_INST_ROM=0, SYNC_INST_MEM=1` |
| 读方式 | 组合逻辑，零延迟 | 同步读，1 周期延迟 |
| 中断延迟 | **2 周期** | 3 周期 |
| 测试状态 | ✅ 全部 PASS | ⚠️ ISR 正确，返回异常 |

### 6.3 如何运行 BRAM 测试

打开任意 `run_cli_*.do`，把 `-gUSE_INST_ROM=1` 改成 `0` 即可：

```bash
# 方式一：直接改 DO 文件（推荐）
#   编辑 run_cli_single_intr.do，找到 -gUSE_INST_ROM=1，改成 -gUSE_INST_ROM=0
vsim -c -do run_cli_single_intr.do

# 方式二：不改文件，命令行覆盖参数（需先编译）
cp single_intr_test.hex nested_test.hex
vsim -onfinish stop -c -gUSE_INST_ROM=0 -gSHADOW_BANKS=4 work.tb_nested_check \
  -do "run 10us; ...; quit -f"
```

---

## 7. 新增测试（2026-07-01）

为第二篇 TVLSI 论文补充的中断嵌套量化测试。

### 7.1 context_integrity_test — 嵌套中断后寄存器完整性

**验证目标**: 两级嵌套（Timer→GPIO）返回后，x1-x31 全部 31 个通用寄存器恢复为中断前的值。

**测试方法**: 主程序预加载 x1=1, x2=2, ..., x31=31。Timer ISR 和 GPIO ISR 内部故意篡改 x1-x10 为错误值。嵌套返回后逐条比对全部 31 个寄存器。

**检查点**: tohost = 0（全部寄存器比对通过）

**CLI 命令**:
```bash
cd sim && vsim -c -do run_cli_context.do
```

**结果**: ✅ **PASS** — 两级嵌套 + 寄存器篡改后，shadow_restore 正确恢复了所有 31 个寄存器的原始值。

### 7.2 degradation_test — 降级复用策略（BANKS=1, POL=1）

**验证目标**: Bank 满时 OVERFLOW_POLICY=1（降级复用），高优先级中断仍可抢占，覆盖最深嵌套层 Bank。

**测试方法**: BANKS=1, POL=1。Timer ISR 先进入（占用 Bank[0]），GPIO 在 Timer ISR 延迟循环期间到达。由于 Bank 满但 POL=1，GPIO 直接抢占并覆盖 Bank[0]（Timer 上下文被牺牲）。GPIO ISR 写入 BEEF0003（降级标记，区别于正常嵌套的 BEEF0001）。

**检查点**: mem[65] = 32'hBEEF0003（GPIO 成功抢占）

**CLI 命令**:
```bash
cd sim && vsim -c -do run_cli_degradation.do
```

**结果**: ✅ **PASS** — GPIO 在 Bank 满时成功抢占，降级复用策略生效。

**与 overflow_test 的对比**:
| | overflow_test (POL=0) | degradation_test (POL=1) |
|---|---|---|
| GPIO 进入时机 | Timer ISR 完成后（排队）| Timer ISR 执行中（抢占覆盖）|
| GPIO marker | BEEF0002（排队标记）| BEEF0003（降级覆盖标记）|
| Timer 上下文 | 完整保留 | 被覆盖丢失 |

### 7.3 tail_chain_test — 尾链优化

**验证目标**: MRET 时刻若有中断 pending，跳过 shadow_restore，Bank 指针不变。

**测试方法**: GPIO ISR 结束前置位 tail_chain flag，在 MRET 前重新使能 Timer（LOAD=1），使 MRET 时 Timer 已 pending。下一 Timer ISR 读取 mcycle 记录进入时间。

**检查点**: tail_chain flag = 1, timer_count >= 1, gpio_count >= 1

**CLI 命令**:
```bash
cd sim && vsim -c -do run_cli_tailchain.do
```

**结果**: ✅ **PASS** — GPIO ISR 执行 + 尾链路径共 29 周期（mcycle 393→422），Timer 在 GPIO MRET 后立即进入。

### 7.4 triple_nested_test — 三级嵌套

**验证目标**: 三级嵌套（SW→Timer→GPIO），bank_ptr 0→1→2→3→2→1→0。

**测试方法**: `soc_top.v` 新增 `intr_software_i` 输入端口，`tb_nested_check.v` 新增 `sw_intr` reg 并在 ~400ns 后脉冲触发。主程序使能 mie[3]+mie[7]+mie[11]，SW 先进入 → Timer 抢占（优先级 7>3）→ GPIO 抢占（优先级 11>7）。三级 ISR 分别写入 CAFE0003、DEAD0007、BEEF000B。

**检查点**: mem[64]=CAFE0003, mem[65]=DEAD0007, mem[66]=BEEF000B

**CLI 命令**:
```bash
cd sim && vsim -c -do run_cli_triple.do
```

**结果**: ✅ **PASS** — 三级嵌套全部触发，每级延迟 2 周期。

**RTL 修改**:
| 文件 | 修改 |
|------|------|
| `soc/top/soc_top.v` | 新增 `intr_software_i` 输入端口，连接至 `core_intr_software` |
| `tb/tb_nested_check.v` | 新增 `sw_intr` reg + `sw_intr=0` 初始化 + ~400ns 脉冲 |

---

## 8. 测试结论

### 8.1 基础 ISR（Bug 修复验证，2026-06-30）

- ✅ **Bug 1 已修复**: `ifu_top.v` 的 `interrupt_taken_i` 期间 PC 正常递增，ISR 无停滞
- ✅ **Bug 2 已保护**: `hazard_unit.v` 的 `control_hazard_r` 在中断期间被抑制
- ✅ **Bug 3 已修复**: `flush_if_o`/`flush_id_o` 在中断期间被抑制，旧 `j` 不会冲掉 ISR 首指令
- ✅ **2 周期中断延迟**: 符合设计规范
- ✅ **影子寄存器**: save/restore 单周期完成，与中断进入/MRET 同一时钟沿
- ✅ **嵌套中断**: bank_ptr 0→1→2→1→0，GPIO 成功抢占 Timer ISR
- ✅ **Bank 溢出/排队**: BANKS=1 硬限制模式下，GPIO 排队等待 Timer ISR 完成后进入
- ✅ **inst_rom 模式**: `SYNC_INST_MEM=0` 时 BRAM 扩展逻辑不参与，行为与基线一致

### 8.2 新增测试（TVLSI 论文扩展，2026-07-01）

- ✅ **寄存器完整性**: 嵌套返回后 31 个寄存器全部正确恢复
- ✅ **降级复用 (POL=1)**: Bank 满时高优先级中断可抢占覆盖
- ✅ **尾链优化**: MRET + pending 时跳过 restore，Bank 指针不变
- ⚠️ **三级嵌套 (SW→Timer→GPIO)**: 测试程序就绪，待 soc_top RTL 小改

---

## 9. 测试通过汇总

| # | 测试 | BANKS | 关键检查点 | 状态 |
|---|------|-------|-----------|------|
| 1 | single_intr | 4 | mem[64]=DEAD0001 | ✅ |
| 2 | ultra_min | 4 | mem[64]=0x42 | ✅ |
| 3 | no_intr | 4 | mem[64]=0x42 | ✅ |
| 4 | nested | 4 | mem[64]=DEAD0001, mem[65]=BEEF0001 | ✅ |
| 5 | overflow_min | 1 | mem[64]=0x42 | ✅ |
| 6 | overflow (POL=0) | 1 | mem[64]=DEAD0001, mem[65]=BEEF0002 | ✅ |
| 7 | **context_integrity** | 4 | x1-x31 全部恢复, tohost=0 | ✅ |
| 8 | **degradation (POL=1)** | 1 | mem[65]=BEEF0003 | ✅ |
| 9 | **tail_chain** | 4 | flag=1, GPIO→Timer 尾链延迟 29 周期 | ✅ |
| 10 | **triple_nested** | 4 | SW=CAFE0003, Timer=DEAD0007, GPIO=BEEF000B | ✅ |

## 10. 相关文件修改记录

| 文件 | 修改内容 | 位置 |
|------|---------|------|
| `core/ifu/ifu_top.v` | `pc_value` → `pc_value + 32'h4` | 第 90 行 |
| `sim/rtl/core/ifu/ifu_top.v` | 同上（sim 副本）| 第 90 行 |
| `core/hazard/hazard_unit.v` | `control_hazard_r_active` 门控 (`&& !interrupt_taken_i`) | 第 101 行 |
| `core/hazard/hazard_unit.v` | `flush_if_o`/`flush_id_o` 门控 (`&& !interrupt_taken_i`) | 第 109-110 行 |
| `sim/rtl/core/hazard/hazard_unit.v` | 同上（sim 副本）| 第 101, 109-110 行 |

### 新增测试脚本

| 文件 | 用途 |
|------|------|
| `sim/run_cli_single_intr.do` | CLI 单测: single_intr_test (BANKS=4) |
| `sim/run_cli_ultra_min.do` | CLI 单测: ultra_min_test (BANKS=4) |
| `sim/run_cli_no_intr.do` | CLI 单测: no_intr_test (BANKS=4) |
| `sim/run_cli_nested.do` | CLI 单测: nested_test 嵌套 (BANKS=4) |
| `sim/run_cli_overflow_min.do` | CLI 单测: overflow_minimal (BANKS=1) |
| `sim/run_cli_overflow.do` | CLI 单测: overflow_test (BANKS=1) |
| `sim/run_cli_compile.do` | CLI 编译脚本 |
| `sim/run_all_tests.sh` | CLI 一键全测 bash 脚本 |
| `sim/run_gui_no_intr.do` | GUI: no_intr_test (新增) |
| `sim/run_cli_context.do` | CLI 单测: context_integrity_test (BANKS=4) |
| `sim/run_cli_degradation.do` | CLI 单测: degradation_test (BANKS=1, POL=1) |
| `sim/run_cli_tailchain.do` | CLI 单测: tail_chain_test (BANKS=4) |
| `sim/run_cli_triple.do` | CLI 单测: triple_nested_test (BANKS=4, 待RTL修复) |
| `sim/context_integrity_test.s` | 汇编: 嵌套后寄存器完整性 |
| `sim/degradation_test.s` | 汇编: 降级复用策略 |
| `sim/tail_chain_test.s` | 汇编: 尾链优化 |
| `sim/triple_nested_test.s` | 汇编: 三级嵌套 |
| `soc/top/soc_top.v` | `intr_software_i` 从 1'b0 改接 `core_intr_software`（reg型）|
