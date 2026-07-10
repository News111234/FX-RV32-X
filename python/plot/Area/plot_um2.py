import matplotlib.pyplot as plt
import numpy as np

designs = ['PicoRV32 (base)\n(Core)', 'Sophon\n(Core)', 'PicoRV32 (full)\n(Core)', 
           'FX-RV32\n(Core)', 'FX-RV32\n(SoC)', 'CVA6\n(Core)']
area_um2 = [20808, 25536, 33086, 74134, 242504, 483704]

colors = ['#aec7e8', '#9467bd', '#1f77b4', '#ff7f0e', '#d62728', '#2ca02c']

plt.figure(figsize=(11, 6))
bars = plt.bar(designs, area_um2, color=colors, edgecolor='black', linewidth=1.2)

for bar in bars:
    height = bar.get_height()
    plt.text(bar.get_x() + bar.get_width()/2., height + 0.02 * max(area_um2),
             f'{int(height):,} µm²', ha='center', va='bottom', fontsize=9, fontname='serif')

plt.ylabel('Area (µm²)', fontsize=14, fontname='serif')
plt.title('Area Comparison of RISC-V Cores and SoC (µm², sorted by area)', fontsize=16, fontname='serif')
plt.xticks(fontsize=10, fontname='serif')
plt.yticks(fontsize=12, fontname='serif')
plt.grid(axis='y', linestyle='--', alpha=0.5)

ax = plt.gca()
ax.ticklabel_format(axis='y', style='plain', useOffset=False)

plt.tight_layout()
plt.savefig('area_comparison_um2.pdf', format='pdf', dpi=300)
plt.savefig('area_comparison_um2.png', dpi=300)
plt.show()