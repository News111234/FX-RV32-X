# DC 功耗报告阅读指南（论文用）

**日期**: 2026-06-10
**设计**: FX-RV32, SMIC 55nm, 200MHz, tt_v1p2_25c

---

## 1. DC 功耗报告的 4 列含义

以分级功耗报告为例：

```
                                       Switch   Int      Leak     Total
Hierarchy                              Power    Power    Power    Power    %
--------------------------------------------------------------------------------
  u_regfile (regfile_SHADOW_EN0)       0.020    1.905    0.618    1.926  34.8
  u_csr_regfile (csr_regfile)          0.004    0.686    0.202    0.690  12.5
```

| 列名 | 全称 | 类型 | 含义 |
|------|------|------|------|
| **Switch Power** | Net Switching Power | **动态** | 信号线上的寄生电容充放电功耗，P = ½CV²f |
| **Int Power** | Cell Internal Power | **动态** | 标准单元内部的短路电流+内部电容充放电功耗 |
| **Leak Power** | Leakage Power | **静态** | 晶体管关断时的亚阈值漏电+栅极漏电 |
| **Total Power** | — | **总计** | Switch + Int + Leak |

### 关系

```
动态功耗 (Dynamic Power)  = Switch Power + Int Power
静态功耗 (Static Power)   = Leak Power
总功耗   (Total Power)    = Switch Power + Int Power + Leak Power
                          = Dynamic Power + Static Power
```

### 单位

| 列 | 单位 | 示例值 |
|----|------|--------|
| Switch Power | **mW** | 0.020 mW |
| Int Power | **mW** | 1.905 mW |
| Leak Power | **uW** | 0.618 uW（注意是微瓦不是毫瓦！） |
| Total Power | **mW** | 1.926 mW |

---

## 2. 论文中如何引用

### 2.1 你的设计特点

SMIC 55nm TT corner 下漏电极低，占比 < 0.1%。例如 regfile：

```
动态功耗 = 1.905 + 0.020 = 1.925 mW
漏电功耗 = 0.618 uW = 0.000618 mW
总功耗   = 1.925 + 0.000618 ≈ 1.926 mW
漏电占比 = 0.000618 / 1.926 ≈ 0.03%
```

**结论：你可以直接引用 Total 列，动态功耗 ≈ 总功耗。**

### 2.2 论文中的表述建议

**表格标题**：
```
Table X. Power breakdown of FX-RV32 SoC at 200MHz (SMIC 55nm, 1.2V, 25°C)
```

**表格列推荐用**：
```
Module          Dynamic Power (mW)    Leakage Power (uW)    Total Power (mW)
regfile         1.925                  0.618                 1.926
csr_regfile     0.690                  0.202                 0.690
...
```

或者如果只列总功耗（因为漏电太小）：
```
Module          Power (mW)
regfile         1.926
csr_regfile     0.690
...
```

**正文解释一句就行**：
> "All power numbers reported are total power (dynamic + leakage). Leakage power is negligible at the 55nm TT corner, accounting for less than 0.1% of total chip power."

### 2.3 审稿人可能会问的问题

| 问题 | 回答 |
|------|------|
| 为什么没单独报动态功耗？ | 动态功耗 = Total - Leakage，漏电 < 0.1%，数值几乎相同 |
| 为什么漏电这么低？ | SMIC 55nm LL (Low Leakage) 工艺，TT corner 室温，HVT 标准单元 |
| FF corner 高温下漏电会怎样？ | 可能增加 5-10 倍，但仍然不超过总功耗的 1-2% |
| SRAM/ROM 的功耗怎么算的？ | 从 Memory Compiler 生成的 .lib 文件中 internal_power 表手动计算，详见 sram_area_power_reading_guide.md |

---

## 3. 不同报告的功耗数据位置

### 3.1 摘要报告 (`power_*.rpt`)

```bash
grep "Total Dynamic\|Cell Leakage" power_sram_rom.rpt
```
输出:
```
Total Dynamic Power    =   5.5364 mW  (100%)
Cell Leakage Power     =   1.8869 uW
```
→ 这是整芯片的总动态功耗和总漏电。**论文里的整芯片总功耗 = 5.5364 + 0.0019 ≈ 5.5383 mW ≈ 5.54 mW**

### 3.2 分级报告 (`power_hier_*.rpt`)

每行 = 一个模块的 Switch + Int + Leak + Total
→ **论文里的各模块功耗从这里取 Total 列**

### 3.3 Power Group 表

```
                 Internal    Switching    Leakage     Total
register          5.4236      0.0059       0.9290      5.4304
combinational     0.0552      0.0513       0.9578      0.1075
```
→ 按电路类型分类（寄存器 vs 组合逻辑）。**论文里可以引用这个表来说明功耗主要消耗在寄存器上。**

---

## 4. Macro (SRAM/ROM) 功耗的注意事项

Macro 是 black box，DC 报告里面积/功耗都显示为 0.0000。Macro 的真实功耗必须从 `.lib` 文件单独提取：

| Macro | 动态功耗来源 | 漏电来源 |
|-------|------------|---------|
| SRAM 1024×32 | `internal_power()` 表 → 读/写能量 (pJ) × 频率 × 活动因子 | `cell_leakage_power` |
| Via-ROM 1024×32 | 同上，只有读能量 | `cell_leakage_power` |

**论文里报的整芯片总功耗 = DC报告中的非Macro功耗 + 从.lib计算的Macro功耗**

---

## 5. 快速命令参考

```bash
# 整芯片动态功耗 + 漏电
grep "Total Dynamic\|Cell Leakage" power_4k.rpt

# 各模块功耗（Total列）
grep "u_core\|u_regfile\|u_data_ram\|u_inst_rom" power_hier_4k.rpt

# 按电路类型分类
grep -A12 "Power Group" power_4k.rpt

# 整芯片面积
grep "Total cell area" area_4k.rpt

# 各模块面积
grep "u_core\|u_data_ram\|u_inst_rom" area_hier_4k.rpt
```

---

## 6. 你的几种配置的数据速查

### 2KB Macro 版推荐数据 (SHADOW_EN=0)

直接从 DC 报告取（不含 macro）：

| 模块 | Total Power (mW) | Leakage (uW) |
|------|-----------------|--------------|
| 整芯片 | 5.538 | 1.887 |
| u_core (CPU核) | 4.026 | 1.434 |
| — u_regfile | 1.926 | 0.618 |
| — u_csr_regfile | 0.692 | 0.202 |
| — u_id_ex_reg | 0.352 | 0.080 |
| — u_ex_mem_reg | 0.320 | 0.074 |
| — u_interrupt_pipeline | 0.286 | 0.073 |
| — u_mem_wb_reg | 0.253 | 0.058 |
| — u_if_id_reg | 0.122 | 0.028 |
| — u_ifu_top | 0.065 | 0.031 |
| u_gpio | 0.483 | 0.114 |
| u_uart_ctrl | 0.493 | 0.151 |
| u_spi_master | 0.168 | 0.056 |
| u_i2c_master | 0.156 | 0.052 |
| u_timer | 0.130 | 0.050 |
| u_bus_arbiter | 0.081 | 0.027 |

加上 macro（从 .lib 手动计算）：

| Macro | Dynamic (mW) | Leakage (uW) |
|-------|-------------|--------------|
| SRAM 1024×32 | 0.197 | 1.584 |
| Via-ROM 1024×32 | 0.275 | 0.676 |

**整芯片总计 = 5.538 + 0.197 + 0.275 = 6.01 mW (动态) + 4.15 uW (漏电)**

---

## 7. 总结

| 问题 | 答案 |
|------|------|
| DC 报告里的 Total 是动态功耗吗？ | Total = 动态(Internal+Switching) + 漏电(Leakage) |
| 论文里该用哪个数？ | 直接用 Total 列，漏电占比 < 0.1%，几乎没区别 |
| 需要单独说明漏电吗？ | 一句话带过即可："Leakage is negligible at 55nm TT" |
| Macro 功耗怎么报？ | DC 不给，从 .lib 手工算，跟 DC 数据加在一起报整芯片 |
| 功耗跟频率什么关系？ | 动态功耗 ∝ 频率，漏电与频率无关。本文所有数据 @200MHz |
