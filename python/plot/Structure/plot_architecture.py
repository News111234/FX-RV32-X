# -*- coding: utf-8 -*-
"""Draw FX-RV32 overall architecture diagram (Fig. 1)."""
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import FancyBboxPatch
import numpy as np

fig, ax = plt.subplots(1, 1, figsize=(14, 9))
ax.set_xlim(0, 16)
ax.set_ylim(0, 11)
ax.set_aspect('equal')
ax.axis('off')

# Colors
C_PIPE  = '#D6EAF8'   # light blue - pipeline stages
C_MEM   = '#FCF3CF'   # light yellow - memories
C_CTRL  = '#FADBD8'   # light red - interrupt/control
C_PERIPH = '#EAFAF1'  # light green - peripherals
C_BUS   = '#E8DAEF'   # light purple - bus
C_BORDER = '#2C3E50'
C_ARROW = '#555555'

def draw_box(ax, x, y, w, h, text, color, fontsize=8, bold=False, edgecolor=None):
    if edgecolor is None:
        edgecolor = C_BORDER
    box = FancyBboxPatch((x-w/2, y-h/2), w, h,
                         boxstyle="round,pad=0.1",
                         facecolor=color, edgecolor=edgecolor, linewidth=1.2)
    ax.add_patch(box)
    weight = 'bold' if bold else 'normal'
    lines = text.split('\n')
    for i, line in enumerate(lines):
        ax.text(x, y + (len(lines)/2 - i - 0.5) * h/(len(lines)+1) * 1.0,
                line, ha='center', va='center', fontsize=fontsize,
                fontweight=weight, color='#1A1A1A')

def draw_arrow(ax, x1, y1, x2, y2, color=C_ARROW, lw=1.2):
    ax.annotate('', xy=(x2, y2), xytext=(x1, y1),
                arrowprops=dict(arrowstyle='->', color=color, lw=lw))

def draw_h_arrow(ax, x1, y1, x2, color=C_ARROW, lw=1.2):
    draw_arrow(ax, x1, y1, x2, y1, color, lw)

# ========== TITLE ==========
ax.text(8, 10.5, 'FX-RV32 Core Architecture', ha='center',
        fontsize=14, fontweight='bold', color='#1F618D')

# ========== PIPELINE STAGES (top row) ==========
pipeline_y = 9.0
stages = [
    ('IF\nInstruction\nFetch',       2.0),
    ('ID\nInstruction\nDecode',      4.5),
    ('EX\nExecute',                  7.0),
    ('MEM\nMemory\nAccess',          9.5),
    ('WB\nWrite\nBack',             12.0),
]
stage_boxes = []
for label, x in stages:
    draw_box(ax, x, pipeline_y, 2.0, 2.0, label, C_PIPE, fontsize=8, bold=True)
    stage_boxes.append((x, pipeline_y))

# Pipeline arrows between stages
for i in range(len(stages)-1):
    x1 = stages[i][1] + 1.0
    x2 = stages[i+1][1] - 1.0
    draw_h_arrow(ax, x1, pipeline_y, x2, '#1F618D', 1.8)
    ax.text((x1+x2)/2, pipeline_y+0.25, '→', ha='center', fontsize=10, color='#1F618D')

# Pipeline registers (below arrows)
for i in range(len(stages)-1):
    x1 = stages[i][1] + 1.0
    x2 = stages[i+1][1] - 1.0
    mx = (x1+x2)/2
    ax.text(mx, pipeline_y-0.4, 'reg', ha='center', fontsize=6, color='#888888', style='italic')

# ========== REGISTER FILE (below ID) ==========
rf_x, rf_y = 4.5, 7.5
draw_box(ax, rf_x, rf_y, 2.5, 1.2,
         'Register File\n32 GPR + 31 Shadow', C_CTRL, fontsize=7, bold=True,
         edgecolor='#C0392B')
draw_arrow(ax, rf_x, pipeline_y-1.0, rf_x, rf_y+0.6, '#C0392B', 1.0)
draw_arrow(ax, rf_x, rf_y-0.6, rf_x, pipeline_y-1.0, '#C0392B', 1.0)

# ========== INSTRUCTION ROM (left of IF) ==========
rom_x, rom_y = 2.0, 7.2
draw_box(ax, rom_x, rom_y, 2.0, 1.0, 'Instruction\nROM', C_MEM, fontsize=8, bold=True)
draw_arrow(ax, rom_x, rom_y+0.5, stages[0][1]-1.0, pipeline_y-0.5, '#7D6608', 1.0)
draw_arrow(ax, stages[0][1], pipeline_y-1.0, rom_x+0.5, rom_y-0.5, '#7D6608', 1.0)

# ========== INTERRUPT SYSTEM (top-right) ==========
intc_x, intc_y = 14.0, 9.0
draw_box(ax, intc_x, intc_y, 2.0, 1.0,
         'Interrupt\nController', C_CTRL, fontsize=7, bold=True, edgecolor='#C0392B')
intp_x, intp_y = 14.0, 7.8
draw_box(ax, intp_x, intp_y, 2.0, 1.0,
         'Interrupt\nPipeline', C_CTRL, fontsize=7, bold=True, edgecolor='#C0392B')
draw_arrow(ax, intc_x, intc_y-0.5, intp_x, intp_y+0.5, '#C0392B', 1.0)

# Interrupt → PC
ax.annotate('handler addr', xy=(stages[0][1]+0.3, pipeline_y+0.8),
            xytext=(intp_x-1.0, intp_y+0.3),
            fontsize=6, ha='center', color='#C0392B',
            arrowprops=dict(arrowstyle='->', color='#C0392B', lw=1.0,
                          connectionstyle='arc3,rad=0.3'))

# ========== BUS ARBITER + DATA RAM (below MEM) ==========
bus_x, bus_y = 9.5, 5.5
draw_box(ax, bus_x, bus_y, 2.2, 1.0, 'Bus Arbiter', C_BUS, fontsize=8, bold=True)
draw_arrow(ax, stages[3][1], pipeline_y-1.0, bus_x, bus_y+0.5, C_ARROW, 1.0)

# Data RAM (below bus)
ram_x, ram_y = 9.5, 4.2
draw_box(ax, ram_x, ram_y, 2.2, 1.0, 'Data RAM\n(64 KB)', C_MEM, fontsize=8, bold=True)
draw_arrow(ax, bus_x, bus_y-0.5, ram_x, ram_y+0.5, C_ARROW, 1.0)

# WB write-back from MEM
ax.annotate('', xy=(ram_x-0.3, ram_y-0.3), xytext=(stages[4][1], pipeline_y-1.0),
            arrowprops=dict(arrowstyle='->', color=C_ARROW, lw=1.0,
                          connectionstyle='arc3,rad=-0.3'))

# Bus → MEM stage return
draw_arrow(ax, bus_x-0.6, bus_y+0.3, stages[3][1]-0.3, pipeline_y-0.5, C_ARROW, 0.8)

# ========== PERIPHERALS (below bus/ram) ==========
periph_y = 2.5
periphs = [
    ('GPIO',  6.0),
    ('UART',  8.0),
    ('Timer', 10.0),
    ('SPI',   12.0),
    ('I2C',   14.0),
]
for label, x in periphs:
    draw_box(ax, x, periph_y, 1.4, 0.8, label, C_PERIPH, fontsize=7, bold=True)
    draw_arrow(ax, bus_x-0.3, bus_y-0.5, x, periph_y+0.4, C_ARROW, 0.7)

# Bus arbiter label
ax.text(bus_x+1.6, bus_y, '← addr decode', fontsize=6, color='#888888', va='center')

# ========== CSR (next to EX) ==========
csr_x, csr_y = 7.0, 7.2
draw_box(ax, csr_x, csr_y, 1.6, 0.9, 'CSR\nRegisters', '#D5F5E3', fontsize=7, bold=True)
draw_arrow(ax, csr_x, csr_y-0.45, stages[2][1], pipeline_y-1.0, C_ARROW, 0.7)

# ========== SHADOW REG note ==========
ax.text(rf_x, rf_y-0.9, 'shadow_save /\nshadow_restore', ha='center',
        fontsize=6, color='#C0392B', style='italic')

# ========== INTERRUPT SOURCES ==========
src_y = 10.2
for i, (label, x_offset) in enumerate([('SW(3)', -1.2), ('Timer(7)', 0), ('Ext(11)', 1.2)]):
    ax.text(intc_x+x_offset, src_y, label, fontsize=6, ha='center', color='#C0392B')
    draw_arrow(ax, intc_x+x_offset, src_y-0.15, intc_x+x_offset*0.3, intc_y+0.5, '#C0392B', 0.7)

# ========== MRET path ==========
ax.annotate('MRET', xy=(intp_x-1.0, intp_y-0.3),
            xytext=(stages[4][1]-0.5, pipeline_y-1.2),
            fontsize=6, ha='center', color='#C0392B',
            arrowprops=dict(arrowstyle='->', color='#C0392B', lw=0.8,
                          connectionstyle='arc3,rad=-0.5'))

# ========== LEGEND ==========
lx, ly = 0.5, 3.0
ax.text(lx, ly, 'Legend', fontsize=8, fontweight='bold')
items = [
    ('Pipeline Stages', C_PIPE),
    ('Memories', C_MEM),
    ('Interrupt / Control', C_CTRL),
    ('Bus', C_BUS),
    ('Peripherals', C_PERIPH),
]
for i, (label, color) in enumerate(items):
    iy = ly - 0.5 - i * 0.4
    box = FancyBboxPatch((lx, iy-0.15), 0.6, 0.3,
                         boxstyle="round,pad=0.02",
                         facecolor=color, edgecolor=C_BORDER, linewidth=1.0)
    ax.add_patch(box)
    ax.text(lx+0.9, iy, label, fontsize=7, va='center')

plt.tight_layout()
out = 'D:/Path/RISC-V-TEST/Project/FX-RV32_RemoveM_Custom/python/plot/Structure/'
plt.savefig(out + 'fig_architecture.png', dpi=200, bbox_inches='tight', facecolor='white')
plt.savefig(out + 'fig_architecture.pdf', bbox_inches='tight', facecolor='white')
plt.close()
print('Saved: fig_architecture.png + fig_architecture.pdf')
