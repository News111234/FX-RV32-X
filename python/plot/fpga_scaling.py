#!/usr/bin/env python3
"""
FPGA 资源缩放图 — FX-RV32-X 多 Bank 影子寄存器
生成论文 Fig.7: FPGA LUT/FF vs Banks + ASIC面积对比

数据来源: Vivado 2022.2 综合, Kintex-7 xc7k325tffg900-2
"""

import matplotlib.pyplot as plt
import matplotlib
import numpy as np

matplotlib.rcParams['font.family'] = 'sans-serif'
matplotlib.rcParams['font.sans-serif'] = ['Arial']
matplotlib.rcParams['mathtext.fontset'] = 'stix'

# ============================================================
# 数据
# ============================================================
banks = [1, 2, 4, 8]
lut   = [4356, 4855, 6829, 6838]    # 实现后 (post-route)
ff    = [3917, 4905, 6914, 10859]   # 实现后 (post-route)
fmax  = [174.0, 163.3, 178.2, 160.4]  # 实现后 Fmax
bram  = [8, 8, 8, 8]

# ASIC 面积 (kGE) for comparison
asic_area = [36.00, 42.99, 62.41, 100.20]

# 理论值 (31 regs * 32 bits = 992 FF per Bank)
theoretical_ff = [992 * b for b in banks]

# ============================================================
# 图1: FPGA LUT & FF 缩放 (双轴)
# ============================================================
fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 5.5))

# --- 左图: FPGA LUT + FF ---
color_lut = '#2196F3'
color_ff  = '#FF5722'

ax1.plot(banks, lut, 'o-', color=color_lut, linewidth=2.5, markersize=10,
         markerfacecolor='white', markeredgewidth=2, label='Slice LUTs')
ax1.plot(banks, ff, 's-', color=color_ff, linewidth=2.5, markersize=10,
         markerfacecolor='white', markeredgewidth=2, label='Slice Registers (FF)')

# 理论 FF 线 (虚线)
ax1.plot(banks, theoretical_ff, '--', color='#FFAB91', linewidth=1.2, alpha=0.7,
         label='Theoretical FF (992/Bank)')

ax1.set_xlabel('Number of Shadow Banks', fontsize=12, fontweight='bold')
ax1.set_ylabel('Resource Count', fontsize=12, fontweight='bold')
ax1.set_title('FPGA Resource Scaling\n(Kintex-7 xc7k325t, Vivado 2022.2)', fontsize=13, fontweight='bold')
ax1.set_xticks(banks)
ax1.grid(True, alpha=0.3, linestyle='--')
ax1.legend(loc='upper left', fontsize=10, framealpha=0.9)

# 在数据点上标注数值
for i, (b, l, f) in enumerate(zip(banks, lut, ff)):
    offset = 150
    ax1.annotate(f'{l:,}', (b, l), textcoords="offset points", xytext=(5, 12),
                fontsize=9, color=color_lut, fontweight='bold')
    ax1.annotate(f'{f:,}', (b, f), textcoords="offset points", xytext=(5, -16),
                fontsize=9, color=color_ff, fontweight='bold')

# --- 右图: ASIC vs FPGA 面积对比 (归一化到 Banks=1) ---
asic_norm  = [a / asic_area[0] for a in asic_area]
lut_norm   = [l / lut[0] for l in lut]
ff_norm    = [f / ff[0] for f in ff]

x_wide = np.arange(len(banks))
width = 0.25

bars1 = ax2.bar(x_wide - width, asic_norm, width, color='#4CAF50', edgecolor='white',
                linewidth=0.5, label='ASIC Area (55nm, kGE)')
bars2 = ax2.bar(x_wide, lut_norm, width, color=color_lut, edgecolor='white',
                linewidth=0.5, label='FPGA LUTs')
bars3 = ax2.bar(x_wide + width, ff_norm, width, color=color_ff, edgecolor='white',
                linewidth=0.5, label='FPGA Registers (FF)')

# 标注增长倍数
for i, (b, a, l, f) in enumerate(zip(banks, asic_norm, lut_norm, ff_norm)):
    ax2.text(x_wide[i] - width, a + 0.03, f'{a:.2f}x', ha='center', fontsize=8, fontweight='bold')
    ax2.text(x_wide[i], l + 0.03, f'{l:.2f}x', ha='center', fontsize=8, fontweight='bold')
    ax2.text(x_wide[i] + width, f + 0.03, f'{f:.2f}x', ha='center', fontsize=8, fontweight='bold')

ax2.set_xticks(x_wide)
ax2.set_xticklabels([f'{b}' for b in banks])
ax2.set_xlabel('Number of Shadow Banks', fontsize=12, fontweight='bold')
ax2.set_ylabel('Normalized Area/Resources (Banks=1 = 1.0)', fontsize=12, fontweight='bold')
ax2.set_title('ASIC vs FPGA Scaling Comparison\n(Normalized to Banks=1)', fontsize=13, fontweight='bold')
ax2.legend(loc='upper left', fontsize=9, framealpha=0.9)
ax2.grid(True, alpha=0.3, linestyle='--', axis='y')

plt.tight_layout(pad=2)
plt.savefig('D:/Path/RISC-V-TEST/Project/FX-RV32_CUSTOM/doc/NewWork/fig_fpga_scaling_v2.png',
            dpi=200, bbox_inches='tight', facecolor='white')
print("Saved: doc/NewWork/fig_fpga_scaling_v2.png")
plt.close()
