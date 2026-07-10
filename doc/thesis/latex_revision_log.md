# FX-RV32 英文 LaTeX 论文修改记录

> 文件: `bare_jrnl_new_sample4.tex` | 格式: IEEE TVLSI | 日期: 2026-06-12

---

## 一、中文版 FX-RV32.md → 英文版 LaTeX 同步修复 (3项)

这三项在中英文版中均存在同样的硬件事实错误。

### 1. IF阶段"负边沿触发寄存器" (L138)

**原文:**
> "To balance combinatorial logic depth and achieve a target frequency of 200 MHz, we use **negative edge-triggered registers** in the IF stage to separate fetch and data preparation, shortening the critical path."

**修改后:**
> "All pipeline registers are positive edge-triggered; no negative-edge clocking or gated clocks are employed in the design."

**原因:** 实际 RTL (`ifu_top.v`, `if_id_reg.v`) 中所有流水线寄存器均为 `posedge clk_i` 触发，不存在任何负边沿设计。

---

### 2. ID阶段"低电平半周期" (L165)

**原文:**
> "The ID stage performs combinatorial decoding **during the low-level half cycle**."

**修改后:**
> "The ID stage is purely combinatorial."

**原因:** ID 阶段是纯组合逻辑译码，不存在"半周期"操作。中文版已同步修正。

---

### 3. 中断冲刷 IF/ID 寄存器 (L263)

**原文:**
> "asserts intr_flush_if/id/ex/mem/wb, inserting NOPs into **all five** pipeline stages"

**修改后:**
> "asserts intr_flush_if (used to stall the IF stage) and intr_flush_ex/mem/wb to flush ID/EX, EX/MEM, and MEM/WB. Crucially, intr_flush_id is **not** asserted — the PC has already been redirected to the interrupt vector address by intr_take_now in the same cycle, and the instruction ROM outputs the first ISR instruction, which passes through IF/ID normally."

**原因:** RTL `hazard_unit.v:110` — `assign intr_flush_id_o = 1'b0;`。中断时 IF/ID 不冲刷，ISR 第一条指令直接通过，避免无谓 NOP 延迟。旧程序残留由 ID/EX 的 `intr_flush_ex` 杀死。

> **⚠ 2026-06-27 回滚**: 2026-06-25 的修订 (`intr_flush_id = interrupt_flush_i`) 基于对 BRAM 时序的误判，已回滚为 `1'b0`。基准版本 `FX-RV32_RemoveM_Custom` 的原始设计经 ROM+BRAM 双模式测试验证正确。

---

## 二、英文版特有问题 (4项)

### 4. 影子寄存器段落文本截断 (L292)

**原文:**
> "...triggered by the single**In contrast**, a conventional software..."

"single" 后丢失了约20个单词。

**修改后:**
> "...triggered by the single-cycle shadow_restore pulse upon MRET execution). In contrast, a conventional software..."

---

### 5. "四个"vs"八个"测试矛盾 (L435)

**原文:**
> "we selected **four** typical workloads"

**修改后:**
> "we selected **eight** typical workloads"

**原因:** 摘要 (L33) 和结论 (L498) 均写 eight benchmark programs，实际 IV.C 节也描述了8个测试。

---

### 6. FPGA频率不一致 (L398)

**原文:**
> "the operating frequency was set to **50 MHz** for easy waveform observation"

**修改后:**
> "the operating frequency was set to **200 MHz** (using the LVDS clock input on the Genesys 2 board)"

**原因:** 全文（摘要、综合结果等）均以 200 MHz 为目标频率；实际 FPGA 板上通过 LVDS 时钟输入运行在 200 MHz。

---

### 7. 术语修正 (L98)

**原文:**
> "implements the complete RV32I **privilege level** and CSRs"

**修改后:**
> "implements the complete RV32I **privileged architecture** and CSRs"

---

## 三、参考文献清理 (2项)

### 8. 删除未引用文献

| 删除的ref | 原文 | 原因 |
|-----------|------|------|
| ref14 | F. Zaruba and L. Benini, "The cost of application-class processing..." (CVA6, TVLSI 2019) | 正文从未 `\cite` |
| ref33 | A. E. El-Gendy, "Cairo University RISC-V (CURISCV) processor" (EIECC 2025) | 正文从未 `\cite` |

### 9. 后续编号重排

删除两篇后，原 ref15 自动成为新 ref14，原 ref16→ref15，…，原 ref32→ref31。正文中所有 `\cite{refXX}` 同步更新。最终: ref1–ref31，共31篇参考文献。

---

## 四、最终验证结果

```
Total citations in text: 31
Total bibitems:          31
Cited but not in bib:    0
In bib but not cited:    0
Status: PERFECT MATCH
```

---

## 四、面积表数据修正（同日，基于综合报告）

根据 `syn/report/area/area_hier_en0.rpt` 和 `area_hier_sh1.rpt` 实际综合数据重算所有面积：

### 综合报告数据

| 配置 | core_top 总面积 | 寄存器堆 |
|------|----------------|---------|
| en0 (SHADOW_EN=0) | 27,879 µm² = **24.89 kGE** | 12,328 µm² = **11.01 kGE** |
| sh1 (SHADOW_EN=1) | 36,252 µm² = **32.37 kGE** | 20,688 µm² = **18.47 kGE** |

影子寄存器净增: 8,360 µm² = **7.46 kGE** (+30%)

### 修正内容

- **表 II/III** 完全重写（中英文两版），使用6个统一分类组件
- **正文所有面积引用** 批量更新：24.3→24.9, 34.5→32.4, 6→7.46, 42%→30% 等
- **英文版额外**: 修正了合成结果节中的 µm² 数值 (27,191→27,879, 38,693→36,252, 11,500→8,360)
- **中文版额外**: 修正了与 PicoRV32 的面积比较百分比

### 关键发现

1. 旧表 II 和表 III 中寄存器堆均写为 10.0 kGE——实际上一个是 11.01，一个是 18.47，差了近一倍
2. 影子寄存器开销之前写为 ~6 kGE / +10 kGE 总面积，实际是 7.46 kGE / +7.48 kGE
3. 旧表 III 中"总线仲裁器与存储器接口"实际不在 core_top 内（bus_arbiter 在 soc_top 层级，693 µm²），已移除

---

## 五、中文版 FX-RV32.md 同步修改（同日完成）

中文版 `FX-RV32.md` 同日进行了以下修改（详见文件中 `【已修改：...】` 标记）：

| # | 问题 | 位置 |
|---|------|------|
| 1 | 摘要注释残留 `//记得把英文版的也给修改了` | L5 |
| 2 | "四组"→"八组"确定性测试 | L15 |
| 3 | PLIC 引用 [27]→[18] (特权架构手册) | L30 |
| 4 | IF阶段半周期/inst_data注释残留 | L69 |
| 5 | III.E注释残留 x2 | L110, L117 |
| 6 | "//感觉图9可以不用放"注释 | L119 |
| 7 | IF阶段重写 (删除半周期/负边沿描述) | L63–69 |
| 8 | 影子寄存器段落重复 (短版+长版) | L124 |
| 9 | III.G "必须缩短篇幅"注释 | L139 |
| 10 | IV标题重复 | L172–173 |
| 11 | CV32E40P 引用 [4]→[6] (3处) | L188, L242, L250 |
| 12 | 参考文献[1] Sophon期刊名 TVLSI 修正 | L263 |
| 13 | 面积表 regfile 矛盾标记 (待核实) | 表II下方 |

---

## 六、待手动处理事项

1. **面积表不一致** — 表II: 寄存器堆(32×32)=10.0kGE; 表III: 寄存器堆+影子(31×32)=10.0kGE。两者数值矛盾，需根据综合报告核实。
2. **插图编号** — 中文版图号跳跃 (1→2→7→...→16，缺3-6和13)，英文版图号连续。需统一。
3. **"FX RV32" vs "FX‑RV32"** — 中文版全文命名未统一。
4. **III.G节** — 作者已标注需要调整/删除/缩短篇幅。
