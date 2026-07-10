# NewWork 文档索引

本目录包含 FX-RV32 项目的新增工作文档。以下按文档类型进行分类索引。

---

## 中断与影子寄存器

| 文档 | 内容 |
|------|------|
| **[multi_bank_shadow_nested_interrupt_plan.md](multi_bank_shadow_nested_interrupt_plan.md)** | 多级影子寄存器嵌套中断方案设计。详细描述 Bank 分配/释放机制、优先级抢占逻辑、尾链优化、Bank 溢出处理（含 OVERFLOW_POLICY 硬限制/降级复用双策略）。 |
| **[nested_intr_debug_progress.md](nested_intr_debug_progress.md)** | 嵌套中断测试调试进展。记录 5 个硬件 Bug 的发现与修复过程：(1) B-type 立即数 bit 排列错误；(2) intr_flush_id 误改→已回滚；(3) BRAM 延迟 flush 扩展；(4) ROM 模式 2 周期 flush 误杀 ISR 首指令；(5) interrupt_taken PC 递增丢失 handler。含仿真证据和最终验证结果。 |
| **[nested_intr_test_guide.md](nested_intr_test_guide.md)** | ⭐ **嵌套中断测试完整指南**。包含：测试程序逻辑、中断延迟分析（2 周期保持不变）、ModelSim 命令行/GUI 波形操作步骤、关键信号说明、自定义测试方法、常见问题排查。 |

---

## 专利

| 文档 | 内容 |
|------|------|
| **[patent_multi_bank_shadow.md](patent_multi_bank_shadow.md)** | 专利交底书：《一种支持优先级中断嵌套的多级影子寄存器上下文保存与恢复装置及方法》。含 9 章节：发明背景、现有技术对比、技术方案、时序图、尾链优化、系统架构、有益效果、发散思维、参考文献。 |
| **[patent_figures_mermaid.md](patent_figures_mermaid.md)** | 专利 Mermaid 图代码。可复制到 Mermaid Live Editor 实时预览并导出 SVG/PNG。包含图 0-7 的 Mermaid 源码（含图 6 Bank 溢出处理决策流程）。 |
| **[fig3_wavedrom.json](fig3_wavedrom.json)** | 专利图 3（两级中断嵌套 Bank 指针变化时序图）的 Wavedrom JSON 源码。 |

---

## 论文

| 文档 | 内容 |
|------|------|
| **[rtas_paper_draft.md](rtas_paper_draft.md)** | RTAS 论文初稿。关于多级影子寄存器嵌套中断的学术论文。 |

---

## 实施与测试

| 文档 | 内容 |
|------|------|
| **[implementation_guide.md](implementation_guide.md)** | 多级影子寄存器实现指南。详细的 RTL 修改步骤、信号连接、参数配置说明。 |
| **[simulation_test_report.md](simulation_test_report.md)** | 仿真测试报告。含回归测试结果、Bank 溢出策略验证、已验证硬件通路、Bug 修复记录（含本次新增 3 个 Bug）。 |

---

## 快速导航

### 我想了解...

| 需求 | 推荐文档 |
|------|---------|
| 如何运行嵌套中断仿真测试 | [nested_intr_test_guide.md](nested_intr_test_guide.md) |
| 怎么看 ModelSim 波形调试中断 | [nested_intr_test_guide.md](nested_intr_test_guide.md) §6 |
| 嵌套中断发现了哪些硬件 Bug | [nested_intr_debug_progress.md](nested_intr_debug_progress.md) |
| 中断延迟是多少，有没有变化 | [nested_intr_test_guide.md](nested_intr_test_guide.md) §2 |
| 专利交底书写了什么 | [patent_multi_bank_shadow.md](patent_multi_bank_shadow.md) |
| 多级影子寄存器方案怎么设计的 | [multi_bank_shadow_nested_interrupt_plan.md](multi_bank_shadow_nested_interrupt_plan.md) |
| RTL 具体怎么改的 | [implementation_guide.md](implementation_guide.md) |
| 论文写了什么 | [rtas_paper_draft.md](rtas_paper_draft.md) |

---

## 关键硬件 Bug 速查

在调试过程中发现并修复了 5 个根因级硬件 Bug：

| # | Bug | 文件 | 表现 | 文档 |
|---|-----|------|------|------|
| 1 | B-type 立即数 bit 排列错误 | `core/id/imm_gen.v` | 非零偏移分支跳错地址 | [§Bug1](nested_intr_debug_progress.md) |
| 2 | ⚠ intr_flush_id 误改→已回滚 | `core/hazard/hazard_unit.v` | ROM 模式 ISR 无法执行 | [§Bug2](nested_intr_debug_progress.md) |
| 3 | BRAM 同步读延迟未覆盖 | `core/hazard/hazard_unit.v` | 分支后第 2 条错指令逃脱 | [§Bug3](nested_intr_debug_progress.md) |
| **4** | **ROM 模式无条件 2 周期 flush** | **`core/hazard/hazard_unit.v`** | **ISR 首指令被杀, store 用错值** | [**§Bug4**](nested_intr_debug_progress.md) |
| **5** | **interrupt_taken 周期 PC 递增** | **`core/ifu/ifu_top.v`** | **handler 指令被旧程序 flush 杀** | [**§Bug5**](nested_intr_debug_progress.md) |

---

*最后更新: 2026-06-30*
