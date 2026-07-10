# Figures for "Interrupt Scheme and Shadow Registers" — English Version

## Figure X-1: Interrupt System Overall Architecture

**Render with**: https://mermaid.live

```mermaid
graph TB
    subgraph Interrupt_Sources [Interrupt Sources]
        SW[Software Interrupt<br/>intr_software_i]
        TIMER[Timer Interrupt<br/>intr_timer_i]
        EXT[External Interrupt<br/>intr_external_i]
        SPI[SPI Interrupt<br/>intr_spi_i]
        I2C[I2C Interrupt<br/>intr_i2c_i]
    end

    subgraph CSR_Regfile [CSR Register File]
        CSR[csr_regfile<br/>mstatus / mtvec<br/>mepc / mcause<br/>mie / mip]
    end

    subgraph Interrupt_Controller [Interrupt Controller]
        IC[interrupt_controller<br/>Priority Encoder<br/>MEI>MTI>SPI>I2C>MSI<br/>Vector Address Calculation]
    end

    subgraph Interrupt_Pipeline [Interrupt Pipeline Controller]
        IP[interrupt_pipeline<br/>2-State FSM<br/>mepc selection + bus_ready dispatch<br/>CSR update control<br/>shadow_save / shadow_restore generation]
    end

    subgraph IFU [Instruction Fetch Unit]
        IFU_BLK[ifu_top<br/>next_pc priority:<br/>interrupt > branch > jump > stall > pc+4]
    end

    subgraph Hazard_Unit [Hazard Unit]
        HAZ[hazard_unit<br/>intr_flush_if/id/ex/mem/wb<br/>5-stage pipeline flush]
    end

    subgraph Regfile [Register File]
        RF[regfile<br/>32 General-Purpose Registers<br/>31 Shadow Registers<br/>3-Level Write Priority]
    end

    SW --> IC
    TIMER --> IC
    EXT --> IC
    SPI --> IC
    I2C --> IC

    CSR -- "mie / mip / mstatus / mtvec" --> IC
    IC -- "intr_pending / intr_cause" --> IP
    IC -- "intr_handler_addr" --> IFU_BLK

    IP -- "interrupt_taken" --> IFU_BLK
    IP -- "interrupt_flush" --> HAZ
    IP -- "mepc / mcause / mstatus write" --> CSR
    IP -- "shadow_save / shadow_restore" --> RF

    HAZ -- "flush control" --> IFU_BLK

    style IC fill:#D5E8D4,stroke:#82B366
    style IP fill:#DAE8FC,stroke:#6C8EBF
    style CSR fill:#FFF2CC,stroke:#D6B656
    style RF fill:#E1D5E7,stroke:#9673A6
    style IFU_BLK fill:#F8CECC,stroke:#B85450
    style HAZ fill:#D5E8D4,stroke:#82B366
```

---

## Figure X-2: Vectored Mode Interrupt Vector Table Memory Layout

**Render with**: https://mermaid.live

```mermaid
graph TB
    subgraph Memory_Address_Space [Memory Address Space]
        direction TB

        BASE["BASE = {mtvec[31:2], 2'b0}<br/>Vector Table Base (4-byte aligned)"]

        subgraph Vector_Slots [Vector Slots — 4 bytes each]
            S0["BASE+0x00 │ cause=0 │ j default_handler"]
            S1["BASE+0x04 │ cause=1 │ j default_handler"]
            S2["BASE+0x08 │ cause=2 │ j default_handler"]
            S3["BASE+0x0C │ cause=3 │ j software_handler  ◀ MSI"]
            S4["BASE+0x10 │ cause=4 │ j default_handler"]
            S5["BASE+0x14 │ cause=5 │ j default_handler"]
            S6["BASE+0x18 │ cause=6 │ j default_handler"]
            S7["BASE+0x1C │ cause=7 │ j timer_handler     ◀ MTI"]
            S8["BASE+0x20 │ cause=8 │ j default_handler"]
            S9["BASE+0x24 │ cause=9 │ j default_handler"]
            S10["BASE+0x28 │ cause=10│ j default_handler"]
            S11["BASE+0x2C │ cause=11│ j external_handler  ◀ MEI"]
            S12["BASE+0x30 │ cause=12│ j spi_handler       ◀ SPI"]
            S13["BASE+0x34 │ cause=13│ j i2c_handler       ◀ I2C"]
        end
    end

    BASE --> S0
    S0 --> S1 --> S2 --> S3 --> S4 --> S5 --> S6 --> S7 --> S8 --> S9 --> S10 --> S11 --> S12 --> S13

    style S3 fill:#D5E8D4,stroke:#82B366,color:#000
    style S7 fill:#DAE8FC,stroke:#6C8EBF,color:#000
    style S11 fill:#FFF2CC,stroke:#D6B656,color:#000
    style S12 fill:#E1D5E7,stroke:#9673A6,color:#000
    style S13 fill:#F8CECC,stroke:#B85450,color:#000
    style BASE fill:#F5F5F5,stroke:#666,color:#000
```

---

## Figure X-3: Constant 2-Cycle Interrupt Response Timing Diagram

**Render with**: https://wavedrom.com/editor.html

Paste the entire `{ signal: [...] }` object below into the left editor panel.

```wavedrom
{ signal: [
  { name: 'clk',            wave: 'p..........', period: 2 },
  { name: 'GPIO intr',      wave: '01.0.......' },
  { name: 'intr_pending',   wave: '01...0.....' },
  { name: 'intr_accepted',  wave: '0.1.0......' },
  { name: 'intr_taken',     wave: '0.1.0......' },
  { name: 'CSR write',      wave: '0.1.0......', data: 'mepc mcause mstatus' },
  { name: 'intr_flush',     wave: '0.1.0......' },
  { name: 'PC (IF stage)',  wave: '=.=.=......', data: 'PC0  PC0+4  handler' },
  { name: 'shadow_save',    wave: '0...1.0....' },
  { name: 'x1-x31 regs',    wave: '=....=.....', data: 'original context  snapshot to shadow' },
],
  head: { text: 'Constant 2-Cycle Interrupt Response Timing' },
  foot: { text: ['GPIO fires', 'T0: accept intr', 'T1: PC=handler', 'ISR in IF'],
          tick: [1, 3, 5, 7] },
  config: { hscale: 2 }
}
```

**Timing explanation** (verified against RTL — `core_top.v`, `interrupt_pipeline.v`, `ifu_top.v`, `pc_reg.v`):

| Signal | Wave | Explanation |
|--------|------|-------------|
| `clk` | `p..........` (period=2) | 5 clock cycles. One full cycle = 2 time units (chars). Rising edges at tu 0, 2, 4, 6, 8. |
| `GPIO intr` | `01.0.......` | 1-cycle pulse: low at tu0, high at tu1-2, clears at tu3. |
| `intr_pending` | `01...0.....` | Follows GPIO but holds **1 extra cycle**: high at tu1-4 (2 cycles total). This ensures it is sampled by `interrupt_pipeline` at the rising edge. |
| `intr_accepted` | `0.1.0......` | 1-cycle registered pulse: high at tu2-3. Goes high at T0↑ (tu2), cleared at T1↑ (tu4). |
| `intr_taken` | `0.1.0......` | Same as `intr_accepted`. 1-cycle pulse. Fed to `ifu_top` as `interrupt_pending_i` for PC redirection. |
| `CSR write` | `0.1.0......` | `mepc`, `mcause`, `mstatus` written simultaneously at T0↑. |
| `intr_flush` | `0.1.0......` | 1-cycle pulse. `hazard_unit` fans this out to all 5 pipeline stages. |
| `PC (IF)` | `=.=.=......` | **PC0** (tu0-1) → **PC0+4** (tu2-3, updated at T0↑ when `pc_reg` sees old `intr_taken=0` and takes normal next PC) → **handler** (tu4+, updated at T1↑ when `pc_reg` sees `intr_taken=1` and `next_pc=intr_handler_addr`). |
| `shadow_save` | `0...1.0....` | 1-cycle pulse at tu4-5, delayed by 1 cycle after acceptance (triggers in `else if (interrupt_accepted)` branch at T1↑). |
| `x1-x31 regs` | `=....=.....` | Original context held until shadow_save, then snapshot taken. ISR can now freely modify registers. |

**Key timing relationship**:
- T0↑ (tu2): `intr_accepted<=1`, `intr_taken<=1`, `CSR write<=1`, `intr_flush<=1`, `PC<=PC0 (hold)`
- T1↑ (tu4): `intr_accepted<=0`, `shadow_save<=1`, `PC<=handler`
- ISR first instruction in IF at tu4 (cycle starting at T1↑)
- **Total: 2 cycles from acceptance to ISR in IF**

**Note**: After exporting SVG, add T0↑/T1↑ edge markers and the "2-cycle" brace annotation in a vector graphics editor.

---

## Figure X-4: Register File Internal Structure (with Shadow Registers)

**Render with**: https://mermaid.live

```mermaid
graph TB
    subgraph Read_Ports [Read Ports — Combinational Logic]
        RADDR1[Read Address 1<br/>raddr1_i]
        RADDR2[Read Address 2<br/>raddr2_i]
        CMP1["Address Match?"]
        CMP2["Address Match?"]
        RDATA1[Read Data 1<br/>rdata1_o]
        RDATA2[Read Data 2<br/>rdata2_o]
    end

    subgraph GPR_Array [General-Purpose Register Array]
        REGS["registers[0:31]<br/>32 × 32-bit<br/>x0 hardwired to 0"]
    end

    subgraph Shadow_Array [Shadow Register Array]
        SHADOW["shadow_registers[1:31]<br/>31 × 32-bit<br/>Gated by SHADOW_EN"]
    end

    subgraph Write_Port [Write Port — 3-Level Priority — Sequential Logic]
        direction TB
        PRI1["① shadow_restore (Highest)<br/>31-way parallel: shadow → regs<br/>Overrides any concurrent WB write"]
        PRI2["② Normal WB Write-back<br/>we_i && waddr_i ≠ 0<br/>Selects single register write"]
        PRI3["③ shadow_save (Lowest)<br/>31-way parallel: regs → shadow<br/>Snapshots full register state"]
    end

    subgraph Write_Inputs [Write Data Inputs]
        WDATA[wdata_i<br/>from WB stage]
        SAVE[shadow_save_i<br/>from interrupt_pipeline]
        RESTORE[shadow_restore_i<br/>from interrupt_pipeline]
        WE[we_i / waddr_i<br/>from WB stage]
    end

    RADDR1 --> REGS
    RADDR2 --> REGS
    RADDR1 --> CMP1
    RADDR2 --> CMP2
    WDATA --> CMP1
    WDATA --> CMP2
    REGS --> RDATA1
    REGS --> RDATA2
    CMP1 -.->|bypass on hit| RDATA1
    CMP2 -.->|bypass on hit| RDATA2

    WDATA --> PRI2
    WE --> PRI2
    RESTORE --> PRI1
    SAVE --> PRI3

    PRI1 --> REGS
    PRI2 --> REGS
    PRI3 --> SHADOW
    PRI1 --> SHADOW
    REGS --> PRI3

    style REGS fill:#D5E8D4,stroke:#82B366
    style SHADOW fill:#E1D5E7,stroke:#9673A6
    style PRI1 fill:#F8CECC,stroke:#B85450
    style PRI2 fill:#FFF2CC,stroke:#D6B656
    style PRI3 fill:#DAE8FC,stroke:#6C8EBF
```

---

## Figure X-5: Complete Interrupt Lifecycle Timing Diagram (with Shadow Register Operations)

**Render with**: https://wavedrom.com/editor.html

Paste the entire `{ signal: [...] }` object below into the left editor panel.

```wavedrom
{ signal: [
  { name: 'clk',            wave: 'p.................', period: 2 },
  { name: 'GPIO intr',      wave: '01.0...............' },
  { name: 'intr_pending',   wave: '01...0.............' },
  { name: 'intr_accepted',  wave: '0.1.0..............' },
  { name: 'intr_taken',     wave: '0.1.0..............' },
  { name: 'CSR write',      wave: '0.1.0..............' },
  { name: 'intr_flush',     wave: '0.1.0..............' },
  { name: 'PC (IF stage)',  wave: '=.=.=......=.....=.', data: 'PC0  PC0+4  handler  mepc  mepc+4' },
  { name: 'shadow_save',    wave: '0...1.0............' },
  { name: 'x1-x31 regs',    wave: '=....=....=......=.', data: 'orig ctx  snapshot  modified by ISR  restored' },
  { name: 'id_ex_mret',     wave: '0.............1.0..' },
  { name: 'shadow_restore', wave: '0.............1.0..' },
  { name: 'mstatus MIE',    wave: '1..0.............1.', data: '1  0  1' },
],
  head: { text: 'Complete Interrupt Lifecycle with Shadow Register Save and Restore' },
  foot: { text: ['GPIO fires', 'T0 accept', 'T1 PC=handler', '', 'ISR running', '', 'MRET EX', 'resume'],
          tick: [1, 3, 5, 9, 16, 20, 22, 24] },
  config: { hscale: 2 }
}
```

**Timing explanation**:
- **tu 0-4**: Interrupt entry (same as Figure X-3). GPIO fires → `intr_pending` holds 2 cycles → T0↑ accept → T1↑ PC=handler + shadow_save.
- **tu 4-20**: ISR executes. `x1-x31` registers freely modified by ISR code. Shadow registers hold pre-interrupt snapshot. `mstatus.MIE` = 0 (interrupts disabled during ISR).
- **tu 22 (MRET in EX)**: `id_ex_mret` = 1 for one full cycle. `shadow_restore` fires (1-cycle pulse). x1-x31 restored from shadow registers in parallel. `mstatus.MIE` restored to 1 (interrupts re-enabled). `interrupt_processed` cleared.
- **tu 24+ (resume)**: PC = mepc. Interrupted program resumes execution transparently. x1-x31 identical to pre-interrupt state.

**Note**: Add phase bracket annotations (Phase 1-6) in a vector graphics editor after exporting SVG, as Wavedrom does not support multi-row overlay labels.

---

## Summary

| Figure | Content | Tool | How to Render |
|--------|---------|------|---------------|
| X-1 | Interrupt System Architecture | Mermaid | https://mermaid.live → paste code → export PNG/SVG |
| X-2 | Vector Table Memory Layout | Mermaid | https://mermaid.live → paste code → export PNG/SVG |
| X-3 | 2-Cycle Interrupt Timing | Wavedrom | https://wavedrom.com/editor.html → paste JSON → export SVG |
| X-4 | Register File with Shadow Regs | Mermaid | https://mermaid.live → paste code → export PNG/SVG |
| X-5 | Complete Interrupt Lifecycle Timing | Wavedrom | https://wavedrom.com/editor.html → paste JSON → export SVG |
