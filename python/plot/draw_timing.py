#!/usr/bin/env python3
"""
Fig.3 — Constant 2-Cycle Interrupt Response Timing Diagram
Matplotlib 绘制, 论文级矢量图
"""

import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np

fig, ax = plt.subplots(figsize=(12, 7))
ax.set_xlim(-0.5, 12.5)
ax.set_ylim(-1.5, 10.5)

# ---- Signal names aligned to left ----
signals = [
    'clk',
    'GPIO intr',
    'intr_pending',
    'intr_accepted',
    'intr_taken',
    'CSR write',
    'intr_flush',
    'PC (IF)',
    'shadow_save',
    'x1-x31 regs',
]
n = len(signals)

for i, name in enumerate(signals):
    ax.text(-0.3, n-1-i, name, ha='right', va='center', fontsize=9,
            fontfamily='monospace', fontweight='bold', color='#2c3e50')

# ---- Helper functions ----
def draw_clk(ax, y, x_start, x_end, period=1.0):
    """Draw clock waveform"""
    xs, ys = [], []
    x = x_start
    half = period / 2
    while x < x_end:
        xs.extend([x, x + half])
        ys.extend([0.3, 0.3])
        xs.extend([x + half, x + half])
        ys.extend([0.0, 0.0])
        xs.extend([x + half, x + period])
        ys.extend([0.3, 0.3])
        x += period
    ax.plot(xs, [y + v for v in ys], 'k-', linewidth=1.0)

def draw_high(ax, y, x1, x2, color='#2c3e50', lw=2.0, alpha=1.0):
    """Draw high level (logic 1)"""
    ax.plot([x1, x2], [y + 0.25, y + 0.25], color=color, linewidth=lw, alpha=alpha)

def draw_low(ax, y, x1, x2, color='#2c3e50', lw=1.0):
    """Draw low level (logic 0)"""
    ax.plot([x1, x2], [y - 0.05, y - 0.05], color=color, linewidth=lw)

def draw_transition(ax, y, x, direction='up', color='#2c3e50', lw=1.0):
    """Draw vertical transition"""
    if direction == 'up':
        ax.plot([x, x], [y - 0.05, y + 0.25], color=color, linewidth=lw)
    else:
        ax.plot([x, x], [y + 0.25, y - 0.05], color=color, linewidth=lw)

def draw_data_label(ax, y, x, text, color='#e74c3c'):
    """Place data label above a high segment"""
    ax.text(x, y + 0.45, text, ha='center', va='bottom', fontsize=7.5,
            fontfamily='monospace', color=color, fontweight='bold')

def draw_phase_bar(ax, y_bottom, x1, x2, text, color):
    """Draw a phase bracket with text"""
    y = y_bottom - 0.3
    ax.plot([x1, x1, x2, x2], [y, y + 0.15, y + 0.15, y], color=color, linewidth=1.5)
    ax.text((x1 + x2) / 2, y - 0.1, text, ha='center', va='top', fontsize=7,
            color=color, fontweight='bold')

# ---- Vertical grid lines (clock edges) ----
edges = list(range(0, 14, 2))
edge_labels = ['T0↑', 'T1↑', 'T2↑', 'T3↑', 'T4↑', '', '']

for i, x in enumerate(edges):
    ax.axvline(x=x, color='#ddd', linewidth=0.5, linestyle='-', zorder=0)
    if i < len(edge_labels) and edge_labels[i]:
        ax.text(x, n - 0.2, edge_labels[i], ha='center', va='bottom',
                fontsize=8, color='#e74c3c', fontweight='bold')

# ---- Draw signals (y = n-1-i, i=signal index) ----
# clk (i=9): continuous clock
draw_clk(ax, 9, 0, 12)

# GPIO intr (i=8): 01.0.......
draw_low(ax, 8, 0, 1)
draw_high(ax, 8, 1, 3, color='#e74c3c', lw=3)
draw_low(ax, 8, 3, 12)

# intr_pending (i=7): 01...0.....
draw_low(ax, 7, 0, 1)
draw_high(ax, 7, 1, 5, color='#e74c3c', lw=3)
draw_low(ax, 7, 5, 12)

# intr_accepted (i=6): 0.1.0......
draw_low(ax, 6, 0, 2)
draw_high(ax, 6, 2, 4, color='#2c3e50', lw=3)
draw_low(ax, 6, 4, 12)

# intr_taken (i=5): 0.1.0......
draw_low(ax, 5, 0, 2)
draw_high(ax, 5, 2, 4, color='#2c3e50', lw=3)
draw_low(ax, 5, 4, 12)

# CSR write (i=4): 0.1.0......
draw_low(ax, 4, 0, 2)
draw_high(ax, 4, 2, 4, color='#2c3e50', lw=3)
draw_low(ax, 4, 4, 12)
draw_data_label(ax, 4, 3, 'mepc mcause mstatus')

# intr_flush (i=3): 0.1.0......
draw_low(ax, 3, 0, 2)
draw_high(ax, 3, 2, 4, color='#2c3e50', lw=3)
draw_low(ax, 3, 4, 12)

# PC (IF) (i=2): =.=.=......  (three distinct values)
# value trajectory: low -> mid -> high
ax.plot([0, 1], [2.25, 2.25], 'k-', linewidth=2.0)
ax.text(0.5, 2.35, 'PC0', ha='center', fontsize=9, fontfamily='monospace', color='#555')
ax.plot([1, 2], [2.25, 2.25], 'k-', linewidth=1.0)
ax.plot([1, 1], [2.25, 2.25], 'k-', linewidth=1.0)  # vline stub
ax.plot([2, 4], [2.15, 2.15], 'k-', linewidth=2.0)
ax.text(3, 2.25, 'PC0+4', ha='center', fontsize=9, fontfamily='monospace', color='#555')
ax.axvline(x=4, ymin=0.55, ymax=0.61, color='#2c3e50', linewidth=1)  # edge transition
ax.plot([4, 12], [2.05, 2.05], 'k-', linewidth=2.0)
ax.text(6, 2.15, 'handler', ha='center', fontsize=8.5, fontfamily='monospace', color='#e74c3c', fontweight='bold')

# shadow_save (i=1): 0...1.0....
draw_low(ax, 1, 0, 4)
draw_high(ax, 1, 4, 6, color='#2c3e50', lw=3)
draw_low(ax, 1, 6, 12)

# x1-x31 (i=0): =....=.....
ax.plot([0, 4], [0.15, 0.15], 'k-', linewidth=2.0)
ax.text(2, 0.25, 'original context', ha='center', fontsize=9, fontfamily='monospace', color='#555')
ax.plot([4, 6], [0.15, 0.15], 'k-', linewidth=1.0, linestyle=':')  # save happening
ax.plot([6, 12], [0.07, 0.07], 'k-', linewidth=2.0)
ax.text(8, 0.17, 'snapshot', ha='center', fontsize=8, fontfamily='monospace', color='#e74c3c', fontweight='bold')

# ---- Phase annotations at bottom ----
phases = [
    (0, 2, 'GPIO fires', '#e74c3c'),
    (2, 4, 'T0 accept', '#e74c3c'),
    (4, 6, 'T1 PC=handler', '#e74c3c'),
    (6, 8, 'ISR in IF', '#2c3e50'),
]
for x1, x2, text, color in phases:
    draw_phase_bar(ax, -0.8, x1, x2, text, color)

# ---- 2-cycle Brace ----
brace_y = -1.2
ax.annotate('', xy=(2, brace_y), xytext=(6, brace_y),
            arrowprops=dict(arrowstyle='<->', color='#e74c3c', lw=2.5))
ax.text(4, brace_y - 0.2, '2-cycle latency', ha='center', va='top', fontsize=11,
        color='#e74c3c', fontweight='bold')

# ---- Title ----
ax.set_title('Constant 2-Cycle Interrupt Response Timing', fontsize=14, fontweight='bold',
             color='#2c3e50', pad=15)

# ---- Clean up axes ----
ax.axis('off')
ax.set_ylim(-1.5, 10.5)

plt.tight_layout(pad=1)
plt.savefig('D:/Path/RISC-V-TEST/Project/FX-RV32_CUSTOM/doc/NewWork/fig_timing_v2.png',
            dpi=250, bbox_inches='tight', facecolor='white')
plt.savefig('D:/Path/RISC-V-TEST/Project/FX-RV32_CUSTOM/doc/NewWork/fig_timing_v2.pdf',
            bbox_inches='tight', facecolor='white')
print("Saved: fig_timing_v2.png + fig_timing_v2.pdf")
plt.close()
