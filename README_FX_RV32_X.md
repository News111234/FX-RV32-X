# FX-RV32-X

A RISC-V processor with **multi-bank shadow registers** for priority-based nested interrupts with **constant 2-cycle latency** at every nesting level.

FX-RV32-X extends the [FX-RV32](https://github.com/News111234/FX-RV32) baseline by replacing the single shadow register bank with an $N$-bank array managed by a purely combinational Bank Controller. All Bank management—allocation, release, preemption judgment, tail-chaining, and overflow handling—is performed autonomously by hardware, requiring zero software intervention and no ISA extensions.

## Key Features

| Feature | Description |
|---------|-------------|
| **Multi-Bank Shadow Registers** | $N$ independent banks (default $N=4$), each 31×32-bit, supporting $N-1$ levels of interrupt nesting |
| **Constant 2-Cycle Latency** | Interrupt entry latency fixed at 2 clock cycles regardless of nesting depth |
| **Zero-Cycle Context Save** | All 31 GPRs captured in parallel in a single cycle per nesting level |
| **Bank Controller** | Pure combinational logic—preemption decision in 0 additional cycles |
| **Tail-Chaining** | Hardware detection and skip of redundant context restore on back-to-back interrupts |
| **Configurable Overflow** | Two policies: Hard Limit (preserve all contexts) and Degradation Reuse (guarantee admission) |
| **Software Transparent** | No ISA extensions, no custom instructions, no new CSRs required |
| **5-Stage Pipeline** | IF → ID → EX → MEM → WB with forwarding and hazard handling |
| **Rich Peripheral Set** | UART, GPIO, Timer, SPI Master, SPI Flash Controller, I2C Master |

## Architecture

```
                    ┌─────────────────────────────────┐
                    │        FX-RV32-X Core            │
                    │                                  │
  External ──────►  │  Interrupt    ┌──────────────┐  │
  Interrupts        │  Controller   │Bank Controller│  │
  (Timer/GPIO/      │  (Priority    │(Combinational)│  │
   SPI/I2C/SW)      │   Encoder)    │Preemption /   │  │
                    │               │Overflow /     │  │
                    │               │Tail-Chain     │  │
                    │               └──────┬───────┘  │
                    │                      │           │
                    │  ┌───────────────────┘           │
                    │  ▼                               │
                    │  Interrupt Pipeline Controller    │
                    │  (Unconditional Accept + CSR)     │
                    │  │                                │
                    │  ▼                               │
                    │  Register File                    │
                    │  ┌──────┬──────┬──────┬──────┐   │
                    │  │Bank 0│Bank 1│Bank 2│Bank N│   │
                    │  │x1-31 │x1-31 │x1-31 │x1-31 │   │
                    │  └──────┴──────┴──────┴──────┘   │
                    └─────────────────────────────────┘
```

## Quick Start

### Prerequisites

- **Simulation**: Modelsim / QuestaSim, or Verilator + GCC
- **FPGA Synthesis**: Vivado 2022.2+ (Xilinx Kintex-7 xc7k325tffg900-2)
- **ASIC Synthesis**: Synopsys Design Compiler (SMIC 55nm)
- **Assembly**: Python 3.6+

### Verilator Simulation

```bash
cd sim
make          # Build the simulation executable
make run      # Build + run with program.hex
make clean    # Remove build artifacts
```

The simulation top module (`core_top_sim`) instantiates the CPU core, data RAM, bus arbiter, and all peripherals. The test program is loaded from `sim/program.hex` (one 32-bit word per line, plain hex).

### Assembling Test Programs

```bash
# Assemble assembly source to hex
cd python
python asm_to_hex.py input.s -o ../sim/program.hex

# Or generate Verilog ROM format
python asm_to_hex.py input.s --rom
```

The assembler (`riscv_asm7.py`) supports RV32I instructions, pseudo-instructions, labels, data directives, and CSR instructions. See `python/asm_to_hex.py --help` for options.

### UVM Verification (Modelsim/Questa)

```bash
cd uvm/nested_uvm
# Run a specific test (10 available)
vsim -c -do "set TEST test_nested; do run_nested.tcl"
# GUI mode with waveforms
vsim -do "set TEST test_triple; set GUI 1; do run_nested.tcl"
# Configure Bank count and overflow policy
vsim -c -do "set TEST test_overflow; set BANKS 1; set POL 0; do run_nested.tcl"
```

**Available UVM tests:**

| # | Test | BANKS | Description |
|---|------|:-----:|-------------|
| 1 | `test_single_intr` | 4 | Single Timer interrupt |
| 2 | `test_ultra_min` | 4 | Minimal interrupt entry/exit |
| 3 | `test_no_intr` | 4 | No interrupt (baseline) |
| 4 | `test_nested` | 4 | Two-level nesting (Timer → GPIO) |
| 5 | `test_overflow` | 1 | Bank overflow with Hard Limit |
| 6 | `test_overflow_min` | 1 | Single-Bank minimal test |
| 7 | `test_context` | 4 | Full 31-register context integrity |
| 8 | `test_degradation` | 1 | Degradation Reuse policy |
| 9 | `test_tailchain` | 4 | Tail-chaining optimization |
| 10 | `test_triple` | 4 | Three-level nesting (SW → Timer → GPIO) |

### Vivado FPGA Synthesis

```bash
cd vivado
# Batch synthesis for Banks=1/2/4/8
run_synth_banks.bat           # Synthesis only (~20 min)
run_synth_banks.bat impl      # Synthesis + Place & Route (~2 hours)
# Or open GUI project
run_synth_banks.bat gui
```

Results are saved to `vivado/synth_results/fpga_summary.md`.

## Memory Map

| Range | Device | Size |
|---|---|---|
| `0x0000_0000` – `0x0000_0FFF` | Data RAM | 4 KB (configurable) |
| `0x1000_0000` – `0x1000_0FFF` | UART | 4 KB |
| `0x1000_1000` – `0x1000_1FFF` | GPIO | 4 KB |
| `0x1000_2000` – `0x1000_2FFF` | Timer | 4 KB |
| `0x1000_3000` – `0x1000_3FFF` | SPI Master | 4 KB |
| `0x1000_4000` – `0x1000_4FFF` | I2C Master | 4 KB |
| `0x2000_0000` – `0x2000_7FFF` | Instruction BRAM | 32 KB |
| `0x3000_0000` – `0x30FF_FFFF` | SPI Flash (read-only) | 16 MB |

## Interrupt System

| ID | Source | Priority | Description |
|:--:|--------|:--:|------|
| 3 | Software | Lowest | Software-triggered interrupt |
| 7 | Timer | Medium | Timer interrupt |
| 11 | External | Highest | GPIO / SPI / I2C (OR-ed) |

> **Note**: The current hardware uses hardcoded priority (`localparam` in `interrupt_controller.v`): MEI(ID=11) > MTI(ID=7) > SPI(ID=12) > I2C(ID=13) > MSI(ID=3). Software can mask specific interrupt sources via `mie`/`mip` CSRs, but cannot dynamically reorder priority levels at runtime.

**Vectored mode**: Handler address = `mtvec_base + cause × 4`.  
**Constant latency**: 2 cycles from acceptance to first ISR instruction in EX, at every nesting level.  
**Context save**: 31 registers (x1–x31) locked in parallel to shadow Bank in a single cycle.

### Configurable Parameters

| Parameter | Default | Description |
|-----------|:------:|-------------|
| `SHADOW_BANKS` | 4 | Number of shadow register banks (supports `BANKS-1` nesting levels) |
| `OVERFLOW_POLICY` | 0 | Bank overflow policy: 0 = Hard Limit, 1 = Degradation Reuse |
| `SHADOW_EN` | 1 | Enable/disable shadow register hardware |
| `DATA_DEPTH` | 1024 | Data RAM depth (words) |
| `FIFO_DEPTH` | 16 | UART TX FIFO depth |
| `INST_DEPTH` | 8192 | Instruction BRAM depth (words) |

## Repository Structure

```
FX-RV32-X/
├── core/                  # CPU core RTL
│   ├── ifu/               # Instruction Fetch (PC + next-PC mux)
│   ├── id/                # Decode (decoder, regfile, imm_gen, ctrl)
│   ├── exu/               # Execute (ALU, branch)
│   ├── mem/               # Memory access (mem_ctrl, mem_top)
│   ├── wbu/               # Write-back (wb_mux, wb_top)
│   ├── pipeline/          # Pipeline registers (IF/ID, ID/EX, EX/MEM, MEM/WB)
│   ├── hazard/            # Hazard unit + Forwarding unit
│   ├── csr/               # CSR register file + CSR instruction logic
│   ├── interrupt/         # Interrupt controller + Pipeline + Bank Controller
│   └── core_top.v         # CPU top-level
├── soc/                   # SoC integration
│   ├── top/               # soc_top (simulation) + soc_top_fpga (FPGA)
│   ├── mem/               # inst_bram, data_ram
│   ├── bus/               # Bus arbiter
│   └── periph/            # UART, GPIO, Timer, SPI, SPI Flash, I2C
├── sim/                   # Verilator simulation
│   ├── rtl/               # RTL copies for simulation build
│   ├── sim_main.cpp       # C++ test harness
│   └── Makefile
├── tb/                    # Verilog testbenches
├── uvm/                   # UVM 1.2 verification
│   └── nested_uvm/        # Nested interrupt test suite (10 tests)
├── python/                # Assembler and utilities
│   ├── riscv_asm7.py      # Full RISC-V assembler (v16)
│   ├── asm_to_hex.py      # CLI assembler frontend
│   └── riscv_arm.py       # Interactive assembler
├── mytests/               # Assembly test programs
├── vivado/                # Vivado project + batch synthesis scripts
│   ├── create_project.tcl
│   ├── synth_fpga_banks.tcl
│   └── run_synth_banks.bat
├── constraints.xdc        # FPGA pin constraints (Kintex-7)
└── README.md
```

## Citation

If you use FX-RV32-X in your research, please cite:

```bibtex
@article{yi2025fxrv32x,
  title={FX-RV32-X: A Multi-Bank Shadow Register Extension for Priority-Based
         Nested Interrupts with Constant 2-Cycle Latency},
  author={Yi, Fengxin},
  journal={submitted to IEEE Trans. Very Large Scale Integr. (VLSI) Syst.},
  year={2025}
}
```

The baseline FX-RV32 processor is described in:

```bibtex
@article{yi2025fxrv32,
  title={FX-RV32: A Lightweight, Deterministic and Low Latency RISC-V
         Processor for Hard Real-Time Embedded Systems},
  author={Yi, Fengxin},
  journal={IEEE Trans. Very Large Scale Integr. (VLSI) Syst.},
  note={submitted for publication}
}
```

## License

This project is provided for educational and research purposes.

## Author

**Fengxin Yi** (易逢鑫)  
Hangzhou International Innovation Institute, BeiHang University  
Hangzhou, China  
📧 1596215367@buaa.edu.cn
