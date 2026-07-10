# 影子寄存器保存时序分析——为何不存在竞争

## 问题

当 MEM 阶段有一条 bus_ready=1 的 load，且同一周期中断到达时，load 结果的寄存器写回与 shadow_save 的时序关系是否安全？

## 结论

**安全，不存在竞争。** 因为 `shadow_save_o` 是 interrupt_pipeline 的 reg 型输出，NBA 语义导致 regfile 实际采样到 `shadow_save_i=1` 的时刻比 load 的 WB 写回晚一个时钟周期，load 数据已先行写入寄存器堆。

## 时序推演

```
tu:       0  1  2  3  4  5  6  7  8  9
clk(p):   1  0  1  0  1  0  1  0  1  0
          ^     ^     ^     ^     ^
          |    T0↑    |    T1↑    |    T2↑
```

### T0↑（tu2）

- interrupt_pipeline：`interrupt_accepted <= 1`。`shadow_save_o` 保持默认值 0。
- mem_wb_reg：`flush_i=0, intr_flush_i=0`（旧值），**正常锁存 load 数据**。`wb_reg_we_o <= 1`，`wb_data <= load_result`。

### T1↑（tu4）

**regfile 侧（采样旧值）**：
- `we_i = wb_reg_we_out = 1`（mem_wb_reg 在 T0↑ 锁存的值，T1 期间仍有效）
- `wdata_i = load_result`
- `shadow_save_i = shadow_save_o(旧值) = 0`（T1↑ 之前 `shadow_save_o` 尚未更新）
- → **load 数据写入 `registers[rd]`** ✅
- → shadow_save 条件为假，**不执行保存**

**interrupt_pipeline 侧**：
- 进入 `else if (interrupt_accepted)`：`shadow_save_o <= 1`（NBA，T1↑ 结束时生效）

### T2↑（tu6）

**regfile 侧**：
- `shadow_save_i = shadow_save_o(旧值) = 1`（T1↑ 写入的值，T2 期间可见）
- `we_i = 0`（mem_wb_reg 在 T1↑ 已被冲刷）
- → **shadow_save 执行**：`shadow_registers[i] <= registers[i]`
- → 此时 `registers[i]` **已包含** T1↑ 写入的 load 结果 ✅

**interrupt_pipeline 侧**：
- 默认值生效：`shadow_save_o <= 0`（脉冲结束）

## 关键机制

`shadow_save_o` 从 interrupt_pipeline 的 reg 输出到 regfile 的采样，天然存在一个时钟周期的流水线延迟：

```
interrupt_pipeline (NBA)          regfile (NBA)
──────────────────────            ──────────────
T1↑: shadow_save_o <= 1          采样 shadow_save_i = 0 → 不保存，执行 WB 写
T2↑: shadow_save_o <= 0 (默认)   采样 shadow_save_i = 1 → 执行影子保存
```

load 的 WB 写入（T1↑）与影子寄存器保存（T2↑）之间存在一个完整时钟周期的间隔，确保影子保存时寄存器堆已包含 load 的结果。`interrupt_latency_analysis.md` 所述"数据正常写回 regfile，影子寄存器随后保存完整状态"是准确的。
