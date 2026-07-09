# shadow_save 提前 1 周期 — 实施记录

## 修改日期

2026-06-16

## 背景

`interrupt_pipeline.v` 中 `shadow_save_o` 的原设计在 `interrupt_accepted` 状态机的**次周期**才触发：
- T2↑: `interrupt_accepted <= 1`
- T2-T3: `interrupt_accepted = 1`，`shadow_save_o = 0`
- T3↑: `shadow_save_o <= SHADOW_EN`（`else if (interrupt_accepted)` 分支）
- T3-T4: `shadow_save_o = 1`
- T4↑: 影子寄存器捕获 x1-x31

从中断信号到来到影子保存完成需 3 个时钟沿。实际上 `intr_take_now` 组合逻辑（2026-06-11 引入，用于 PC 提前跳转）已经为 `shadow_save` 的提前触发提供了条件 — 中断在接受前一个周期就被确定性地预判了。

## 修改目标

将 `shadow_save_o` 提前 1 个时钟周期，与 `interrupt_accepted` 在同一时钟沿触发，影子捕获从 T4↑ 提前到 T3↑。

## 修改清单

| 文件 | 修改位置 | 改动内容 |
|------|---------|------|
| `core/interrupt/interrupt_pipeline.v` | 第 188-199 行 | 将 `shadow_save_o <= SHADOW_EN` 从 `else if (interrupt_accepted)` 分支移至第一个 `if` 分支 |

## 详细修改

### 改前

```verilog
if (interrupt_condition_all && !interrupt_accepted && !interrupt_processed) begin
    interrupt_accepted    <= 1'b1;
    ...
    // 发起中断控制信号
    interrupt_taken_o <= 1'b1;
    interrupt_flush_o <= 1'b1;
    interrupt_pc_o    <= interrupt_pc;

    // 注意: 影子寄存器保存在下一个周期触发(见else if分支)
    // 这样确保当前周期内所有WB写入先完成，再保存完整的寄存器状态
end
// 下一周期：标记为已处理，触发影子寄存器保存
else if (interrupt_accepted) begin
    interrupt_accepted <= 1'b0;
    interrupt_processed <= 1'b1;
    shadow_save_o <= SHADOW_EN;    // T3↑ 锁存, T3-T4 有效, T4↑ 捕获
end
```

### 改后

```verilog
if (interrupt_condition_all && !interrupt_accepted && !interrupt_processed) begin
    interrupt_accepted    <= 1'b1;
    ...
    // 发起中断控制信号
    interrupt_taken_o <= 1'b1;
    interrupt_flush_o <= 1'b1;
    interrupt_pc_o    <= interrupt_pc;

    // 影子寄存器保存: 与 interrupt_accepted 同一时钟沿触发
    // intr_take_now 组合逻辑保证 PC 已跳转到 handler, 本周期 T2-T3 期间 shadow_save=1
    // T3↑ 寄存器堆采样 shadow_save, 以 WB > shadow_save 优先级完成捕获
    // 比原设计(T3-T4才触发, T4↑捕获)提前了1个时钟周期
    shadow_save_o <= SHADOW_EN;
end
// 下一周期：标记为已处理
else if (interrupt_accepted) begin
    interrupt_accepted <= 1'b0;
    interrupt_processed <= 1'b1;
    // shadow_save 已在上个周期触发，此处不再重复
end
```

## 时序对比

### 改前（3 周期）

```
T2↑:  interrupt_accepted <= 1    (shadow_save 未触发)
T2-T3: shadow_save_o = 0
T3↑:  shadow_save_o <= 1        (else-if 分支)
T3-T4: shadow_save_o = 1        → 寄存器堆收到保存请求
T4↑:  影子寄存器捕获 x1-x31     ← 影子保存完成
```

### 改后（2 周期）

```
T2↑:  interrupt_accepted <= 1    (shadow_save 同步触发!)
T2-T3: shadow_save_o = 1        → 寄存器堆收到保存请求
T3↑:  影子寄存器捕获 x1-x31     ← 影子保存完成 (提前1周期)
       interrupt_processed <= 1  (默认值 auto-clear shadow_save → 单周期脉冲)
```

## 副作用分析

| 检查项 | 结论 |
|--------|------|
| T3↑ 捕获的寄存器状态 vs T4↑ | **完全一致** — T3-T4 期间 MEM/WB 已被冲刷为 NOP（reg_we=0），无新 WB 写入 |
| 被冲刷指令的脏数据 | 不会进入 — `intr_flush_ex/mem/wb=1` 将 ID/EX、EX/MEM、MEM/WB 冲刷为 NOP |
| WB 写回优先级 | 正确 — 寄存器堆优先级 `WB > shadow_save`，T3↑ 若有 WB 写入则先于影子捕获完成 |
| SHADOW_EN=0 | `shadow_save_o <= 0`，综合工具优化掉 |
| MRET 误触发 | 不会 — `interrupt_processed=1` 时 `intr_take_now=0` |
| 不提前触发 | 不会 — `shadow_save_o` 在 `if` 分支内，仅在中断接受周期触发 |

## 硬件开销

**零开销。** 仅将 `shadow_save_o` 赋值语句从一个分支移动到另一个分支。

## 相关文档

| 文件 | 内容 |
|------|------|
| `interrupt_2cycle_strict_implementation.md` | `intr_take_now` 引入记录（PC提前跳转，省1周期） |
| `interrupt_2cycle_implementation.md` | 初版 2-cycle 中断延迟实施记录 |
| `shadow_save_race_condition.md` | 影子保存竞态分析 |
| `shadow_register_guide.md` | 影子寄存器机制总览 |
