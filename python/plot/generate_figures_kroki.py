#!/usr/bin/env python3
"""
自动生成论文4张示意图 — 通过 kroki.io API
图1: 架构图 (mermaid)
图2: 两级嵌套流程图 (mermaid)
图3: 2周期时序图 (wavedrom)
图4: 多Bank寄存器堆结构图 (mermaid)
"""

import urllib.request
import urllib.error
import time
import os

OUT_DIR = "D:/Path/RISC-V-TEST/Project/FX-RV32_CUSTOM/doc/NewWork"
KROKI = "https://kroki.io"

# ============================================================
# 图 1: 多Bank影子寄存器整体架构 (Fig. 1 in paper)
# ============================================================
FIG1_MERMAID = """flowchart LR
    EXT["External Interrupts<br/>Timer / GPIO / SPI / I2C"]

    subgraph CPU["FX-RV32-X Processor Core"]
        direction LR
        IF["IF<br/>Fetch"] --> ID["ID<br/>Decode"] --> EX["EX<br/>Execute"] --> MEM["MEM<br/>Memory"] --> WB["WB<br/>Writeback"]

        INTRCTRL["Interrupt Controller<br/>Priority Encoder<br/>Vector Address Calc"]
        INTRPIPE["Interrupt Pipeline<br/>Unconditional Accept + CSR<br/>Bank Pointer Management"]
        BANKCTRL["Bank Controller<br/>Pure-Combinational<br/>Preemption / Overflow / Tail-Chain"]
        REGFILE["Register File<br/>x0-x31 GPR<br/>Bank[0..N-1] Shadow"]
    end

    EXT --> INTRCTRL
    INTRCTRL -->|"intr_pending / intr_cause"| INTRPIPE
    INTRCTRL -->|"new_priority"| BANKCTRL
    INTRPIPE -->|"interrupt_accepted"| BANKCTRL
    BANKCTRL -->|"allow_nesting / bank_full / tail_chain"| INTRPIPE
    INTRCTRL -->|"intr_handler_addr"| IF
    INTRPIPE -.->|"bank_ptr / shadow_save / shadow_restore"| REGFILE
    ID -.-> REGFILE
    WB -.-> REGFILE

    style BANKCTRL fill:#fff3cd,stroke:#f0ad4e,stroke-width:3px
    style REGFILE fill:#d1ecf1,stroke:#0c5460,stroke-width:3px
    style INTRPIPE fill:#d4edda,stroke:#155724,stroke-width:2px
    style INTRCTRL fill:#d4edda,stroke:#155724,stroke-width:2px"""

# ============================================================
# 图 2: 两级中断嵌套流程 (Fig. 2 in paper)
# ============================================================
FIG2_MERMAID = """flowchart LR
    subgraph P1["1. Interrupt Entry<br/>bank_ptr 0 to 1"]
        direction TB
        S1[" "]
        T1["T1: IRQ request<br/>intr_pending=1<br/>intr_take_now=1"]
        T2["T2^: Accept (same edge)<br/>PC to handler<br/>interrupt_taken=1<br/>shadow_save=1<br/>ID/EX+EX/MEM+MEM/WB to NOP<br/>(IF/ID preserved)<br/>CSR: mepc/mcause/mstatus<br/>bank_ptr 0 to 1"]
        S1 --> T1 --> T2
    end

    subgraph P2["2. Timer ISR<br/>bank_ptr = 1"]
        direction TB
        S2[" "]
        T5["T3: 1st ISR instr in EX<br/>Latency = 2 cycles"]
        T6["Timer ISR body<br/>Clear Timer IRQ source<br/>Set MIE (re-enable ints)"]
        S2 --> T5 --> T6
    end

    subgraph P3["3. GPIO Preemption<br/>bank_ptr 1 to 2"]
        direction TB
        S3[" "]
        G1["T6: Preemption request<br/>prio 11 > 7<br/>allow_nesting=1"]
        G2["T7^: Accept (same edge)<br/>PC to GPIO handler<br/>shadow_save=1<br/>mcause=0x8000000B<br/>bank_ptr 1 to 2"]
        G4["T8^: Context saved<br/>regfile samples shadow_save<br/>x1-x31 to Bank[1]<br/>Single-cycle parallel lock"]
        S3 --> G1 --> G2 --> G4
    end

    subgraph P4["4. GPIO ISR<br/>bank_ptr = 2"]
        direction TB
        S4[" "]
        G5["T8: 1st instr in EX<br/>Latency = 2 cycles"]
        G6["GPIO ISR body<br/>gpio_count++<br/>MRET"]
        G7["T11: MRET<br/>shadow_restore=1<br/>bank_ptr 2 to 1"]
        S4 --> G5 --> G6 --> G7
    end

    subgraph P5["5. Return<br/>bank_ptr 2 to 1 to 0"]
        direction TB
        S5[" "]
        T7["T12: Context restored<br/>Bank[1] to x1-x31<br/>(Timer ISR context)"]
        T8["T14: MRET<br/>bank_ptr 1 to 0<br/>Bank[0] to x1-x31<br/>(Main program context)"]
        M1["Main program resumes<br/>bank_ptr=0, MIE=1"]
        S5 --> T7 --> T8 --> M1
    end

    M0["Main Program<br/>bank_ptr=0, MIE=1"] --> P1
    P1 --> P2 --> P3 --> P4 --> P5

    style S1 fill:none,stroke:none,color:white
    style S2 fill:none,stroke:none,color:white
    style S3 fill:none,stroke:none,color:white
    style S4 fill:none,stroke:none,color:white
    style S5 fill:none,stroke:none,color:white
    style T2 fill:#d4edda,stroke:#155724
    style G2 fill:#fff3cd,stroke:#f0ad4e
    style G4 fill:#fff3cd,stroke:#f0ad4e
    style G7 fill:#d1ecf1,stroke:#0c5460
    style T8 fill:#d1ecf1,stroke:#0c5460"""

# ============================================================
# 图 3: 2周期中断时序图 (Fig. 3 in paper) — Wavedrom
# ============================================================
FIG3_WAVEDROM = """{ signal: [
  { name: 'clk',            wave: 'p..........', period: 2 },
  { name: 'GPIO intr',      wave: '01.0.......' },
  { name: 'intr_pending',   wave: '01...0.....' },
  { name: 'intr_accepted',  wave: '0.1.0......' },
  { name: 'intr_taken',     wave: '0.1.0......' },
  { name: 'CSR write',      wave: '0.1.0......', data: 'mepc mcause mstatus' },
  { name: 'intr_flush',     wave: '0.1.0......' },
  { name: 'PC (IF stage)',  wave: '=.=.=......', data: 'PC0  PC0+4  handler' },
  { name: 'shadow_save',    wave: '0...1.0....' },
  { name: 'x1-x31 regs',    wave: '=....=.....', data: 'original context  snapshot' },
],
  head: { text: 'Constant 2-Cycle Interrupt Response Timing' },
  foot: { text: ['GPIO fires', 'T0 accept', 'T1 PC=handler', 'ISR in IF'],
          tick: [1, 3, 5, 7] },
  config: { hscale: 2 }
}"""

# ============================================================
# 图 4: 多Bank寄存器堆结构 (Fig. 4 in paper) — Mermaid
# ============================================================
FIG4_MERMAID = """graph TB
    subgraph Read_Ports["Read Ports - Combinational"]
        RADDR1["Read Addr 1 (rs1)"]
        RADDR2["Read Addr 2 (rs2)"]
        RDATA1["Read Data 1"]
        RDATA2["Read Data 2"]
    end

    subgraph GPR_Array["General-Purpose Registers"]
        REGS["x0-x31 (32 x 32-bit)<br/>x0 hardwired to 0"]
    end

    subgraph Shadow_MultiBank["Multi-Bank Shadow Register Array"]
        direction LR
        B0["Bank[0]<br/>x1-x31<br/>31 x 32b"]
        B1["Bank[1]<br/>x1-x31<br/>31 x 32b"]
        B2["Bank[2]<br/>x1-x31<br/>31 x 32b"]
        B3["Bank[N-1]<br/>x1-x31<br/>31 x 32b"]
        BMUX["Bank Select MUX<br/>(bank_ptr controlled)"]
    end

    subgraph Write_Port["Write Port - 3-Level Priority"]
        direction TB
        PRI1["1. shadow_restore (Highest)<br/>31-way parallel: Bank[ptr] to regs<br/>Overrides concurrent WB"]
        PRI2["2. Normal WB Write-back<br/>we_i && waddr_i != 0<br/>Single register write"]
        PRI3["3. shadow_save (Lowest)<br/>31-way parallel: regs to Bank[ptr-1]<br/>Snapshots full register state"]
    end

    subgraph Write_Inputs["Write Control Signals"]
        WDATA["wdata_i (WB stage)"]
        SAVE["shadow_save_i"]
        RESTORE["shadow_restore_i"]
        WE["we_i / waddr_i"]
        BPTR["bank_ptr[3:0]"]
    end

    RADDR1 --> REGS
    RADDR2 --> REGS
    REGS --> RDATA1
    REGS --> RDATA2

    WDATA --> PRI2
    WE --> PRI2
    RESTORE --> PRI1
    SAVE --> PRI3
    BPTR --> BMUX

    PRI1 --> REGS
    PRI2 --> REGS
    PRI3 --> B0
    PRI3 --> B1
    PRI3 --> B2
    PRI3 --> B3
    PRI1 --> B0
    PRI1 --> B1
    PRI1 --> B2
    PRI1 --> B3
    REGS --> PRI3
    BMUX -.-> PRI1

    style REGS fill:#D5E8D4,stroke:#82B366
    style B0 fill:#E1D5E7,stroke:#9673A6
    style B1 fill:#E1D5E7,stroke:#9673A6
    style B2 fill:#E1D5E7,stroke:#9673A6
    style B3 fill:#E1D5E7,stroke:#9673A6
    style BMUX fill:#fff3cd,stroke:#f0ad4e
    style PRI1 fill:#F8CECC,stroke:#B85450
    style PRI2 fill:#FFF2CC,stroke:#D6B656
    style PRI3 fill:#DAE8FC,stroke:#6C8EBF"""


def render_kroki(diagram_type, source, output_path, description):
    """Render a diagram via kroki.io API."""
    url = f"{KROKI}/{diagram_type}/png"
    data = source.encode('utf-8')

    print(f"  Rendering {description}...", end=" ", flush=True)
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, data=data, method='POST')
            req.add_header('Content-Type', 'text/plain')
            with urllib.request.urlopen(req, timeout=60) as resp:
                png_data = resp.read()
            with open(output_path, 'wb') as f:
                f.write(png_data)
            size_kb = len(png_data) / 1024
            print(f"OK ({size_kb:.0f} KB)")
            return True
        except urllib.error.HTTPError as e:
            print(f"HTTP {e.code} (attempt {attempt+1}/3)")
            if attempt < 2:
                time.sleep(2)
        except Exception as e:
            print(f"Error: {e} (attempt {attempt+1}/3)")
            if attempt < 2:
                time.sleep(2)
    print("FAILED")
    return False


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    figures = [
        ("mermaid", FIG1_MERMAID, f"{OUT_DIR}/fig1_v2.png", "Fig.1 Architecture"),
        ("mermaid", FIG2_MERMAID, f"{OUT_DIR}/fig2_v2.png", "Fig.2 Nested Flow"),
        ("wavedrom", FIG3_WAVEDROM, f"{OUT_DIR}/fig_timing_v2.png", "Fig.3 Timing"),
        ("mermaid", FIG4_MERMAID, f"{OUT_DIR}/fig_regfile_v2.png", "Fig.4 Regfile Multi-Bank"),
    ]

    print("Generating 4 figures via kroki.io...")
    print(f"Output directory: {OUT_DIR}")
    print()

    success = 0
    for dia_type, source, path, desc in figures:
        if render_kroki(dia_type, source, path, desc):
            success += 1
        time.sleep(1)  # rate limiting

    print()
    print(f"Done: {success}/4 figures generated successfully")

    if success < 4:
        print("\nFailed figures need manual export:")
        print("  Fig.1+2+4: https://mermaid.live")
        print("  Fig.3:     https://wavedrom.com/editor.html")
        print("\nSource code: doc/NewWork/patent_figures_mermaid.md")
        print("             doc/interrupt/figures_english.md")


if __name__ == '__main__':
    main()
