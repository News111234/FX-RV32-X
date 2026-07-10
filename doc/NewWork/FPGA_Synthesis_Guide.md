# FX-RV32-X FPGA 原型验证 — Vivado 综合指南

**目标**: 在 Kintex-7 FPGA 上验证多 Bank 影子寄存器的资源开销和时序  
**设备**: Xilinx Kintex-7 xc7k325tffg900-2 (Genesys 2 开发板)  
**时钟**: 200 MHz (LVDS 差分输入)

---

## 前置条件

1. Vivado 2023.x+ 已安装
2. 确保 Vivado 在 PATH 中，或修改 `run_synth_banks.bat` 中的 `VIVADO_BIN` 路径

---

## 快速开始

### 方式 1: 批量综合 (推荐，获取论文数据)

```batch
cd vivado
run_synth_banks.bat           # 仅综合 4 个配置，约 20 分钟
run_synth_banks.bat impl      # 综合+实现 4 个配置，约 2 小时
```

脚本自动执行：
- Banks=1 (基准单 Bank) → `BANKS1_POL0_*`
- Banks=2 → `BANKS2_POL0_*`
- Banks=4 (默认) → `BANKS4_POL0_*`
- Banks=8 → `BANKS8_POL0_*`

每个配置：
1. 创建 in-memory 工程
2. 添加所有 RTL 源文件
3. `synth_design -generic {SHADOW_BANKS=N OVERFLOW_POLICY=0}`
4. 报告利用率 + 时序
5. (可选) opt + place + route

### 方式 2: GUI 工程 (调试/单配置分析)

```batch
cd vivado
run_synth_banks.bat gui       # 打开 GUI 工程
```

在 GUI 中可手动修改参数、查看原理图、分析关键路径。

### 方式 3: TCL 直接调用

```tcl
# 在 Vivado Tcl Console 中:
cd vivado
source synth_fpga_banks.tcl
# 带参数:
# vivado -mode batch -source vivado/synth_fpga_banks.tcl -tclargs -impl 1
```

---

## 输出文件

结果保存在 `vivado/synth_results/`：

| 文件 | 内容 |
|------|------|
| `fpga_summary.md` | 汇总表 (含 ASIC vs FPGA 对比) |
| `BANKS1_POL0_utilization.rpt` | Banks=1 资源利用率 |
| `BANKS1_POL0_timing.rpt` | Banks=1 时序报告 |
| ... | (Banks=2/4/8 同理) |

---

## 技术说明

### 参数传递链路

```
soc_top_fpga (TOP)
  ├── SHADOW_BANKS    →  soc_top  →  core_top  →  regfile / interrupt_pipeline / bank_controller
  └── OVERFLOW_POLICY →  soc_top  →  core_top  →  bank_controller
```

Vivado `synth_design -generic` 设置顶层参数 → 自动向下传递。

### 关键模块

| 模块 | 新增 | 说明 |
|------|:--:|------|
| `core/interrupt/bank_controller.v` | ✅ | 纯组合逻辑 Bank 分配/释放/尾链/降级决策 |
| `core/id/regfile.v` | 修改 | `SHADOW_BANKS` 参数化寄存器堆 |
| `core/interrupt/interrupt_pipeline.v` | 修改 | `SHADOW_BANKS` 参数化 Bank 指针 |
| `core/core_top.v` | 修改 | 传递 `SHADOW_BANKS` / `OVERFLOW_POLICY` |
| `soc/top/soc_top.v` | 修改 | 传递参数到 core_top |
| `soc/top/soc_top_fpga.v` | 修改 | 顶层参数，供 Vivado -generic 覆盖 |

### 预期结果参考

基于 DC 55nm 综合数据，FPGA 上预期：
- Banks=1 → Banks=8 的 LUT 增长约 2.5-3×
- BRAM 数量不变 (影子寄存器用 FF 实现，非 BRAM)
- fmax 基本不变 (bank_controller 是纯组合逻辑，不在关键路径上)
- 关键路径仍为 ALU + 转发 MUX 路径

---

## 故障排除

### Vivado 不在 PATH

编辑 `run_synth_banks.bat`，修改 VIVADO_BIN 为实际安装路径：
```batch
set VIVADO_BIN=C:\Xilinx\Vivado\2024.1\bin\vivado.bat
```

### synth_design 报错 "Unknown generic"

确保 `soc_top_fpga.v` 有 `SHADOW_BANKS` / `OVERFLOW_POLICY` 参数声明。
修复方法：重新运行 `vivado/create_project.tcl` 或检查 `soc/top/soc_top_fpga.v`。

### 时序不收敛 (WNS < 0)

1. 降低目标频率 (修改 `constraints.xdc` 中的 `create_clock -period`)
2. 使用 `Flow_PerfOptimized_high` 策略 (已配置)
3. 检查是否需要流水线优化

---

## 论文集成

综合完成后，将 `fpga_summary.md` 中的数据填入论文：
- **Table IV** (FPGA 资源占用): LUT/FF/BRAM/DSP 各列
- **Section V.C** (FPGA 实现): Fmax 讨论
- **Fig. 7**: 可新增 FPGA LUT/FF 随 Bank 数变化的柱状图 (参考 `python/plot/bank_area_scaling.py`)
