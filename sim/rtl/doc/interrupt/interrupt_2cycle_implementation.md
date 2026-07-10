# 中断恒定 2 周期延迟 — 实施记录

## 修改日期

2026-05-29（2026-05-30 修正：移除无效的 `flush_ex` 改动）

## 修改目标

去掉 `interrupt_pipeline` 中 EX 分支/跳转和 MEM load 两个阻塞条件，实现中断延迟恒定 2 个时钟周期，并通过 `bus_ready` 信号消除 MEM load 的副作用。

## 修改清单

| 文件 | 改动行 | 改动内容 |
|------|:---:|------|
| `core/interrupt/interrupt_pipeline.v` | 19 | 更新模块描述注释 |
| `core/interrupt/interrupt_pipeline.v` | 40 | 新增 `bus_ready_i` 输入端口 |
| `core/interrupt/interrupt_pipeline.v` | 78-79 | 两个阻塞条件改为 `1'b1` |
| `core/interrupt/interrupt_pipeline.v` | 89-112 | mepc 计算按 `bus_ready` 分流 |
| `core/core_top.v` | 493 | `bus_re_o` 条件 kill |
| `core/core_top.v` | 622 | `bus_ready_i` 连入 interrupt_pipeline |

**共 6 处改动，2 个文件。**

## 各改动详情

### 1. `interrupt_pipeline.v` — 新增 `bus_ready_i` 端口

```verilog
// 第 40 行，mem_mem_we_i 之后新增
input  wire        bus_ready_i,       // 总线ready (判断MEM load是否完成)
```

### 2. `interrupt_pipeline.v` — 去掉阻塞条件

```verilog
// 第 78-79 行
// 改前:
assign interrupt_condition[1] = ~(ex_branch_taken_i || ex_jump_taken_i);
assign interrupt_condition[2] = ~mem_mem_re_i;

// 改后:
assign interrupt_condition[1] = 1'b1;   // 不等待EX分支/跳转
assign interrupt_condition[2] = 1'b1;   // 不等待MEM load
```

### 3. `interrupt_pipeline.v` — mepc 计算分流

```verilog
// 第 89-112 行
always @(*) begin
    if (mem_valid_i && (mem_pc_i != 32'b0)) begin
        if (mem_mem_re_i && !bus_ready_i) begin
            interrupt_pc = mem_pc_i;        // load未完成 → 重做
        end else begin
            interrupt_pc = mem_pc_i + 4;    // load已完成 或 非load → 跳过
        end
    end else if (ex_valid_i && (ex_pc_i != 32'b0)) begin
        interrupt_pc = ex_pc_i;             // EX指令(含分支) → 重做
    end else if (id_valid_i && (id_pc_i != 32'b0)) begin
        interrupt_pc = id_pc_i;
    end else begin
        interrupt_pc = if_pc_i;
    end
end
```

mepc 取值规则：

| 最深有效阶段 | 条件 | mepc | MRET 后行为 |
|-------------|------|:---:|------------|
| MEM | load 且 `bus_ready=0` | `mem_pc` | 重做 load |
| MEM | load 且 `bus_ready=1` | `mem_pc+4` | 继续执行下一条 |
| MEM | 非 load（store 等） | `mem_pc+4` | 继续执行下一条 |
| EX | 任意（含分支/跳转） | `ex_pc` | 重做该指令 |
| ID | 任意 | `id_pc` | 重做该指令 |
| IF | 任意 | `if_pc` | 重做该指令 |

### 4. `core_top.v` — `bus_re_o` 条件 kill

```verilog
// 第 493 行
// 改前:
assign bus_re_o = mem_bus_re;

// 改后:
assign bus_re_o = mem_bus_re && !(interrupt_taken_pipe && !bus_ready_i);
```

逻辑表达式：`bus_re_o = bus_re && NOT(中断来了 AND load没完成)`

| 场景 | `interrupt_taken` | `bus_ready` | `bus_re_o` | 效果 |
|------|:---:|:---:|:---:|------|
| 正常运行 | 0 | — | `mem_bus_re` | 透传 |
| 中断 + load 已完成 | 1 | 1 | `mem_bus_re` | 不掐，load 正常收尾 |
| 中断 + load 未完成 | 1 | 0 | `0` | 掐断，外设取消事务 |

### 5. `core_top.v` — `bus_ready_i` 连入 interrupt_pipeline

```verilog
// 第 622 行，interrupt_pipeline 实例化中新增
.bus_ready_i(bus_ready_i),
```

---

## 为什么 EX 分支/跳转不需要额外改硬件

去掉阻塞条件后，中断和分支可能在同一个周期发生。但现有硬件已经正确处理了这个场景，无需额外修改：

| 保护层 | 文件 | 机制 |
|--------|------|------|
| PC 优先级 | `ifu_top.v:54` | `next_pc = interrupt ? handler : branch ? target : ...` |
| 流水线冲洗 | `hazard_unit.v:88-92` | `intr_flush_* = interrupt_flush_i` 冲洗全部五级 |
| 中断 override stall | `pc_reg.v:31` | `!stall \|\| interrupt_pending` 时更新 PC |
| mepc 保存 | `interrupt_pipeline.v:100` | `mepc = ex_pc`，MRET 后重做分支指令 |

时序：

```
T0: EX 有 branch_taken=1，中断同时 pending
    → condition_all=1（不再阻塞）
T0↑: interrupt_accepted=1, interrupt_taken=1, mepc=ex_pc
T1: next_pc = intr_target（中断优先，忽略 branch_target）
    intr_flush_* 冲洗全部流水线（IF/ID 中分支目标处的指令变 NOP）
T1↑: PC = handler
T2: 第一条 ISR 取指

MRET 后: PC = mepc = ex_pc → 分支指令重新执行
          影子寄存器保护了条件寄存器 → 重判结果一致
```

结论：**EX 分支/跳转零副作用，也不需要零额外硬件。**

> 注：`core_top.v:660` 的 `flush_ex` 是一根死线（声明并赋值但从未连接到任何模块实例），分支冲洗实际由 `hazard_unit` 的 `flush_if_o`/`flush_id_o` 产生。在初版方案中曾修改 `flush_ex`，后发现无效已恢复原样。

---

## 延迟保证

改后所有流水线状态下，中断总延迟恒为 2 周期：

```
T0: 中断源触发 → intr_pending=1 → condition_all=1 (无条件)
T0↑: interrupt_accepted=1, interrupt_taken=1, mepc=分流后的PC
T1: next_pc = intr_target, bus_re_o 条件掐断
T1↑: PC = handler 地址
T2: 第一条 ISR 取指  ← 恒定 2 周期
```

| 流水线状态 | 改前 | 改后 |
|-----------|:---:|:---:|
| EX 无分支 + MEM 无 load | 2 | **2** |
| EX 有分支/跳转 | 3 | **2** |
| MEM 有 load (bus_ready=1) | 3 | **2** |
| MEM 有 load (bus_ready=0) | 2+N | **2** |
| EX 分支 + MEM load | 4+N | **2** |

---

## 硬件开销

| 项目 | 开销 |
|------|:---:|
| `interrupt_pipeline` 新增端口 | 1 wire |
| 去掉 2 个 condition 项 | -3 级门 |
| mepc 分流逻辑 | +3 LUT |
| `bus_re_o` 条件 kill | +2 LUT |
| **净增** | **~5 LUT, 0 FF** |

---

## 相关文档

| 文件 | 内容 |
|------|------|
| `interrupt_2cycle_guaranteed.md` | 完整方案设计与副作用分析 |
| `interrupt_latency_analysis.md` | 初版中断延迟分析 |
| `interrupt_vector_mode.md` | 中断向量模式 (Direct / Vectored) |
| `shadow_register_guide.md` | 影子寄存器上下文保存/恢复 |
