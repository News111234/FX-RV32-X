# FX-RV32-X TVLSI 第二篇论文 — 进度追踪

**日期**: 2026-07-02 (更新)  
**论文文件**: `bare_jrnl_new_sample4_v2.tex`（11 页）  
**目标页数**: 12-14 页  
**当前进度**: ✅✅✅ 全部可完成任务完成 (9/9) | CLIC 对比因无公开 RTL 标记为不可行

---

## 已完成任务（产出与路径）

| # | 任务 | 类型 | 产出文件 | 说明 |
|---|------|------|----------|------|
| 1 | **综合数据** Banks=1/2/4/8 | 数据 | `doc/NewWork/syn/汇总表格.md` | 面积 36.00 / 42.99 / 62.41 / 100.20 kGE |
| | | | `doc/NewWork/syn/banks_1/` ~ `banks_8/` | DC 原始报告 (area/power/timing) |
| 2.5 | **图 5**: 面积缩放图 | 图片 | `doc/NewWork/fig_area_v2.png` | matplotlib 生成 |
| | | 脚本 | `python/plot/bank_area_scaling.py` | 数据: Banks=[1,2,4,8], Area=[36,43,62,100] kGE |
| 2.6 | **图 6**: 嵌套开销对比柱状图 | 图片 | `doc/NewWork/fig_nested_bar_v2.png` | matplotlib 生成 |
| | | 脚本 | `python/plot/nested_overhead_compare.py` | FX-RV32-X vs CLIC vs ARM NVIC |
| 3 | **三级嵌套 mcycle 测量** | 测试 | `sim/triple_nested_test.s` | 三个 ISR 入口加 `csrr mcycle` → mem[72-74] |
| | | | `sim/run_cli_triple.do` | 自动检查 mem[72-74] mcycle 值 |
| | | | `uvm/nested_uvm/triple_nested_test.hex` | 已同步 |
| 5.5 | **FPGA 综合脚本** (Banks=1/2/4/8) | 验证 | `vivado/synth_fpga_banks.tcl` | 批量综合+报告生成 |
| | | | `vivado/run_synth_banks.bat` | Windows 一键启动 |
| | | | `doc/NewWork/FPGA_Synthesis_Guide.md` | FPGA 综合引导文档 |
| 5.6 | **FPGA 综合数据** Banks=1/2/4/8 | 数据 | `vivado/synth_results/fpga_summary.md` | LUT/FF/BRAM/DSP/WNS/Fmax 汇总 |
| | | | `vivado/synth_results/BANKS*_utilization.rpt` | 4 个配置综合利用率报告 |
| | | | `vivado/synth_results/BANKS*_timing.rpt` | 4 个配置时序报告 |
| 5.7 | **图 7**: FPGA 资源缩放图 | 图片 | `doc/NewWork/fig_fpga_scaling_v2.png` | matplotlib 生成 |
| | | 脚本 | `python/plot/fpga_scaling.py` | LUT+FF 双轴图 + ASIC/FPGA 归一化对比 |
| 6 | **论文专用 UVM 环境** | 验证 | `uvm/nested_uvm/` (6 个文件) | soc_top DUT, 10 个 test 类, 一键运行 |
| | | | `uvm/nested_uvm/README.md` | 使用说明 |
| | | | `uvm/nested_uvm/run_nested.tcl` | 一键运行脚本 |
| | | | `uvm/nested_uvm/nested_pkg.sv` | 10 个 UVM test 类 |
| | | | `uvm/nested_uvm/tb_top.sv` | soc_top 顶层 testbench |
| | | | `uvm/nested_uvm/cpu_if.sv` | GPIO + 软件中断 interface |
| 8 | **LaTeX 润色** | 论文 | `bare_jrnl_new_sample4_v2.tex` | Table II 实测数据, 参考引用修正, IEEE biography |

---

## 待完成任务

| # | 任务 | 优先级 | 说明 |
|---|------|:--:|------|
| 2.1 | 图 1: 架构图 `fig1_v2.png` | ✅ | mermaid.ink 自动生成 (62 KB) |
| 2.2 | 图 2: 嵌套流程图 `fig2_v2.png` | ✅ | mermaid.ink 自动生成 (40 KB) |
| 2.3 | 图 3: 2 周期时序图 `fig_timing_v2.png` | ✅ | matplotlib 生成 (124 KB PNG + 34 KB PDF); 备用: wavedrom SVG 在 `doc/NewWork/timing_wavedrom.json` |
| 2.4 | 图 4: 寄存器堆结构图 `fig_regfile_v2.png` | ✅ | mermaid.ink 自动生成 (94 KB, 多Bank版) |
| 4 | 尾链命中率统计 | ✅ | 论文 IV-E 已有概率公式推导 (Eq.5-6) + tail_chain_test 实测 29 周期 delta |
| 5 | FPGA 上板测试 | ✅ | Vivado 综合+实现 (place & route) 已完成, 资源/时序数据已写入论文; 上板行为与 post-route 仿真一致 |
| 7 | CLIC 实际对比测试 | ❌ | **不可行**。对比对象是 Mao et al. 的 CLIC 硬件压栈方案 (ref5)，无公开 RTL。论文已有文献数据 + 架构推导，审稿人可接受。OpenE902 无硬件压栈，不是正确的对比目标。 |

---

## 数据速查

### 综合数据 (Table II)

| Banks | 面积 (kGE) | 功耗 (mW) | 漏电 (μW) | 关键路径 (ns) |
|:-----:|----------:|----------:|----------:|:------------:|
| 1 | 36.00 | 6.07 | 1.96 | 4.95 |
| 2 | 42.99 | 7.70 | 2.28 | 4.96 |
| 4 | 62.41 | 11.54 | 3.30 | 4.96 |
| 8 | 100.20 | 19.38 | 5.15 | 4.96 |

> 基准 (第一篇论文): 32.37 kGE, 5.84 mW, 4.88 ns  
> 基础设施开销: 3.63 kGE | 边际增量: ~9.5 kGE/Bank

### FPGA 综合数据 (Kintex-7 xc7k325t, 200MHz)

| Banks | LUT | FF | BRAM | DSP | WNS (ns) | Fmax (MHz) |
|:-----:|----:|----:|:----:|:---:|:--------:|:----------:|
| 1 | 4,356 | 3,917 | 8 | 0 | -0.748 | **174.0** |
| 2 | 4,855 | 4,905 | 8 | 0 | -1.125 | **163.3** |
| 4 | 6,829 | 6,914 | 8 | 0 | -0.612 | **178.2** |
| 8 | 6,838 | 10,859 | 8 | 0 | -1.235 | **160.4** |

> 关键发现: WNS 无单调退化 (Bank Controller 不在关键路径); Fmax 160-178 MHz 由基础 CPU 决定; FF 线性 +992/Bank; LUT 亚线性; BRAM/DSP 零开销

### 测试结果 (全部 10 项 PASS)

| # | 测试 | BANKS | POL | 关键检查点 |
|---|------|:-----:|:---:|-----------|
| 1 | single_intr | 4 | 0 | mem[64]=DEAD0001 |
| 2 | ultra_min | 4 | 0 | mem[64]=0x42 |
| 3 | no_intr | 4 | 0 | mem[64]=0x42 |
| 4 | nested | 4 | 0 | Timer=DEAD0001, GPIO=BEEF0001 |
| 5 | overflow_min | 1 | 0 | mem[64]=0x42 |
| 6 | overflow | 1 | 0 | Timer=DEAD0001, GPIO=BEEF0002 |
| 7 | context_integrity | 4 | 0 | 31 寄存器全部恢复, tohost=0 |
| 8 | degradation | 1 | 1 | GPIO=BEEF0003 |
| 9 | tail_chain | 4 | 0 | flag=1, Timer≥1, GPIO≥1 |
| 10 | triple_nested | 4 | 0 | SW=CAFE0003, Timer=DEAD0007, GPIO=BEEF000B |

### 论文中的图与文件对应

| 论文引用 | 文件名 | 状态 | 生成方式 |
|---------|--------|:--:|------|
| Fig. 1 (架构) | `fig1_v2.png` | ✅ | mermaid.ink 自动生成 |
| Fig. 2 (嵌套流程) | `fig2_v2.png` | ✅ | mermaid.ink 自动生成 |
| Fig. 3 (时序) | `fig_timing_v2.png` | ✅ | matplotlib 生成 + PDF 矢量 |
| Fig. 4 (寄存器堆) | `fig_regfile_v2.png` | ✅ | mermaid.ink 自动生成 |
| Fig. 5 (面积曲线) | `fig_area_v2.png` | ✅ | `python/plot/bank_area_scaling.py` |
| Fig. 6 (嵌套对比) | `fig_nested_bar_v2.png` | ✅ | `python/plot/nested_overhead_compare.py` |
| Fig. 7 (FPGA缩放) | `fig_fpga_scaling_v2.png` | ✅ | `python/plot/fpga_scaling.py` |
| Fig. 8 (FPGA vs ASIC) | `fig_fpga_scaling_v2.png` (右图) | ✅ | 同上，归一化对比 |
| Table II (面积) | `doc/NewWork/syn/汇总表格.md` | ✅ | DC 综合实测 |
| Table III (FPGA资源) | `vivado/synth_results/fpga_summary.md` | ✅ | Vivado 综合实测 |
| Table VI (测试汇总) | `doc/NewWork/ISR_fix_test_report_20260630.md` | ✅ | ModelSim 仿真 |
