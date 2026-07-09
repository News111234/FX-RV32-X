# 中断延迟从 3 周期降至 2 周期 — 方案与实施记录

## 修改日期

2026-06-11 (初版) / 2026-06-25 (修订) / 2026-06-27 (回滚) / 2026-06-30 (Bug #5: PC hold)

> **⚠ 2026-06-27 回滚**: 2026-06-25 将 `intr_flush_id` 改为 `interrupt_flush_i` 的修订是基于对 BRAM 时序的误判。实测 (hazard_unit.v 修复后) 表明 `intr_flush_id = 1'b0` 对 ROM 和 BRAM 均正确: IF/ID 中的旧程序残留指令 (分支等) 会在下一级的 `intr_flush_ex` 处被杀死, 且 `interrupt_taken` 信号在 EX 级阻挡了分支的 PC 重定向。恢复为基准版本 `FX-RV32_RemoveM_Custom` 的原始设计。

## 背景

### 中断延迟的两种定义

| 定义 | 起点 | 终点 | 当前延迟 |
|------|------|------|:---:|
| 论文定义 | 中断请求被接受 (T2↑) | 第一条 ISR 指令取指完成 (T3↑) | **2 周期** |
| 引用文献定义 | 中断请求被接受 (T2↑) | 第一条 ISR 指令译码完成/开始执行 (T4↑) | **3 周期** |

论文中的"2 周期延迟"只在取指完成的意义上成立。若按引用文献更严格的定义（译码完成 = 指令进入执行阶段），实际延迟为 3 周期，存在漏洞。

### 当前时序（3 周期）

以 GPIO 中断为例，波形如下：

```
T1↑:   GPIO_Interrupt 0→1, intr_pending 紧跟着变为 1
T1-T2: intr_pending=1, interrupt_taken_pipe=0(寄存器旧值), PC 正常 +4
T2↑:   interrupt_accepted<=1, interrupt_taken_pipe<=1, interrupt_flush<=1
       ← 中断请求接受。但 PC 依然正常 +4 (T1-T2 期间 interrupt_taken=0)
T2-T3: interrupt_taken=1 → next_pc=handler, flush 全部 =1
T3↑:   PC <= handler (跳转!)  flush 清除
T3-T4: PC=handler, ROM 输出第一条 ISR 指令 → 取指阶段
T4↑:   IF/ID 锁存第一条 ISR 指令 → 取指完成
T4-T5: 第一条 ISR 指令在 ID 阶段 → 译码阶段
T5↑:   ID/EX 锁存第一条 ISR 指令 → 译码完成, 进入执行

中断延迟 = T2↑ → T3↑ → T4↑ → T5↑ = 3 周期
           (T2-T3:周期1) (T3-T4:周期2,取指) (T4-T5:周期3,译码)
```

### 瓶颈根因

**`interrupt_taken_pipe` 是寄存器输出。** 在 T1-T2 期间（`intr_pending=1` 的第一个周期），`interrupt_taken_pipe` 仍然是旧值 0。因此 `next_pc` 等于正常 PC+4 而不是 handler 地址。PC 要到 T3↑ 才跳转到 handler，比中断接受晚了一个周期。

```
T1-T2: intr_pending=1, interrupt_taken_pipe=0 → next_pc = PC+4 (不是handler!)
T2↑:   PC <= PC+4 (浪费!)
       interrupt_taken_pipe <= 1
T2-T3: interrupt_taken_pipe=1 → next_pc = handler
T3↑:   PC <= handler (晚了一个周期)
```

## 方案设计

### 核心思路

新增一个**组合逻辑**信号 `intr_take_now`，在 `intr_pending=1` 的第一个周期就为 1，驱动 `next_pc` 立即指向 handler。同时抑制 IF/ID 流水线寄存器的中断刷新，让第一条 ISR 指令不被误杀。

### 目标时序（2 周期）

```
T1↑:   GPIO_Interrupt 0→1, intr_pending=1
T1-T2: intr_take_now=1(组合逻辑!) → next_pc=handler(立即!)
T2↑:   PC <= handler, interrupt_accepted<=1 ← 跳转和接受同一时钟沿!
       interrupt_flush<=1
       IF/ID 锁存的是旧 PC 处指令 (将在 ID/EX 被刷新杀死)
T2-T3: PC=handler, ROM 输出第一条 ISR 指令
       intr_flush_id=0 (抑制!) → IF/ID 不刷新 → 第一条 ISR 指令正常流入
       intr_flush_ex=1 → ID/EX 被刷新 (杀旧指令)
T3↑:   IF/ID <= 第一条 ISR 指令 ← 取指完成!
       PC <= handler+4
T3-T4: 第一条 ISR 指令在 ID 阶段 (译码)
T4↑:   ID/EX <= 第一条 ISR 指令 ← 译码完成! 2 周期!
```

### 为什么 `intr_take_now` 只在第一个周期为 1

```verilog
wire intr_take_now = interrupt_condition_all && !interrupt_accepted && !interrupt_processed;
```

- `interrupt_condition_all` = `intr_pending`（其他条件均为 `1'b1`）
- T1-T2 期间：`intr_pending=1`, `interrupt_accepted=0`, `interrupt_processed=0` → `intr_take_now=1`
- T2↑：`interrupt_accepted <= 1` → T2-T3 期间 `interrupt_accepted=1` → `intr_take_now=0`（自动清零）

不需要额外控制逻辑来清除。

### 为什么必须同时抑制 IF/ID 刷新

若只让 PC 提前跳转但不抑制 IF/ID 刷新：

```
T2-T3: PC=handler, ROM 输出第一条 ISR 指令
       intr_flush_id=1 → IF/ID 将在 T3↑ 被刷新为 NOP
T3↑:   IF/ID <= NOP ← 第一条 ISR 指令被杀死!
```

**`intr_flush_id` 必须改为 0**，让第一条 ISR 指令通过 IF/ID。旧程序指令在 IF/ID 中残留的问题由下一级的 `intr_flush_ex=1` 处理 — 旧指令最多走到 ID 阶段，在进入 EX 之前被杀死。

## 具体修改

### 涉及文件

| 文件 | 改动概述 |
|------|----------|
| `core/interrupt/interrupt_pipeline.v` | 新增 `intr_take_now_o` 组合逻辑输出 |
| `core/hazard/hazard_unit.v` | `intr_flush_id_o` 改为 `1'b0` |
| `core/ifu/ifu_top.v` | 新增 `intr_take_now_i` 端口 → `next_pc` 最高优先级 |
| `core/ifu/pc_reg.v` | 新增 `intr_take_now_i` 端口 → stall 覆盖 |
| `core/core_top.v` | 新增 `intr_take_now` 线 + 连线 |

### 改动 1：`interrupt_pipeline.v` — 新增组合逻辑输出

**新增端口（第 72 行）：**
```verilog
output wire        intr_take_now_o,   // 组合逻辑: 本周期即将接受中断(用于PC提前跳转)
```

**新增逻辑（第 91-92 行）：**
```verilog
// 在中断pending的第一个周期就为1, interrupt_accepted变1后自动清零
// 让PC在中断接受的同一个时钟沿就跳转到handler, 省一个周期
wire intr_take_now = interrupt_condition_all && !interrupt_accepted && !interrupt_processed;
assign intr_take_now_o = intr_take_now;
```

### 改动 2：`hazard_unit.v` — 只改一行

**改前（原始代码，所有冲刷信号直连）：**
```verilog
assign intr_flush_id_o  = interrupt_flush_i;
assign intr_flush_ex_o  = interrupt_flush_i;
```

**改后（最终版本，2026-06-27 验证通过）：**
```verilog
// IF/ID 不冲刷: 让第一条ISR指令直接通过
// PC已由intr_take_now重定向, ROM/BRAM输出handler指令正常进入IF/ID
// 旧程序分支残留被下一级intr_flush_ex杀死,不会执行
assign intr_flush_id_o  = 1'b0;
assign intr_flush_ex_o  = interrupt_flush_i;
assign intr_flush_mem_o = interrupt_flush_i;
assign intr_flush_wb_o  = interrupt_flush_i;
```

### 改动 3：`ifu_top.v` — 组合逻辑驱动 next_pc

**新增端口：**
```verilog
input  wire        intr_take_now_i,     // 组合逻辑: 本周期即将接受中断(提前跳转PC)
```

**next_pc 优先级（改前）：**
```verilog
assign next_pc = (!rst_n)               ? 32'h0 :
                 (interrupt_taken_i)  ? intr_target_i :    // ← 寄存器信号
                 (branch_taken_i)       ? branch_target_i :
                 ...
```

**next_pc 优先级（改后）：**
```verilog
// intr_take_now_i: 组合逻辑, 在中断pending的第一个周期就为1, 让PC提前跳转到handler
// interrupt_taken_i: 仅用于pc_reg的stall覆盖, 不参与next_pc选择
//   (否则T2-T3期间next_pc又变handler, PC无法递增到handler+4)
assign next_pc = (!rst_n)               ? 32'h0 :
                 (intr_take_now_i)       ? intr_target_i :   // ← 组合逻辑
                 (branch_taken_i)       ? branch_target_i :
                 ...
```

**pc_reg 实例化新增端口连接：**
```verilog
.intr_take_now_i(intr_take_now_i),
```

### 改动 4：`pc_reg.v` — stall 覆盖

**新增端口：**
```verilog
input  wire        intr_take_now_i,   // 组合逻辑中断接受 (中断时强制更新)
```

**改前：**
```verilog
else if (!stall || interrupt_taken_i) begin
```

**改后：**
```verilog
else if (!stall || interrupt_taken_i || intr_take_now_i) begin
```

### 改动 5：`core_top.v` — 连线

**新增内部线（第 208 行）：**
```verilog
wire        intr_take_now;          // 组合逻辑: 中断即将被接受(PC提前跳转)
```

**ifu_top 实例化新增：**
```verilog
.intr_take_now_i   (intr_take_now),
```

**interrupt_pipeline 实例化新增：**
```verilog
.intr_take_now_o    (intr_take_now),
```

## 副作用分析

### 与之前 2-cycle 优化的兼容性

2026-05-29 的"恒定 2 周期延迟"优化（去掉 EX 分支/MEM load 阻塞条件）引入了 `bus_ready_i` 端口和 `bus_re_o` 条件 kill 逻辑。这些逻辑的时序锚点是寄存器信号 `interrupt_taken_pipe`（T2↑ 变为 1），本次改动未修改该信号，因此完全兼容。

### 逐场景验证

| 场景 | 是否受影响 | 分析 |
|------|:---:|------|
| **MEM load 已完成** (bus_ready=1) | 否 | MEM/WB 在 T2↑ 采样 `intr_flush_i` 时还是旧值 0（`interrupt_flush_pipe` 刚在同一沿变 1），load 数据正常锁存 |
| **MEM load 未完成** (bus_ready=0) | 否 | `bus_re_o` kill 逻辑依赖 `interrupt_taken_pipe` 寄存器，时序未变。T2-T3 期间 `bus_re_o = 0` 掐断总线请求 |
| **EX 分支/跳转** | 否 | ifu_top 优先级 interrupt > branch。mepc=ex_pc 保证 MRET 后重做分支指令 |
| **旧指令逃逸** | 否 | T2↑ 时 IF/ID 锁存的旧指令，T3↑ 被 `intr_flush_ex=1` 杀死在 ID/EX，永远进不了 EX |
| **load-use stall 并发** | 已处理 | `pc_reg` 新增 `intr_take_now_i` 覆盖 stall，保证中断时 PC 一定更新 |

### `intr_flush_id = 0` 的安全性

旧指令逃逸路径分析：

```
T1-T2: PC=P_old, ROM 输出指令@P_old
T2↑:   IF/ID <= 指令@P_old (旧程序最后一条指令)
       PC <= handler
T2-T3: IF/ID 输出 = 指令@P_old → 进入 ID 阶段
       ROM 输出 = 指令@handler (第一条 ISR)
       intr_flush_ex=1 → ID/EX 将在 T3↑ 被刷新
T3↑:   ID/EX <= NOP ← 指令@P_old 被杀死 ✓
       IF/ID <= 指令@handler ← intr_flush_id=0 让它通过 ✓
T3-T4: 指令@handler 在 ID 阶段
T4↑:   ID/EX <= 指令@handler (intr_flush_ex 已为 0) ✓
```

旧指令最多走到 ID 阶段，永远不会进入 EX。

## 硬件开销

| 资源 | 增加 | 说明 |
|------:|:---:|------|
| **FF** | 0 | 无新增寄存器 |
| **LUT** | ~1 | `intr_take_now` = 3 输入 AND |
| **Wire** | 4 | 1 内部线 + 3 处端口连接 |

PC 选择 MUX 规模不变（仍是 6 选 1），只是最高优先级的 select 信号来源从寄存器换成了组合逻辑。

## 延迟保证

改后，从中断请求被接受到第一条 ISR 指令译码完成，恒为 2 个时钟周期：

```
T2↑(中断接受) → T3↑(取指完成) → T4↑(译码完成) = 2 周期
```

## 仿真问题与修复

Modelsim 仿真中发现两个问题，已于 2026-06-11 修复。

### 问题 1：PC 进入 ISR 后 handler 指令被旧程序 flush 杀死 (2026-06-30 二次修复)

**现象 (2026-06-11 首次修复后):** 某些中断测试（如 overflow_test）中，PC 在跳到 handler 后，handler 地址上的 `j isr_xxx` 指令被旧程序的 control_hazard flush 同时杀死，而 `interrupt_taken_i` 将 PC 强制递增到 handler+4，导致 handler 指令永久丢失，CPU 陷入死循环。

**根因 (2026-06-30 发现):** 2026-06-11 修复使用 `pc_value + 32'h4` 确实能阻挡旧 EX 分支/跳转信号，但存在被忽略的副作用：同一周期旧程序跳转触发的 `control_hazard` flush（`flush_if=1`）会同时杀死刚进入 IF/ID 的 handler 指令。PC 递增后 handler 地址被跳过。

**2026-06-11 修复（初始版，有缺陷）：**
```verilog
// T2-T3 期间：挡分支 + 递增 PC
(interrupt_taken_i) ? pc_value + 32'h4 :  // ← PC 递增→handler 指令永久丢失!
```

**2026-06-30 二次修复（Bug #5，最终版）：**
```verilog
// T2-T3 期间：挡分支 + HOLD PC (handler 指令在 flush 后可重新取指)
(interrupt_taken_i) ? pc_value :           // ← PC hold: 同样阻挡分支, 且不丢 handler
```

| 周期 | intr_take_now | interrupt_taken_i | next_pc | 说明 |
|------|:---:|:---:|------|------|
| T1-T2 | 1 | 0 | handler | 组合逻辑提前跳转 |
| T2-T3 | 0 | 1 | handler (hold) | 挡住旧 EX 分支，**PC 不动** |
| T3-T4 | 0 | 0 | handler+4 | handler 重新取指完成 |

### 问题 2：编译报错 — wire 引用了尚未声明的 reg 信号

**现象：** Modelsim 编译 `interrupt_pipeline.v` 时报错，`wire intr_take_now` 赋值语句中引用了 `interrupt_accepted` 和 `interrupt_processed`，而这两个 `reg` 的声明在文件后面才出现。

**原因：** `wire intr_take_now = interrupt_condition_all && !interrupt_accepted && !interrupt_processed;` 最初被放在第 91 行（中断条件判断之后），而 `reg interrupt_accepted` 和 `reg interrupt_processed` 的声明在第 125-126 行（状态机之前）。部分 Verilog 工具不支持 forward reference。

**修复：** 将 `intr_take_now` 的组合逻辑移到 `reg` 声明之后（第 125-128 行之间），确保引用的信号已声明：

```verilog
// 改前（第 91 行）：在 reg 声明之前
wire intr_take_now = interrupt_condition_all && !interrupt_accepted && !interrupt_processed;
assign intr_take_now_o = intr_take_now;

// ... 中间隔了 interrupt_pc 选择和 reg 声明 ...

// 改后（第 125-128 行，紧接 reg 声明之后）：
reg         interrupt_accepted;
reg         interrupt_processed;
reg [31:0]  saved_interrupt_pc;
reg [31:0]  saved_interrupt_cause;

// ========== 组合逻辑: 中断即将被接受 (用于PC提前跳转) ==========
wire intr_take_now = interrupt_condition_all && !interrupt_accepted && !interrupt_processed;
assign intr_take_now_o = intr_take_now;
```

### 问题 3：PC 和 GPIO 中断信号同步变化，比 intr_taken_o 快了一个周期

**现象：** 波形上 PC 在 GPIO 中断信号变为 1 的同一时刻就跳转到 handler，而 `interrupt_taken_o`（即 `interrupt_taken_pipe`）在一个周期后才变为 1。PC 比 intr_taken_o 快了一个周期。

**原因分析：** PC 跳转由组合逻辑 `intr_take_now` 驱动，`intr_take_now` 依赖 `intr_pending`，而 `intr_pending` 跟随 GPIO 中断信号组合变化。因此 GPIO 一变化，`next_pc` 就立即变为 handler，PC 在下一个时钟沿（波形上看起来和 GPIO 变化"同时"）就跳转了。而 `intr_taken_o` 是寄存器输出，要到再下一个时钟沿才可见。

这不是 bug，是设计的预期行为。时序对比：

| | 原设计 | 新设计 |
|------|------|------|
| T1-T2 | next_pc = PC+4 (interrupt_taken_pipe=0) | next_pc = handler (intr_take_now=1, 组合逻辑) |
| T2↑ | PC <= PC+4, interrupt_taken_pipe <= 1 | **PC <= handler**, interrupt_taken_pipe <= 1 |
| T2-T3 | next_pc = handler (interrupt_taken_pipe=1) | next_pc = handler+4 (interrupt_taken_pipe=1) |
| T3↑ | PC <= handler | PC <= handler+4 |

在原设计中，GPIO 在 T1↑ 变 1，PC 要到 T3↑ 才跳转到 handler — **PC 比 GPIO 晚两个周期**。

在新设计中，GPIO 在 T1↑ 变 1 → `intr_take_now`（组合逻辑）在 T1-T2 期间立即驱动 `next_pc=handler` → PC 在 T2↑ 跳转 — **PC 只比 GPIO 晚一个周期，和 intr_taken_o 在同一时钟沿变化**。

这是正确的行为：PC 在中断被接受的同一个时钟沿就跳转到 handler，正是这"提前"的一个周期将中断延迟从 3 周期降到了 2 周期。

### 最终 next_pc 时序表

```
         T1-T2              T2↑            T2-T3             T3↑            T3-T4
   ────────┼──────────────────┼────────────────┼─────────────────┼───────────────┼──
   intr_take_now=1            │ intr_take_now=0                │ intr_take_now=0
   intr_pending=1             │ intr_pending=1                │ intr_pending=1
   intr_accepted=0            │ intr_accepted=1               │ intr_accepted=0
   intr_processed=0           │ intr_processed=0              │ intr_processed=1
                              │                               │
   next_pc = handler ─────────┤ next_pc = handler+4 ──────────┤ next_pc = handler+8
                              │                               │
              ┌── 时钟沿 ─────┘               ┌── 时钟沿 ─────┘
              │ PC <= handler                  │ PC <= handler+4
              │ intr_taken <= 1                │ intr_taken <= 0
              │ intr_flush <= 1                │ intr_flush <= 0
              │                               │
          ISR取指开始                      第二条ISR取指
```

## 相关文档

| 文件 | 内容 |
|------|------|
| `interrupt_2cycle_guaranteed.md` | 初版恒定 2 周期延迟方案设计 |
| `interrupt_2cycle_implementation.md` | 初版实施记录（2026-05-29） |
| `interrupt_latency_analysis.md` | 中断延迟分析 |
| `shadow_register_guide.md` | 影子寄存器机制 |
| `shadow_save_race_condition.md` | 影子保存竞态分析 |
