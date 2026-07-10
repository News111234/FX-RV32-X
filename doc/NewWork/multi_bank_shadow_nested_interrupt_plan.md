# FX-RV32 多 Bank 影子寄存器 + 优先级中断嵌套 技术方案

> **产出目标：** 1 篇发明专利 + 1 篇会议论文
>
> **基线基础：** TVLSI 论文 "FX-RV32: A Lightweight, Deterministic and Low Latency RISC-V Processor for Hard Real-Time Embedded Systems"
>
> **日期：** 2026-06-30
>
> **状态：** RTL 实施完成（含 OVERFLOW_POLICY 降级复用），Modelsim 仿真验证通过

---

## 1. 背景与动机

### 1.1 TVLSI 论文已达成

| 维度 | 指标 |
|------|------|
| 中断延迟 | 固定 2 周期（**无条件接受**，不等待 EX 分支/跳转或 MEM 加载） |
| 上下文保存 | 1 周期并行快照，31 个影子寄存器（x1–x31） |
| 上下文恢复 | 1 周期（MRET 触发 shadow_restore 脉冲） |
| GPIO 延迟 | 1 周期（标准 SW 指令，不需要 ISA 扩展） |
| 确定性 | 8 个基准测试 × 40 轮，零周期抖动 |
| 面积 | 基线 24.9 kGE，带影子 32.4 kGE @55nm |
| **明确局限** | **不支持中断嵌套**（只有 1 组影子寄存器，抢占会覆盖上下文） |

### 1.2 为什么中断嵌套是刚需

在硬实时嵌入式系统中，不同外部事件有不同紧急程度：

| 场景 | 高优先级事件 | 低优先级事件 | 嵌套需求 |
|------|-------------|-------------|---------|
| 汽车 EPS 转向 | 扭矩传感器超限 (Timer IRQ) | 角度定期采样 (SPI IRQ) | **必须抢占** |
| 无人机飞控 | IMU 数据就绪 (GPIO IRQ, 1kHz) | 遥测下行 (UART IRQ, 10Hz) | **必须抢占** |
| 工业电机 | 过流保护 (GPIO IRQ, 硬实时) | 速度环 PID (Timer IRQ) | **必须抢占** |
| 医疗设备 | 紧急停机 (External IRQ) | 数据记录 (I2C IRQ) | **必须抢占** |

当高优先级事件到达时，如果处理器正在服务低优先级中断：
- **不允许抢占** → 高优先级事件被阻塞，可能导致设备损坏或控制失效
- **允许抢占但软件保存上下文** → 数十周期的非确定性延迟

### 1.3 现有方案对比

| 方案 | 嵌套支持 | 保存方式 | 单级保存延迟 | 嵌套保存延迟 |
|------|---------|---------|-------------|-------------|
| ARM Cortex-M3/4 NVIC | ✓ | 自动压栈到内存 (8 regs) | 12 周期 | 12 周期/级 |
| RISC-V CLIC 硬件堆栈 [Mao 2021] | ✓ | 串行 push 到内部堆栈 (10 regs) | 11 周期 | 11 周期/级 |
| Sophon snapreg [Huang 2025] | ✗ | 单组快照寄存器 (32 regs) | 1 周期 | **不支持** |
| CV32E40P [Balas 2021] | ✓ | 软件 store/load | 24 周期 (EABI) | 24 周期/级 |
| **本方案 (FX-RV32-Nested)** | **✓** | **N 组全并行影子寄存器** | **1 周期** | **1 周期/级** |

**结论：** 业界尚无 "全并行硬件保存 + 多级嵌套 + 确定性" 的方案。本方案唯一同时满足三个条件。

---

## 2. 技术方案总览

### 2.1 核心思想

将 FX-RV32 现有的 1 组 × 31 个影子寄存器扩展为 **N 组 × M 个影子寄存器**（N 可配置，默认 N=4, M=31），每级中断嵌套占用一组 Bank。增加一个 **硬件 Bank 控制器**（`bank_controller.v`），自动管理 Bank 的分配/释放、优先级抢占判定、溢出检测和 Tail-Chaining 优化。整个嵌套机制对软件完全透明。

### 2.2 四个技术层

```
多Bank 影子寄存器嵌套系统
  │
  ├─ Layer 1: 硬件 Bank 指针管理 (interrupt_pipeline)
  │   └─ Bank 自动分配 (interrupt_accepted && allow_nesting → bank_ptr++)
  │   └─ Bank 自动释放 (MRET → bank_ptr--)
  │   └─ Bank 溢出检测 (bank_ptr == SHADOW_BANKS → bank_full=1)
  │
  ├─ Layer 2: 优先级抢占判定电路 (bank_controller, 纯组合逻辑)
  │   └─ current_priority 硬件自动跟踪
  │   └─ 组合逻辑抢占比较 (new_priority > current_priority → preemption_allowed)
  │   └─ 0 额外延迟
  │
  ├─ Layer 3: Tail-Chaining 优化
  │   └─ MRET 时检测 pending → 跳过 restore+save 冗余
  │   └─ 连续中断间节省 1 周期
  │
  └─ Layer 4: Bank 溢出可配置策略 (OVERFLOW_POLICY 参数)
      └─ 硬限制策略 (OVERFLOW_POLICY=0, 默认): 阻塞新中断, 等 MRET 释放 Bank
      └─ 降级复用策略 (OVERFLOW_POLICY=1): bank_ptr 保持 N, 覆盖 Bank[N-1]
```

---

## 3. 详细硬件设计

### 3.1 新增模块：`bank_controller.v` (纯组合逻辑)

**设计决策**：`bank_controller` 为**纯组合逻辑**模块——所有时序关键信号（`bank_ptr`、`shadow_save`、`shadow_restore`）由 `interrupt_pipeline` 在同一 `always` 块内管理，消除跨模块时序竞争。

```
Module: bank_controller (纯组合逻辑)
功能:  多 Bank 影子寄存器的硬件决策单元

参数:
  SHADOW_BANKS      = 4     // Bank 数量
  TAIL_CHAIN_EN     = 0     // Tail-chaining 使能 (默认关闭)
  OVERFLOW_POLICY   = 0     // Bank 溢出策略: 0=硬限制, 1=降级复用

端口:
  输入:
    clk_i, rst_n_i
    bank_ptr_i [3:0]                   // 当前 Bank 指针 (来自 interrupt_pipeline)
    mret_in_ex_i                       // MRET 指令在 EX 阶段
    intr_pending_i                     // 有中断 pending (用于 tail-chain 判断)
    interrupt_processing_i             // 当前正在服务中断
    current_priority_i [3:0]           // 当前服务中断优先级 (0=无中断)
    new_priority_i [3:0]               // 新中断优先级

  输出 (纯组合逻辑):
    allow_nesting_o                    // 允许嵌套: 抢占 && (未满 || 降级复用)
    bank_full_o                        // Bank 已满 (bank_ptr == SHADOW_BANKS)
    tail_chain_detect_o                // Tail-Chaining 检测
    degradation_reuse_o                // 降级复用模式 (Bank 满但允许嵌套)
```

**优先级抢占判定：**

```verilog
// 当前无中断服务 或 新中断优先级更高 → 允许抢占
wire preemption_allowed = (current_priority_i == 4'd0) ||
                          (new_priority_i > current_priority_i);
```

**Bank 溢出检测：**

```verilog
// bank_ptr == SHADOW_BANKS → 所有 Bank 已用尽
wire bank_full = (bank_ptr_i == SHADOW_BANKS[3:0]);
```

**Tail-Chaining 判定：**

```verilog
// MRET 在 EX 阶段，且同时有新的中断 pending
wire tail_chain_detect = TAIL_CHAIN_EN && mret_in_ex_i && intr_pending_i;
```

**综合决策（降级复用 + 允许嵌套）：**

```verilog
// 降级复用: Bank 满时, 若 OVERFLOW_POLICY=1 且新中断优先级更高, 允许覆盖最深嵌套层
wire degradation_reuse = (OVERFLOW_POLICY == 1) && bank_full && preemption_allowed;

// 可以分配新 Bank: 优先级允许 且 (未满 或 降级复用) 且 非 Tail-Chain
assign allow_nesting_o = preemption_allowed && (!bank_full || degradation_reuse) && !tail_chain_detect;
```

### 3.2 修改模块：`regfile.v`

**现有结构：**
```
regfile
  ├─ rf [31:0] [0:31]          // 32 个通用寄存器
  └─ shadow [31:0] [1:31]      // 1 组 × 31 个影子寄存器
```

**修改后结构：**
```
regfile #(
    .SHADOW_BANKS = 4,          // Bank 数量（新增 parameter）
    .SHADOW_EN    = 1           // 原有 parameter
)
  ├─ rf [31:0] [0:31]          // 32 个通用寄存器（不变）
  └─ shadow [31:0] [0:SHADOW_BANKS-1] [1:31]  // N 组 × 31 个影子寄存器
```

**写端口逻辑（修改后）：**

```verilog
// 写入优先级: shadow_restore > normal_WB > shadow_save
// Bank 索引说明:
//   - 保存: shadow[bank_ptr_i - 1]  (bank_ptr 已在同周期递增)
//   - 恢复: shadow[bank_ptr_i]      (bank_ptr 已在同周期递减)

always @(posedge clk_i) begin
    if (!rst_n_i) begin
        // 复位逻辑不变
    end else if (shadow_restore_i) begin
        // 从当前 Bank 恢复 x1-x31（最高优先级）
        for (int i = 1; i < 32; i++)
            rf[i] <= shadow[bank_ptr_i][i];
    end else if (reg_we_i && rd_addr_i != 0) begin
        // 正常 WB 写
        rf[rd_addr_i] <= wb_data_i;
    end else if (shadow_save_i) begin
        // 保存到 Bank[bank_ptr-1]（最低优先级）
        // bank_ptr 已在 interrupt_pipeline 中递增，索引 bank_ptr-1 即保存到刚分配的 Bank
        for (int i = 1; i < 32; i++)
            shadow[bank_ptr_i - 1][i] <= rf[i];
    end
end
```

**关键时序**：`shadow_save` 和 `bank_ptr` 递增发生在同一时钟沿（T1↑）。在下一个时钟沿（T2↑），regfile 采样到 `shadow_save_i=1` 且 `bank_ptr_i` 已递增，根据 `bank_ptr_i - 1` 计算保存索引。例如首次中断 bank_ptr 由 0→1，保存到 Bank[0]（主程序上下文）；嵌套时 bank_ptr 由 1→2，保存到 Bank[1]（Timer ISR 上下文）。

### 3.3 修改模块：`interrupt_pipeline.v`

**核心变更**：Bank 指针（`bank_ptr_reg`）管理从 bank_controller 移入 interrupt_pipeline，在同一 `always` 块内管理 `shadow_save`/`shadow_restore`/`bank_ptr`，消除跨模块时序竞争。

**新增/修改端口：**

```
// 来自 bank_controller (纯组合逻辑决策输入)
input  wire        allow_nesting_i,       // 允许分配新 Bank
input  wire        bank_full_i,           // Bank 已满
input  wire        tail_chain_detect_i,   // Tail-Chaining 检测
input  wire        degradation_reuse_i,   // 降级复用模式 (Bank 满但允许嵌套)

// 到 bank_controller 及外部
output wire        interrupt_accepted_o,  // 中断已接受 (通知 bank_controller)
output wire        interrupt_processing_o,// 正在服务中断 (给 bank_controller)
output reg  [3:0]  bank_ptr_o,            // 当前 Bank 指针
```

**Bank 指针管理逻辑（在同一 always 块内）：**

```verilog
// 中断进入时:
if (allow_nesting_i) begin
    shadow_save_o <= 1'b1;  // 保存当前上下文到 Bank[bank_ptr-1]
    if (!degradation_reuse_i) begin
        bank_ptr_reg <= bank_ptr_reg + 4'd1;  // 正常递增
    end
    // 降级复用: bank_ptr 保持 N 不变, 覆盖 Bank[N-1]
end
else if (bank_ptr_reg == 4'd0) begin
    // 首次中断 (主程序→ISR): 保存主程序上下文到 Bank[0]
    shadow_save_o <= 1'b1;
    bank_ptr_reg <= 4'd1;
end

// MRET 返回时:
else if (id_ex_mret) begin
    if (tail_chain_detect_i) begin
        // Tail-Chaining: 跳过 restore, bank_ptr 不变
    end else begin
        bank_ptr_reg     <= bank_ptr_reg - 4'd1;  // 先递减
        shadow_restore_o <= 1'b1;                  // 再触发恢复
    end
end
```

**中断进入时序（2 周期延迟不变，Bank 分配在周期 1 完成）：**

```
Cycle 0:  外设/软件/定时器发出中断请求
          中断控制器组合逻辑: 优先级仲裁 + 抢占判定 + 向量地址计算
          intr_take_now 同步置 1 → next_pc = handler 地址 (组合逻辑)
Cycle 1:  PC ← handler 地址 (寄存器更新)
          interrupt_taken_o 置 1 (中断正式接受)
          shadow_save_o 置 1 + bank_ptr 递增 (同一时钟沿)
          intr_flush_ex/mem/wb (冲刷旧程序残留, IF/ID 不冲刷)
Cycle 2:  第一条 ISR 指令进入 EX 阶段执行
```

**修改后的 MRET 处理（带 Bank 管理和尾链）：**

正常 MRET（当前 ISR 返回后无更高优先级中断等待）：
```
Cycle 0:  MRET 在 EX 阶段
Cycle 1:  bank_ptr-- (先递减), shadow_restore ← Bank[bank_ptr]
          从 Bank 恢复被中断程序的 x1-x31
          mstatus.MIE 恢复
Cycle 2:  被中断程序的第一条指令进入 ID
```

尾链 MRET（当前 ISR 返回时检测到 intr_pending=1 且 TAIL_CHAIN_EN=1）：
```
Cycle 0:  MRET 在 EX 阶段, bank_controller 检测到 tail_chain_detect=1
          → 跳过 shadow_restore, bank_ptr 保持不变
Cycle 1:  intr_pending=1 → 接受新中断
          bank_ptr 已 > 0, Bank[bank_ptr-1] 已持有有效上下文 → 不触发额外 save
          PC ← 新 handler 地址
Cycle 2:  新 ISR 第一条指令进入 ID

收益: 省掉 1 个周期的 shadow_restore。正常路径需 3 周期，尾链只需 2 周期。
```

### 3.4 修改模块：`interrupt_controller.v`

**新增功能：** 当前服务优先级和新中断优先级的编码输出，供 bank_controller 进行抢占判定。

```verilog
// 优先级编码 (4-bit, 数值越大优先级越高)
// MEI (外部): 11, MTI (定时器): 7, MSI (软件): 3
// 0 = 无中断服务中

output wire [3:0] current_priority_o,  // 当前服务中断优先级
output wire [3:0] new_priority_o,      // 新中断优先级 (用于抢占比较)
```

`current_priority_o` 通过中断 pending 状态和优先级仲裁结果组合逻辑产生——当中断被接受时，对应优先级的编码输出为当前服务优先级；无中断时输出 0。`new_priority_o` 由中断控制器的优先级编码器直接输出。

### 3.5 实施文件清单

以下为实施过程中涉及的全部文件，按操作类型列出。

#### 新增文件 (2 个)

| 文件路径 | 功能说明 |
|----------|---------|
| `core/interrupt/bank_controller.v` | 多 Bank 硬件管理器——**纯组合逻辑决策单元**。参数：`SHADOW_BANKS`（默认 4）、`TAIL_CHAIN_EN`（默认 0）、`OVERFLOW_POLICY`（默认 0）。输出 `allow_nesting_o`（抢占 && (未满 \|\| 降级复用)）、`bank_full_o`、`tail_chain_detect_o`、`degradation_reuse_o`。所有时序信号（bank_ptr、shadow_save、shadow_restore）由 interrupt_pipeline 管理 |
| `tb/tb_nested_intr.v` | 嵌套中断验证 testbench（Modelsim，非 UVM）。实例化 `core_top`，提供指令 ROM/数据 RAM/GPIO+Timer 中断激励，检查 `tohost` 结果。关键观测信号：`bank_ptr`、`shadow_save`、`shadow_restore` |

#### 修改的 RTL 文件 (6 个)

| 文件路径 | 修改内容 |
|----------|---------|
| `core/id/regfile.v` | 影子寄存器从 `reg [31:0] shadow_registers [1:31]`（1 组×31）扩展为 `reg [31:0] shadow_registers [0:SHADOW_BANKS-1][1:31]`（N 组×31）。新增 `SHADOW_BANKS` 参数和 `bank_ptr_i` 输入端口。保存到 `shadow[bank_ptr_i - 1]`，从 `shadow[bank_ptr_i]` 恢复。bank_ptr 在 interrupt_pipeline 中先更新再触发，regfile 仅根据 bank_ptr_i 完成数据锁存 |
| `core/id/id_top.v` | 新增 `SHADOW_BANKS` 参数（默认 4）和 `bank_ptr_i` 输入端口，透传至 `regfile` 实例化 |
| `core/interrupt/interrupt_pipeline.v` | **最大改动**。新增 `bank_ptr` 寄存器管理（中断进入时递增、MRET 时递减）、`shadow_save_o` 和 `shadow_restore_o` 在同一 `always` 块内生成。新增输入：`allow_nesting_i`、`bank_full_i`、`tail_chain_detect_i`、`degradation_reuse_i`（来自 bank_controller）。新增输出：`bank_ptr_o`、`interrupt_accepted_o`、`interrupt_processing_o`。首次中断：`bank_ptr==0` 时触发 shadow_save 保存主程序上下文到 Bank[0]。嵌套：`allow_nesting && !degradation_reuse` 时递增 bank_ptr 并保存。降级复用：`degradation_reuse` 时 bank_ptr 保持 N，覆盖 Bank[N-1]。Tail-Chaining：MRET 时若 `tail_chain_detect_i=1`，跳过 restore 且 bank_ptr 不变 |
| `core/interrupt/interrupt_controller.v` | 新增 `current_priority_o` 和 `new_priority_o` 输出端口，用于 bank_controller 的优先级抢占判断。优先级值编码：MEI=11 (GPIO/SPI/I2C共用), MTI=7, MSI=3 |
| `core/csr/csr_regfile.v` | MISA 初始值修正（MXL=1）、中断 CSR 写入优先级保护（mstatus/mepc/mcause 不被同时的 CSR 指令覆盖）。预留自定义 CSR 地址 `0xBC0`（mneststatus）和 `0xBC1`（mprio）接口 |
| `core/core_top.v` | 实例化 `bank_controller`（纯组合逻辑）和更新后的 `interrupt_pipeline`。新增 `OVERFLOW_POLICY` 参数（默认 0）。新增内部连线：`allow_nesting`、`bank_full`、`tail_chain_detect`、`degradation_reuse`、`interrupt_processing_pipe`、`bank_ptr`、`shadow_save`、`shadow_restore`。`id_top` 实例化增加 `.SHADOW_BANKS(4)` 参数和 `.bank_ptr_i(bank_ptr)` 连接 |

#### 测试/脚本文件 (3 个)

| 文件路径 | 说明 |
|----------|------|
| `sim/nested_intr_test.s` | RISC-V 汇编测试程序。Timer ISR（优先级 7）→ GPIO ISR（优先级 11）抢占 → 验证嵌套上下文保存/恢复 → `tohost=0` 表示 PASS |
| `sim/nested_intr_test.hex` | 汇编后的 hex 机器码（193 words），由 `python/asm_to_hex.py` 生成 |
| `sim/run_nested.do` | Modelsim 一键仿真 TCL 脚本。汇编测试程序 → 编译全部 RTL → 启动仿真 → 波形输出 |

#### 文档文件 (4 个)

| 文件路径 | 说明 |
|----------|------|
| `doc/NewWork/multi_bank_shadow_nested_interrupt_plan.md` | 本文件——完整技术方案 |
| `doc/NewWork/implementation_guide.md` | 实施指南（架构、参数配置、仿真操作、面积估算） |
| `doc/NewWork/patent_multi_bank_shadow.md` | 专利文档（7 张图 + 完整说明书） |
| `doc/NewWork/patent_figures_mermaid.md` | 7 张图的 Mermaid 源码（可在 mermaid.live 导出 SVG） |

---

## 4. 中断嵌套完整流程示例

### 4.1 3 级嵌套时序

```
时间轴 →

主程序运行中 (bank_ptr=0, current_priority=00)
  │
  ├─ Timer IRQ (优先级 7, 低) 到达 ─────────────────────
  │   interrupt_accepted                                       [Cycle T]
  │   bank_ptr: 0→1                                           [Cycle T+1, 寄存器更新]
  │   shadow_save → Bank[0] (x1-x31 快照, 主程序上下文)        [Cycle T+1↑, 1 cycle]
  │   current_priority: 00→7                                  [Cycle T+1]
  │   PC → mtvec + 7×4                                        [Cycle T+1]
  │   intr_flush_ex/mem/wb                                     [Cycle T+1]
  │   第一条 ISR_Timer 指令进入 EX                              [Cycle T+2]
  │
  │   ISR_Timer 执行中... (bank_ptr=1)
  │   │
  │   ├─ GPIO IRQ (优先级 11, 高!) 到达 ───────────────────
  │   │   new_priority(11) > current_priority(7) → 抢占!        [组合逻辑, 0cycle]
  │   │   bank_ptr: 1→2                                        [Cycle T+1]
  │   │   current_priority: 7→11                               [Cycle T+1]
  │   │   PC → mtvec + 11×4                                    [Cycle T+1]
  │   │   shadow_save → Bank[1] (保存 ISR_Timer 的现场)         [Cycle T+1↑, 1 cycle]
  │   │   第一条 ISR_GPIO 指令进入 EX                            [Cycle T+2]
  │   │
  │   │   ISR_GPIO 执行中... (bank_ptr=2)
  │   │   │
  │   │   │   ... 紧急处理 ...
  │   │   │
  │   │   MRET 执行 (bank_ptr=2, 无 pending)  ────────────────
  │   │   shadow_restore from Bank[1] (恢复 ISR_Timer 现场)     [1 cycle]
  │   │   bank_ptr: 2→1
  │   │   current_priority: 11→7
  │   │
  │   继续 ISR_Timer... (bank_ptr=1)
  │   │
  │   MRET 执行 (bank_ptr=1, 无 pending)  ────────────────────
  │   shadow_restore from Bank[0] (恢复主程序现场)               [1 cycle]
  │   bank_ptr: 1→0
  │   current_priority: 7→0
  │
主程序继续 (bank_ptr=0)
```

### 4.2 Tail-Chaining 示例

```
ISR_Timer 执行完毕, 即将 MRET (bank_ptr=1)
  同时 GPIO IRQ (优先级更高) 已经 pending
  │
  MRET 在 EX 阶段
  bank_controller 检测: TAIL_CHAIN_EN && mret_in_ex && intr_pending → tail_chain_detect=1
  │
  ├─ 正常路径: restore Bank[0] → bank_ptr=0 → 中断延迟 2cyc → save Bank[0]
  │   (restore 1 + 中断延迟 2 = 总共 3 周期到新 ISR)
  │
  └─ Tail-Chaining: 跳过 restore → bank_ptr 保持 1 → 直接跳转 ISR_GPIO
      (2 周期延迟到新 ISR, 节省 1 周期 restore)
```

---

## 5. 软硬件接口

### 5.1 新增 CSR 寄存器

| CSR 地址 | 名称 | 位宽 | 描述 |
|----------|------|------|------|
| 0xBC0 | `mneststatus` | 32 | [3:0]=bank_ptr (RO), [7:4]=max_bank (RO), [8]=overflow (W1C), [9]=tail_chain_en (RW) |
| 0xBC1 | `mprio` | 32 | [1:0]=current_priority (RO), [7:4]=threshold (RW) |

### 5.2 参数配置表

| Parameter | 默认 | 范围 | 描述 |
|-----------|------|------|------|
| `SHADOW_EN` | 1 | 0/1 | 影子寄存器总使能 |
| `SHADOW_BANKS` | 4 | 1–16 | 影子 Bank 数量 |
| `OVERFLOW_POLICY` | 0 | 0/1 | Bank 溢出策略: 0=硬限制(阻塞), 1=降级复用(覆盖) |
| `TAIL_CHAIN_EN` | 0 | 0/1 | Tail-chaining 优化使能 (默认关闭，需进一步验证) |

`SHADOW_EN=0` 时整个多 Bank 逻辑被综合工具优化掉，恢复为基线 24.9 kGE。

### 5.3 软件使用示例

```c
// ISR 代码 —— 和单级影子寄存器完全一样，嵌套对软件透明
void timer_isr() __attribute__((interrupt("machine"))) {
    // 不需要 push/pop
    // 硬件已自动将上下文保存到正确的 Bank
    timer_clear_irq();
    do_work();
    // MRET 时硬件自动从正确的 Bank 恢复
}

void gpio_isr() __attribute__((interrupt("machine"))) {
    // 可以抢占 timer_isr，硬件自动分配新 Bank
    gpio_clear_irq();
    emergency_stop();
    // MRET 自动恢复 timer_isr 的上下文
}

int main() {
    // 设置中断优先级（由 software 配置）
    // 优先级 11 > 7，GPIO 可以抢占 Timer
    // 无需其他任何配置
    while (1) { wfi(); }
}
```

---

## 6. 面积与时序估算

### 6.1 面积分解

每 Bank 的硬件开销（参考 TVLSI 论文的 7.46 kGE for 31×32bit）：

| 组件 | 面积 (kGE) | 说明 |
|------|-----------|------|
| 31×32bit DFF 阵列 | ~4.0 | 31 × 32 = 992 个 DFF |
| 读 MUX (N:1) | ~1.0 | N 个 Bank 的读选择 |
| 写控制逻辑 | ~0.8 | Bank 地址解码 + 写使能生成 |
| **1 Bank 合计** | **~5.8** | 论文中含控制逻辑总计 7.46，此处拆分细化 |
| Bank 控制器 | ~2.0 | bank_ptr 状态机 + 抢占比较 + tail-chain |
| 优先级跟踪 | ~0.5 | current_priority + 比较器 |

**总核心面积估算（@55nm，含多 Bank）：**

| 配置 | 额外面积 | 总核心面积 | 相对基线增幅 |
|------|---------|-----------|-------------|
| 基线 (SHADOW_EN=0) | 0 | 24.9 kGE | — |
| N=1（当前） | +7.46 | 32.4 kGE | +30% |
| N=2（本方案默认） | +7.46+2.0+0.5 ≈ +10.0 | 34.9 kGE | +40% |
| N=4 | +5.8×4+2.0+0.5 ≈ +25.7 | 50.6 kGE | +103% |
| N=8 | +5.8×8+2.0+0.5 ≈ +48.9 | 73.8 kGE | +196% |

> 注：以上为估算，准确数据需 DC 综合确认。N=4 时约 50 kGE 仍在嵌入式可接受范围内（对比 OpenE902 的 74.9 kGE）。

### 6.2 关键路径分析

新增逻辑的关键路径检查：

| 路径 | 组合逻辑 | 是否在关键路径上 |
|------|---------|----------------|
| priority_compare: new_prio > current_prio | 4-bit 比较器 | **否**（与 ALU 无关，只是新增的并行路径） |
| bank_ptr MUX: 读数据 N→1 选择 | 16:1 MUX (N=4) | **否**（regfile 读已在 ID 阶段，不跨阶段） |
| bank_full 检测 | bank_ptr == SHADOW_BANKS 比较 | **否** |
| tail_chain_detect | TAIL_CHAIN_EN && mret && pending (AND) | **否** |
| allow_nesting | preemption && (!full \|\| degradation_reuse) && !tail_chain (组合) | **否** |

**结论：新增逻辑不在 CPU 核心的时序关键路径上，不影响 200 MHz 目标频率。**

---

## 7. 会议论文规划

### 7.1 论文大纲

**标题：** *"Enabling Priority-Based Interrupt Nesting with Multi-Bank Shadow Registers for Deterministic RISC-V Processors"*

**建议会议：** RTAS / DATE / CASES / ICCAD

| Section | 页数 | 内容 |
|---------|------|------|
| Abstract | 0.25 | 嵌套中断对实时系统的必要性；多 Bank 影子寄存器方案；2 周期延迟不变量；对比已有方案 |
| I. Introduction | 1.0 | 硬实时系统嵌套需求；现有方案局限；本方案贡献（多 Bank + 抢占 + tail-chain + 软件透明） |
| II. Background & Motivation | 0.75 | RISC-V 中断架构；单级影子寄存器原理；嵌套的必要性场景分析 |
| III. Multi-Bank Shadow Register Architecture | 1.5 | Bank 阵列结构；Bank 控制器状态机；抢占判定电路；Tail-chaining 优化；溢出降级策略 |
| IV. Implementation | 0.75 | Verilog 实现细节；参数配置；与中断流水线的集成；软件接口 |
| V. Evaluation | 1.5 | 嵌套延迟测量 (1/2/3 级)；Tail-chaining 收益；面积随 Bank 数 scaling；确定性验证；与 CLIC/ARM NVIC/CV32E40P 比较 |
| VI. Related Work | 0.25 | CLIC 硬件堆栈、Sophon snapreg、ARM Cortex-M NVIC、FlexPRET |
| VII. Conclusion | 0.25 | 总结 |
| **合计** | **~6.25** | |

### 7.2 实验矩阵

| 实验 | 测量指标 | 对比对象 |
|------|---------|---------|
| 嵌套中断延迟 | 1/2/3 级嵌套各需要多少周期 | FX-RV32 (base, 软件嵌套) vs FX-RV32-Nested (N=4) vs OpenE902 (CLIC) vs CV32E40P |
| Tail-chaining 收益 | tail-chain 启用/禁用时连续中断的总延迟 | FX-RV32-Nested (TC on vs off) vs ARM Cortex-M tail-chain |
| Bank 数量面积 scaling | N=1/2/4/8 的面积和频率 | DC 综合结果柱状图 |
| 嵌套确定性 | 嵌套场景 40 轮 cycle 计数 | 所有 40 轮的直方图 |
| 抢占延迟 | 高优先级到达 → 抢占完成 → 新 ISR 第一条指令 | 本方案 vs software nesting |
| Bank 溢出行为 | 溢出时阻塞/降级的波形 | — |

### 7.3 与 TVLSI 论文的差异化

| 维度 | TVLSI 论文 | 本会议论文 |
|------|-----------|-----------|
| 贡献 | 单级影子寄存器 + 无条件 2 周期中断 | 多 Bank + 嵌套 + 抢占 + 无条件 2 周期 + 尾链 |
| 中断接受 | 无条件（不等待 EX/MEM） | 无条件（不变） |
| 中断模型 | 平级（不支持嵌套） | 优先级嵌套（支持抢占） |
| Bank 数量 | 固定 1 | 可配置 N（默认 4） |
| 实验重点 | 中断延迟绝对值 | 嵌套延迟 scaling + 抢占延迟 + tail-chain 收益 |
| 对比对象 | Sophon/OpenE902/CV32E40P/PicoRV32 | 同左 + 增加嵌套场景对比 + ARM NVIC 的 tail-chain |

**不重叠**——两篇论文解决的是不同层次的问题：
- TVLSI: "最低延迟是多少"（2 周期）
- 会议: "最低延迟如何在嵌套场景下保持不变"（还是 2 周期）

---

## 8. 专利撰写规划

### 8.1 专利名称

《一种支持优先级中断嵌套的多 Bank 影子寄存器上下文保存与恢复装置及方法》

### 8.2 权利要求树

```
独立权利要求 1：多 Bank 影子寄存器上下文保存/恢复装置
  从属 1.1: Bank 数量可配置（parameter SHADOW_BANKS）
  从属 1.2: 每 Bank 保存的寄存器数量可配置
  从属 1.3: Bank 指针硬件自动管理（中断接受时递增，MRET 时递减）
  从属 1.4: 与标准 RISC-V mtvec 向量模式兼容
  从属 1.5: SHADOW_EN=0 时自动综合优化掉（零额外面积）

独立权利要求 2：优先级抢占硬件判定电路
  从属 2.1: current_priority 寄存器硬件自动更新
  从属 2.2: 组合逻辑优先级比较（0 额外延迟）
  从属 2.3: 抢占判定与 Bank 指针的协同工作流（抢占→bank_ptr++, 不抢占→保持）
  从属 2.4: 优先级可编程（软件通过 CSR 配置）

独立权利要求 3：Tail-Chaining 优化方法
  从属 3.1: MRET 阶段检测 pending 中断的硬件电路
  从属 3.2: 跳过冗余 shadow_restore 的控制逻辑
  从属 3.3: Bank 指针在 tail-chain 期间保持不变的机制
  从属 3.4: Tail-chaining 使能/禁用开关（CSR 控制）

独立权利要求 4：Bank 溢出处理装置
  从属 4.1: 硬限制策略（阻塞新中断 + 置位溢出异常标志，OVERFLOW_POLICY=0）
  从属 4.2: 降级复用策略（bank_ptr 保持 N，覆盖 Bank[N-1]，OVERFLOW_POLICY=1）
  从属 4.3: 策略通过 Verilog 参数在综合时静态配置，不增加运行时面积开销
```

### 8.3 核心实施例

实施例 1：N=4 的三级嵌套中断处理器
实施例 2：Tail-Chaining 加速的连续中断处理器
实施例 3：Bank 溢出硬限制的安全关键处理器

---

## 9. 实施计划

| 阶段 | 工作 | 涉及文件 | 预估工时 |
|------|------|---------|---------|
| **P1** | 新建 `bank_controller.v` | `core/interrupt/bank_controller.v` | 4h |
| **P2** | 修改 `regfile.v` 支持多 Bank | `core/id/regfile.v` | 4h |
| **P3** | 修改 `interrupt_pipeline.v` 集成 bank_controller | `core/interrupt/interrupt_pipeline.v` | 4h |
| **P4** | 修改 `interrupt_controller.v` 增加优先级抢占 | `core/interrupt/interrupt_controller.v` | 3h |
| **P5** | 修改 `csr_regfile.v` 增加 mneststatus/mprio | `core/csr/csr_regfile.v` | 2h |
| **P6** | 更新 `core_top.v` 实例化 bank_controller | `core/core_top.v` | 1h |
| **P7** | 更新 `id_top.v` 传递 Bank 控制信号 | `core/id/id_top.v` | 1h |
| **P8** | 编写 UVM 嵌套测试程序 | `uvm/nested_intr_test.s` | 4h |
| **P8** | UVM 仿真 + 波形验证 | — | 6h |
| **P9** | DC 综合（面积/时序数据） | `syn/` | 4h |
| **P10** | FPGA 验证 | — | 4h |
| **P11** | 专利撰写 | — | 16h |
| **P12** | 会议论文撰写 | — | 24h |
| **总计** | | | **约 76 小时** |

---

## 10. 风险与对策

| 风险 | 影响 | 对策 |
|------|------|------|
| N=4 时面积超预期 (>60 kGE) | 竞争力下降 | 降低默认 N=2；允许只保存 x1-x15（caller-saved）以减少每 Bank 面积 |
| 多 Bank MUX 引入时序违例 | 降频 | 在 regfile 读路径增加一级流水；200MHz 裕量足够，风险低 |
| Tail-chaining 引入 corner case bug | 功能正确性 | UVM 全覆盖验证（连续中断、嵌套+tail-chain 组合）；TAIL_CHAIN_EN 默认关闭 |
| 降级复用丢失上下文 | 嵌套链断裂 | OVERFLOW_POLICY=1 仅用于安全关键紧急停机场景；默认 OVERFLOW_POLICY=0 确保上下文完整性 |
| 与 CLIC 方案比较缺乏说服力 | 论文被拒 | 重点强调 "确定性" 而非单纯 "更少周期"；许多方案不提供确定性 |

---

> **作者：** Yi Fengxin, Beihang University
>
> **日期：** 2026-06-30
>
> **状态：** 方案设计完成，RTL 实施完成（含 OVERFLOW_POLICY），Modelsim 仿真验证通过
