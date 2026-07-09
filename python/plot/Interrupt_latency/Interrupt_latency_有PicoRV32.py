import matplotlib.pyplot as plt
import numpy as np

# 数据准备（新增 PicoRV32 条目）
data = [
    ("Sophon", "non-hardware vectoring\n-C ABI handler", 39),
    ("Sophon", "non-hardware vectoring\n-snapreg", 7),
    ("Sophon", "hardware vectoring\n-inline handler", 3),
    ("OpenE902", "hardware vectoring", 9),
    ("Fast Interrupt", "hardware stacking", 13),
    ("CV32E40P", "vectored interrupt\n-EABI", 24),
    ("CV32E40P", "vectored interrupt\n-regular ABI", 33),
    ("FX-RV32", "hardware vectoring", 2),
    ("PicoRV32", "non-vectored\n-custom retirq (fastest)", 7),   # 非向量模式，自定义retirq指令，固定入口地址0x10
]

# 配色：比浅色稍深，但比原深色浅（为 PicoRV32 添加淡黄色）
cpu_colors = {
    "Sophon": "#89C4F4",      # 天蓝
    "OpenE902": "#F5B041",    # 橘黄
    "Fast Interrupt": "#82E0AA", # 草绿
    "CV32E40P": "#F1948A",    # 珊瑚
    "FX-RV32": "#B28BDF",     # 淡紫
    "PicoRV32": "#F7DC6F",    # 淡黄（新增）
}

labels = [item[1] for item in data]
latencies = [item[2] for item in data]
cpu_names = [item[0] for item in data]
colors = [cpu_colors[cpu] for cpu in cpu_names]

fig, ax = plt.subplots(figsize=(10, 6))
y_pos = np.arange(len(labels))
bars = ax.barh(y_pos, latencies, color=colors, edgecolor='black', linewidth=0.5)

# 添加数值标签（偏移 0.2，紧贴条形末端）
for i, (bar, lat) in enumerate(zip(bars, latencies)):
    ax.text(bar.get_width() + 0.2, bar.get_y() + bar.get_height()/2,
            f'{lat}', va='center', fontsize=9)

ax.set_yticks(y_pos)
ax.set_yticklabels(labels, fontsize=8)
ax.set_xlabel('Interrupt Latency (cycles)', fontsize=12)
ax.set_ylabel('CPU / Interrupt Mode', fontsize=12)
ax.set_title('Interrupt Latency Comparison Among Different CPUs', fontsize=14)
ax.xaxis.grid(True, linestyle='--', alpha=0.7)

# 图例放置右上角（自动包含新增的 PicoRV32）
handles = [plt.Rectangle((0,0),1,1, color=cpu_colors[name]) for name in cpu_colors.keys()]
ax.legend(handles, cpu_colors.keys(), loc='upper right', fontsize=9)

plt.tight_layout()
plt.savefig('interrupt_latency_comparison_medium.png', dpi=300, bbox_inches='tight')
plt.show()