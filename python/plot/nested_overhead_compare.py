# nested_overhead_compare.py — 嵌套中断开销对比柱状图
import matplotlib.pyplot as plt
import numpy as np

depths = [1, 2, 3, 4]
fxrv32x = [5, 10, 15, 20]       # 2 entry + 3 exit per level
clic = [24, 48, 72, 96]          # ~24 cycles per level (13 entry + exit)
arm_nvic = [15, 30, 45, 60]      # ~15 cycles per level (12 stack + variable)

x = np.arange(len(depths))
width = 0.25

fig, ax = plt.subplots(figsize=(6, 4.5))

bars1 = ax.bar(x - width, fxrv32x, width, color='#2E86AB', edgecolor='white', linewidth=0.5,
               label='FX-RV32-X (this work)')
bars2 = ax.bar(x, clic, width, color='#A23B72', edgecolor='white', linewidth=0.5,
               label='CLIC Hardware Stacking [5]')
bars3 = ax.bar(x + width, arm_nvic, width, color='#F18F01', edgecolor='white', linewidth=0.5,
               label='ARM Cortex-M4 NVIC [7]')

# 标注值
for bars in [bars1, bars2, bars3]:
    for bar in bars:
        h = bar.get_height()
        ax.text(bar.get_x() + bar.get_width()/2, h + 2,
                f'{int(h)}', ha='center', va='bottom', fontsize=8, fontweight='bold')

ax.set_xlabel('Nesting Depth', fontsize=11)
ax.set_ylabel('Cumulative Overhead (clock cycles)', fontsize=11)
ax.set_title('Nested Interrupt Cumulative Overhead Comparison (200 MHz)', fontsize=12, fontweight='bold')
ax.set_xticks(x)
ax.set_xticklabels([f'{d}' for d in depths])
ax.legend(fontsize=9)
ax.grid(axis='y', alpha=0.3, linestyle='--')
ax.set_ylim(0, 120)

# 精简标注
ax.annotate('2-cycle entry per level\n(5 cycles/level total)',
            xy=(0, 5), xytext=(0.8, 20), fontsize=8, color='#2E86AB',
            arrowprops=dict(arrowstyle='->', color='#2E86AB', lw=1))
ax.annotate('11-cycle serial stacking\n+ 13-cycle entry/exit',
            xy=(1, 48), xytext=(2.2, 70), fontsize=8, color='#A23B72',
            arrowprops=dict(arrowstyle='->', color='#A23B72', lw=1))

plt.tight_layout()
plt.savefig('../../doc/NewWork/fig_nested_bar_v2.png', dpi=200, bbox_inches='tight')
print('Saved fig_nested_bar_v2.png')
