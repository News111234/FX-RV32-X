# SRAM 面积与功耗数据读取指南

**日期**: 2026-06-10
**SRAM**: S55NLLG1PH 512×32-bit Single-Port Register-File
**工艺**: SMIC 55nm LL RVT, tt_v1p2_25c
**数据来源**: `/home/yifengxin/asic_synth/sram_gen/sram_512x32_tt_1.2_25.lib`

---

## 1. 背景：为什么 DC 综合报告看不到 SRAM 的面积和功耗？

SRAM 是一个 **hard macro**（硬核 IP），不是由标准单元搭出来的。DC 综合时把它当作 **black box**：

- DC 只知道 SRAM 的端口（输入/输出信号名和位宽）
- DC **不知道** SRAM 内部结构 → 无法计算内部功耗、无法计算版图面积
- 综合报告里 `u_sram` 显示为 `0.0000`（面积）和 `0.000`（功耗）

SRAM 的真实面积和功耗数据存放在 Memory Compiler 生成的 **`.lib` 文件**（Liberty 格式）中，需要手动读取。

---

## 2. 数据文件位置

```
/home/yifengxin/asic_synth/sram_gen/
├── sram_512x32_tt_1.2_25.lib      ← 典型工艺角 (25°C, 1.2V)，主要看这个
├── sram_512x32_ff_1.32_-40.lib    ← Fast corner (-40°C, 1.32V)
├── sram_512x32_ff_1.32_0.lib
├── sram_512x32_ff_1.32_125.lib
├── sram_512x32_ss_1.08_-40.lib    ← Slow corner (-40°C, 1.08V)
├── sram_512x32_ss_1.08_125.lib
├── sram_512x32.v                  ← Verilog 仿真模型
├── sram_512x32.lef                ← LEF 物理库
└── sram_512x32_stub.v             ← DC 综合用的 stub (手写)
```

---

## 3. 单位定义

`.lib` 文件头部定义了所有单位：

```
time_unit           : "1ns"       # 时间单位: 1 纳秒
voltage_unit        : "1V"        # 电压单位: 1 伏特
current_unit        : "1mA"       # 电流单位: 1 毫安
leakage_power_unit  : "1mW"       # 漏电功耗单位: 1 毫瓦
capacitive_load_unit: (1, pf)     # 电容单位: 1 皮法
```

**推导单位**:
- 功耗单位 = 1V × 1mA = **1 mW**
- 能量单位 = 1mW × 1ns = **1 pJ** (皮焦耳)
- `internal_power` 表中的数值单位为 **pJ/次操作**

---

## 4. SRAM 面积

### 4.1 从 .lib 读取

```tcl
area : 21194.215;    # 单位: 平方微米 (sq.um)
```

### 4.2 数值

| 项目 | 数值 |
|------|------|
| **SRAM macro 面积** | **21,194.215 sq.um** |
| 等价门数 (按 1 NAND2 ≈ 2.5 sq.um) | ~8,478 门 |

### 4.3 整芯片面积计算

以 A2 配置（无影子寄存器 + SRAM）为例:

```
DC 分级报告面积 (不含 SRAM)    37,128.28  sq.um
SRAM macro 面积 (从 .lib)     +21,194.22  sq.um
wrapper 逻辑 (data_ram_sram)   +    28.84  sq.um
                              ------------
整芯片实际总面积              = 58,351.34  sq.um
```

### 4.4 查找命令

```bash
grep -A3 "wire_load.*sample" /home/yifengxin/asic_synth/sram_gen/sram_512x32_tt_1.2_25.lib
```

输出:
```
wire_load("sample") {
    resistance   : 1.6e-05;
    capacitance  : 0.0002;
    area         : 1.7;          ← 这个是 wire_load 模型面积，忽略
```

```bash
# 真实的 cell 面积在这行的附近，位于 cell(sram_512x32) 定义中
grep "area" /home/yifengxin/asic_synth/sram_gen/sram_512x32_tt_1.2_25.lib
```

输出:
```
area : 1.7;                  ← wire_load 的面积 (忽略)
area : 21194.215;            ← 这才是 SRAM macro 的真实面积!
```

---

## 5. SRAM 功耗

### 5.1 漏电功耗 (Leakage Power)

```tcl
cell_leakage_power : 0.000993;    # 单位: mW
```

| 项目 | 数值 |
|------|------|
| **SRAM 漏电功耗** | **0.000993 mW = 0.993 uW ≈ 1.0 uW** |

对比: 寄存器版 data_ram 漏电功耗为 **8.083 uW**，SRAM 漏电仅为其 **1/8**。

查找命令:
```bash
grep "cell_leakage_power" /home/yifengxin/asic_synth/sram_gen/sram_512x32_tt_1.2_25.lib
```

---

### 5.2 动态功耗 (Dynamic Power)

动态功耗记录在 `internal_power()` 表中，按操作类型分为以下几种。

#### 5.2.1 读操作功耗

`.lib` 中的 when 条件:

```
when: "!CEN & (WEN | 所有BWEN=1)"
意思: 芯片使能 (CEN=0) 且 (读模式 (WEN=1) 或 所有字节都不写 (BWEN全1))
→ 即: 执行读操作
```

| 时钟沿能量 | 数值 |
|-----------|------|
| rise_power | **7.976 pJ** |
| fall_power | 0.000 pJ |

#### 5.2.2 写操作功耗

```
when: "!CEN & !WEN & 至少一个BWEN=0"
意思: 芯片使能 (CEN=0) 且 写模式 (WEN=0) 且 至少一个 bit 被写入
→ 即: 执行写操作
```

| 时钟沿能量 | 数值 |
|-----------|------|
| rise_power | **11.788 pJ** |
| fall_power | 0.000 pJ |

> 写操作比读操作功耗更高 (11.788 vs 7.976 pJ)，因为写操作需要驱动位线并对存储节点充放电。

#### 5.2.3 空闲时钟功耗

```
when: "CEN"
意思: 芯片未使能 (CEN=1)，SRAM 处于待机状态
```

| 时钟沿能量 | 数值 |
|-----------|------|
| rise_power | **0.021 pJ** |
| fall_power | 0.000 pJ |

#### 5.2.4 信号引脚翻转功耗

CEN/WEN 等信号引脚自身翻转时消耗的能量:

| 引脚 | 能量/次翻转 |
|------|-----------|
| CEN, WEN 等信号 | **0.475 pJ** |

#### 5.2.5 功耗汇总表

| 操作 | 能量 (pJ) |
|------|-----------|
| 读操作 (CLK 上升沿) | 7.976 |
| 写操作 (CLK 上升沿) | 11.788 |
| 空闲时钟 | 0.021 |
| 信号引脚翻转 | 0.475/引脚 |
| **漏电** | **0.000993 mW** |

查找命令:
```bash
grep "values (" /home/yifengxin/asic_synth/sram_gen/sram_512x32_tt_1.2_25.lib
```

输出:
```
values ("11.788, 11.788")    ← 写操作 CLK 上升沿能量
values ("0.000, 0.000")      ← 写操作 CLK 下降沿能量
values ("7.976, 7.976")      ← 读操作 CLK 上升沿能量
values ("0.000, 0.000")      ← 读操作 CLK 下降沿能量
values ("0.021, 0.021")      ← 空闲时钟能量
values ("0.000, 0.000")      
values ("0.475, 0.475")      ← 信号引脚翻转能量
values ("0.475, 0.475")      ← 信号引脚翻转能量
```

---

### 5.3 动态功耗换算公式

```
动态功耗 (mW) = 能量 (pJ) × 时钟频率 (MHz) × 活动因子
```

推导:
```
能量 (pJ) × 频率 (MHz)
= (能量 × 10⁻¹² J) × (频率 × 10⁶ Hz)
= 能量 × 频率 × 10⁻⁶ W
= 能量 × 频率 × 10⁻³ mW
```

**简化公式**:
```
P(mW) = E(pJ) × F(MHz) × α / 1000
```

其中 α = 活动因子 (在本次分析中取 0.1)

### 5.4 实际计算 (200MHz, 活动因子 0.1, 70%读 30%写)

```
读操作占比       = 70% × 0.1 = 0.07
写操作占比       = 30% × 0.1 = 0.03
空闲占比         = 1 - 0.1   = 0.90

读功耗    = 7.976 pJ × 200 MHz × 0.07 / 1000 = 7.976 × 14 / 1000 = 0.1117 mW
写功耗    = 11.788 pJ × 200 MHz × 0.03 / 1000 = 11.788 × 6 / 1000 = 0.0707 mW
空闲功耗  = 0.021 pJ × 200 MHz × 0.90 / 1000 = 0.021 × 180 / 1000 = 0.0038 mW
信号功耗  = 忽略 (远小于上述各项)
                -----------------
SRAM 总动态功耗 = 0.186 mW
SRAM 漏电功耗   = 0.001 mW
                -----------------
SRAM 总功耗     = 0.187 mW ≈ 0.19 mW
```

> **保守取整**: 实际文档中使用 `0.21 mW` 作为 SRAM 功耗估算值，为计算方便做了向上取整。

---

## 6. 整芯片功耗计算

### 6.1 以 A2 配置为例 (无影子寄存器 + SRAM)

```
DC 报告功耗 (不含 SRAM 内部)    5.5364 mW  (动态)
DC 报告漏电 (不含 SRAM 内部)    1.8869 uW  (漏电)
SRAM 动态功耗 (从 .lib 计算)   +0.186  mW
SRAM 漏电功耗 (从 .lib)        +0.993  uW
                               -----------
整芯片实际总动态功耗            = 5.722 mW  (约 5.75 mW)
整芯片实际总漏电功耗            = 2.880 uW
```

### 6.2 四种配置整芯片功耗汇总

| 配置 | DC 动态 | SRAM 动态 | 总动态 | DC 漏电 | SRAM 漏电 | 总漏电 |
|------|---------|----------|--------|---------|----------|--------|
| A1 (寄存器) | 37.585 mW | — | **37.59 mW** | 9.967 uW | — | **9.97 uW** |
| A2 (SRAM) | 5.536 mW | 0.186 mW | **5.72 mW** | 1.887 uW | 0.993 uW | **2.88 uW** |
| B1 (寄存器+影子) | 39.403 mW | — | **39.40 mW** | 10.274 uW | — | **10.27 uW** |
| B2 (SRAM+影子) | 7.349 mW | 0.186 mW | **7.54 mW** | 2.192 uW | 0.993 uW | **3.19 uW** |

---

## 7. SRAM 时序参数 (tt_v1p2_25c)

`.lib` 中的时序信息同样对综合流程很重要:

| 参数 | 符号 | 典型值 (ns) | 说明 |
|------|------|------------|------|
| Clock-to-Q 延迟 | Tcq | **0.846 ~ 1.202** | 时钟上升到 Q 有效 (取决于负载) |
| 地址 Setup 时间 | Tas | **0.193 ~ 0.269** | 地址在 CLK↑ 前稳定 |
| 数据 Setup 时间 | Tds | **0.204 ~ 0.269** | 数据在 CLK↑ 前稳定 |
| 最小周期 | Tcyc | ~1.54 | 最大频率约 650 MHz |

> 200MHz (5ns) 下裕量充足，时序不是瓶颈。

---

## 8. 快速命令参考

```bash
# 查看 SRAM 面积
grep -A1 "area.*:" /home/yifengxin/asic_synth/sram_gen/sram_512x32_tt_1.2_25.lib | grep -v "wire_load"

# 查看 SRAM 漏电功耗
grep "cell_leakage_power" /home/yifengxin/asic_synth/sram_gen/sram_512x32_tt_1.2_25.lib

# 查看 SRAM 动态能量值
grep "values (" /home/yifengxin/asic_synth/sram_gen/sram_512x32_tt_1.2_25.lib

# 查看 SRAM Clock-to-Q 延迟
grep -A9 "cell_rise(sram_512x32_mem_out_delay_template)" /home/yifengxin/asic_synth/sram_gen/sram_512x32_tt_1.2_25.lib

# 查看分级面积报告中 data_ram 的占比
grep "u_data_ram" /home/yifengxin/asic_synth/FX-RV32/area_hier_en0.rpt
```

---

## 9. 关键结论

| 指标 | 寄存器 data_ram | SRAM data_ram | 节省 |
|------|----------------|---------------|------|
| 面积 | **163,419 sq.um** | **21,194 sq.um** | **↓ 87%** |
| 动态功耗 | **32.060 mW** | **~0.19 mW** | **↓ 168x** |
| 漏电功耗 | **8.083 uW** | **~0.99 uW** | **↓ 8x** |

SRAM 的面积和功耗数据**不会出现在 DC 综合的摘要报告中**，必须从 Memory Compiler 生成的 `.lib` 文件手动提取。在分级报告中 (`area_hier_*.rpt`) 可以看到 SRAM wrapper 的面积（约 28.84 sq.um），但 SRAM macro 本身显示为 `0.0000`。
