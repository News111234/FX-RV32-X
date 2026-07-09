import matplotlib.pyplot as plt
import numpy as np

# 数据准备（新增三个 Sophon 配置）
cpu_modes = [
    "FX-RV32",
    "FX-RV32 Shadow_Registers",
    "Sophon RV32I",
    "Sophon RV32I+CLIC",
    "Sophon RV32I+EEI4",
    "Sophon RV32I+EEI8",
    "Sophon RV32I+EEI16",
    "Sophon RV32I+EEI32",
    "OpenE902"
]

area = [
    27191, 38693,          # FX-RV32 两种
    32116, 34115, 37939,   # Sophon RV32I, +CLIC, +EEI4
    43306, 55476, 70737,   # Sophon EEI8, EEI16, EEI32
    83924                  # OpenE902
]

critical_path = [
    4.89, 4.88,            # FX-RV32
    5.04, 5.04, 5.10,      # Sophon RV32I, +CLIC, +EEI4
    5.08, 5.10, 5.08,      # Sophon EEI8, EEI16, EEI32
    5.63                   # OpenE902
]

bar_color = "#89C4F4"
line_color = "#E67E22"

fig, ax1 = plt.subplots(figsize=(12, 6))   # 稍加宽以容纳更多标签
x = np.arange(len(cpu_modes))
bars = ax1.bar(x, area, color=bar_color, edgecolor='black', linewidth=0.8, label='Area (µm²)', alpha=0.8)
ax1.set_ylabel('Area (µm²)', fontsize=12, color=bar_color)
ax1.tick_params(axis='y', labelcolor=bar_color)
ax1.set_xticks(x)
ax1.set_xticklabels(cpu_modes, rotation=30, ha='right', fontsize=8)  # 旋转角度增大，字体略小

# 柱顶数值
for bar, a in zip(bars, area):
    ax1.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.02*max(area),
             f'{a}', ha='center', va='bottom', fontsize=7, color='black')

ax2 = ax1.twinx()
ax2.plot(x, critical_path, color=line_color, marker='o', linewidth=2, markersize=6,
         label='Critical Path (ns)')
ax2.set_ylabel('Critical Path (ns)', fontsize=12, color=line_color)
ax2.tick_params(axis='y', labelcolor=line_color)

# 折线图数值标签向右偏移15像素
for i, cp in enumerate(critical_path):
    ax2.annotate(f'{cp}', (i, cp), textcoords="offset points", xytext=(12, -8),
                 ha='center', fontsize=7, color=line_color)

lines1, labels1 = ax1.get_legend_handles_labels()
lines2, labels2 = ax2.get_legend_handles_labels()
ax1.legend(lines1 + lines2, labels1 + labels2, loc='upper left', fontsize=10)

ax1.grid(axis='y', linestyle='--', alpha=0.6)
ax1.set_title('Synthesis Results: Area vs Critical Path', fontsize=14)

plt.tight_layout()
plt.savefig('area_critical_path_comparison.png', dpi=300, bbox_inches='tight')
plt.show()