import matplotlib.pyplot as plt
import matplotlib.ticker as ticker

# ========== 数据 ==========
tests = {
    'test1_vvadd':   {'cycles': 143,  'color': '#1f77b4', 'marker': 'o', 'label': 'Vector Addition'},
    'test2_fib':     {'cycles': 97,   'color': '#ff7f0e', 'marker': 's', 'label': 'Recursive Fibonacci'},
    'test3_matmul':  {'cycles': 23,   'color': '#2ca02c', 'marker': '^', 'label': 'Matrix Multiplication'},
    'test4_bubble':  {'cycles': 1081, 'color': '#d62728', 'marker': 'd', 'label': 'Bubble Sort'},
    # ---- 新增测试5：LFSR ----
    'test5_lfsr':    {'cycles': 2053, 'color': '#9467bd', 'marker': 'v', 'label': 'LFSR'},
}

# 运行次数：保持原脚本的 1‑40（若你希望改为 1‑20，可修改 range）
iterations = list(range(1, 41))

# ========== 图表设置 ==========
plt.rcParams.update({
    'font.family': 'serif',
    'font.size': 11,
    'axes.linewidth': 1.2,
    'lines.linewidth': 2.0,
    'lines.markersize': 6,
    'legend.frameon': True,
    'legend.fancybox': False,
    'legend.edgecolor': 'black',
    'legend.framealpha': 1.0,
    'grid.linestyle': '--',
    'grid.alpha': 0.6,
    'figure.dpi': 150,
    'savefig.bbox': 'tight',
    'savefig.pad_inches': 0.1,
})

# 为每个测试生成单独的图
for name, data in tests.items():
    fig, ax = plt.subplots(figsize=(6, 4))

    # 绘制水平线（所有运行次数均相同）
    y = [data['cycles']] * len(iterations)
    ax.plot(iterations, y, color=data['color'], marker=data['marker'], label=data['label'])

    # 强制纵轴范围稍微扩展，避免线贴边
    ax.set_ylim(data['cycles'] * 0.8, data['cycles'] * 1.2)
    # 纵轴主要刻度只显示该数值
    ax.yaxis.set_major_locator(ticker.FixedLocator([data['cycles']]))
    ax.yaxis.set_major_formatter(ticker.ScalarFormatter())

    # 坐标轴标签
    ax.set_xlabel('Run Index', fontweight='bold')
    ax.set_ylabel('Execution Time (Cycles)', fontweight='bold')
    ax.set_title(f'Deterministic Execution of {data["label"]}', fontsize=13, fontweight='bold')

    # 网格与图例
    ax.grid(True)
    ax.legend(loc='upper right', fontsize=10)

    # 调整布局
    fig.tight_layout()

    # 保存图片
    filename = f'{name}_deterministic.png'
    fig.savefig(filename)
    plt.close(fig)
    print(f'Saved {filename}')

print('All figures generated.')