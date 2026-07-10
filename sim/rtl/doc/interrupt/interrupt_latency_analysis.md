# 中断延迟分析与恒定 2 周期方案

## 当前中断延迟分析

### 中断接受条件

在 `core/interrupt/interrupt_pipeline.v` 第 77-82 行定义了中断接受的前置条件：

```verilog
wire [4:0] interrupt_condition;

assign interrupt_condition[0] = intr_pending_i;                          // 条件0: 有中断等待
assign interrupt_condition[1] = ~(ex_branch_taken_i || ex_jump_taken_i); // 条件1: EX 阶段无分支/跳转
assign interrupt_condition[2] = ~mem_mem_re_i;                           // 条件2: MEM 阶段无 load
assign interrupt_condition[3] = 1'b1;
assign interrupt_condition[4] = 1'b1;

wire interrupt_condition_all = &interrupt_condition;  // 全部满足才接受
```

只有当五个条件全部满足（`interrupt_condition_all = 1`）时，中断才会在下一个时钟沿被接受。条件 1 和条件 2 不满足时，中断**每个周期重新检查**，直到条件清除后才接受。

### 两种延迟的概念

需要区分两个概念：

| 概念 | 定义 | 当前状态 |
|------|------|----------|
| **中断响应延迟** | 从条件满足到第一条 ISR 指令取指的时间 | **恒定 2 周期** |
| **中断总延迟** | 从中断源触发到第一条 ISR 指令取指的时间 | **可变**（依赖条件 1、2 何时满足） |

即：硬件响应速度是固定的（2 拍），但响应**启动时机**不固定。

### 各种场景下的实际延迟

| 场景 | 额外等待 | 总延迟 | 说明 |
|------|:---:|:---:|------|
| EX 无分支、MEM 无 load | 0 | **2 周期** | 理想情况 |
| EX 有分支/跳转 | 1 拍 | **3 周期** | 等分支完成 |
| MEM 有 load，bus_ready 已到 | 1 拍 | **3 周期** | 等 load 完成 |
| MEM 有 load，bus_ready 未到（慢外设） | N 拍 | **2+N 周期** | 持续等待 |
| EX 有分支 且 MEM 有 load | 2+N 拍 | **4+N 周期** | 两重等待叠加 |

**响应延迟是固定的（2 周期），但总延迟不固定。**

---

## 恒定 2 周期总延迟方案

### 设计目标

无论 EX 阶段是否有分支/跳转、MEM 阶段是否有未完成的 load，中断总延迟恒定为 2 个时钟周期。

### 核心思路

去掉两个阻塞条件（条件 1、条件 2），中断无条件接受。副作用由硬件在关键路径上的微小改动来消化。

### 改动文件清单

| 文件 | 改动 | 开销 |
|------|------|:---:|
| `core/interrupt/interrupt_pipeline.v` | 去掉条件 1、条件 2，中断无条件接受 | 0 LUT（减少逻辑） |
| `core/core_top.v` | 中断时抑制分支/跳转的 EX 流水线冲洗 | 1 LUT |
| `core/core_top.v` | 中断时掐断 MEM 阶段 pending 的总线读请求 | 1 LUT |
| **合计** | | **2 LUT** |

不需要新增寄存器、不需要新状态机、不需要改接口。

---

## 各改动详解

### 改动 1：`interrupt_pipeline.v` — 去掉阻塞条件

**位置**：第 78-79 行

```verilog
// ===== 改前 =====
assign interrupt_condition[1] = ~(ex_branch_taken_i || ex_jump_taken_i);
assign interrupt_condition[2] = ~mem_mem_re_i;

// ===== 改后 =====
assign interrupt_condition[1] = 1'b1;  // 不再等待 EX 分支/跳转
assign interrupt_condition[2] = 1'b1;  // 不再等待 MEM load
```

**mepc 保存逻辑不变**（第 89-103 行）。现有逻辑从流水线最深有效阶段取 PC：

```verilog
if (mem_valid_i && (mem_pc_i != 32'b0)) begin
    interrupt_pc = mem_pc_i;      // 取 MEM 阶段 PC
end else if (ex_valid_i && (ex_pc_i != 32'b0)) begin
    interrupt_pc = ex_pc_i;       // 取 EX 阶段 PC
end else if (id_valid_i && (id_pc_i != 32'b0)) begin
    interrupt_pc = id_pc_i;       // 取 ID 阶段 PC
end else begin
    interrupt_pc = if_pc_i;       // 取 IF 阶段 PC
end
```

这意味着：
- EX 有分支时取中断 → `mepc = 分支指令的 PC`，分支没跳，MRET 后重新执行分支指令
- MEM 有 load 时取中断 → `mepc = load 指令的 PC`，load 被取消，MRET 后重新执行

### 改动 2：`core_top.v` — 中断时抑制分支冲洗

**位置**：第 658 行

```verilog
// ===== 改前 =====
assign flush_ex = ex_branch_taken || ex_jump_taken;

// ===== 改后 =====
assign flush_ex = (ex_branch_taken || ex_jump_taken) && !interrupt_taken_pipe;
```

当 `interrupt_taken_pipe = 1`（中断已被接受）时，EX 阶段的分支/跳转信号被抑制，不产生流水线冲洗。原因是 ifu_top 中 `next_pc` 的优先级本就是 `interrupt > branch > jump`（见 `ifu_top.v` 第 53-58 行），PC 已正确跳转到中断 handler，不需要分支冲洗再来改动 PC。

### 改动 3：`core_top.v` — 中断时掐断 pending 的 load 总线请求

**位置**：第 492-498 行（`bus_re_o` 的 assign）

```verilog
// ===== 改前 =====
assign bus_re_o = mem_bus_re;

// ===== 改后 =====
// 中断时 kill 未完成的 load 总线请求，避免 ISR 执行期间外设响应污染 WB 阶段
assign bus_re_o = mem_bus_re && !interrupt_taken_pipe;
```

MEM 阶段有 load 时，`bus_re_o` 正通过总线向外设请求数据。中断来了如果不掐掉，外设响应可能在 ISR 执行期间回来，导致：
1. WB 阶段在 ISR 运行期间意外写入寄存器
2. 写回的数据不属于 ISR，污染寄存器状态

掐断后，外设看到 `bus_re` 撤销，停止响应。load 指令在 MRET 后重新执行。

---

## 恒定 2 周期时序

改后无论 EX/MEM 处于什么状态，中断总延迟恒定为 2 个时钟周期：

```
         T0              T0↑              T1              T1↑              T2
    ─────┼───────────────┼────────────────┼───────────────┼────────────────┼───

  中断源触发            │                 │                │                │
    → intr_pending=1    │                 │                │                │
   (组合逻辑)           │                 │                │                │
                        │                 │                │                │
  interrupt_condition   │                 │                │                │
    _all = 1 ✓          │                 │                │                │
  (不再等EX/MEM)        │                 │                │                │
                        │                 │                │                │
            ┌─ 时钟沿 ──┘                 │                │                │
            │ interrupt_accepted ← 1       │                │                │
            │ interrupt_taken    ← 1       │                │                │
            │ mepc               ← 最深PC   │                │                │
            │ csr_mepc_we        ← 1       │                │                │
            │ csr_mcause_we      ← 1       │                │                │
            │ csr_mstatus_we     ← 1       │                │                │
            │                             │                │                │
            │ interrupt_taken=1 可见       │                │                │
            │ → ifu_top: next_pc = intr_target            │                │
            │ → flush_ex = 0 (被抑制)      │                │                │
            │ → bus_re_o = 0 (load请求kill)│                │                │
            │                             │                │                │
            │                ┌─ 时钟沿 ────┘                │                │
            │                │ PC ← handler地址             │                │
            │                │                              │                │
            │                │ 第一条ISR指令取指             │                │
            │                │ ←── 恒定2周期 ──→            │                │
```

### 各阶段行为总结

| 阶段 | 中断时状态 | 处理方式 |
|------|-----------|----------|
| IF | 刚取出的指令 | 直接丢弃（`intr_flush_if` 冲洗），下周期取 ISR 指令 |
| ID | 正在译码 | 直接丢弃（`intr_flush_id` 冲洗） |
| EX | 有分支/跳转 | 分支不跳（`flush_ex` 被抑制），mepc 指向分支指令 |
| EX | 普通指令 | 直接丢弃（`intr_flush_ex` 冲洗），mepc 指向该指令 |
| MEM | 有 load 等待响应 | 总线请求掐断（`bus_re_o = 0`），mepc 指向 load 指令 |
| MEM | 有 load 刚好完成 | 数据正常写回 regfile，影子寄存器随后保存完整状态 |
| MEM | 有 store | store 已发出（`bus_we + bus_ack` 已锁存），正常完成 |

---

## 副作用分析

### 被取消的 load 指令

- **对 RAM load**：完全安全。MRET 后 load 重新执行，读取相同地址，得到相同数据，写入相同寄存器。**幂等操作**。
- **对 FIFO 读（如 UART RX）**：重新执行会读走下一个数据，导致数据丢失。但当前设计的 UART 只有 TX，没有 RX FIFO，暂不受影响。将来添加 RX 时需注意。
- **对 SPI/I2C 数据寄存器读**：重新执行会触发新的总线读，可能读到下一笔数据。与 UART RX 同理，需在外设驱动中处理。

### 被取消的分支指令

- 分支指令未执行跳转，mepc 指向分支指令本身（不是目标地址）。
- MRET 后程序从分支指令恢复，重新判断分支条件。如果条件依赖的寄存器在 ISR 中没有被修改（影子寄存器保证），分支结果与中断前一致。
- **逻辑上完全等价**。

### 刚好完成的 load

- 如果 load 在中断被接受的同一个周期收到 `bus_ready`，数据进入 MEM/WB 寄存器。
- 下一拍（中断处理周期）WB 写入寄存器。
- 再下一拍影子寄存器保存（`shadow_save = 1`），此时 regfile 已包含 load 结果。
- 保存的上下文是"load 已完成"的完整状态。MRET 后 PC 仍指向 load 指令（mepc = load PC），load 会被重复执行一次。
- 对于 RAM：两次 load 结果相同，无副作用。
- 更优的做法：这种情况应该 `mepc = load_PC + 4`（跳过已完成指令），但需要判断 `bus_ready` 状态，增加硬件复杂度。当前方案选择简单安全——多执行一次幂等 load。

---

## 硬件开销汇总

| 项目 | 改动 | 开销 |
|------|------|:---:|
| `interrupt_condition[1]` | `~(ex_branch \| ex_jump)` → `1'b1` | 减少 2 级门 |
| `interrupt_condition[2]` | `~mem_mem_re` → `1'b1` | 减少 1 级门 |
| `flush_ex` | 加 `&& !interrupt_taken_pipe` | +1 LUT |
| `bus_re_o` | 加 `&& !interrupt_taken_pipe` | +1 LUT |
| **净增** | | **2 LUT** |

与整个 CPU 的资源（Kintex-7 约 20 万 LUT）相比，占比小于 0.001%。

---

## 相关文件

| 文件 | 角色 |
|------|------|
| `core/interrupt/interrupt_controller.v` | 中断优先级编码、handler 地址计算 |
| `core/interrupt/interrupt_pipeline.v` | 中断接受条件判断、CSR 更新、影子寄存器控制 |
| `core/core_top.v` | 顶层连接、flush/bus_re 控制逻辑 |
| `core/ifu/ifu_top.v` | PC 下一地址选择（中断 > 分支 > 跳转 > stall > pc+4） |
| `core/ifu/pc_reg.v` | PC 寄存器（中断时强制更新，忽略 stall） |
| `doc/interrupt_vector_mode.md` | 中断向量模式说明（Direct / Vectored） |
| `doc/shadow_register_guide.md` | 影子寄存器机制说明 |
