# Paper Figures — TVLSI Paper 2 (FX-RV32-X)

All 8 figures for `bare_jrnl_new_sample4_v2.tex`.

| 文件 | 论文引用 | 内容 | 生成方式 |
|------|:--:|------|------|
| `fig1_v2.png` | Fig. 1 | 多Bank影子寄存器整体架构 | mermaid.ink |
| `fig2_v2.png` | Fig. 2 | 两级中断嵌套流程 (P1-P5) | mermaid.ink |
| `fig_timing_v2.png` | Fig. 3 | 2周期中断响应时序图 | matplotlib |
| `fig_timing_v2.pdf` | Fig. 3 | 同上, PDF矢量版 | matplotlib |
| `fig_regfile_v2.png` | Fig. 4 | 多Bank寄存器堆内部结构 | mermaid.ink |
| `fig_area_v2.png` | Fig. 5 | ASIC面积随Bank数缩放曲线 | matplotlib |
| `fig_nested_bar_v2.png` | Fig. 6 | 嵌套开销对比 (FX vs CLIC vs NVIC) | matplotlib |
| `fig_fpga_scaling_v2.png` | Fig. 7 | FPGA LUT/FF缩放 + ASIC/FPGA对比 | matplotlib |

## 生成脚本

| 图 | 脚本 |
|---|------|
| Fig. 5 | `python/plot/bank_area_scaling.py` |
| Fig. 6 | `python/plot/nested_overhead_compare.py` |
| Fig. 7 | `python/plot/fpga_scaling.py` |
| Fig. 3 | `python/plot/draw_timing.py` |
| Fig. 1/2/4 | `python/plot/gen_figures.py` (via mermaid.ink) |

## 备用素材

| 文件 | 说明 |
|------|------|
| `doc/NewWork/patent_figures_mermaid.md` | 原始 mermaid 代码 (可去 mermaid.live 重新编辑) |
| `doc/interrupt/figures_english.md` | Wavedrom 时序图代码 |
| `doc/NewWork/timing_wavedrom.json` | Wavedrom 格式时序图 |
