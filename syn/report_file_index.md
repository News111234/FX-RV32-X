# FX-RV32 综合报告文件索引

**日期**: 2026-06-10
**设计**: FX-RV32 @ SMIC 55nm, 200MHz
**综合工具**: Synopsys Design Compiler Q-2019.12-SP5-3

---

## 1. 四种配置及报告文件总览

| 配置 | 代号 | SHADOW_EN | data_ram | 综合脚本 |
|------|------|-----------|----------|---------|
| A1 | SH0_REG | 0 (关闭) | 寄存器阵列 | `run_synth.tcl` |
| A2 | SH0_SRAM | 0 (关闭) | SRAM macro | `run_synth_sram.tcl` |
| B1 | SH1_REG | 1 (开启) | 寄存器阵列 | `run_synth_sh1.tcl` |
| B2 | SH1_SRAM | 1 (开启) | SRAM macro | `run_synth_sram_sh1.tcl` |

---

## 2. 配置 A1 — 无影子寄存器 + 寄存器 data_ram

**综合脚本**: `/home/yifengxin/asic_synth/FX-RV32/run_synth.tcl`
**报告目录**: `/home/yifengxin/asic_synth/FX-RV32/`

| 报告类型 | 文件名 | 完整路径 |
|---------|--------|---------|
| **功耗摘要** | `power_en0.rpt` | `/home/yifengxin/asic_synth/FX-RV32/power_en0.rpt` |
| **功耗分级** | `power_hier_en0.rpt` | `/home/yifengxin/asic_synth/FX-RV32/power_hier_en0.rpt` |
| **功耗 Cell 级** | `power_cell_en0.rpt` | `/home/yifengxin/asic_synth/FX-RV32/power_cell_en0.rpt` |
| **面积摘要** | `area_en0.rpt` | `/home/yifengxin/asic_synth/FX-RV32/area_en0.rpt` |
| **面积分级** | `area_hier_en0.rpt` | `/home/yifengxin/asic_synth/FX-RV32/area_hier_en0.rpt` |
| **时序报告** | `timing_en0.rpt` | `/home/yifengxin/asic_synth/FX-RV32/timing_en0.rpt` |

**综合产物**:

| 文件 | 路径 |
|------|------|
| DDC 数据库 | `/home/yifengxin/asic_synth/FX-RV32/soc_top.ddc` |
| 门级网表 | `/home/yifengxin/asic_synth/FX-RV32/soc_top_netlist.v` |
| SDF 延时 | `/home/yifengxin/asic_synth/FX-RV32/soc_top.sdf` |
| SDC 约束 | `/home/yifengxin/asic_synth/FX-RV32/soc_top.sdc` |

### A1 关键数据

```
Total Dynamic Power  = 37.5853 mW
Cell Leakage Power   =  9.9668 uW
Total Cell Area      = 200445.28
Sequential Cells     = 19293
Combinational Cells  = 33786
```

---

## 3. 配置 A2 — 无影子寄存器 + SRAM data_ram

**综合脚本**: `/home/yifengxin/asic_synth/FX-RV32/run_synth_sram.tcl`
**报告目录**: `/home/yifengxin/asic_synth/sram_gen/`

| 报告类型 | 文件名 | 完整路径 |
|---------|--------|---------|
| **功耗摘要** | `power_sram.rpt` | `/home/yifengxin/asic_synth/sram_gen/power_sram.rpt` |
| **功耗分级** | `power_hier_sram.rpt` | `/home/yifengxin/asic_synth/sram_gen/power_hier_sram.rpt` |
| **面积摘要** | `area_sram.rpt` | `/home/yifengxin/asic_synth/sram_gen/area_sram.rpt` |
| **面积分级** | `area_hier_sram.rpt` | `/home/yifengxin/asic_synth/sram_gen/area_hier_sram.rpt` |
| **时序报告** | `timing_sram.rpt` | `/home/yifengxin/asic_synth/sram_gen/timing_sram.rpt` |

**综合产物**:

| 文件 | 路径 |
|------|------|
| DDC 数据库 | `/home/yifengxin/asic_synth/sram_gen/soc_top_sram.ddc` |
| 门级网表 | `/home/yifengxin/asic_synth/sram_gen/soc_top_sram_netlist.v` |
| SDF 延时 | `/home/yifengxin/asic_synth/sram_gen/soc_top_sram.sdf` |
| SDC 约束 | `/home/yifengxin/asic_synth/sram_gen/soc_top_sram.sdc` |

### A2 关键数据

```
Total Dynamic Power  =  5.5364 mW  (不含 SRAM, SRAM 外加 +0.213 mW = 5.75 mW)
Cell Leakage Power   =  1.8869 uW  (不含 SRAM, SRAM 外加 +0.993 uW = 2.88 uW)
Total Cell Area      = 37128.28    (不含 SRAM, SRAM 外加 +21194 = 58322)
Sequential Cells     =  2909
Combinational Cells  =  9327
```

> ⚠️ **注意**: SRAM 为 black box macro，功耗和面积数据需从 `.lib` 手动提取相加。
> SRAM 数据来源: `/home/yifengxin/asic_synth/sram_gen/sram_512x32_tt_1.2_25.lib`

---

## 4. 配置 B1 — 有影子寄存器 + 寄存器 data_ram

**综合脚本**: `/home/yifengxin/asic_synth/FX-RV32/run_synth_sh1.tcl`
**报告目录**: `/home/yifengxin/asic_synth/FX-RV32/`

| 报告类型 | 文件名 | 完整路径 |
|---------|--------|---------|
| **功耗摘要** | `power_sh1.rpt` | `/home/yifengxin/asic_synth/FX-RV32/power_sh1.rpt` |
| **功耗分级** | `power_hier_sh1.rpt` | `/home/yifengxin/asic_synth/FX-RV32/power_hier_sh1.rpt` |
| **面积摘要** | `area_sh1.rpt` | `/home/yifengxin/asic_synth/FX-RV32/area_sh1.rpt` |
| **面积分级** | `area_hier_sh1.rpt` | `/home/yifengxin/asic_synth/FX-RV32/area_hier_sh1.rpt` |
| **时序报告** | `timing_sh1.rpt` | `/home/yifengxin/asic_synth/FX-RV32/timing_sh1.rpt` |

**综合产物**:

| 文件 | 路径 |
|------|------|
| DDC 数据库 | `/home/yifengxin/asic_synth/FX-RV32/soc_top_sh1.ddc` |
| 门级网表 | `/home/yifengxin/asic_synth/FX-RV32/soc_top_sh1_netlist.v` |
| SDF 延时 | `/home/yifengxin/asic_synth/FX-RV32/soc_top_sh1.sdf` |
| SDC 约束 | `/home/yifengxin/asic_synth/FX-RV32/soc_top_sh1.sdc` |

**SHADOW_EN=1 RTL 源文件**:

| 文件 | 路径 |
|------|------|
| id_top (SHADOW_EN=1) | `/home/yifengxin/asic_synth/shadow_en1/id_top_sh1.v` |
| interrupt_pipeline (SHADOW_EN=1) | `/home/yifengxin/asic_synth/shadow_en1/interrupt_pipeline_sh1.v` |

### B1 关键数据

```
Total Dynamic Power  = 39.4029 mW
Cell Leakage Power   = 10.2735 uW
Total Cell Area      = 208775.00
Sequential Cells     = 20287  (+994 vs A1)
Combinational Cells  = 35023  (+1237 vs A1)
```

---

## 5. 配置 B2 — 有影子寄存器 + SRAM data_ram

**综合脚本**: `/home/yifengxin/asic_synth/FX-RV32/run_synth_sram_sh1.tcl`
**报告目录**: `/home/yifengxin/asic_synth/FX-RV32/`

| 报告类型 | 文件名 | 完整路径 |
|---------|--------|---------|
| **功耗摘要** | `power_sram_sh1.rpt` | `/home/yifengxin/asic_synth/FX-RV32/power_sram_sh1.rpt` |
| **功耗分级** | `power_hier_sram_sh1.rpt` | `/home/yifengxin/asic_synth/FX-RV32/power_hier_sram_sh1.rpt` |
| **面积摘要** | `area_sram_sh1.rpt` | `/home/yifengxin/asic_synth/FX-RV32/area_sram_sh1.rpt` |
| **面积分级** | `area_hier_sram_sh1.rpt` | `/home/yifengxin/asic_synth/FX-RV32/area_hier_sram_sh1.rpt` |
| **时序报告** | `timing_sram_sh1.rpt` | `/home/yifengxin/asic_synth/FX-RV32/timing_sram_sh1.rpt` |

**综合产物**:

| 文件 | 路径 |
|------|------|
| DDC 数据库 | `/home/yifengxin/asic_synth/FX-RV32/soc_top_sram_sh1.ddc` |
| 门级网表 | `/home/yifengxin/asic_synth/FX-RV32/soc_top_sram_sh1_netlist.v` |
| SDF 延时 | `/home/yifengxin/asic_synth/FX-RV32/soc_top_sram_sh1.sdf` |
| SDC 约束 | `/home/yifengxin/asic_synth/FX-RV32/soc_top_sram_sh1.sdc` |

### B2 关键数据

```
Total Dynamic Power  =  7.3492 mW  (不含 SRAM, SRAM 外加 +0.213 mW = 7.56 mW)
Cell Leakage Power   =  2.1919 uW  (不含 SRAM, SRAM 外加 +0.993 uW = 3.18 uW)
Total Cell Area      = 45430.28    (不含 SRAM, SRAM 外加 +21194 = 66624)
Sequential Cells     =  3903
Combinational Cells  = 10594
```

---

## 6. 报告文件路径速查表

### 功耗报告

| 配置 | 功耗摘要 | 功耗分级 | 功耗 Cell 级 |
|------|---------|---------|-------------|
| **A1** (无影子+寄存器) | `asic_synth/FX-RV32/power_en0.rpt` | `asic_synth/FX-RV32/power_hier_en0.rpt` | `asic_synth/FX-RV32/power_cell_en0.rpt` |
| **A2** (无影子+SRAM) | `asic_synth/sram_gen/power_sram.rpt` | `asic_synth/sram_gen/power_hier_sram.rpt` | — |
| **B1** (有影子+寄存器) | `asic_synth/FX-RV32/power_sh1.rpt` | `asic_synth/FX-RV32/power_hier_sh1.rpt` | — |
| **B2** (有影子+SRAM) | `asic_synth/FX-RV32/power_sram_sh1.rpt` | `asic_synth/FX-RV32/power_hier_sram_sh1.rpt` | — |

> 所有路径以 `/home/yifengxin/` 为根目录。

### 面积报告

| 配置 | 面积摘要 | 面积分级 |
|------|---------|---------|
| **A1** (无影子+寄存器) | `asic_synth/FX-RV32/area_en0.rpt` | `asic_synth/FX-RV32/area_hier_en0.rpt` |
| **A2** (无影子+SRAM) | `asic_synth/sram_gen/area_sram.rpt` | `asic_synth/sram_gen/area_hier_sram.rpt` |
| **B1** (有影子+寄存器) | `asic_synth/FX-RV32/area_sh1.rpt` | `asic_synth/FX-RV32/area_hier_sh1.rpt` |
| **B2** (有影子+SRAM) | `asic_synth/FX-RV32/area_sram_sh1.rpt` | `asic_synth/FX-RV32/area_hier_sram_sh1.rpt` |

### 时序报告

| 配置 | 时序报告 |
|------|---------|
| **A1** | `asic_synth/FX-RV32/timing_en0.rpt` |
| **A2** | `asic_synth/sram_gen/timing_sram.rpt` |
| **B1** | `asic_synth/FX-RV32/timing_sh1.rpt` |
| **B2** | `asic_synth/FX-RV32/timing_sram_sh1.rpt` |

---

## 7. SRAM 相关文件

| 文件 | 说明 | 路径 |
|------|------|------|
| Liberty 模型 (TT) | 时序+功耗 | `asic_synth/sram_gen/sram_512x32_tt_1.2_25.lib` |
| Liberty 模型 (FF) | 3 个 corner | `asic_synth/sram_gen/sram_512x32_ff_1.32_*.lib` |
| Liberty 模型 (SS) | 2 个 corner | `asic_synth/sram_gen/sram_512x32_ss_1.08_*.lib` |
| LEF 物理库 | P&R 用 | `asic_synth/sram_gen/sram_512x32.lef` |
| Verilog 仿真模型 | 门级仿真用 | `asic_synth/sram_gen/sram_512x32.v` |
| Verilog 综合 stub | DC 黑盒综合 | `asic_synth/sram_gen/sram_512x32_stub.v` |
| SRAM wrapper | 接口转换 RTL | `FX-RV32/soc/mem/data_ram_sram.v` |

> 全路径: `/home/yifengxin/` + 上表路径

---

## 8. 综合脚本路径

| 脚本 | 路径 |
|------|------|
| A1: 无影子+寄存器 | `/home/yifengxin/asic_synth/FX-RV32/run_synth.tcl` |
| A2: 无影子+SRAM | `/home/yifengxin/asic_synth/FX-RV32/run_synth_sram.tcl` |
| B1: 有影子+寄存器 | `/home/yifengxin/asic_synth/FX-RV32/run_synth_sh1.tcl` |
| B2: 有影子+SRAM | `/home/yifengxin/asic_synth/FX-RV32/run_synth_sram_sh1.tcl` |

---

## 9. 相关文档

| 文档 | 路径 |
|------|------|
| 功耗报告修复记录 | `/home/yifengxin/power_report_fix.md` |
| Memory Compiler 使用指南 | `/home/yifengxin/syn/memory_compiler_usage_guide.md` |
| 影子寄存器 & SRAM 对比报告 | `/home/yifengxin/syn/shadow_sram_power_comparison.md` |
| **本文件 (报告索引)** | `/home/yifengxin/syn/report_file_index.md` |
