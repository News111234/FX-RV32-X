# FX-RV32-X 多 Bank 综合引导文档

**目的**: 在服务器上完成 Banks=2/4/8 的 DC 综合，收集面积/功耗/时序数据  
**使用方式**: 服务器上启动 Claude，读入本文档即可开始工作  
**报告输出路径**: `doc/NewWork/syn/`（本文档同级目录下的 syn 子文件夹）

---

## 1. 背景

FX-RV32-X 是一个支持优先级中断嵌套的多 Bank 影子寄存器扩展。第一篇 TVLSI 论文已发布 Banks=1 的综合数据（32.4 kGE, 5.84 mW, 4.88 ns）。第二篇论文需要 Banks=2/4/8 的综合数据来画面积缩放曲线。

### 多 Bank 机制简述

- 影子寄存器（Shadow Register）：31 个 32-bit 寄存器，中断时单周期并行锁存 x1-x31
- Bank：一组完整的影子寄存器副本。N 个 Bank = N 组 31×32-bit 寄存器
- Bank 指针：硬件计数器，指示当前嵌套深度。0=主程序，1=第一级 ISR，2=第二级
- 基线（Banks=1）：面积 32.4 kGE，等同于第一篇论文的 SHADOW_EN=1 配置
- 每个额外 Bank 的预期面积增量：约 7.5 kGE（31×32-bit flip-flops + 写控制逻辑）

### 需要跑的综合配置

| Banks | 参数值 | 说明 |
|:-----:|:-----:|------|
| 1 | `SHADOW_BANKS=1` | **已有数据，不需要重跑**。面积 32.4 kGE, 功耗 5.84 mW, 路径 4.88 ns |
| 2 | `SHADOW_BANKS=2` | 支持 1 级嵌套 |
| 4 | `SHADOW_BANKS=4` | 默认配置，支持 3 级嵌套 |
| 8 | `SHADOW_BANKS=8` | 支持 7 级嵌套 |

---

## 2. 环境确认

### 2.1 检查 DC 环境

```bash
which dc_shell
dc_shell -version
```

如果 `dc_shell` 不可用，检查：
```bash
# Synopsys Design Compiler 常见路径
ls /usr/synopsys/ 2>/dev/null
ls /opt/synopsys/ 2>/dev/null
ls /tools/synopsys/ 2>/dev/null
```

### 2.2 确认工作目录

```bash
cd D:/Path/RISC-V-TEST/Project/FX-RV32_CUSTOM   # Windows
# 或
cd /path/to/RISC-V-TEST/Project/FX-RV32_CUSTOM   # Linux
ls syn/run_synth.tcl   # 确认综合脚本存在
ls core/core_top.v     # 确认 RTL 源文件存在
```

### 2.3 确认输出目录

```bash
mkdir -p doc/NewWork/syn
```

所有综合报告将复制到此目录下，以 Bank 数量命名子文件夹：
```
doc/NewWork/syn/
├── banks_1/    # 已有数据（从 syn/report/ 复制）
├── banks_2/    # 本次生成
├── banks_4/    # 本次生成
└── banks_8/    # 本次生成
```

---

## 3. 需要修改的参数

多 Bank 参数 `SHADOW_BANKS` 在两个文件中独立定义，**必须同时修改且保持一致**：

### 文件 1: `core/core_top.v`

约第 18-20 行附近：

```verilog
module core_top #(
    parameter SHADOW_EN    = 1,
    parameter SHADOW_BANKS = 4,      // ← 修改此行
    parameter OVERFLOW_POLICY = 0
) (
```

### 文件 2: `core/interrupt/interrupt_pipeline.v`

约第 17 行附近：

```verilog
module interrupt_pipeline #(
    parameter SHADOW_EN    = 1,
    parameter SHADOW_BANKS = 4       // ← 修改此行
) (
```

### 综合时修改方式

每次跑综合前，修改上述两个文件中的 `SHADOW_BANKS` 值为目标值（2、4 或 8）。

**或者**，如果综合脚本支持 `-g` 参数传递 parameter 值（类似 Modelsim），可以直接：
```tcl
# 在 run_synth.tcl 中
set SHADOW_BANKS 2
```

如果脚本不支持，则直接编辑 Verilog 源文件。

---

## 4. 综合步骤

### 4.1 Banks=2

```bash
# 1. 修改参数
#    编辑 core/core_top.v → SHADOW_BANKS = 2
#    编辑 core/interrupt/interrupt_pipeline.v → SHADOW_BANKS = 2

# 2. 运行综合
cd syn
# 根据原有流程执行，可能是：
dc_shell -f run_synth.tcl
# 或者 source DC_command.txt 再用 dc_shell

# 3. 收集报告
mkdir -p ../doc/NewWork/syn/banks_2
cp report/area/area_hier*.rpt ../doc/NewWork/syn/banks_2/
cp report/power/power_hier*.rpt ../doc/NewWork/syn/banks_2/
cp report/timing/*.rpt ../doc/NewWork/syn/banks_2/
```

### 4.2 Banks=4

```bash
# 1. 修改参数为 4
# 2. 运行综合
# 3. 收集报告到 doc/NewWork/syn/banks_4/
```

### 4.3 Banks=8

```bash
# 1. 修改参数为 8
# 2. 运行综合
# 3. 收集报告到 doc/NewWork/syn/banks_8/
```

### 4.4 Banks=1（可选，用于验证）

如果怀疑环境差异导致 Banks=1 数据与第一篇论文不一致，可以重跑一次 Banks=1 作为基准：

```bash
# SHADOW_BANKS = 1
# 收集报告到 doc/NewWork/syn/banks_1/
```

---

## 5. 数据提取

综合完成后，从报告中提取以下数据，汇总到表格：

### 从面积报告提取

文件: `doc/NewWork/syn/banks_X/area_hier*.rpt`

找到 `core_top` 行，记录：
- **Cell Area** (总面积)
- 换算: 1 kGE = 1120 μm² (55nm SMIC 工艺)

示例格式：
```
core_top        36252.0 μm²  =  32.37 kGE
```

### 从功耗报告提取

文件: `doc/NewWork/syn/banks_X/power_hier*.rpt`

找到 `core_top` 行，记录：
- **Total Dynamic Power** (mW)
- **Leakage Power** (μW)

### 从时序报告提取

文件: `doc/NewWork/syn/banks_X/timing/*.rpt`

记录：
- **Critical Path** (ns)
- **Max Frequency** = 1 / Critical_Path (MHz)

### 汇总表模板

综合完成后，将数据填入此表：

| Banks | 面积 (μm²) | 面积 (kGE) | 功耗 (mW) | 关键路径 (ns) | 最高频率 (MHz) |
|:-----:|----------|----------|----------|:-----------:|:------------:|
| 1 | 36,252 (已有) | 32.37 (已有) | 5.84 (已有) | 4.88 (已有) | 205 (已有) |
| 2 | ? | ? | ? | ? | ? |
| 4 | ? | ? | ? | ? | ? |
| 8 | ? | ? | ? | ? | ? |

### 关键观察点

综合完成后，在报告中确认以下问题：

1. **面积是否线性增长？** 每个额外 Bank 应增加约 7.5 kGE（31×32-bit flip-flops）。如果增量显著偏离此值，检查是否有额外的组合逻辑被综合进去。

2. **关键路径是否基本不变？** Bank 选择 MUX 在寄存器堆写入路径上，不应在 ALU→数据 RAM 的关键路径上。预期变化 < 1%。

3. **功耗是否线性增长？** 每个额外 Bank 增加的 31 个 32-bit 寄存器带来额外的时钟树功耗（翻转率低——影子寄存器在中断时才激活）。

---

## 6. 综合完成后

### 6.1 验证数据合理性

- Banks=4 面积应约为 47-48 kGE (32.4 + 2×7.5)
- Banks=8 面积应约为 62-63 kGE (32.4 + 4×7.5)——注意 1→8 是增加 7 个 Bank
- 关键路径波动应 < 0.05 ns (< 1%)

### 6.2 更新论文

用实际数据替换 `bare_jrnl_new_sample4_v2.tex` 中的 Table II 估算值，并更新 IV-B 节的三点分析。

### 6.3 生成面积缩放图

用 Python matplotlib 画 Banks vs Area 柱状图，保存为 `fig_area_v2.png`。

---

## 7. 常见问题

**Q: DC 综合报 "cannot elaborate" 错误？**
第一篇论文 CLAUDE.md 中提到三个 Verilog 语法错误（`core_top.v`, `id_top.v`, `id_ex_reg.v` 的端口连接问题）。如果这些错误未修复，DC 会把子模块当成 black box，面积数据会缺失。检查方法：
```bash
grep -i "black box" syn/report/*.log
```
如果有 black box，需要先修复 RTL 语法，或者让 DC 忽略这些错误继续（面积数据可能不完整）。

**Q: SHADOW_BANKS 改大后综合时间显著增加？**
正常。Banks=8 有 8×31=248 个 32-bit 寄存器（总共 7936 个 flip-flop），综合工具需要更多时间优化。预计 Banks=2 约 15 分钟，Banks=4 约 20 分钟，Banks=8 约 30 分钟（取决于服务器性能）。

**Q: 综合结果和预期差异大？**
首先检查 SHADOW_BANKS 在两个文件中是否一致。如果不一致，一个模块按 Banks=4 例化、另一个按 Banks=2 例化，综合会出错或产生意外面积。

**Q: 服务器是 Linux，路径不对？**
本文档中的路径使用 Unix 风格（`/`）。Windows 和 Linux 的路径分隔符不同，根据实际情况调整。综合脚本 `run_synth.tcl` 中可能使用了 `../core/` 等相对路径，确认它们在服务器上的相对位置不变。

---

## 8. 参考文档

| 文档 | 路径 | 内容 |
|------|------|------|
| 第一篇 TVLSI 论文 | `bare_jrnl_new_sample4.tex` | 已有综合数据 (Table II, III) |
| 第二篇 TVLSI 论文 | `bare_jrnl_new_sample4_v2.tex` | 待填入新数据 |
| 综合脚本 | `syn/run_synth.tcl` | DC 综合 TCL 脚本 |
| 综合旧报告索引 | `syn/report_file_index.md` | 已有 Banks=1 报告的索引 |
| 面积报告示例 | `syn/report/area/area_hier_en0.rpt` | SHADOW_EN=0 的面积数据 |
| 面积报告示例 | `syn/report/area/area_hier_sh1.rpt` | SHADOW_EN=1 (Banks=1) 的面积数据 |
| 论文待办清单 | `doc/NewWork/TVLSI_Paper2_TODO.md` | 全部待办事项 |

---

**服务器启动 Claude 后的第一步**: 确认 DC 环境可用，检查 `syn/run_synth.tcl` 是否能正常运行。如果一切就绪，从 Banks=2 开始跑。
