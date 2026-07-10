#!/usr/bin/env python3
"""使用 mermaid.ink API 生成 mermaid 图, wavedrom 图用本地方式"""

import urllib.request
import zlib
import base64
import os
import json

OUT = "D:/Path/RISC-V-TEST/Project/FX-RV32_CUSTOM/doc/NewWork"

# ========== Mermaid 图 (使用 mermaid.ink) ==========
def mermaid_to_png(code, outpath):
    # Direct base64url encoding (no compression) — simpler and more reliable
    encoded = base64.urlsafe_b64encode(code.encode('utf-8')).decode()
    url = f"https://mermaid.ink/img/{encoded}"
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = resp.read()
        with open(outpath, 'wb') as f:
            f.write(data)
        return len(data)
    except Exception as e:
        print(f"  FAIL: {e}")
        return 0

# ========== Wavedrom 图 (使用 wavedrom.com editor 的截图... 不行, 用 svg 转) ==========
# wavedrom 也可以用 kroki, 但 403 了。尝试直接生成 Wavedrom SVG 用 bit-field 方式
# 其实对于时序图, 可以手写 SVG

# ========== Fig 1: Architecture ==========
fig1 = """graph LR
    EXT["External IRQ<br/>Timer/GPIO/SPI/I2C"]
    subgraph CPU["FX-RV32-X Core"]
        direction LR
        IF["IF Fetch"] --> ID["ID Decode"] --> EX["EX Execute"] --> MEM["MEM Memory"] --> WB["WB Writeback"]
        IC["Interrupt Controller<br/>Priority + Vector"]
        IP["Interrupt Pipeline<br/>Accept + CSR + Bank Ptr"]
        BC["Bank Controller<br/>Comb. Preemption Judge"]
        RF["Register File<br/>GPR + N-Bank Shadow"]
    end
    EXT --> IC -->|"pending/cause"| IP
    IC -->|"priority"| BC
    IP -->|"accepted"| BC
    BC -->|"allow/full/tail"| IP
    IC -->|"handler addr"| IF
    IP -.->|"save/restore/ptr"| RF
    ID -.-> RF
    WB -.-> RF
    style BC fill:#fff3cd,stroke:#f0ad4e,stroke-width:3px
    style RF fill:#d1ecf1,stroke:#0c5460,stroke-width:3px"""

# ========== Fig 2: Nested Flow ==========
fig2 = """flowchart LR
    subgraph P1["1. Entry (0->1)"]
        T2["T2: Accept edge<br/>PC=handler, save=1<br/>flush EX/MEM/WB<br/>CSR write, bank_ptr=1"]
    end
    subgraph P2["2. Timer ISR (ptr=1)"]
        T5["T3: 1st instr EX<br/>Latency = 2 cycles"]
        T6["Clear Timer, set MIE"]
    end
    subgraph P3["3. GPIO Preempt (1->2)"]
        G2["T7: Accept GPIO<br/>PC=GPIO handler<br/>save=1, bank_ptr=2"]
        G4["T8: x1-x31 -> Bank[1]<br/>Single-cycle lock"]
    end
    subgraph P4["4. GPIO ISR (ptr=2)"]
        G5["T8: 1st instr EX<br/>Latency = 2 cycles"]
        G7["MRET: restore=1<br/>bank_ptr=1"]
    end
    subgraph P5["5. Return (2->1->0)"]
        T7["T12: Bank[1] -> regs<br/>Timer ctx restored"]
        T8["T14: Bank[0] -> regs<br/>Main ctx restored"]
    end
    M0["Main<br/>ptr=0"] --> P1 --> P2 --> P3 --> P4 --> P5
    style T2 fill:#d4edda,stroke:#155724
    style G2 fill:#fff3cd,stroke:#f0ad4e
    style G7 fill:#d1ecf1,stroke:#0c5460"""

# ========== Fig 4: Multi-Bank Register File ==========
fig4 = """graph TB
    subgraph RD["Read Ports"]
        RA1["raddr1 (rs1)"] --> R1["rdata1"]
        RA2["raddr2 (rs2)"] --> R2["rdata2"]
    end
    GPR["GPR x0-x31<br/>32 x 32-bit"]
    subgraph SH["Multi-Bank Shadow Array"]
        direction LR
        B0["Bank[0]<br/>x1-x31"]
        B1["Bank[1]<br/>x1-x31"]
        B2["Bank[2]<br/>x1-x31"]
        BN["Bank[N-1]<br/>x1-x31"]
        MUX["Bank Select MUX<br/>(bank_ptr)"]
    end
    subgraph WP["Write Port - 3 Priority Levels"]
        direction TB
        P1["1. shadow_restore (Highest)<br/>Bank[ptr] -> GPR (parallel)"]
        P2["2. Normal WB<br/>Single register write"]
        P3["3. shadow_save (Lowest)<br/>GPR -> Bank[ptr-1] (parallel)"]
    end
    RA1 --> GPR
    RA2 --> GPR
    GPR --> R1
    GPR --> R2
    P1 --> GPR
    P2 --> GPR
    P3 --> B0
    P3 --> B1
    P3 --> B2
    P3 --> BN
    GPR --> P3
    MUX -.-> P1
    style GPR fill:#D5E8D4,stroke:#82B366
    style B0 fill:#E1D5E7,stroke:#9673A6
    style B1 fill:#E1D5E7,stroke:#9673A6
    style B2 fill:#E1D5E7,stroke:#9673A6
    style BN fill:#E1D5E7,stroke:#9673A6
    style P1 fill:#F8CECC,stroke:#B85450
    style P2 fill:#FFF2CC,stroke:#D6B656
    style P3 fill:#DAE8FC,stroke:#6C8EBF"""

# ========== Render ==========
figures = [
    ("fig1_v2.png", fig1, "Fig.1 Architecture"),
    ("fig2_v2.png", fig2, "Fig.2 Nested Flow"),
    ("fig_regfile_v2.png", fig4, "Fig.4 Regfile Multi-Bank"),
]

print("Generating figures via mermaid.ink...")
for fname, code, desc in figures:
    outpath = os.path.join(OUT, fname)
    print(f"  {desc}...", end=" ", flush=True)
    size = mermaid_to_png(code, outpath)
    if size:
        print(f"OK ({size/1024:.0f} KB)")
    else:
        print("FAILED")

# ========== Fig 3: Wavedrom timing (手动生成 SVG) ==========
# Wavedrom 时序图直接写 SVG
print("  Fig.3 Timing (manual SVG)...", end=" ", flush=True)
svg = '''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 400" width="800" height="400">
  <style>
    text { font-family: monospace; font-size: 14px; }
    .title { font-size: 16px; font-weight: bold; }
    .wave-high { stroke: #2c3e50; stroke-width: 2.5; fill: none; }
    .wave-low { stroke: #2c3e50; stroke-width: 1; fill: none; }
    .edge { stroke: #e74c3c; stroke-width: 1; stroke-dasharray: 4,4; }
    .label { font-size: 12px; fill: #555; }
    .signal-name { font-size: 13px; font-weight: bold; fill: #2c3e50; }
  </style>
  <!-- Title -->
  <text x="400" y="25" text-anchor="middle" class="title">Constant 2-Cycle Interrupt Response Timing</text>

  <!-- Signal names -->
  <text x="10" y="60" class="signal-name">clk</text>
  <text x="10" y="95" class="signal-name">GPIO intr</text>
  <text x="10" y="130" class="signal-name">intr_pending</text>
  <text x="10" y="165" class="signal-name">intr_accepted</text>
  <text x="10" y="200" class="signal-name">intr_taken</text>
  <text x="10" y="235" class="signal-name">CSR write</text>
  <text x="10" y="270" class="signal-name">intr_flush</text>
  <text x="10" y="305" class="signal-name">PC (IF)</text>
  <text x="10" y="340" class="signal-name">shadow_save</text>
  <text x="10" y="375" class="signal-name">x1-x31</text>

  <!-- Clock grid -->
  <line x1="140" y1="40" x2="140" y2="390" stroke="#ddd" stroke-width="0.5"/>
  <line x1="240" y1="40" x2="240" y2="390" stroke="#ddd" stroke-width="0.5"/>
  <line x1="340" y1="40" x2="340" y2="390" stroke="#ddd" stroke-width="0.5"/>
  <line x1="440" y1="40" x2="440" y2="390" stroke="#ddd" stroke-width="0.5"/>
  <line x1="540" y1="40" x2="540" y2="390" stroke="#ddd" stroke-width="0.5"/>
  <line x1="640" y1="40" x2="640" y2="390" stroke="#ddd" stroke-width="0.5"/>

  <!-- Edge labels -->
  <text x="140" y="395" text-anchor="middle" class="label">T0</text>
  <text x="240" y="395" text-anchor="middle" class="label">T1</text>
  <text x="340" y="395" text-anchor="middle" class="label">T2</text>
  <text x="440" y="395" text-anchor="middle" class="label">T3</text>
  <text x="540" y="395" text-anchor="middle" class="label">T4</text>
  <text x="640" y="395" text-anchor="middle" class="label">T5</text>

  <text x="120" y="50" class="label" text-anchor="end">GPIO fires</text>
  <text x="220" y="50" class="label" text-anchor="end">T0 accept</text>
  <text x="360" y="50" class="label">T1 PC=handler</text>
  <text x="480" y="50" class="label">ISR in IF</text>

  <!-- clk wave (5 cycles shown) -->
  <polyline points="140,48 140,55 180,55 180,48 190,48 190,55 230,55 230,48 240,48 240,55 280,55 280,48 290,48 290,55 330,55 330,48 340,48 340,55 380,55 380,48 390,48 390,55 430,55 430,48 440,48 440,55 480,55 480,48 490,48 490,55 530,55 530,48 540,48 540,55 580,55 580,48 590,48 590,55 630,55 630,48 640,48 640,55 680,55 680,48" stroke="#2c3e50" stroke-width="1.5" fill="none"/>

  <!-- GPIO intr: 01.0...... -->
  <line x1="140" y1="90" x2="160" y2="90" stroke="#2c3e50" stroke-width="1"/>
  <line x1="160" y1="80" x2="240" y2="80" stroke="#e74c3c" stroke-width="2.5"/>
  <line x1="240" y1="80" x2="260" y2="80" stroke="#e74c3c" stroke-width="2.5"/>
  <line x1="260" y1="90" x2="680" y2="90" stroke="#2c3e50" stroke-width="1"/>

  <!-- intr_pending: 01...0..... -->
  <line x1="140" y1="125" x2="160" y2="125" stroke="#2c3e50" stroke-width="1"/>
  <line x1="160" y1="115" x2="340" y2="115" stroke="#e74c3c" stroke-width="2.5"/>
  <line x1="340" y1="115" x2="360" y2="115" stroke="#e74c3c" stroke-width="2.5"/>
  <line x1="360" y1="125" x2="680" y2="125" stroke="#2c3e50" stroke-width="1"/>

  <!-- intr_accepted: 0.1.0...... -->
  <line x1="140" y1="160" x2="210" y2="160" stroke="#2c3e50" stroke-width="1"/>
  <line x1="210" y1="150" x2="310" y2="150" stroke="#2c3e50" stroke-width="2.5"/>
  <line x1="310" y1="160" x2="680" y2="160" stroke="#2c3e50" stroke-width="1"/>

  <!-- intr_taken: 0.1.0...... (same) -->
  <line x1="140" y1="195" x2="210" y2="195" stroke="#2c3e50" stroke-width="1"/>
  <line x1="210" y1="185" x2="310" y2="185" stroke="#2c3e50" stroke-width="2.5"/>
  <line x1="310" y1="195" x2="680" y2="195" stroke="#2c3e50" stroke-width="1"/>

  <!-- CSR write: 0.1.0...... -->
  <line x1="140" y1="230" x2="210" y2="230" stroke="#2c3e50" stroke-width="1"/>
  <line x1="210" y1="220" x2="310" y2="220" stroke="#2c3e50" stroke-width="2.5"/>
  <line x1="310" y1="230" x2="680" y2="230" stroke="#2c3e50" stroke-width="1"/>
  <text x="260" y="218" text-anchor="middle" font-size="10" fill="#e74c3c">mepc,mcause,mstatus</text>

  <!-- intr_flush: 0.1.0...... -->
  <line x1="140" y1="265" x2="210" y2="265" stroke="#2c3e50" stroke-width="1"/>
  <line x1="210" y1="255" x2="310" y2="255" stroke="#2c3e50" stroke-width="2.5"/>
  <line x1="310" y1="265" x2="680" y2="265" stroke="#2c3e50" stroke-width="1"/>

  <!-- PC: =.=.=...... with data labels -->
  <line x1="140" y1="300" x2="190" y2="300" stroke="#2c3e50" stroke-width="1"/>
  <line x1="210" y1="300" x2="290" y2="300" stroke="#2c3e50" stroke-width="1"/>
  <line x1="310" y1="300" x2="680" y2="300" stroke="#2c3e50" stroke-width="1"/>
  <text x="160" y="298" text-anchor="middle" font-size="11" fill="#555">PC0</text>
  <text x="255" y="298" text-anchor="middle" font-size="11" fill="#555">PC0+4</text>
  <text x="400" y="298" text-anchor="middle" font-size="11" fill="#e74c3c">handler</text>
  <!-- dotted transitions -->
  <line x1="190" y1="300" x2="210" y2="300" stroke="#2c3e50" stroke-width="0.5" stroke-dasharray="2,2"/>
  <line x1="290" y1="300" x2="310" y2="300" stroke="#2c3e50" stroke-width="0.5" stroke-dasharray="2,2"/>

  <!-- shadow_save: 0...1.0.... -->
  <line x1="140" y1="335" x2="340" y2="335" stroke="#2c3e50" stroke-width="1"/>
  <line x1="340" y1="325" x2="440" y2="325" stroke="#2c3e50" stroke-width="2.5"/>
  <line x1="440" y1="335" x2="680" y2="335" stroke="#2c3e50" stroke-width="1"/>

  <!-- x1-x31: =....=..... -->
  <line x1="140" y1="370" x2="240" y2="370" stroke="#2c3e50" stroke-width="1"/>
  <line x1="340" y1="370" x2="680" y2="370" stroke="#2c3e50" stroke-width="1"/>
  <text x="185" y="368" text-anchor="middle" font-size="11" fill="#555">original context</text>
  <text x="440" y="368" text-anchor="middle" font-size="11" fill="#e74c3c">snapshot</text>
  <line x1="240" y1="370" x2="340" y2="370" stroke="#2c3e50" stroke-width="0.5" stroke-dasharray="2,2"/>

  <!-- Annotations -->
  <text x="240" y="45" text-anchor="middle" font-size="11" fill="#e74c3c" font-weight="bold">T0&#x2191;</text>
  <text x="340" y="45" text-anchor="middle" font-size="11" fill="#e74c3c" font-weight="bold">T1&#x2191;</text>

  <!-- "2-cycle" brace annotation -->
  <line x1="210" y1="405" x2="310" y2="405" stroke="#e74c3c" stroke-width="2"/>
  <line x1="210" y1="400" x2="210" y2="410" stroke="#e74c3c" stroke-width="2"/>
  <line x1="310" y1="400" x2="310" y2="410" stroke="#e74c3c" stroke-width="2"/>
  <text x="260" y="418" text-anchor="middle" font-size="12" fill="#e74c3c" font-weight="bold">2-cycle latency</text>
</svg>'''

svg_path = os.path.join(OUT, "fig_timing_v2.svg")
with open(svg_path, 'w', encoding='utf-8') as f:
    f.write(svg)
print(f"OK ({len(svg)/1024:.0f} KB SVG)")

# Convert SVG to PNG using Python's cairosvg if available
try:
    import cairosvg
    png_path = os.path.join(OUT, "fig_timing_v2.png")
    cairosvg.svg2png(url=svg_path, write_to=png_path, output_width=1600, output_height=800)
    size = os.path.getsize(png_path) / 1024
    print(f"  Converted to PNG: {size:.0f} KB")
except ImportError:
    print("  (cairosvg not available, SVG only. Install: pip install cairosvg)")

print("\nDone!")
print("Note: Fig.3 timing is hand-drawn SVG for precise control.")
print("For production quality, consider exporting from https://wavedrom.com/editor.html")
