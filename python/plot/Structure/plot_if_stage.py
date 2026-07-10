# -*- coding: utf-8 -*-
"""Draw IF Stage architecture diagram using matplotlib."""
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch
import numpy as np

fig, ax = plt.subplots(1, 1, figsize=(12, 6))
ax.set_xlim(0, 14)
ax.set_ylim(0, 8)
ax.set_aspect('equal')
ax.axis('off')

# Color scheme
C_REG  = '#D6EAF8'   # light blue - registers
C_LOGIC = '#FCF3CF'   # light yellow - combinational logic
C_ROM  = '#FCF3CF'    # light yellow
C_PIPE = '#EAFAF1'    # light green - pipeline registers
C_INTR = '#FADBD8'    # light red - interrupt signals
C_BORDER = '#2C3E50'

def draw_box(ax, x, y, w, h, text, color, fontsize=8, bold=False):
    """Draw a rounded box with text."""
    box = FancyBboxPatch((x-w/2, y-h/2), w, h,
                         boxstyle="round,pad=0.1",
                         facecolor=color, edgecolor=C_BORDER, linewidth=1.2)
    ax.add_patch(box)
    weight = 'bold' if bold else 'normal'
    lines = text.split('\n')
    line_h = h / (len(lines) + 0.5)
    for i, line in enumerate(lines):
        ax.text(x, y + (len(lines)/2 - i - 0.5) * line_h * 0.85,
                line, ha='center', va='center', fontsize=fontsize,
                fontweight=weight, color='#1A1A1A')

def draw_input(ax, x, y, text, color):
    """Draw a small input label box."""
    box = FancyBboxPatch((x-0.55, y-0.2), 1.1, 0.4,
                         boxstyle="round,pad=0.05",
                         facecolor=color, edgecolor=C_BORDER, linewidth=0.8)
    ax.add_patch(box)
    ax.text(x, y, text, ha='center', va='center', fontsize=6,
            color='#1A1A1A')

def draw_arrow(ax, x1, y1, x2, y2, color='#555555', lw=1.0):
    """Draw an arrow."""
    ax.annotate('', xy=(x2, y2), xytext=(x1, y1),
                arrowprops=dict(arrowstyle='->', color=color, lw=lw))

def draw_arrow_label(ax, x1, y1, x2, y2, label, color='#555555', lw=1.0):
    """Draw an arrow with a label."""
    ax.annotate('', xy=(x2, y2), xytext=(x1, y1),
                arrowprops=dict(arrowstyle='->', color=color, lw=lw))
    ax.text((x1+x2)/2, (y1+y2)/2 + 0.15, label, fontsize=6,
            ha='center', va='bottom', color=color, style='italic')

# ── Draw a bounding box for IF Stage ──
rect = mpatches.Rectangle((0.3, 0.3), 13.4, 6.8, fill=False,
                           edgecolor='#1F618D', linewidth=2, linestyle='-')
ax.add_patch(rect)
ax.text(0.6, 6.9, 'IF Stage', fontsize=9, fontweight='bold', color='#1F618D')

# ── Input signals (left side, vertical) ──
inputs = [
    ('stall_i',          C_LOGIC),
    ('branch_taken_i',   C_LOGIC),
    ('jump_taken_i',     C_LOGIC),
    ('branch_target_i',  C_REG),
    ('jump_target_i',    C_REG),
    ('intr_take_now_i',  C_INTR),
    ('interrupt_taken_i',C_INTR),
    ('intr_target_i',    C_REG),
]
in_x = 1.5
for i, (label, color) in enumerate(inputs):
    y = 5.5 - i * 0.65
    draw_input(ax, in_x, y, label, color)

# ── IFU Top (center) ──
ifu_x, ifu_y = 5.0, 2.8
draw_box(ax, ifu_x, ifu_y, 2.8, 3.5,
         'IFU Top\n(ifu_top)\n\nnext_pc priority:\nintr_take_now >\ninterrupt_taken >\nbranch > jump >\nstall > pc+4',
         C_LOGIC, fontsize=7, bold=True)

# ── PC Register (above IFU) ──
pc_x, pc_y = 5.0, 5.9
draw_box(ax, pc_x, pc_y, 2.2, 0.9, 'PC Register\n(pc_reg)', C_REG, fontsize=8, bold=True)

# ── Instruction ROM (right of PC) ──
rom_x, rom_y = 8.5, 5.9
draw_box(ax, rom_x, rom_y, 2.0, 1.0, 'Instruction ROM\n(inst_rom)', C_ROM, fontsize=8, bold=True)

# ── IF/ID Pipeline Register (right of IFU) ──
pipe_x, pipe_y = 9.5, ifu_y
draw_box(ax, pipe_x, pipe_y, 2.0, 1.2, 'IF/ID Pipeline\nRegister\n(if_id_reg)', C_PIPE, fontsize=8, bold=True)

# ── Arrows: inputs → IFU ──
for i in range(len(inputs)):
    sy = 5.5 - i * 0.65
    draw_arrow(ax, 2.1, sy, ifu_x - 1.4, ifu_y + 1.3 - i * 0.30, color='#888888', lw=0.7)

# ── IFU ↔ PC ──
ax.annotate('next_pc', xy=(ifu_x+0.3, pc_y-0.45), xytext=(ifu_x+0.3, ifu_y+1.75),
            fontsize=7, ha='center', color='#1F618D',
            arrowprops=dict(arrowstyle='->', color='#1F618D', lw=1.5))
ax.annotate('pc', xy=(ifu_x-0.3, ifu_y+1.75), xytext=(ifu_x-0.3, pc_y-0.45),
            fontsize=7, ha='center', color='#7D6608',
            arrowprops=dict(arrowstyle='->', color='#7D6608', lw=1.5))

# ── PC → ROM (pc_addr) ──
draw_arrow_label(ax, pc_x+1.1, pc_y, rom_x-1.0, rom_y, 'pc_addr', color='#1F618D', lw=1.2)

# ── ROM → IFU (instr_i) ──
ax.annotate('instr_i', xy=(ifu_x+1.2, ifu_y+1.2), xytext=(rom_x-0.3, rom_y-0.5),
            fontsize=7, ha='center', color='#7D6608',
            arrowprops=dict(arrowstyle='->', color='#7D6608', lw=1.2,
                          connectionstyle='arc3,rad=-0.4'))

# ── IFU → IF/ID (instr, pc, pc+4) ──
draw_arrow_label(ax, ifu_x+1.4, ifu_y, pipe_x-1.0, ifu_y, 'instr, pc,\npc+4', color='#1F618D', lw=1.5)

# ── Legend ──
legend_x, legend_y = 11.5, 6.5
ax.text(legend_x, legend_y, 'Legend', fontsize=8, fontweight='bold')
items = [
    ('Register', C_REG),
    ('Combinational', C_LOGIC),
    ('Pipeline Reg', C_PIPE),
    ('Interrupt', C_INTR),
]
for i, (label, color) in enumerate(items):
    ly = legend_y - 0.4 - i * 0.35
    box = FancyBboxPatch((legend_x-0.3, ly-0.15), 0.6, 0.3,
                         boxstyle="round,pad=0.02",
                         facecolor=color, edgecolor=C_BORDER, linewidth=0.8)
    ax.add_patch(box)
    ax.text(legend_x+0.5, ly, label, fontsize=7, va='center')

# ── Note ──
ax.text(7, 0.6, 'intr_take_now: combinational — PC jumps to handler immediately upon interrupt pending.\n'
        'interrupt_taken: registered — blocks stale branch/jump signals in the next cycle.',
        ha='center', fontsize=7, color='#922B21', style='italic')

plt.tight_layout()
plt.savefig('D:/Path/RISC-V-TEST/Project/FX-RV32_RemoveM_Custom/python/plot/Structure/fig_if_stage.png',
            dpi=200, bbox_inches='tight', facecolor='white')
plt.savefig('D:/Path/RISC-V-TEST/Project/FX-RV32_RemoveM_Custom/python/plot/Structure/fig_if_stage.pdf',
            bbox_inches='tight', facecolor='white')
plt.close()
print('Saved: fig_if_stage.png + fig_if_stage.pdf')
