# 嵌套中断测试进展文档 (最终版)

**日期**: 2026-06-30
**作者**: Yi Fengxin & Claude Code

---

## 最终状态: ✅ 全部测试通过 (2026-06-30 Bug #4修复后验证)

### 回归测试结果

| # | 测试 | mem[64] (timer) | mem[65] (gpio) | 结果 |
|---|------|-----------------|-----------------|------|
| 1 | ultra_min_test | 0x00000042 | - | ✅ PASS |
| 2 | single_intr_test | 0xDEAD0001 | - | ✅ PASS |
| 3 | no_intr_test | 0x00000042 | - | ✅ PASS |
| 4 | nested_test | 0xDEAD0001 | 0xBEEF0001 | ✅ PASS |

### 嵌套中断测试详细结果

```
timer_count   = 0xDEAD0001  ← Timer ISR 执行
gpio_count    = 0xBEEF0001  ← GPIO ISR 执行 (嵌套抢占)
preempted     = 0           ← Timer ISR 在 MRET 前清除
tohost        = 0           ← PASS
```

**验证流程**:
1. C226: Timer ISR 进入 (bank_ptr=1), 写 marker `0xDEAD0001` 到 mem[64], preempted=1 到 mem[66]
2. C241: Timer ISR 清除 Timer 中断 (CPU_WR busaddr=0x10002000 wdata=4), 重开 MIE
3. C304: GPIO 抢占 (bank_ptr=2, shadow_save=1 保存 Timer ISR 上下文到 Bank 1)
4. C314: GPIO ISR 写 marker `0xBEEF0001` 到 mem[65] ✅
5. C317: GPIO ISR 清除 GPIO 中断标志 (CPU_WR busaddr=0x10001014 wdata=1), MRET 返回
6. C318: shadow_restore=1, bank_ptr=1 (恢复 Timer ISR 上下文从 Bank 1)
7. C319-C357: Timer ISR 延迟循环继续执行
8. C359: Timer ISR MRET, 返回 main_loop
9. Main loop: gpio_count=0xBEEF0001 ≥ 1 → loop 退出 → tohost=0 → PASS

---

## 已修复的 Bug (共 5 个, 根因级别)

### Bug 1: B-type 立即数生成器 bit 顺序错误 (imm_gen.v) ⭐ 根因 #1

**文件**: `core/id/imm_gen.v` 第 47-53 行

**问题**: B-type 立即数的 bit 排列错误。RISC-V 规范要求:
```
offset[12:1] = {inst[31], inst[7], inst[30:25], inst[11:8]}
```
但硬件实现为:
```verilog
// 错误: inst[7] 放到了 bit 1 位置, inst[30:25] 放到了 11:6
imm_o = {{20{instr_i[31]}}, instr_i[30:25], instr_i[11:8], instr_i[7], 1'b0};
```

**影响**: 所有非零偏移的条件分支计算错误目标地址!
- `bltu t0, t1, main_loop` (offset=-12) 被解码为 offset=-22, 目标 0x52 (应该是 0x5C)
- 这导致 main_loop 跳转到 GPIO/Timer 设置代码中间, 反复重置外设
- 最小 blt 测试未发现是因为 offset=0 时任何 bit 排列都产生 0

**修复**:
```verilog
// 正确: inst[7]=imm[11] 放在 bit 11, inst[30:25]=imm[10:5] 放在 10:5
imm_o = {{20{instr_i[31]}}, instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0};
```

**注意**: `sim/rtl/core/id/imm_gen.v` 已经正确 (可能是不同版本)。只有 `core/id/imm_gen.v` 有 bug。

---

### Bug 2: 中断进入时 IF/ID 未刷新 (hazard_unit.v) ⭐ 根因 #2

**文件**: `core/hazard/hazard_unit.v` 第 110 行

**问题**: `intr_flush_id_o` 硬编码为 0:
```verilog
assign intr_flush_id_o  = 1'b0;  // 错误: IF/ID 不刷新
```

中断进入时, IF/ID 中仍有旧程序的残留指令。该指令传播到 ID/EX 并执行:
- 若为分支指令 (如 Timer ISR 的 `bnez`), 会错误重定向 PC
- PC 被重定向到旧程序代码, 而非 ISR handler
- 导致 ISR 代码无法正确执行

**仿真证据** (修复前):
```
C304: GPIO 中断进入 (bank_ptr=2)
C305: PC=0x22C (GPIO handler), 但 IFID 中有旧 bnez
C306: bnez 在 ID/EX 执行, bt=1 → PC 跳回 0x260 (Timer ISR delay loop!)
→ GPIO ISR 代码从未执行!
```

**修复 (2026-06-25, 已废弃)**:
```verilog
// 旧修复 (已废弃, 2026-06-27 回滚):
// assign intr_flush_id_o  = interrupt_flush_i;
// 正确修复 (2026-06-27): 根本问题不在此, 恢复为:
assign intr_flush_id_o  = 1'b0;  // IF/ID 不冲刷 (与基准版本一致)
```

**关于原有设计的重新评估**: CLAUDE.md 文档说明 `intr_flush_id=0` 是为了 "让第一条 ISR 指令通过 IF/ID"。但实际时序是:
1. intr_take_now → PC 重定向到 handler
2. BRAM 有 1 周期延迟, handler 指令还未输出
3. interrupt_taken=1 时, IF/ID 中只有旧程序的残留指令
4. 刷新 IF/ID 是正确的——handler 指令会在下一周期自然进入

---

### Bug 3: 控制冒险 flush 未覆盖 BRAM 延迟 (hazard_unit.v) ⭐ 根因 #3

**文件**: `core/hazard/hazard_unit.v` 第 79-102 行

**问题**: BRAM 同步读有 1 周期延迟, 分支/跳转后产生 2 条错误指令进入 IF, 但 flush 仅持续 1 周期。

**修复**: 添加 `control_hazard_r` 寄存器将 flush 延长至 2 周期:
```verilog
reg control_hazard_r;
wire control_hazard_extended = control_hazard || control_hazard_r;
assign flush_if_o = control_hazard_extended;
assign flush_id_o = control_hazard_extended;
```

---

### Bug 4: 控制冒险扩展冲刷无条件激活——ROM模式下误杀ISR首指令 (hazard_unit.v) ⭐ 根因 #4

**文件**: `core/hazard/hazard_unit.v` 第 85-109 行

**问题**: `control_hazard_extended` 无条件包含 `control_hazard_r`（2周期冲刷），但该机制仅为 BRAM 同步读设计。系统使用 `inst_rom.v`（组合读，`SYNC_INST_MEM=0`），仅需 1 周期冲刷。

**时序分析**: 向量表 `j isr_timer` (0x21C→0x220) 在 EX 执行:
1. 第1周期: flush IF/ID, PC←0x220 ✓（杀 PC+4 处的错误指令）
2. 第2周期(扩展, control_hazard_r=1): flush IF/ID ✗（杀死 ROM 输出的 0x220 处的 addi）, PC←0x224 ✗（跳过跳转目标）
3. 冲刷结束: CPU 从 0x224 取指(sw), 跳过 0x220(addi)。sw 用 t0 旧值(0x10002000, Timer 基地址)→写错误数据

**影响范围**: 所有使用 inst_rom.v 的中断测试。ISR 中的 store 指令使用未更新的寄存器值。ultra_min_test、nop_test、minimal_isr_test 均受影响。

**修复 (2026-06-30)**:
1. `hazard_unit.v` 新增 `parameter SYNC_INST_MEM = 1`:
```verilog
// ROM (SYNC_INST_MEM=0): 仅1周期flush
// BRAM (SYNC_INST_MEM=1): 2周期flush + PC stall防止跳过跳转目标
wire control_hazard_extended = control_hazard || (SYNC_INST_MEM && control_hazard_r);
assign stall_if_o = load_use_hazard || (SYNC_INST_MEM && control_hazard_r);
assign stall_id_o = load_use_hazard || (SYNC_INST_MEM && control_hazard_r);
assign flush_if_o = control_hazard_extended;
assign flush_id_o = control_hazard_extended;
```
2. `core/core_top.v` 传递 `.SYNC_INST_MEM(SYNC_INST_MEM)` 到 hazard_unit 实例化
3. `sim/rtl/core/hazard/hazard_unit.v` 同步自 core/

**为什么之前没发现**: single_intr_test 标记为 PASS 实际是 tohost 默认值 0 造成的误判（ISR 未正确执行但 tohost 未被写入非零值）。

**修复后预期** (ROM 模式): JAL→1周期flush→ROM输出跳转目标指令→IF/ID正常捕获→ISR第一条指令正确执行→转发正常工作

---

### Bug 5: `interrupt_taken_i` 周期 PC 递增导致 handler 指令被旧程序 flush 杀死 (ifu_top.v) ⭐ 根因 #5

**文件**: `core/ifu/ifu_top.v` 第 88-90 行

**问题**: 中断进入后 `interrupt_taken_i` 强制 `next_pc = pc_value + 4`（原意是阻挡旧程序分支/跳转信号）。但同一周期旧程序的 jump/branch 在 EX 触发 `control_hazard` flush，该 flush 会杀死 handler 地址（如 0x21C）上刚取到的 `j isr_timer` 指令。PC 递增后 handler 指令永久丢失。

**时序分析**（以 overflow_test 为例）:
1. C72: PC=0x21C (handler), 旧程序 jump 在 EX → flush_if=1, interrupt_taken_i=1 → next_pc=0x220
2. posedge C72: IF/ID ← FLUSHED（`j isr_timer` 被杀）, PC ← 0x220
3. C73: PC=0x220 = `j spin` → **死循环!** handler 永远丢失

ultra_min_test 恰好能工作是因为 `j isr_timer` 的跳转目标 = PC+4 = 0x220，handler 恰好在 0x220。

**修复 (2026-06-30)**:
```verilog
// 原代码:
(interrupt_taken_i) ? pc_value + 32'h4   // 递增→跳过handler

// 修复后:
(interrupt_taken_i) ? pc_value            // HOLD: 阻挡分支且保留handler地址
```
PC hold 同样有效阻挡旧程序分支/跳转（`interrupt_taken_i` 仍有最高优先级），同时 handler 地址在 flush 后可重新取指。

**影响的测试**: 所有 `isr` 不紧邻向量表 JAL 指令的测试（overflow_test、nested_intr_test 等）。

---

## 文件变更汇总

| 文件 | 变更 | Bug # |
|------|------|-------|
| **`core/id/imm_gen.v`** | 修复 B-type 立即数 bit 排列 | #1 |
| **`core/hazard/hazard_unit.v`** | 2026-06-25: intr_flush_id_o = interrupt_flush_i (Bug #2, 已废弃) / 2026-06-27: 回滚为 1'b0 | #2 |
| **`core/hazard/hazard_unit.v`** | control_hazard_r 延长 flush 2 周期 (Bug #3) ; **2026-06-30: SYNC_INST_MEM 条件化 flush/stall (Bug #4)** | #3, #4 |
| **`core/core_top.v`** | pc_current 连接 (早期修复) ; **传递 SYNC_INST_MEM 到 hazard_unit (Bug #4)** | #4 |
| **`core/ifu/ifu_top.v`** | pc_delayed 寄存器 (早期修复) ; **2026-06-30: interrupt_taken_i 改用 pc_value hold (Bug #5)** | #5 |
| `core/core_top.v` | pc_current 连接 (早期修复) | - |
| `sim/nested_test.s` | blt→bltu, Timer 中断清除先于 MIE 重开 | - |
| `sim/minimal_blt_test.s` | 最小 blt 分支测试 | - |
| **`core/interrupt/interrupt_pipeline.v`** | **移除 bank_ptr > 0 条件 —— 首次中断现在正确保存主程序上下文至 Bank[0]** | **#15** |
| **`core/interrupt/bank_controller.v`** | **新增 OVERFLOW_POLICY 参数 + degradation_reuse 信号（纯组合逻辑）** | **#16** |
| **`core/core_top.v`** | **新增 OVERFLOW_POLICY 参数 + degradation_reuse 连线 + bank_controller 实例化** | **#17** |
| **`sim/rtl/core/interrupt/*`** | **同步自 core/（中断流水线 + Bank 控制器）** | **#15-17** |
| **`sim/rtl/core/core_top.v`** | **同步自 core/（OVERFLOW_POLICY + degradation_reuse + Bug #4/#5）** | **#4, #5, #17** |
| **`sim/rtl/core/hazard/hazard_unit.v`** | **同步自 core/（Bug #4）** | **#4** |
| **`sim/rtl/core/ifu/ifu_top.v`** | **同步自 core/（Bug #5）** | **#5** |
| **`sim/rtl/core/interrupt/interrupt_pipeline.v`** | **同步自 core/（bank_ptr_o wire 修正）** | - |
| `sim/overflow_test.s` | **新增**: Bank溢出测试程序 | - |
| `sim/overflow_minimal.s` | **新增**: 最小溢出验证 (SHADOW_BANKS=1) | - |

---

## 参考

- 关键 RTL: `core/id/imm_gen.v:47-53`, `core/hazard/hazard_unit.v:85-109`, `core/ifu/ifu_top.v:85-94`, `core/interrupt/interrupt_pipeline.v:115-222`, `core/interrupt/bank_controller.v:16-76`, `core/core_top.v:4-7,373-374`
- 测试: `sim/nested_test.s`, `sim/overflow_test.s`, `sim/overflow_minimal.s`, `sim/ultra_min_test.s`
- 仿真脚本: `sim/run_batch.do` (命令行批量), `sim/run_gui.do` (GUI波形)
