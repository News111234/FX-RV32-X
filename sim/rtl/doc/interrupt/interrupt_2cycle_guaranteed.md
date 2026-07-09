# 中断恒定 2 周期延迟 — 无副作用方案

## 1. 问题回顾

当前 `interrupt_pipeline.v` 的中断接受条件包含两个阻塞项：

```verilog
// 第 78-79 行
assign interrupt_condition[1] = ~(ex_branch_taken_i || ex_jump_taken_i); // 等 EX 无分支
assign interrupt_condition[2] = ~mem_mem_re_i;                           // 等 MEM 无 load
```

这导致中断总延迟不固定（2 + N 周期）。要去掉这两个条件、实现恒定 2 周期延迟，需要处理随之而来的副作用。

---

## 2. 副作用的根因分析

中断到来时，MEM 阶段的 load 指令处于两种互斥状态之一：

```
状态 A: bus_ready = 1  →  load 已完成，数据正从总线送入 MEM/WB 寄存器
状态 B: bus_ready = 0  →  load 等待中，总线请求尚未被外设响应
```

**区分这两种状态的唯一硬件信号就是 `bus_ready`。** 当前 `interrupt_pipeline` 没有接入这个信号，所以无法区分，只能"一刀切"处理。把 `bus_ready` 接进去，就能对两种状态分别处理，各自消除副作用。

---

## 3. 各场景副作用与解决方案

### 3.1 MEM 有 load 且已完成（bus_ready = 1）

**中断前的状态**：load 指令在 MEM 阶段，外设已经返回数据（`bus_ready=1`，`bus_rdata=有效`）。MEM/WB 寄存器将在本时钟沿捕获数据，下一拍 WB 写回寄存器堆。

**如果粗暴处理**：`intr_flush_wb` 冲洗 MEM/WB 寄存器 → 已完成的数据被丢弃。`mepc = mem_pc`，MRET 后 load 重新执行。对于 RAM 读是浪费一个周期，对于 FIFO 读会读到下一个数据（数据丢失）。

**正确做法**：load 既然完成了，就让它正常结束。

- `mepc = mem_pc + 4` —— 跳过已完成指令，MRET 后继续执行下一条
- 不冲洗 MEM/WB —— load 数据正常写入 regfile
- 不掐断 `bus_re_o` —— 总线事务正常收尾
- 影子寄存器在下一拍保存，此时 regfile 已包含 load 结果

**结论：零副作用。**

### 3.2 MEM 有 load 且未完成（bus_ready = 0）

**中断前的状态**：load 指令在 MEM 阶段，已发出总线请求（`bus_re=1`），但外设尚未响应（`bus_ready=0`）。

**正确做法**：取消这次总线请求，load 指令的 PC 被保存为 mepc，MRET 后重新执行。

- `mepc = mem_pc` —— 指向 load 自身，MRET 后重做
- 掐断 `bus_re_o` —— 总线请求撤销
- 冲洗 MEM/WB —— 防止不确定数据进入 regfile

**外设侧分析**：因为 `bus_ready` 从未拉高，外设没有完成数据读取。对 RAM：`bus_ack` 虽然在 T0 时钟沿锁存了 `bus_re=1`，但在 T1 看到 `bus_re=0` 后 FSM 回 IDLE。最关键的是——`bus_ready` 在 T0 时就是 0（否则就进入 3.1 的处理了），所以数据没有被取走。MRET 后重做 load，完全等价于第一次执行。

```
T0: bus_re=1, addr=valid, bus_ready=0
T0↑: 中断接受, interrupt_taken=1
T1: bus_re→0 (掐断), 外设看到请求取消 → 不响应
T1↑: MEM被冲洗
T2: ISR取指

MRET后: PC=mepc=mem_pc → load重做, 外设从零开始处理 ✓
```

**结论：零副作用。**

### 3.3 EX 有分支/跳转

**中断前的状态**：分支/跳转指令在 EX 阶段，`ex_branch_taken=1`（或 `ex_jump_taken=1`），IFU 正常情况下下一拍会跳转到目标地址。

**正确做法**：中断优先级高于分支。分支不跳，PC 跳转到中断 handler。mepc 指向分支指令自身。

- `mepc = ex_pc` —— 指向分支指令，MRET 后重新判断
- 抑制 `flush_ex` —— `flush_ex = (branch || jump) && !interrupt_taken`
- IFU 的 `next_pc` 优先级天然是 `interrupt > branch > jump`，PC 正确跳转到 handler

**条件码一致性**：影子寄存器保存了分支指令前的完整寄存器状态。MRET 后影子恢复，分支重新判断条件码，结果与中断前完全一致。

**结论：零副作用。**

### 3.4 MEM 有 store

**说明**：store 指令不阻塞中断（`interrupt_condition[2]` 只检查 `~mem_mem_re_i`，不检查 `mem_we_i`）。当前设计中 store 本来就不影响中断延迟。

store 是"发出即完成"的——总线仲裁器在 store 发出的那一拍就锁存了地址、数据和控制信号。中断来了不会撤销已发出的 store。无需特别处理。

**结论：无副作用，无需改动。**

---

## 4. 修改方案

### 4.1 涉及文件

| 文件 | 改动概述 |
|------|----------|
| `core/interrupt/interrupt_pipeline.v` | 新增 `bus_ready_i` 端口；去掉两个阻塞条件；mepc 计算逻辑区分 load 完成/未完成 |
| `core/core_top.v` | 把 `bus_ready_i` 连到 `interrupt_pipeline`；`flush_ex` 加中断抑制；`bus_re_o` 条件 kill |

### 4.2 `interrupt_pipeline.v` 改动

**改动 A：新增端口**

```verilog
module interrupt_pipeline #(
    parameter SHADOW_EN = 0
) (
    // ... 现有端口不变 ...

    // ========== 总线状态（新增）==========
    input  wire        bus_ready_i,       // 总线 ready 信号，用于判断 load 是否完成

    // ... 其余端口不变 ...
);
```

**改动 B：去掉阻塞条件（第 78-79 行）**

```verilog
// ===== 改前 =====
assign interrupt_condition[1] = ~(ex_branch_taken_i || ex_jump_taken_i);
assign interrupt_condition[2] = ~mem_mem_re_i;

// ===== 改后 =====
assign interrupt_condition[1] = 1'b1;  // 不等待 EX 分支/跳转
assign interrupt_condition[2] = 1'b1;  // 不等待 MEM load
```

**改动 C：mepc 计算逻辑（第 89-103 行）**

```verilog
// ===== 改前 =====
always @(*) begin
    if (mem_valid_i && (mem_pc_i != 32'b0)) begin
        interrupt_pc = mem_pc_i;
        selected_stage = 3'd0;
    end else if (ex_valid_i && (ex_pc_i != 32'b0)) begin
        interrupt_pc = ex_pc_i;
        selected_stage = 3'd1;
    end else if (id_valid_i && (id_pc_i != 32'b0)) begin
        interrupt_pc = id_pc_i;
        selected_stage = 3'd2;
    end else begin
        interrupt_pc = if_pc_i;
        selected_stage = 3'd3;
    end
end

// ===== 改后 =====
always @(*) begin
    if (mem_valid_i && (mem_pc_i != 32'b0)) begin
        // MEM 阶段有指令，判断是否需要重做
        if (mem_mem_re_i && !bus_ready_i) begin
            // load 未完成 (bus_ready=0) → 取消，重做
            interrupt_pc = mem_pc_i;
        end else begin
            // load 已完成 (bus_ready=1) 或非 load 指令 → 跳过
            interrupt_pc = mem_pc_i + 4;
        end
        selected_stage = 3'd0;
    end else if (ex_valid_i && (ex_pc_i != 32'b0)) begin
        // EX 阶段指令（含分支/跳转）→ 取消，重做
        interrupt_pc = ex_pc_i;
        selected_stage = 3'd1;
    end else if (id_valid_i && (id_pc_i != 32'b0)) begin
        // ID 阶段指令 → 取消，重做
        interrupt_pc = id_pc_i;
        selected_stage = 3'd2;
    end else begin
        // IF 阶段指令 → 取消，重做
        interrupt_pc = if_pc_i;
        selected_stage = 3'd3;
    end
end
```

mepc 选择逻辑总结：

| 最深有效阶段 | 条件 | mepc | 含义 |
|-------------|------|:---:|------|
| MEM | load 且 `bus_ready=0` | `mem_pc` | load 未完成，重做 |
| MEM | load 且 `bus_ready=1` | `mem_pc+4` | load 已完成，跳过 |
| MEM | 非 load（store 等） | `mem_pc+4` | 已完成，跳过 |
| EX | 任意（含分支/跳转） | `ex_pc` | 取消，重做 |
| ID | 任意 | `id_pc` | 取消，重做 |
| IF | 任意 | `if_pc` | 取消，重做 |

### 4.3 `core_top.v` 改动

**改动 D：`flush_ex` 加中断抑制（第 658 行）**

```verilog
// ===== 改前 =====
assign flush_ex = ex_branch_taken || ex_jump_taken;

// ===== 改后 =====
assign flush_ex = (ex_branch_taken || ex_jump_taken) && !interrupt_taken_pipe;
```

**改动 E：`bus_re_o` 条件 kill（第 492 行）**

```verilog
// ===== 改前 =====
assign bus_re_o = mem_bus_re;

// ===== 改后 =====
// 中断时，若 load 未完成(bus_ready=0)则掐断总线请求；
// 若 load 已完成(bus_ready=1)则不掐，让它正常收尾。
assign bus_re_o = mem_bus_re && !(interrupt_taken_pipe && !bus_ready_i);
```

**改动 F：`interrupt_pipeline` 实例化新增端口连接（约第 607 行）**

```verilog
interrupt_pipeline u_interrupt_pipeline (
    // ... 现有连接不变 ...
    .bus_ready_i       (bus_ready_i),    // 新增
    // ... 其余不变 ...
);
```

---

## 5. 完整时序验证

### 场景 A：MEM load 已完成（bus_ready = 1）

```
        T0                  T0↑                 T1                  T1↑                 T2
   ─────┼───────────────────┼───────────────────┼───────────────────┼───────────────────┼──

  bus_ready=1 ──────────────┐                   │                   │                   │
  bus_rdata=有效            │                   │                   │                   │
                             │                   │                   │                   │
  intr_pending=1             │                   │                   │                   │
  condition_all=1 ✓          │                   │                   │                   │
                             │                   │                   │                   │
                 ┌── 时钟沿 ──┘                   │                   │                   │
                 │ interrupt_accepted ← 1          │                   │                   │
                 │ interrupt_taken    ← 1          │                   │                   │
                 │ mepc ← mem_pc + 4  (跳过已完成load)                  │                   │
                 │                   │                   │                   │
                 │ interrupt_taken=1 可见              │                   │
                 │ → flush_ex = 0 (分支冲洗抑制)        │                   │
                 │ → bus_re_o: 1 && !(1 && !1) = 1 (不掐)              │
                 │   load 数据正常流过 MEM→WB          │                   │
                 │                   │                   │                   │
                 │                   │   ┌── 时钟沿 ────┘                   │
                 │                   │   │ WB: regfile[x] ← load_data      │
                 │                   │   │ shadow_save ← 1 (保存含load结果)  │
                 │                   │   │ PC ← handler地址                 │
                 │                   │   │                   │                   │
                 │                   │   │ 第一条ISR取指     │                   │
                 │                   │   │ ←── 恒定2周期 ──→│                   │
                 │                   │   │                   │                   │

  MRET后: PC = mepc = mem_pc + 4 → 从load之后继续 ✓
```

### 场景 B：MEM load 未完成（bus_ready = 0）

```
        T0                  T0↑                 T1                  T1↑                 T2
   ─────┼───────────────────┼───────────────────┼───────────────────┼───────────────────┼──

  bus_ready=0 ──────────────────────────────────┐                   │                   │
  bus_re=1 (MEM发出请求)      │                   │                   │                   │
                             │                   │                   │                   │
  intr_pending=1             │                   │                   │                   │
  condition_all=1 ✓          │                   │                   │                   │
                             │                   │                   │                   │
                 ┌── 时钟沿 ──┘                   │                   │                   │
                 │ interrupt_accepted ← 1          │                   │                   │
                 │ interrupt_taken    ← 1          │                   │                   │
                 │ mepc ← mem_pc      (重做load)    │                   │                   │
                 │                   │                   │                   │
                 │ interrupt_taken=1 可见              │                   │
                 │ → flush_ex = 0 (分支冲洗抑制)        │                   │
                 │ → bus_re_o: 1 && !(1 && !0) = 0 (掐断)              │
                 │   外设看到 bus_re↓ → 取消事务        │                   │
                 │                   │                   │                   │
                 │                   │   ┌── 时钟沿 ────┘                   │
                 │                   │   │ intr_flush 冲洗 MEM/WB          │
                 │                   │   │ shadow_save ← 1                 │
                 │                   │   │ PC ← handler地址                 │
                 │                   │   │                   │                   │
                 │                   │   │ 第一条ISR取指     │                   │
                 │                   │   │ ←── 恒定2周期 ──→│                   │
                 │                   │   │                   │                   │

  MRET后: PC = mepc = mem_pc → load重做, 外设从未响应过, 安全 ✓
```

### 场景 C：EX 有分支且 MEM 有未完成 load（最复杂情况）

```
        T0                  T0↑                 T1                  T1↑                 T2
   ─────┼───────────────────┼───────────────────┼───────────────────┼───────────────────┼──

  EX: branch_taken=1        │                   │                   │                   │
  MEM: load, bus_ready=0    │                   │                   │                   │
  intr_pending=1            │                   │                   │                   │
  condition_all=1 ✓         │                   │                   │                   │
                            │                   │                   │                   │
                ┌── 时钟沿 ──┘                   │                   │                   │
                │ interrupt_accepted ← 1          │                   │                   │
                │ mepc ← mem_pc    (最深=MEM, bus_ready=0→重做)      │                   │
                │                   │                   │                   │
                │ interrupt_taken=1 可见              │                   │
                │ → flush_ex = 0 (分支被抑制, 不跳)    │                   │
                │ → bus_re_o = 0 (load请求掐断)        │                   │
                │ → next_pc = intr_target (中断优先)   │                   │
                │                   │                   │                   │
                │                   │   ┌── 时钟沿 ────┘                   │
                │                   │   │ PC ← handler                    │
                │                   │   │                   │                   │
                │                   │   │ 第一条ISR取指     │                   │
                │                   │   │ ←── 恒定2周期 ──→│                   │

  MRET后: PC = mepc = mem_pc → load重做 → 结果确定后分支重新判断 → 逻辑等价 ✓
```

---

## 6. 硬件开销

| 改动 | 位置 | 开销 |
|------|------|:---:|
| `interrupt_pipeline` 新增 `bus_ready_i` 端口 | 模块接口 | 1 wire |
| 去掉 `condition[1]`、`condition[2]` 两项 | interrupt_pipeline | -3 级门 |
| mepc 计算加 `bus_ready` 条件判断 | interrupt_pipeline | ~3 LUT |
| `flush_ex` 加 `&& !interrupt_taken_pipe` | core_top | ~1 LUT |
| `bus_re_o` 加条件 kill | core_top | ~2 LUT |
| **净增** | | **~6 LUT, 0 FF, 1 wire** |

---

## 7. 中断延迟保证

改后，从**中断源触发到第一条 ISR 指令取指**，恒为 2 个时钟周期，无论流水线处于任何状态：

| 流水线状态 | 改前延迟 | 改后延迟 |
|-----------|:---:|:---:|
| 空闲（无分支、无 load） | 2 | **2** |
| EX 有分支/跳转 | 3 | **2** |
| MEM 有 load（bus_ready=1） | 3 | **2** |
| MEM 有 load（bus_ready=0，慢外设） | 2+N | **2** |
| EX 分支 + MEM load | 4+N | **2** |

---

## 8. 相关文件索引

| 文件 | 说明 |
|------|------|
| `core/interrupt/interrupt_pipeline.v` | 中断流水线控制器（本次主要修改对象） |
| `core/interrupt/interrupt_controller.v` | 中断优先级与 handler 地址计算 |
| `core/core_top.v` | 顶层连接，flush/bus_re 控制 |
| `core/ifu/ifu_top.v` | PC 下一地址优先级 |
| `core/ifu/pc_reg.v` | PC 寄存器 |
| `doc/interrupt_vector_mode.md` | 中断向量模式说明 |
| `doc/interrupt_latency_analysis.md` | 中断延迟分析（初版方案） |
| `doc/shadow_register_guide.md` | 影子寄存器机制 |
