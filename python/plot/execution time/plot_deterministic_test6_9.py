import matplotlib.pyplot as plt
import matplotlib.ticker as ticker

# ========== Data: test6–test9 ==========
# Cycle counts per iteration obtained from 40-run simulation
# All 40 runs of each test produced identical cycle counts (variance = 0)
tests = {
    'test6_forwarding': {
        'cycles': 34,
        'color': '#e377c2',
        'marker': 'o',
        'label': 'Forwarding Chain'
    },
    'test7_branching': {
        'cycles': 21,
        'color': '#17becf',
        'marker': 's',
        'label': 'Decision Tree'
    },
    'test8_memdep': {
        'cycles': 44,
        'color': '#bcbd22',
        'marker': '^',
        'label': 'Memory Access'
    },
    'test9_Interrupt': {
        'lines': [
            {'cycles': 2,  'color': '#d62728', 'marker': 'o', 'label': 'Latency'},
            {'cycles': 10, 'color': '#1f77b4', 'marker': 's', 'label': 'ISR'},
        ],
        'ylim_min': 0,
        'ylim_max': 15,
        'yticks': [2, 10],
    },
}

iterations = list(range(1, 41))

# ========== Global style ==========
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

# ========== Generate one figure per test ==========
for name, data in tests.items():
    fig, ax = plt.subplots(figsize=(6, 4))

    # 特殊处理 Interrupt: 画两条线 (Latency + ISR)
    if 'lines' in data:
        for line in data['lines']:
            y = [line['cycles']] * len(iterations)
            ax.plot(iterations, y,
                    color=line['color'],
                    marker=line['marker'],
                    label=line['label'])
        ax.set_ylim(data['ylim_min'], data['ylim_max'])
        ax.yaxis.set_major_locator(ticker.FixedLocator(data['yticks']))
        title_label = 'Interrupt'
    else:
        y = [data['cycles']] * len(iterations)
        ax.plot(iterations, y,
                color=data['color'],
                marker=data['marker'],
                label=data['label'])
        margin = max(data['cycles'] * 0.15, 5)
        ax.set_ylim(data['cycles'] - margin, data['cycles'] + margin)
        ax.yaxis.set_major_locator(ticker.FixedLocator([data['cycles']]))
        title_label = data['label']

    ax.yaxis.set_major_formatter(ticker.ScalarFormatter())
    ax.set_xlabel('Run Index', fontweight='bold')
    ax.set_ylabel(' Time (Cycles)', fontweight='bold')
    ax.set_title(
        f'Deterministic Execution of {title_label}',
        fontsize=13, fontweight='bold'
    )

    ax.grid(True)
    ax.legend(loc='upper right', fontsize=10)

    fig.tight_layout()

    filename = f'{name}_deterministic.png'
    fig.savefig(filename)
    plt.close(fig)
    print(f'Saved {filename}')

print('All figures generated.')
