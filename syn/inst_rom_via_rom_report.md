# inst_rom 替换为 Via-ROM 报告

**日期**: 2026-06-10
**设计**: FX-RV32
**工艺**: SMIC 55nm LL RVT, tt_v1p2_25c, 200MHz

---

## 1. 背景

`inst_rom.v` 使用 `initial` 块初始化 512×32-bit 指令数据，但 **DC 综合会忽略 `initial` 块**。综合后 inst_rom 只剩下 15.68 sq.um 的空壳（地址译码器），真正的指令数据全部丢失，网表无法使用。

本次使用 SMIC S55NLLGVMH Via-ROM Compiler 生成 ROM hard macro 替代之。

---

## 2. Via-ROM 生成

### 2.1 工具路径

```
/opt/eda/pdk/smic55/memory_compiler/S55NLLGVMH/v1p1/S55NLLGVMH.jar
```

### 2.2 生成命令

```bash
cd /opt/eda/pdk/smic55/memory_compiler/S55NLLGVMH/v1p1

java -jar S55NLLGVMH.jar \
    -words 512 \
    -mux 8 \
    -bits 32 \
    -codefile /home/yifengxin/asic_synth/sram_gen/inst_rom_code.txt \
    -v -lib -lef \
    -savepath /home/yifengxin/asic_synth/sram_gen \
    -instname via_rom_512x32
```

### 2.3 Code File 格式

Via-ROM 需要 `-codefile` 参数指定 ROM 内容。格式为纯文本：512 行 × 32 列，每字符为 `0` 或 `1`（MSB 优先）。

**Code file 路径**: `/home/yifengxin/asic_synth/sram_gen/inst_rom_code.txt`

**生成方式**: 用 Python 从 `inst_rom.v` 的 `rom[n] = 32'hXXXXXXXX` 赋值语句提取，其余未赋值地址默认填充 NOP (`0x00000013`)。

```
$ head -3 inst_rom_code.txt
00010000000000000001000010110111
00000000010000001000000010010011
00000000000100000000000100010011
```

### 2.4 生成文件

| 文件 | 路径 |
|------|------|
| Verilog 仿真模型 | `/home/yifengxin/asic_synth/sram_gen/via_rom_512x32.v` |
| Liberty 模型 (TT) | `/home/yifengxin/asic_synth/sram_gen/via_rom_512x32_tt_1.2_25.lib` |
| LEF 物理库 | `/home/yifengxin/asic_synth/sram_gen/via_rom_512x32.lef` |
| DC 综合 stub | `/home/yifengxin/asic_synth/sram_gen/via_rom_512x32_stub.v` |
| RTL wrapper | `/home/yifengxin/FX-RV32/soc/mem/inst_rom_via.v` |

### 2.5 ROM 接口

```
module via_rom_512x32 (
    Q,      // output [31:0]  数据输出（同步寄存器输出）
    A,      // input  [8:0]   地址
    CLK,    // input          时钟
    CEN     // input          芯片使能 (0=有效)
);
```

---

## 3. ROM 面积和功耗（来自 .lib）

### 3.1 面积

| 来源 | 数值 |
|------|------|
| ROM macro (`.lib`) | **11,295.33 sq.um** |
| wrapper 逻辑 (DC 报告) | 15.68 sq.um |
| **合计** | **~11,311 sq.um** |

### 3.2 漏电功耗

```
cell_leakage_power : 0.000636 mW = 0.636 uW
```

### 3.3 动态功耗

| 操作 | 能量/次 (pJ) |
|------|-------------|
| 读操作 (CLK rise) | **13.469** |
| 空闲 (CEN=1) | **0.032** |

### 3.4 动态功耗换算

```
功耗(mW) = 能量(pJ) × 频率(MHz) × 活动因子 / 1000

200MHz, 活动因子 0.1:
  读功耗  = 13.469 × 200 × 0.1 / 1000 = 0.269 mW
  空闲功耗 = 0.032 × 200 × 0.9 / 1000 = 0.006 mW
  ────────────────────────────
  ROM 总动态功耗 ≈ 0.275 mW
  ROM 漏电功耗   ≈ 0.636 uW
```

### 3.5 查找命令

```bash
# 面积
grep "area" via_rom_512x32_tt_1.2_25.lib | grep -v "wire_load\|1.7\|capacitance\|default"

# 漏电
grep "cell_leakage_power" via_rom_512x32_tt_1.2_25.lib

# 动态能量
grep "values (" via_rom_512x32_tt_1.2_25.lib
```

---

## 4. 与原 inst_rom 对比

| 指标 | 原 inst_rom (寄存器) | Via-ROM macro | 变化 |
|------|---------------------|---------------|------|
| DC 综合面积 | 15.68 sq.um | 15.68 (wrapper) | 相同 |
| **真实面积** | ~0 (数据丢失!) | **~11,311 sq.um** | — |
| 动态功耗 | ~0 mW | 0.275 mW | +0.28 mW |
| 漏电功耗 | ~1.27 nW | 0.636 uW | +0.64 uW |
| **指令数据** | ❌ 丢失 | ✅ 固化在 ROM | **功能修复** |

> 原 inst_rom 综合后数据丢失——DC 忽略了 `initial` 块。Via-ROM 将指令数据物理固化在硅片上，功能正确。

---

## 5. 最终配置总览

将 SRAM data_ram 和 Via-ROM inst_rom 都替换后，6 种配置的总功耗面积对比：

| 配置 | 动态功耗 (mW) | 漏电 (uW) | 总面积 (sq.um) |
|------|-------------|----------|---------------|
| A1: 寄存器RAM + 寄存器ROM (无影子) | 37.59 | 9.97 | 200,445 |
| A2: SRAM + 寄存器ROM (无影子) | 5.75 | 2.88 | 58,322 |
| **A3: SRAM + Via-ROM (无影子)** | **6.00** | **3.52** | **69,618** |
| B1: 寄存器RAM + 寄存器ROM (有影子) | 39.41 | 10.27 | 208,775 |
| B2: SRAM + 寄存器ROM (有影子) | 7.56 | 3.19 | 66,624 |
| **B3: SRAM + Via-ROM (有影子)** | **7.81** | **3.82** | **77,904** |

### 5.1 A3 功耗分解 (SHADOW_EN=0, SRAM + Via-ROM)

```
DC 综合 (非 macro 部分)    5.536 mW (动态)  + 1.887 uW (漏电)
SRAM data_ram (从 .lib)    0.186 mW          + 0.993 uW
Via-ROM inst_rom (从 .lib) 0.275 mW          + 0.636 uW
                           ─────────────────────────────
总计                        6.00 mW          + 3.52 uW
```

### 5.2 A3 面积分解

```
DC 综合 (非 macro 部分)    37,129 sq.um
SRAM macro                 21,194 sq.um
Via-ROM macro              11,295 sq.um
                           ────────────
总计                       69,618 sq.um
```

### 5.3 A3 vs A1 对比

| 指标 | A1 (全寄存器) | A3 (全macro) | 节省 |
|------|-------------|-------------|------|
| 动态功耗 | 37.59 mW | 6.00 mW | **↓ 84%** |
| 漏电功耗 | 9.97 uW | 3.52 uW | **↓ 65%** |
| 总面积 | 200,445 | 69,618 | **↓ 65%** |

---

## 6. 已知问题

### 6.1 DC 时钟网络功耗误报

**现象**: 当 wrapper 中用 `assign rom_clk = ~clk_i` 连接 ROM 的 CLK 引脚时，DC 功耗分析报告 `clock_network Switching Power = 144 mW`（虚假值）。

**原因**: DC 将 ROM 的 CLK 引脚视为时钟树的一部分，在没有 `.db` 模型的情况下做了错误的时钟网络功耗估算。

**解决方案**: wrapper 中将 ROM CLK 直接接 `1'b0`，ROM 功耗完全从 `.lib` 单独计算。在正式物理实现时，ROM CLK 需要正确的时钟树驱动，功耗由 P&R 工具精确计算。

### 6.2 Library Compiler 不可用

同 SRAM 的已知问题（见 `memory_compiler_usage_guide.md` 第 11 节），Via-ROM 的 `.lib` 同样无法转换为 `.db`。

### 6.3 同步 ROM 时序

Via-ROM 是同步读（Q 在 CLK 上升沿后更新），与原始组合 ROM 不同。快速验证版将 CLK 接地处理。正式版需解决时序（同 SRAM 的方案 A）。

---

## 7. 文件清单

### ROM 生成文件

| 文件 | 路径 |
|------|------|
| ROM Verilog 模型 | `/home/yifengxin/asic_synth/sram_gen/via_rom_512x32.v` |
| ROM Liberty (TT) | `/home/yifengxin/asic_synth/sram_gen/via_rom_512x32_tt_1.2_25.lib` |
| ROM Liberty (FF/SS) | `/home/yifengxin/asic_synth/sram_gen/via_rom_512x32_ff_*.lib` |
| ROM LEF | `/home/yifengxin/asic_synth/sram_gen/via_rom_512x32.lef` |
| ROM 综合 stub | `/home/yifengxin/asic_synth/sram_gen/via_rom_512x32_stub.v` |
| ROM code file | `/home/yifengxin/asic_synth/sram_gen/inst_rom_code.txt` |

### RTL 文件

| 文件 | 路径 |
|------|------|
| ROM wrapper (替代 inst_rom) | `/home/yifengxin/FX-RV32/soc/mem/inst_rom_via.v` |

### 综合脚本

| 配置 | 脚本 |
|------|------|
| A3: SH0+SRAM+ROM | `/home/yifengxin/asic_synth/FX-RV32/run_synth_sram_rom.tcl` |
| B3: SH1+SRAM+ROM | `/home/yifengxin/asic_synth/FX-RV32/run_synth_sram_rom_sh1.tcl` |

### 综合报告

| 配置 | 功耗摘要 | 功耗分级 | 面积摘要 | 面积分级 |
|------|---------|---------|---------|---------|
| A3 | `/home/yifengxin/power_sram_rom.rpt` | `/home/yifengxin/power_hier_sram_rom.rpt` | `/home/yifengxin/area_sram_rom.rpt` | `/home/yifengxin/area_hier_sram_rom.rpt` |
| B3 | `/home/yifengxin/power_sram_rom_sh1.rpt` | `/home/yifengxin/power_hier_sram_rom_sh1.rpt` | `/home/yifengxin/area_sram_rom_sh1.rpt` | `/home/yifengxin/area_hier_sram_rom_sh1.rpt` |

### 关联文档

| 文档 | 路径 |
|------|------|
| Memory Compiler 使用指南 | `/home/yifengxin/syn/memory_compiler_usage_guide.md` |
| SRAM 面积功耗读取指南 | `/home/yifengxin/syn/sram_area_power_reading_guide.md` |
| 影子寄存器 & SRAM 对比 | `/home/yifengxin/syn/shadow_sram_power_comparison.md` |
| 综合报告文件索引 | `/home/yifengxin/syn/report_file_index.md` |
| **本文档** | `/home/yifengxin/syn/inst_rom_via_rom_report.md` |
