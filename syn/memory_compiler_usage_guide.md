# SMIC 55nm Memory Compiler 使用指南

**编写日期**: 2026-06-10
**作者**: Yi Fengxin, Beihang University
**适用设计**: FX-RV32 (RISC-V SoC)
**工艺**: SMIC 55nm Logic Low Leakage (S55NLL)

---

## 目录

1. [工具概览](#1-工具概览)
2. [文件路径](#2-文件路径)
3. [环境要求](#3-环境要求)
4. [S55NLLG1PH 单口 SRAM 编译器](#4-s55nllg1ph-单口-sram-编译器)
5. [命令行生成教程](#5-命令行生成教程)
6. [GUI 方式生成](#6-gui-方式生成)
7. [输出文件说明](#7-输出文件说明)
8. [SRAM 接口信号](#8-sram-接口信号)
9. [集成到 Design Compiler 综合流程](#9-集成到-design-compiler-综合流程)
10. [实战案例: data_ram 替换](#10-实战案例-data_ram-替换)
11. [已知问题与注意事项](#11-已知问题与注意事项)

---

## 1. 工具概览

SMIC 55nm 工艺提供了多款 Memory Compiler，可以根据需求生成不同规格的 SRAM/Register-File 硬核宏（hard macro）。生成的宏包含完整的时序模型、功耗模型、物理版图和仿真模型。

### 可用 Compiler 列表

| Compiler 名称 | 类型 | 路径 |
|--------------|------|------|
| **S55NLLG1PH** | 单口 Register-File (高速) | `S55NLLG1PH/` |
| **S55NLLG2PH** | 双口 Register-File | `S55NLLG2PH/v1p1pb_CDK/` |
| **S55NLLGDPH** | 双口 Register-File | `S55NLLGDPH/` |
| **S55NLLGSPH** | 单口 Register-File | `S55NLLGSPH/v1p1pa/` |
| **S55NLLGVMH** | Via ROM | `S55NLLGVMH/v1p1/` |

---

## 2. 文件路径

### Memory Compiler 主目录

```
/opt/eda/pdk/smic55/memory_compiler/
├── S55NLLG1PH/                    # 单口高速 Register-File
│   ├── S55NLLG1PH.jar             # Java 可执行程序
│   ├── S55NLLG1PH.csh             # C Shell 启动脚本 (java -jar S55NLLG1PH.jar&)
│   ├── S55NLLG1PH.notes           # 发布说明 (版本、DRC/LVS信息)
│   └── S55NLLG1PH_ug.pdf          # 用户手册 (24页)
├── S55NLLG2PH/
│   └── v1p1pb_CDK/
│       ├── S55NLLG2PH.jar
│       └── S55NLLG2PH_ug.pdf
├── S55NLLGDPH/
│   ├── S55NLLGDPH.jar
│   └── S55NLLGDPH_ug.pdf
├── S55NLLGSPH/
│   └── v1p1pa/
│       ├── S55NLLGSPH.jar
│       └── S55NLLGSPH_ug.pdf
└── S55NLLGVMH/
    └── v1p1/
        ├── S55NLLGVMH.jar
        └── S55NLLGVMH_ug.pdf
```

### 标准单元库路径

```
/home/yifengxin/smic55_rvt_lib/synopsys/1.2v/
├── scc55nll_hd_rvt_tt_v1p2_25c_basic.db    # 当前使用的 .db
├── scc55nll_hd_rvt_tt_v1p2_25c_ccs.db      # CCS 功耗模型 (更精确)
├── scc55nll_hd_rvt_tt_v1p2_25c_ecsm.db     # ECSM 模型
├── ... (ff/ss corners 等)
```

### 本项目 SRAM 生成输出目录

```
/home/yifengxin/asic_synth/sram_gen/
├── sram_512x32.v                  # Verilog 仿真模型 (带时序检查)
├── sram_512x32_stub.v             # DC 综合用 stub (本项目手写)
├── sram_512x32.lef                # LEF 物理库 (给 P&R 工具用)
├── sram_512x32_tt_1.2_25.lib      # Liberty 时序功耗模型 (TT 25°C)
├── sram_512x32_ff_1.32_-40.lib    # FF corner
├── sram_512x32_ff_1.32_0.lib
├── sram_512x32_ff_1.32_125.lib
├── sram_512x32_ss_1.08_-40.lib    # SS corner
├── sram_512x32_ss_1.08_125.lib
├── data_ram_sram.v                # SRAM wrapper (项目RTL)
└── soc_top_sram*                  # SRAM版综合输出
```

---

## 3. 环境要求

- **Java**: JDK 1.6 或更高版本
- **操作系统**: Linux x86_64
- **磁盘空间**: 每个 SRAM 实例约 1-5 MB

### 验证 Java 版本

```bash
java -version
# 本服务器: OpenJDK 1.8.0_302
```

---

## 4. S55NLLG1PH 单口 SRAM 编译器

### 4.1 IP 信息

| 属性 | 值 |
|------|-----|
| IP Code | S55NLLG1PH |
| 类型 | Standard Memory Compiler |
| 工艺 | 55nm Logic Low Leakage Process |
| GDS 版本 | V1.3 |
| DK 版本 | V1.3.a |
| 发布日期 | 2015-02-12 |

### 4.2 主要特性

- 高速、高密度
- 优化的电源分配方案（Over the cell power routing）
- **支持 bit-write 功能**（逐 bit 写掩码，适用于 SB/SH/SW 指令）
- 低动态功耗和低漏电功耗
- 为 Synopsys 等高级设计工具提供时序和功耗模型
- 输出多种格式: Verilog, Liberty (.lib), LEF, GDSII, CDL (LVS), MBIST

### 4.3 可配置参数

| 参数 | 说明 | 可选值 |
|------|------|--------|
| `-words` | 字数 (深度) | 根据位宽和 mux 有不同范围 |
| `-bits` | 位宽 | 根据 words 和 mux 有不同范围 |
| `-mux` | 列复用因子 | **1, 2, 4** (控制版图宽高比) |
| `-bitwrite` | 位写使能 | on/off (toggle) |

**mux 参数对版图的影响：**
- `mux=1`: 最窄最高（适合高度受限的场景）
- `mux=4`: 最宽最矮（适合宽度受限的场景）

### 4.4 输出格式选项

| 命令行参数 | 输出文件 | 用途 |
|-----------|---------|------|
| `-v` | `.v` | Verilog 仿真模型 |
| `-lib` | `_corner.lib` | Liberty 时序/功耗模型 (多 corner) |
| `-lef` | `.lef` | LEF 物理库 (Place & Route) |
| `-gds` | `.gds` | GDSII 版图 (流片) |
| `-cdl` | `.cdl` | CDL 网表 (LVS 验证) |
| `-pdf` | `.pdf` | 数据手册 (自动生成) |
| `-mbist` | — | MBIST 模型 (DFT) |

---

## 5. 命令行生成教程

### 5.1 基本语法

```bash
cd /opt/eda/pdk/smic55/memory_compiler/S55NLLG1PH
java -jar S55NLLG1PH.jar [options...]
```

### 5.2 完整选项

```
java -jar S55NLLG1PH.jar [options...]
  -help          显示帮助信息
  -bits VAL      位宽
  -words VAL     字数 (深度)
  -mux VAL       列复用因子 (1, 2, 4)
  -bitwrite      使能 bit-write
  -v             生成 Verilog 模型
  -lib           生成 Synopsys .lib 模型 (多 corner 自动生成)
  -lef           生成 LEF 物理库
  -gds           生成 GDSII 版图
  -cdl           生成 LVS 网表
  -pdf           生成 PDF 数据手册
  -mbist         生成 MBIST 模型
  -savepath VAL  指定输出目录
  -instname VAL  指定实例名称
```

### 5.3 示例: 生成 512×32 单口 SRAM (本项目实战)

```bash
# 创建输出目录
mkdir -p /home/yifengxin/asic_synth/sram_gen

# 生成 SRAM (512 words × 32 bits, mux=4, bit-write ON)
cd /opt/eda/pdk/smic55/memory_compiler/S55NLLG1PH
java -jar S55NLLG1PH.jar \
    -words 512 \
    -mux 4 \
    -bits 32 \
    -bitwrite \
    -v \
    -lib \
    -lef \
    -savepath /home/yifengxin/asic_synth/sram_gen \
    -instname sram_512x32
```

### 5.4 生成过程中的输出

```
Generating sram_512x32.v     ... Done.
Generating sram_512x32.lib   ... Done.
Generating sram_512x32.lef   ... Done.
```

### 5.5 附加输出: 生成 GDSII (如需流片)

```bash
java -jar S55NLLG1PH.jar \
    -words 512 -mux 4 -bits 32 -bitwrite \
    -gds -cdl -pdf \
    -savepath /home/yifengxin/asic_synth/sram_gen \
    -instname sram_512x32
```

---

## 6. GUI 方式生成

如果服务器有 X11 转发，可以使用图形界面：

```bash
cd /opt/eda/pdk/smic55/memory_compiler/S55NLLG1PH
java -jar S55NLLG1PH.jar &
```

GUI 操作步骤：
1. 在 **Memory Parameters** 面板选择 Words、Mux、Bits
2. 勾选 **Bit-Write** checkbox (需要字节/半字写入时)
3. 点击 **Preview** 查看面积/时序预览
4. 在 **Output View** 面板勾选需要的输出格式
5. 点击 **Generate**，选择保存路径
6. 在 **Message** 面板查看生成状态

---

## 7. 输出文件说明

### 7.1 Verilog 仿真模型 (.v)

```
sram_512x32.v
```

- 包含完整的时序检查 (`specify` 块)
- 支持 X 态传播，适用于门级仿真
- **注意: 不可直接用于综合**！模型含 `!==` 运算符，DC 无法编译

### 7.2 Liberty 模型 (.lib)

```
sram_512x32_tt_1.2_25.lib      # Typical, 1.2V, 25°C
sram_512x32_ff_1.32_-40.lib    # Fast, 1.32V, -40°C
sram_512x32_ff_1.32_0.lib      # Fast, 1.32V, 0°C
sram_512x32_ff_1.32_125.lib    # Fast, 1.32V, 125°C
sram_512x32_ss_1.08_-40.lib    # Slow, 1.08V, -40°C
sram_512x32_ss_1.08_125.lib    # Slow, 1.08V, 125°C
```

- `.lib` 是 ASCII 文本格式的 Liberty 时序/功耗模型
- DC 需要 `.db` 二进制格式 → 需用 Library Compiler 转换: `read_lib → write_lib -format db`
- **已知问题**: 本服务器 LC (Library Compiler) 工具链有兼容性问题，`.lib → .db` 转换会崩溃 (见第11节)

每个 `.lib` 文件包含:
- `cell_leakage_power`: 漏电功耗 (mW)
- `area`: 版图面积 (sq.um)
- `internal_power()`: 内部功耗表 (读/写能量, pJ/access)
- `timing()`: 时序弧 (clock-to-Q delay, setup/hold)
- `capacitance`: 引脚电容 (pf)

### 7.3 LEF 物理库 (.lef)

```
sram_512x32.lef
```

- 给 IC Compiler II / Innovus 等 P&R 工具用
- 包含宏的物理尺寸、引脚位置、阻挡层信息

### 7.4 GDSII 版图 (.gds)

- 用于最终流片的物理版图
- 需通过 DRC/LVS 验证

### 7.5 CDL 网表 (.cdl)

- 晶体管级网表，用于 LVS (Layout vs. Schematic) 验证

---

## 8. SRAM 接口信号

### 8.1 端口列表

```
module sram_512x32 (
    Q,      // output [31:0]  读数据输出 (寄存器输出)
    CLK,    // input          时钟
    CEN,    // input          芯片使能 (0=有效, 低有效)
    WEN,    // input          写使能 (1=读, 0=写, 低有效为写)
    BWEN,   // input  [31:0]  逐bit写掩码 (0=写该bit, 1=保持)
    A,      // input  [8:0]   字地址 (9 bits for 512 words)
    D       // input  [31:0]  写数据
);
```

### 8.2 真值表

| CEN | WEN | BWEN[i] | 操作 |
|-----|-----|---------|------|
| 1 | X | X | 无操作 (deslected) |
| 0 | 1 | 1 | **读**: Q = mem[A] |
| 0 | 0 | 0 | **写**: mem[A][i] = D[i]; Q[i] = 新值 |
| 0 | 0 | 1 | **保持**: mem[A][i] 不变; Q[i] = 旧值 |
| 0 | X | X (部分X) | 未知行为 |

### 8.3 关键时序参数 (tt_1.2_25)

| 参数 | 符号 | 典型值 | 说明 |
|------|------|--------|------|
| 时钟周期 | Tcyc | ~1.54 ns | 最小周期 |
| 访问时间 | Ta | ~0.85 ns | Clock-to-Q 延迟 |
| 地址 Setup | Tas | ~0.50 ns | 地址在时钟前的建立时间 |
| 地址 Hold | Tah | ~0.25 ns | 地址在时钟后的保持时间 |
| 数据 Setup | Tds | ~0.50 ns | 数据在时钟前的建立时间 |

### 8.4 与寄存器型 data_ram 的接口差异

| 信号 | 寄存器 data_ram | SRAM macro | 转换方式 |
|------|----------------|------------|---------|
| 地址 | `addr_i[31:0]` 字节地址 | `A[8:0]` 字地址 | `addr_i[10:2]` → `A` |
| 读数据 | `rdata_o` 组合输出 | `Q` **同步输出** | **关键时序差异** |
| 读使能 | `re_i` (高有效) | `CEN` (低有效) | `CEN = ~(re_i \| we_i)` |
| 写使能 | `we_i` (高有效) | `WEN` (低有效) | `WEN = ~we_i` |
| 字节控制 | `width_i[2:0]` + `addr_i[1:0]` | `BWEN[31:0]` per-bit | 译码转换 |
| 写数据 | `wdata_i` | `D` | 直连 |

---

## 9. 集成到 Design Compiler 综合流程

### 9.1 完整流程

```
Memory Compiler → .lib → (LC: read_lib → write_lib -format db) → .db → DC link_library
                                    ↓ (本服务器不可用)
Memory Compiler → .v (仿真用, 不能综合)
                → 手写 stub → DC analyze (综合 black box)
                → .lef → P&R 工具
                → .gds → 最终流片
```

### 9.2 当前验证方案 (快速版)

由于本服务器 Library Compiler 不可用，采用以下快速验证方案：

1. **创建综合 stub** (`sram_512x32_stub.v`): 只含端口声明、无内部逻辑的黑盒模块
2. **创建 wrapper** (`data_ram_sram.v`): 完成地址/控制信号转换
3. **综合时**: SRAM 为 black box，设置 `dont_touch`
4. **功耗/面积计算**: 从 `.lib` 手动提取，与 DC 报告的非 SRAM 部分相加

### 9.3 综合脚本示例

见 `/home/yifengxin/asic_synth/FX-RV32/run_synth_sram.tcl`

关键设置:
```tcl
# SRAM stub 加入 analyze 列表
analyze -format verilog -lib WORK [list \
    /home/yifengxin/asic_synth/sram_gen/sram_512x32_stub.v \
    ... ]

# dont_touch SRAM 实例
set_dont_touch [get_cells -hierarchical *u_sram*] true

# 功耗分析必须在 compile 前使能
set power_enable_analysis TRUE
```

### 9.4 正式方案 (待解决 LC 问题后)

```tcl
# 1. 转换 .lib → .db
read_lib sram_512x32_tt_1.2_25.lib
write_lib sram_512x32 -format db -output sram_512x32_tt_1p2_25c.db

# 2. DC 脚本中 link
set link_library [list * $target_library sram_512x32_tt_1p2_25c.db]
```

---

## 10. 实战案例: data_ram 替换

### 10.1 原始 data_ram

- `soc/mem/data_ram.v`: 512×32-bit = 2KB
- 实现方式: `reg [31:0] mem [0:511]` + 组合读写逻辑
- 支持 SB/SH/SW 字节/半字写入, LB/LH/LW/LBU/LHU 读取

### 10.2 替换为 SRAM

文件: `soc/mem/data_ram_sram.v`

关键设计点:
1. **地址转换**: 字节地址 `addr_i[31:2]` → 字地址 `A[8:0]`
2. **BWEN 生成**: `width_i` + `addr_i[1:0]` 译码为 32-bit per-bit 写掩码
3. **时钟方案** (快速验证): SRAM 用 `~clk_i` (下降沿), 读数据在下一个上升沿前稳定
4. **读数据扩展**: 从 32-bit Q 中提取字节/半字并做符号扩展

### 10.3 对比结果 (200MHz, tt_v1p2_25c, toggle_rate=0.1)

| 指标 | 寄存器版 | SRAM版 | 改善 |
|------|----------|--------|------|
| **data_ram 面积** | ~163,317 sq.um | ~21,194 sq.um | **↓ 87%** |
| **整芯片面积** | 200,445 sq.um | 58,322 sq.um | **↓ 71%** |
| **data_ram 动态功耗** | 32.060 mW | 0.213 mW | **↓ 150倍** |
| **data_ram 漏电功耗** | 8.083 uW | 0.993 uW | **↓ 8倍** |
| **整芯片总功耗** | 37.60 mW | 5.75 mW | **↓ 85%** |

### 10.4 SRAM 自身功耗分解 (200MHz, 10% 活动因子)

| 功耗来源 | 能量/操作 | 功耗 |
|----------|----------|------|
| 读操作 (CLK + read path) | 11.788 pJ | 0.16 mW |
| 写操作 (CLK + write path) | 7.976 pJ | 0.05 mW |
| 平均 (70%读/30%写) | 10.64 pJ | 0.21 mW |
| 漏电 | — | 0.001 mW |
| **合计** | — | **0.21 mW** |

---

## 11. 已知问题与注意事项

### 11.1 Library Compiler (.lib → .db) 转换问题

**现象**: `lc_shell` (R-2020.09-SP3 和 O-2018.06-SP1) 在处理 SMIC 55nm Memory Compiler 生成的 `.lib` 文件时崩溃 (SIGSEGV, error code 11)。

**可能原因**:
1. 本服务器操作系统为 CentOS/RHEL 7 (kernel 3.10), 而 LC R-2020.09 适配 RHEL 8
2. SMIC .lib 使用了较新的 Liberty 语法 (如 `type` 定义、`base_type : array` 等)，可能与旧版 LC 不兼容
3. 许可限制 (`dc_shell` 的 `read_lib` 报 "not licensed for 'db'")

**当前 workaround**: 手工提取 .lib 关键数据 + DC 黑盒综合 (见第9.2节)

**建议的解决方向**:
- 在 RHEL 8 环境中运行 LC
- 使用更新版本的 Library Compiler
- 联系 SMIC 获取可直接使用的 `.db` 文件
- 或使用第三方工具 (如 Silvaco) 转换 Liberty 格式

### 11.2 同步读时序问题

SRAM 是**同步读** (Q 在时钟沿后更新), 而原 data_ram 是**组合读** (地址变化立即更新输出)。直接替换会导致 mem_wb_reg 在同一时钟沿捕获旧数据。

**快速验证方案 (方案 B)**: SRAM 用下降沿时钟 → Q 在 negedge 后 ~1ns 稳定 → posedge 捕获 OK
**正式方案 (方案 A)**: 增加 1 级流水寄存器 (MEM 多 1 拍), 利用已有的 load-use stall 机制

### 11.3 Stub 综合限制

使用 stub 综合时:
- SRAM 内部功耗不计入 DC 报告 (需手动加)
- SRAM 输入/输出引脚电容不计入 (影响外围电路 timing)
- 需手动计算 total power = DC报告(非SRAM) + SRAM数据(来自.lib)

---

## 附录: 相关文件清单

| 文件 | 路径 | 说明 |
|------|------|------|
| Memory Compiler 主程序 | `/opt/eda/pdk/smic55/memory_compiler/S55NLLG1PH/S55NLLG1PH.jar` | Java 可执行 |
| 用户手册 | `/opt/eda/pdk/smic55/memory_compiler/S55NLLG1PH/S55NLLG1PH_ug.pdf` | 24页 PDF |
| 发布说明 | `/opt/eda/pdk/smic55/memory_compiler/S55NLLG1PH/S55NLLG1PH.notes` | 版本/DRC/LVS 信息 |
| SRAM Verilog 模型 | `/home/yifengxin/asic_synth/sram_gen/sram_512x32.v` | 仿真用 |
| SRAM 综合 stub | `/home/yifengxin/asic_synth/sram_gen/sram_512x32_stub.v` | DC 综合用 |
| SRAM Liberty 模型 | `/home/yifengxin/asic_synth/sram_gen/sram_512x32_tt_1.2_25.lib` | 时序/功耗 |
| SRAM LEF 物理库 | `/home/yifengxin/asic_synth/sram_gen/sram_512x32.lef` | P&R 用 |
| SRAM wrapper | `/home/yifengxin/FX-RV32/soc/mem/data_ram_sram.v` | RTL |
| SRAM 综合脚本 | `/home/yifengxin/asic_synth/FX-RV32/run_synth_sram.tcl` | DC TCL |
| SRAM 综合输出 | `/home/yifengxin/asic_synth/sram_gen/soc_top_sram.ddc` | DC 数据库 |
| 功耗修复文档 | `/home/yifengxin/power_report_fix.md` | DC 功耗报告修复记录 |
