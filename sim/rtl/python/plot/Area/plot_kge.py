import matplotlib.pyplot as plt
import numpy as np

# 数据：设计名称和等效门数 (kGE)
# 换算：1 kGE = 1120 μm² (1 GE = 1.12 μm²)
# PicoRV32 (full) 面积 33086 μm² → 33086 / 1120 = 29.5 kGE
designs = [
    'PicoRV32 (base)\n(Core)',
    'FX-RV32\n(Core)',
    'Sophon\n(Core)',
    'PicoRV32 (full)\n(Core)',
    'FX-RV32\n(Shadow Register)'
    
]
area_kge = [18.6, 24.8, 28.6, 29.5, 34.5]

# 颜色（按顺序分配，共5个）
colors = ['#aec7e8', '#ff7f0e', '#2ca02c', '#1f77b4', '#d62728']

plt.figure(figsize=(11, 6))
bars = plt.bar(designs, area_kge, color=colors, edgecolor='black', linewidth=1.2)

# 柱顶数值标签
for bar in bars:
    height = bar.get_height()
    plt.text(bar.get_x() + bar.get_width()/2., height + 0.02 * max(area_kge),
             f'{height:.1f} kGE', ha='center', va='bottom', fontsize=9, fontname='serif')

plt.ylabel('Equivalent Gate Count (kGE)', fontsize=14, fontname='serif')
plt.title('Area Comparison of RISC-V Cores  (kGE)', fontsize=16, fontname='serif')
plt.xticks(fontsize=10, fontname='serif')
plt.yticks(fontsize=12, fontname='serif')
plt.grid(axis='y', linestyle='--', alpha=0.5)

ax = plt.gca()
ax.ticklabel_format(axis='y', style='plain', useOffset=False)

plt.tight_layout()
plt.savefig('area_comparison_kge.pdf', format='pdf', dpi=300)
plt.savefig('area_comparison_kge.png', dpi=300)
plt.show()