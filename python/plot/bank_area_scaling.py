# bank_area_scaling.py — FX-RV32-X Bank 数量 vs 面积/功耗 图
import matplotlib.pyplot as plt
import numpy as np

banks = [1, 2, 4, 8]
area_kge = [36.00, 42.99, 62.41, 100.20]
power_mw = [6.07, 7.70, 11.54, 19.38]
area_um2 = [40314, 48152, 69897, 112230]

fig, ax1 = plt.subplots(figsize=(6, 4))

# 面积柱状图
color_area = '#4472C4'
bars = ax1.bar(np.arange(len(banks)) - 0.15, area_kge, 0.3,
               color=color_area, edgecolor='white', linewidth=0.5, label='Area (kGE)')
ax1.set_xlabel('Number of Banks (N)', fontsize=11)
ax1.set_ylabel('Area (kGE)', fontsize=11, color=color_area)
ax1.tick_params(axis='y', labelcolor=color_area)
ax1.set_xticks(np.arange(len(banks)))
ax1.set_xticklabels([f'{b}' for b in banks])

# 标注面积值
for bar, val in zip(bars, area_kge):
    ax1.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 1.0,
             f'{val:.1f}', ha='center', va='bottom', fontsize=9, color=color_area)

# 标注增量
deltas = ['—', '+7.0', '+19.4', '+37.8']
for i, (bar, d) in enumerate(zip(bars, deltas)):
    if i == 0:
        continue
    ax1.text(bar.get_x() + bar.get_width()/2, bar.get_height()/2,
             d, ha='center', va='center', fontsize=8, color='white', fontweight='bold')

# 原始单 Bank 基准线
ax1.axhline(y=32.37, color='gray', linestyle='--', linewidth=0.8, alpha=0.7)
ax1.text(3.5, 32.37, 'Original single-bank FX-RV32: 32.37 kGE',
         fontsize=8, color='gray', va='bottom', ha='right')

# 功耗折线 (右轴)
ax2 = ax1.twinx()
color_power = '#ED7D31'
ax2.plot(np.arange(len(banks)) - 0.15, power_mw, 'o-', color=color_power, linewidth=1.5,
         markersize=6, label='Power (mW)')
ax2.set_ylabel('Power (mW)', fontsize=11, color=color_power)
ax2.tick_params(axis='y', labelcolor=color_power)
for i, p in enumerate(power_mw):
    ax2.annotate(f'{p:.1f}', (i - 0.15, p), textcoords="offset points",
                 xytext=(0, 10), ha='center', fontsize=8, color=color_power)

# 风格
ax1.set_ylim(0, 120)
ax2.set_ylim(0, 25)
ax1.grid(axis='y', alpha=0.3, linestyle='--')
ax1.set_title('FX-RV32-X: Area and Power vs. Bank Count (55 nm CMOS)', fontsize=12, fontweight='bold')

# 图例
lines1, labels1 = ax1.get_legend_handles_labels()
lines2, labels2 = ax2.get_legend_handles_labels()
ax1.legend(lines1 + lines2, labels1 + labels2, loc='upper left', fontsize=9)

plt.tight_layout()
plt.savefig('../../doc/NewWork/fig_area_v2.png', dpi=200, bbox_inches='tight')
print('Saved fig_area_v2.png')
