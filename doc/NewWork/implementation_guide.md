# FX-RV32 多Bank影子寄存器嵌套中断 — 实施指南

> 版本: v1.3
> 日期: 2026-06-30
> 基线: 专利一基础方案（有条件中断接受 + 单组影子寄存器）

---

## 1. 架构概述

本发明在专利一基础方案之上实现以下改进。其中，无条件两周期中断延迟已在 FX-RV32 论文处理器中实现；本实施指南以 FX-RV32 为起点，重点描述**多 Bank 影子寄存器阵列**的增量改动。

### 1.0 专利一 → FX-RV32 → 本发明的演进路径

| 阶段 | 中断接受 | 影子寄存器 | 嵌套 | 延迟 |
|------|---------|-----------|------|------|
| 专利一基础方案 | 有条件（等 EX 分支/跳转 + MEM load） | 单组 | 不支持 | 可变（2/3/3+N/4+N 周期） |
| FX-RV32 论文处理器 | **无条件**（intr_take_now 组合逻辑立即重定向） | 单组 | 不支持 | **恒定 2 周期** |
| **本发明（专利二）** | 无条件（同 FX-RV32） | **N 组（默认 4）** | **支持（优先级抢占）** | **恒定 2 周期（与嵌套深度无关）** |

### 1.1 本发明的核心增量：多 Bank 影子寄存器阵列

将单组影子寄存器扩展为 N 组（默认 N=4），配合硬件 Bank 控制器和优先级抢占机制，支持多级中断嵌套。每级嵌套的上下文保存仍为 1 个时钟周期（全并行锁存），中断进入延迟不受嵌套深度影响。

### 1.1 新增/修改文件

| 文件 | 状态 | 说明 |
|------|------|------|
| `core/interrupt/bank_controller.v` | **新增** | 多Bank硬件管理器: Bank分配/释放、优先级抢占、Tail-Chaining、溢出处理 (含 OVERFLOW_POLICY 降级复用) |
| `core/id/regfile.v` | 修改 | 影子寄存器从1组扩展为N组 (`SHADOW_BANKS`参数) |
| `core/id/id_top.v` | 修改 | 新增 `bank_ptr_i`、`SHADOW_BANKS` 参数传递 |
| `core/interrupt/interrupt_pipeline.v` | 修改 | 影子寄存器控制集成 bank_controller 决策；bank_ptr 寄存器管理（中断进入时递增、MRET 时递减）；`shadow_save`/`shadow_restore` 在同一 `always` 块生成；首次中断保存主程序上下文至 Bank[0]；降级复用模式下 bank_ptr 保持 N；新增 `interrupt_accepted_o`/`interrupt_processing_o`/`bank_ptr_o` 输出 |
| `core/interrupt/interrupt_controller.v` | 修改 | 新增 `current_priority_o`/`new_priority_o` 优先级输出 |
| `core/core_top.v` | 修改 | 实例化 `bank_controller`; 新增Bank控制信号连接; **传递 `SYNC_INST_MEM` 到 `hazard_unit`** |
| `core/hazard/hazard_unit.v` | 修改 | **新增 `SYNC_INST_MEM` 参数: ROM模式1周期flush, BRAM模式2周期flush+PC stall (Bug #4)** |
| `core/ifu/ifu_top.v` | 修改 | **`interrupt_taken_i` 周期 PC hold 而非递增, 防止 handler 指令被旧程序 flush 杀死 (Bug #5)** |
| `core/interrupt/interrupt_pipeline.v` | 修改 | `bank_ptr_o` 改为 `output wire` (assign驱动, 编译错误修复) |

### 1.2 测试/脚本文件

| 文件 | 说明 |
|------|------|
| `tb/tb_nested_intr.v` | 嵌套中断验证testbench (Modelsim, 非UVM) |
| `sim/nested_intr_test.s` | 嵌套中断汇编测试程序 |
| `sim/nested_intr_test.hex` | 汇编后的hex程序 (193 words) |
| `sim/overflow_test.s` | **新增**: Bank溢出测试 (SHADOW_BANKS=1硬限制验证) |
| `sim/overflow_minimal.s` | **新增**: 最小溢出验证 (仅Timer ISR, SHADOW_BANKS=1) |
| `sim/ultra_min_test.s` | **新增**: 最小ISR测试 (addi+sw, Bug #4根因验证) |
| `sim/run_batch.do` | **新增**: 命令行批量回归测试脚本 |
| `sim/run_gui.do` | **新增**: GUI波形验证脚本 (论文截图用) |
| `sim/run_nested.do` | Modelsim一键仿真TCL脚本 |

---

## 2. 参数配置

### 2.1 SHADOW_BANKS (核心参数)

| 文件 | 行 | 默认值 | 说明 |
|------|-----|--------|------|
| `core/core_top.v` | `id_top #(.SHADOW_BANKS(4))` | 4 | ID阶段Bank数 |
| `core/core_top.v` | `bank_controller #(.SHADOW_BANKS(4))` | 4 | Bank控制器Bank数 |
| `core/id/regfile.v` | `parameter SHADOW_BANKS = 4` | 4 | 影子寄存器Bank阵列维度 |

**三个位置必须一致。** N=4 支持最多3级嵌套 (1级主中断 + 2级抢占)。

### 2.2 bank_controller 子参数

| 参数 | 默认 | 说明 |
|------|------|------|
| `SHADOW_BANKS` | 4 | Bank数量 |
| `TAIL_CHAIN_EN` | 1 | Tail-Chaining使能 (1=开启) |
| `OVERFLOW_POLICY` | 0 | 溢出策略: 0=硬限制(阻塞, 默认), 1=降级复用(Bank满时覆盖最深嵌套层) |

---

## 3. 硬件架构

### 3.1 Bank指针生命周期

```
bank_ptr = 0  ─────── 主程序 (无中断)
   │ interrupt_accepted && preemption_allowed
   ▼
bank_ptr = 1  ─────── 第1级ISR
   │ higher_priority_interrupt → preemption
   ▼
bank_ptr = 2  ─────── 第2级ISR (嵌套)
   │ MRET (无pending)
   ▼
bank_ptr = 1  ─────── 返回第1级ISR
   │ MRET
   ▼
bank_ptr = 0  ─────── 返回主程序
```

### 3.2 优先级编码

| 中断源 | ID | 优先级值 | 说明 |
|--------|-----|---------|------|
| MEI (外部) | 11 | 11 | 最高，GPIO/SPI/I2C 共用此 ID |
| MTI (定时器) | 7 | 7 | |
| MSI (软件) | 3 | 3 | 最低 |

### 3.3 模块连接图（实际实施版本）

```
interrupt_controller
  ├── intr_pending_o ──────────→ interrupt_pipeline
  ├── intr_cause_o ────────────→ interrupt_pipeline
  ├── intr_handler_addr_o ─────→ ifu_top
  ├── current_priority_o ──────→ bank_controller (优先级跟踪)
  └── new_priority_o ──────────→ bank_controller (优先级跟踪)

bank_controller — 纯组合逻辑决策
  ├── allow_nesting_o ─────────→ interrupt_pipeline (抢占 && (未满 || 降级复用))
  ├── bank_full_o ─────────────→ interrupt_pipeline
  ├── tail_chain_detect_o ─────→ interrupt_pipeline (MRET+pending)
  └── degradation_reuse_o ─────→ interrupt_pipeline (Bank满但允许嵌套)

interrupt_pipeline — 时序控制 + Bank指针管理
  ├── shadow_save_o ───────────→ id_top → regfile
  ├── shadow_restore_o ────────→ id_top → regfile
  ├── bank_ptr_o ──────────────→ id_top → regfile
  ├── interrupt_accepted_o ────→ bank_controller (通知)
  └── interrupt_processing_o ──→ bank_controller (状态)

regfile — 含 N 组影子 Bank
  ├── bank_ptr_i ────────────── 选择当前Bank
  ├── shadow_save_i ─────────── 保存到 Bank[bank_ptr-1]
  └── shadow_restore_i ──────── 从 Bank[bank_ptr] 恢复
```

**关键设计决策（与方案文档的差异）**：
- `bank_controller` 为**纯组合逻辑**——所有时序关键信号（bank_ptr、shadow_save、shadow_restore）由 `interrupt_pipeline` 在同一 `always` 块内管理，消除跨模块时序竞争
- `shadow_save` 和 `bank_ptr` 递增在同一时钟沿触发，保证影子保存使用正确的 Bank 索引（bank_ptr_i - 1）
- `shadow_restore` 使用时 `bank_ptr` 已先递减，因此 regfile 中恢复索引为 `bank_ptr_i`（非 `bank_ptr_i - 1`）
- `TAIL_CHAIN_EN` 默认值为 `0`（关闭），因为 Tail-Chaining 的上下文复用语义需进一步验证
- `OVERFLOW_POLICY` 默认值为 `0`（硬限制），Bank 满时阻塞新中断；设为 `1`（降级复用）时允许嵌套，bank_ptr 保持 N 不变，覆盖 Bank[N-1]
- `degradation_reuse` 信号为组合逻辑：`OVERFLOW_POLICY==1 && bank_full && preemption_allowed`

---

## 4. 实施文件清单

### 新增文件

| 文件 | 行数(约) | 说明 |
|------|---------|------|
| `core/interrupt/bank_controller.v` | 77 | 多 Bank 纯组合逻辑决策单元 |
| `tb/tb_nested_intr.v` | 285 | 嵌套中断 Modelsim testbench |

### 修改的 RTL 文件

| 文件 | 修改内容 |
|------|---------|
| `core/id/regfile.v` | 影子寄存器 1组→N组二维阵列；新增 `SHADOW_BANKS` 参数和 `bank_ptr_i` 端口；恢复索引改为 `shadow[bank_ptr_i]` |
| `core/id/id_top.v` | 新增 `SHADOW_BANKS` 参数和 `bank_ptr_i` 端口透传 |
| `core/interrupt/interrupt_pipeline.v` | 新增 bank_ptr 寄存器管理；shadow_save/restore 由 bank_controller 决策输入触发；新增 `allow_nesting_i`/`bank_full_i`/`tail_chain_detect_i` 输入；新增 `bank_ptr_o`/`interrupt_accepted_o`/`interrupt_processing_o` 输出 |
| `core/interrupt/interrupt_controller.v` | 新增 `current_priority_o`/`new_priority_o` 优先级编码输出 |
| `core/csr/csr_regfile.v` | MISA MXL 修正；中断 CSR 写入优先级保护 |
| `core/core_top.v` | 实例化 bank_controller；新增 `OVERFLOW_POLICY` 参数（默认 0）；连接 allow_nesting/bank_full/tail_chain_detect/degradation_reuse/interrupt_processing_pipe 等内部连线；更新 interrupt_pipeline/id_top 端口连接 |

### 测试/脚本文件

| 文件 | 说明 |
|------|------|
| `sim/nested_intr_test.s` | 嵌套中断汇编测试程序 (Timer→GPIO 抢占) |
| `sim/nested_intr_test.hex` | 汇编后 hex 文件 (193 words) |
| `sim/run_nested.do` | Modelsim 一键仿真 TCL 脚本 |

### 文档文件

| 文件 | 说明 |
|------|------|
| `doc/NewWork/multi_bank_shadow_nested_interrupt_plan.md` | 完整技术方案（含文件清单） |
| `doc/NewWork/implementation_guide.md` | 本文件——实施指南 |
| `doc/NewWork/patent_multi_bank_shadow.md` | 专利文档（含 6 张图） |
| `doc/NewWork/patent_figures_mermaid.md` | 6 张图的 Mermaid 源码 |
| `doc/code_review_report.md` | 全代码审查报告及修复记录 |

---

## 5. Modelsim仿真

### 5.1 前置条件

- Modelsim/Questa 已安装且在PATH中
- 测试程序已汇编: `sim/nested_intr_test.hex`

### 5.2 运行仿真

```bash
# GUI模式 (推荐, 可看波形)
cd sim
vsim -do run_nested.do

# 命令行模式
cd sim
vsim -c -do run_nested.do
```

### 5.3 关键波形信号

| 信号 | 说明 |
|------|------|
| `u_core_top/bank_ptr` | 当前Bank指针 (0=主程序, ≥1=嵌套层级) |
| `u_core_top/shadow_save` | 单周期脉冲: 上下文保存到当前Bank |
| `u_core_top/shadow_restore` | 单周期脉冲: 从当前Bank恢复上下文 |
| `u_core_top/intr_take_now` | 组合逻辑: PC即将跳转到handler |
| `u_core_top/interrupt_taken_pipe` | 寄存器: 中断已接受 |
| `u_core_top/intr_pending` | 组合逻辑: 有中断等待 |

### 5.4 预期波形行为

```
Cycle T:   中断请求到达, intr_take_now=1 → next_pc=handler (组合逻辑)
           PC 仍为旧值 (主程序), 当前指令继续执行
Cycle T+1: PC←handler 地址, interrupt_taken_o=1, shadow_save=1, bank_ptr++
Cycle T+2: 第一条ISR指令进入ID → EX
           (如果是抢占: bank_ptr=2, shadow_save=1 → Bank[1])
...
MRET:     shadow_restore=1 → 从Bank恢复, bank_ptr--
           (如果是尾链: bank_ptr不变, 跳过restore+save)
```

### 5.5 测试结果判定

- `tohost` (地址 0xFC) = 0 → **PASS**
- `tohost` = 1 → FAIL (测试超时)
- `tohost` = 2 → Timer ISR 上下文被破坏
- `tohost` = 3 → GPIO ISR 上下文错误

---

## 6. 软件模型

### 6.1 编程模型

多Bank影子寄存器对软件**完全透明**。ISR不需要任何 push/pop 操作:

```c
// Timer ISR (低优先级)
void __attribute__((interrupt("machine"))) timer_isr() {
    // 无需保存寄存器 — 硬件自动保存到Bank
    do_timer_work();
    // 无需恢复寄存器 — MRET自动从Bank恢复
}

// GPIO ISR (高优先级, 可抢占Timer ISR)
void __attribute__((interrupt("machine"))) gpio_isr() {
    // 无需保存寄存器 — 硬件自动保存到新Bank
    emergency_handler();
    // MRET自动恢复Timer ISR的上下文
}
```

### 6.2 限制

1. **最大嵌套深度**: SHADOW_BANKS - 1 (默认3级)
2. **不支持中断嵌套内再触发同级中断**: 只有更高优先级才能抢占
3. **Bank溢出行为**: 默认硬限制 (阻塞新中断 + 置overflow标志)
4. **单组影子寄存器不保留中断嵌套历史**: 每级ISR独立使用自己的Bank

---

## 7. 面积估算

| 配置 | 影子寄存器面积 | 核心总面积 (估算) | 相对基线增幅 |
|------|---------------|-------------------|-------------|
| SHADOW_EN=0 (基线) | 0 | 24.9 kGE | — |
| SHADOW_EN=1, BANKS=1 (原版) | +7.46 | 32.4 kGE | +30% |
| SHADOW_EN=1, BANKS=2 | +15.0 | 39.9 kGE | +60% |
| **SHADOW_EN=1, BANKS=4** (默认) | **+30.0** | **54.9 kGE** | **+120%** |
| SHADOW_EN=1, BANKS=8 | +60.0 | 84.9 kGE | +241% |

> 注: 面积为55nm工艺估算值，准确数据需DC综合确认。

---

## 8. 与 TVLSI 论文的关系

本发明的多 Bank 影子寄存器方案是 FX-RV32 TVLSI 论文的下一代扩展：

| 维度 | 专利一基础方案 | FX-RV32 论文 | **本发明（专利二）** |
|------|--------------|-------------|-------------------|
| 中断接受 | 有条件 | **无条件** | 无条件 |
| 中断延迟 | 可变 | **恒定 2 周期** | 恒定 2 周期 |
| 上下文保存 | 1 周期（单组） | 1 周期（单组） | **1 周期/级（多 Bank）** |
| 中断模型 | 平级 | 平级 | **优先级嵌套** |
| 抢占支持 | 不支持 | 不支持 | **支持（硬件自动）** |
| Bank 数量 | 1 | 1 | **N（可配置，默认 4）** |
| Tail-Chaining | 无 | 无 | **支持（省 1 周期 restore）** |
| ISA 扩展 | 不需要 | 不需要 | 不需要 |

---

## 9. 文件索引

### RTL 源码（修改/新增）

| 文件 | 说明 |
|------|------|
| `core/interrupt/bank_controller.v` | **新增** — 多Bank纯组合逻辑决策单元 |
| `core/id/regfile.v` | **修改** — 多Bank影子寄存器二维阵列 |
| `core/id/id_top.v` | **修改** — 新增 bank_ptr/SHADOW_BANKS |
| `core/interrupt/interrupt_pipeline.v` | **修改** — bank_ptr管理 + Bank控制集成 + 降级复用处理 |
| `core/interrupt/interrupt_controller.v` | **修改** — 优先级编码输出 |
| `core/csr/csr_regfile.v` | **修改** — MISA修正 + 写入优先级保护 |
| `core/core_top.v` | **修改** — bank_controller实例化 |

### 测试与脚本

| 文件 | 说明 |
|------|------|
| `tb/tb_nested_intr.v` | **新增** — Modelsim嵌套中断testbench |
| `sim/nested_intr_test.s` | **新增** — 嵌套中断汇编测试程序 |
| `sim/nested_intr_test.hex` | **新增** — 汇编后hex (193 words) |
| `sim/run_nested.do` | **新增** — Modelsim一键仿真TCL脚本 |

### 文档

| 文件 | 说明 |
|------|------|
| `doc/NewWork/multi_bank_shadow_nested_interrupt_plan.md` | 完整技术方案 (含文件清单) |
| `doc/NewWork/implementation_guide.md` | 本文件 — 实施指南 |
| `doc/NewWork/patent_multi_bank_shadow.md` | 专利文档 (含6张ASCII图) |
| `doc/NewWork/patent_figures_mermaid.md` | 6张图的Mermaid源码 |
| `doc/code_review_report.md` | 全代码审查报告 (2026-06-22)
