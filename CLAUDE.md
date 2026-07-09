# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FX-RV32 is a 5-stage pipeline RISC-V CPU (RV32I only — no M extension) with peripherals, written in Verilog. Target FPGA: Xilinx Kintex-7 xc7k325tffg900-2 at 200MHz. Author: Yi Fengxin, Beihang University.

**Important:** The Python assembler (`riscv_asm7.py`) supports RV32M/A/F/D/C pseudo-instructions, but the hardware only implements RV32I. M-extension instructions (mul, div, etc.) will not execute correctly on this core.

## Build / Simulation Commands

### Verilator Simulation (CoreMark benchmark)

```bash
cd sim && make          # builds obj_dir/Vcore_top_sim
cd sim && make run      # build + run simulation
cd sim && make clean    # remove build artifacts
```

The simulation C++ harness (`sim/sim_main.cpp`) toggles clk every 5ns (100MHz effective), resets for 100ns, then runs until CoreMark `perf_score != 0` or 30ms timeout. The top module is `core_top_sim` — a standalone simulation wrapper that instantiates `data_ram`, `bus_arbiter`, and all peripherals internally (it does NOT wrap `core_top`; it's a self-contained simulation SoC with extensive debug ports).

**The `sim/rtl/` directory** already contains copies of the RTL source files that the Makefile discovers via `find rtl -name "*.v"`. If you add new Verilog files to `core/` or `soc/`, you must also copy them into the corresponding `sim/rtl/` subdirectory, or edit the Makefile's `SOURCES` line to also search `../core/` and `../soc/`.

The Makefile suppresses several Verilator warnings (`PINMISSING`, `MULTIDRIVEN`, `LATCH`, `WIDTHTRUNC`, `WIDTHEXPAND`, `CASEINCOMPLETE`, `UNSIGNED`) — these are expected given the design style; do not "fix" them unless you've verified a real issue.

The simulation reads `sim/program.hex` (plain hex, one 32-bit word per line) as the binary program. To generate this from assembly:

```bash
cd python && python asm_to_hex.py input.s -o ../sim/program.hex
# Or the manual two-step flow:
cd python && python riscv_asm7.py input.s > /tmp/machine_code.txt
cd mytests && python convert_hex.py /tmp/machine_code.txt ../sim/program.hex
```

### Python Assembler (convert RISC-V assembly to machine code)

**`python/asm_to_hex.py`** is the **preferred CLI assembler**. It imports `riscv_asm7.py`'s `FullRISCVAssembler` and provides proper argument parsing:
```bash
cd python
python asm_to_hex.py input.s                  # plain hex to stdout
python asm_to_hex.py input.s -o program.hex   # write to file
python asm_to_hex.py input.s --rom            # Verilog ROM format (rom[i]=32'hXXXXX;)
python asm_to_hex.py input.s --base 0x200     # set starting address
```

**`riscv_asm7.py`** is the underlying assembler engine (v16, also usable directly):
```bash
cd python && python riscv_asm7.py              # interactive mode
cd python && python riscv_asm7.py input.s      # assemble a file to stdout
```

It supports labels, pseudo-instructions, data directives (`.section`, `.ascii`, `.word`, `.byte`, `.globl`, `.balign`), CSR instructions, `%hi()`/`%lo()` address modifiers, and character constants. Output is 32-bit hex machine code in Verilog ROM format by default.

**`riscv_arm.py`** is an older, simpler interactive assembler. Use it for quick one-off instruction encoding.

**Additional Python utilities:**
- `python/rom_output/gen_rom.py` — Converts hex machine code to Verilog `rom[i]=32'hXXXXX;` format for pasting into `inst_rom.v` or `inst_bram.v`.
- `python/jal_branch_recognize/recognize_jal_branch.py` — Parses RISC-V hex and inserts 2 NOPs after every JAL/B-type instruction (useful for early pipeline versions without hardware hazard handling).
- `mytests/convert_hex.py` — Converts Verilog-hex format (with `@` address markers, as produced by `riscv64-unknown-elf-objcopy -O verilog`) to plain hex (one 32-bit word per line) for `sim/program.hex`. Does NOT assemble.
- `python/plot/` — Matplotlib scripts for generating paper/thesis figures. Subdirectories: `Area/` (area comparison), `Interrupt_latency/` (interrupt latency comparison), `Synthesis/` (synthesis results), `execution time/` (deterministic test execution time), `Structure/` (CPU structure diagram).

An SPI test example is at `python/spi_test.s`. A bootloader assembly source is at `python/bootloader.s`.

### UVM Verification (Modelsim/Questa)

The `uvm/` directory contains a UVM 1.2 verification environment for the CPU core:

```bash
# Assemble a test program
cd python && python riscv_asm7.py ../uvm/alu_test.s > ../uvm/alu_test.hex

# Run simulation (console mode)
cd uvm
vsim -c -do "set HEX_FILE alu_test.hex; set TEST_NAME cpu_test_alu; do run_msim.tcl"

# Run with GUI waveform viewer
vsim -do "set HEX_FILE alu_test.hex; set GUI_MODE 1; do run_msim.tcl"

# Run different test classes
vsim -c -do "set HEX_FILE alu_test.hex; set TEST_NAME cpu_test_interrupt; do run_msim.tcl"
vsim -c -do "set HEX_FILE ../sim/program.hex; set TEST_NAME cpu_test_coremark; do run_msim.tcl"

# Windows quick launch (recommended for GUI users)
cd uvm && run_uvm.bat alu_test.hex
cd uvm && run_uvm.bat ..\sim\program.hex
cd uvm && run_uvm.bat alu_test.hex gui
cd uvm && run_uvm.bat hazard gui       # load-use hazard test + waveform
cd uvm && run_uvm.bat intr gui         # interrupt test + waveform
cd uvm && run_uvm.bat alu gui          # basic ALU test + waveform
```

**UVM test assembly files** (in `uvm/`): `alu_test.s`, `intr_test.s`, `load_use_test.s`, `store_test.s`, `gpio_toggle_test.s` — each has a corresponding `.hex` output.

**UVM test classes** (in `uvm/riscv_uvm_pkg.sv`):
- `cpu_test_alu` — runs a hex program, reports results at end of simulation
- `cpu_test_interrupt` — runs a hex program, triggers timer interrupt at cycle 2000
- `cpu_test_hazard` — for RAW/load-use hazard test programs
- `cpu_test_coremark` — runs until `perf_score != 0` (30ms timeout)

**UVM TCL variables** (`+set VAR=value` in vsim):
| Variable | Default | Description |
|----------|---------|-------------|
| `TEST_NAME` | `cpu_test_alu` | UVM test class name |
| `HEX_FILE` | `""` | Path to test program hex file |
| `GUI_MODE` | `0` | Open waveform window |
| `DUMP_VCD` | `0` | Generate VCD waveform dump |
| `COV_ENABLE` | `1` | Enable code coverage collection |
| `WAVE_ENABLE` | `1` | Add waveform groups in GUI mode |

The UVM testbench (`uvm/uvm_tb_top.sv`) instantiates `core_top` with simulated instruction ROM (4096×32bit) and data RAM (64KB). The instruction ROM is loaded from the hex file by the UVM driver. Note: the UVM environment uses a simple `inst_rom`, not the `inst_bram` bootloader used by `soc_top`. See `uvm/README.md` for full architecture details.

UVM test result logs are in `uvm/test_result_alu.md`, `uvm/test_result_hazard.md`, and `uvm/test_result_interrupt.md`. Additional UVM documentation (Chinese): `uvm/UVM_仿真指南.md`, `uvm/问题修复记录.md`.

### Modelsim Simulation (manual, without UVM)

Load `tb/tb_soc_top.v` (SoC-level — full system with peripherals) or `tb/tb_core_top.v` (core-level — CPU core only with debug signal breakout) as the top-level testbench and run in Modelsim GUI/console. No TCL scripts are provided for non-UVM Modelsim — set up the project manually.

**Testbench details:**
- `tb/tb_core_top.v` — instantiates `core_top_sim`. Breaks out internal debug signals: pipeline stage states, register file x0-x14, UART FIFO, CSR registers, hazard/forwarding, interrupt pipeline signals. Includes GPIO stimulus and monitors CoreMark completion at address 0x3F4.
- `tb/tb_soc_top.v` — instantiates full `soc_top`. Uses a `tohost` mechanism at address 0x000000FC (write 0 = PASS, non-zero = FAIL). Provides GPIO external input stimulus and SPI/I2C signal monitoring.

### Vivado Synthesis / FPGA Bitstream

**One-click project creation (recommended):**
```bash
# Windows (double-click create_project.bat, or run):
cd vivado && vivado -source create_project.tcl

# Linux/WSL:
cd vivado && bash create_project.sh
```
This TCL script creates the Vivado project at `vivado/RISCV_TEST/`, adds all RTL sources from `core/` and `soc/`, sets `soc_top_fpga` as top module, loads `constraints.xdc`, and opens the Vivado GUI. From the GUI, manually click: **Synthesis → Implementation → Generate Bitstream**.

Alternatively, open the existing project at `vivado/RISCV_TEST/RISCV_TEST.xpr`.

**Pin constraints** (`constraints.xdc`): 200MHz LVDS clock on AD12/AD11, UART TX on Y23, UART RX on AB22, SPI Flash on R23/R24/R25/P24, I2C on Y16/Y17, 8 LEDs on T28/V19/U30/U29/V20/V26/W24/W23. GPIO pins are commented out — assign as needed.

### Design Compiler Synthesis

`source DC_command.txt` which sources Synopsys environment and runs `syn/run_synth.tcl`. The TCL targets SMIC 55nm library, reads all RTL files via `analyze`, sets a 200MHz clock constraint, and compiles.

**Synthesis reports** are in `syn/` — area reports, power reports, and comparison analyses (ROM vs SRAM, shadow SRAM power, 4KB upgrade). Key reference documents: `syn/report_file_index.md` (index of all reports), `syn/memory_compiler_usage_guide.md`, `syn/sram_area_power_reading_guide.md`, `syn/power_report_reading_guide.md`. A power analysis script is at `syn/run_synth_power.tcl`.

**Known issues:** Three Verilog syntax errors block elaboration — all submodules become black boxes. The specific errors were previously logged in `error.md` (now deleted). The errors involve mixed ordered/named port connections and syntax issues in `core_top.v`, `id_top.v`, and `id_ex_reg.v`. These must be fixed before DC synthesis will succeed.

## Architecture

### Pipeline: IF → ID → EX → MEM → WB

- **IF** (`core/ifu/`): PC register and instruction fetch. `ifu_top.v` selects next PC among `intr_target > branch_target > jump_target > pc+4`. Instruction comes from the SoC's instruction memory.
- **ID** (`core/id/`): Decoder, control unit, immediate generator, register file (32 regs + 31 shadow regs). The `id_top.v` instantiates all ID submodules and routes `shadow_save_i`/`shadow_restore_i` to the register file.
- **EX** (`core/exu/`): ALU, branch unit. Also multiplexes forwarded data from MEM/WB stages. CSR instructions execute here and their result is forwarded alongside the ALU result.
- **MEM** (`core/mem/`): Memory access control — `mem_top.v` issues bus requests to the SoC bus arbiter. `mem_ctrl.v` performs address alignment checking (LW/SW aligned to 2 bytes, LH/SH to 1 byte) and address range checking (0x00000000–0x0FFFFFFF), producing `mem_misalign_o`/`mem_error_o` exception flags.
- **WB** (`core/wbu/`): Write-back mux (`wb_mux.v`) selecting ALU result, memory data, PC+4, or CSR result.

Pipeline registers: `if_id_reg`, `id_ex_reg`, `ex_mem_reg`, `mem_wb_reg` in `core/pipeline/`.

### Hazard Handling

- **Load-use hazard** (`core/hazard/hazard_unit.v`): When a load is in EX but not yet in MEM, and the next instruction reads its destination register, the pipeline stalls IF/ID for one cycle. Also handles control hazard flushes. Flush duration is parameterized by `SYNC_INST_MEM`: **ROM** (combinational read, `SYNC_INST_MEM=0`) uses 1-cycle flush; **BRAM** (synchronous read, `SYNC_INST_MEM=1`) uses 2-cycle flush via `control_hazard_r` extension, with PC stall during the extension cycle to prevent PC overshoot.
- **Interrupt flush** (`core/hazard/hazard_unit.v`): On interrupt entry, ID/EX, EX/MEM, and MEM/WB are flushed with NOP. **IF/ID is NOT flushed** (`intr_flush_id_o = 1'b0`, matching baseline `FX-RV32_RemoveM_Custom`). The PC is already redirected to the handler by `intr_take_now`, so the first ISR instruction passes through IF/ID normally — works for both ROM (combinational, 2-cycle latency) and BRAM (synchronous, 3-cycle latency). Old program branch instructions in IF/ID are killed at ID/EX by `intr_flush_ex` before they reach EX.
- **Forwarding** (`core/hazard/forwarding_unit.v`): Resolves RAW hazards by forwarding ALU results from EX/MEM or MEM/WB back to EX inputs, avoiding stalls for non-load dependencies. 2-bit encoding: `00`=no forward, `01`=from EX/MEM, `10`=from MEM/WB. Forwarding is suppressed during stalls. EX/MEM loads are excluded from forwarding (data not ready until MEM).

**Important — B-type immediate generator fix (June 2026):** The B-type immediate generator in `core/id/imm_gen.v` had incorrect bit ordering. RISC-V spec requires `offset[12:1] = {inst[31], inst[7], inst[30:25], inst[11:8]}`, but the implementation placed `inst[7]` at bit 1 instead of bit 11, and `inst[30:25]` at bits 11:6 instead of 10:5. This caused all non-zero branch offsets to be decoded incorrectly (e.g., offset -12 became -22). The `sim/rtl/core/id/imm_gen.v` copy was already correct.

### Interrupt System

- **interrupt_controller** (`core/interrupt/interrupt_controller.v`): Priority encoder (MEI > MTI > SPI > I2C > MSI). Supports direct and vectored modes via `mtvec.MODE`. Computes `intr_handler_addr` — in Direct mode it's `{mtvec[31:2], 2'b0}`, in Vectored mode it's `BASE + cause×4`.
- **interrupt_pipeline** (`core/interrupt/interrupt_pipeline.v`): Coordinates interrupt acceptance timing. The design implements **constant 2-cycle interrupt latency** (see `doc/interrupt/interrupt_2cycle_implementation.md`): EX branch/jump and MEM load no longer block interrupt acceptance. The `bus_ready_i` input port distinguishes completed vs pending MEM loads — completed loads are allowed to finish (mepc = mem_pc+4), pending loads are cancelled (mepc = mem_pc, bus_re_o killed). EX branch/jump instructions have mepc = ex_pc so they re-execute after MRET.
- **CSR** (`core/csr/`): `csr_regfile.v` implements `mstatus`, `misa`, `mie`, `mtvec`, `mscratch`, `mepc`, `mcause`, `mtval`, `mip`, and read-only `mvendorid`/`marchid`/`mimpid`/`mhartid`, plus 64-bit `mcycle`/`minstret` counters. Three independent write ports: interrupt auto-write (mepc/mcause/mstatus, highest priority) and CSR instruction write. `csr_instructions.v` handles all 6 CSR instruction variants (CSRRW/CSRRS/CSRRC/CSRRWI/CSRRSI/CSRRCI).

### Shadow Registers (Hardware Context Save/Restore)

On interrupt entry, the register file (`core/id/regfile.v`) saves x1-x31 to 31 internal shadow registers in a single cycle. On MRET, it restores them. This eliminates software push/pop in ISRs. Write priority: shadow_restore > normal WB > shadow_save. See `doc/interrupt/shadow_register_guide.md` for details.

**SHADOW_EN parameter** (`doc/interrupt/shadow_en_config.md`): Controls whether shadow register hardware is active. Defined in three locations with the same default:
- `core/id/id_top.v` line 18: `parameter SHADOW_EN = 1`
- `core/id/regfile.v` line 14: `parameter SHADOW_EN = 1` (overridden by id_top's `.SHADOW_EN(SHADOW_EN)` at instantiation)
- `core/interrupt/interrupt_pipeline.v` line 22: `parameter SHADOW_EN = 1`

**Current defaults: all `1`** (enabled). To disable, change all three to `0`, or override at instantiation in `core/core_top.v`. The id_top and interrupt_pipeline parameters are logically independent — changing one without the other results in partial operation (shadow save/restore signals generated but register file ignores them, or vice versa).

### SoC Integration (`soc/`)

```
soc_top (soc/top/soc_top.v)              — simulation top: CPU + memories + peripherals
soc_top_fpga (soc/top/soc_top_fpga.v)    — FPGA top: adds IBUFDS for LVDS clock, IOBUF for GPIO,
                                           power-on reset counter, LED heartbeat indicators
bus_arbiter (soc/bus/bus_arbiter.v)      — routes CPU bus requests by address
inst_bram (soc/mem/inst_bram.v)          — true dual-port instruction BRAM (32KB) with bootloader
inst_rom (soc/mem/inst_rom.v)            — simple instruction ROM (legacy, used by UVM testbench only)
data_ram (soc/mem/data_ram.v)            — data RAM (default 1024 words = 4KB, parameterized)
```

**Critical: `inst_bram.v` vs `inst_rom.v`.** `soc_top.v` instantiates `inst_bram` (true dual-port Block RAM, 8192×32bit = 32KB). Port A serves CPU instruction fetch; Port B connects to the bus for program loading. It contains a **68-instruction bootloader** (hardcoded in the initial block at addresses 0x000–0x1FF, 2KB, write-protected) that supports two program-loading modes:
1. **UART mode**: Bootloader enables UART RX, polls for data (~10ms timeout), receives program size then program words, writes them to BRAM starting at address 0x200.
2. **SPI Flash mode**: Bootloader reads from SPI Flash at `0x3000_0000` via `spi_flash_ctrl`. Checks for magic number `0x46585256` ("FXRV"), reads program size, copies code to BRAM starting at 0x200.

After loading, the bootloader jumps to address 0x200 (user program entry point). Addresses 0x000–0x1FF are write-protected.

`inst_rom.v` is a simple 1024-word ROM used only by the UVM testbench (`uvm/uvm_tb_top.sv`). The pre-built test ROMs in `soc/mem/test_inst_rom/` target this legacy ROM format.

### Memory Map

| Range | Device | Size |
|---|---|---|
| 0x0000_0000 - 0x0000_0FFF | data_ram | 4KB (default; parameter `DATA_DEPTH=1024`) |
| 0x1000_0000 - 0x1000_0FFF | UART | 4KB |
| 0x1000_1000 - 0x1000_1FFF | GPIO | 4KB |
| 0x1000_2000 - 0x1000_2FFF | Timer | 4KB |
| 0x1000_3000 - 0x1000_3FFF | SPI | 4KB |
| 0x1000_4000 - 0x1000_4FFF | I2C | 4KB |
| 0x2000_0000 - 0x2000_7FFF | inst_bram | 32KB |
| 0x3000_0000 - 0x30FF_FFFF | SPI Flash (read-only) | 16MB |

### Interrupt IDs

| ID | Source |
|----|--------|
| 3 | Software |
| 7 | Timer |
| 11 | External (GPIO / SPI / I2C OR-ed together) |

SPI (ID 12) and I2C (ID 13) interrupts are merged into external interrupt (ID 11) at the SoC level. The ISR must poll each peripheral's status register to determine the actual source.

### Peripherals (`soc/periph/`)

- **UART** (`uart_ctrl.v`, `uart_tx.v`, `uart_rx.v`): Full TX+RX UART with configurable-depth TX FIFO (default 16 entries). 115200 baud default. Register map: TX_DATA (0x00, WO), STATUS (0x04, RO — [0]=tx_ready, [1]=tx_idle, [2]=rx_ready, [3]=fifo_full, [10:4]=fifo_count), CTRL (0x08, RW — [0]=tx_enable, [1]=rx_enable), BAUD_DIV (0x0C), RX_DATA (0x10, RO — read clears rx_ready), IRQ_FLAG (0x14 — [0]=tx_done, [1]=rx_done, write 1 to clear). RX uses 16× oversampling. Full design doc at `doc/uart_design.md`.
- **GPIO** (`gpio.v`): 32-bit bidirectional, per-pin direction control, level/edge-triggered interrupt with independent per-pin interrupt enable. Register offsets: OUT=0x00, OE=0x04, IN=0x08 (RO), IE=0x0C, EDGE=0x10, IF=0x14 (write 1 clear).
- **Timer** (`timer.v`): 32-bit down counter, one-shot or auto-reload modes. Register offsets: CTRL=0x00 ([0]=enable, [1]=auto_reload, [2]=clear_irq), LOAD=0x04, COUNT=0x08 (RO), IER=0x0C. Writing LOAD while disabled also loads COUNT. Special case: load=0 disables timer.
- **SPI master** (`spi_master.v`): 4 modes (CPOL/CPHA), 8/16-bit transfer, configurable MSB/LSB first. Register offsets: CTRL=0x00, CLK_DIV=0x04, DATA=0x08, STATUS=0x0C, IRQ_FLAG=0x10. SCK frequency = f_sys / (2×(clk_div+1)).
- **SPI Flash controller** (`spi_flash_ctrl.v`): Dedicated read-only controller for S25FL256S SPI Flash. Issues READ command (0x03) + 24-bit address, reads 4 bytes, assembles into 32-bit word. Used by the `inst_bram` bootloader for program loading. Default SPI frequency: 10MHz. State machine handles the full command/address/data/CS sequence.
- **I2C master** (`i2c_master.v`): Standard (100kHz) and fast (400kHz) modes, 7-bit addressing. Open-drain outputs with tri-state control. Register offsets: CTRL=0x00, CLK_DIV=0x04, TX_DATA=0x08, RX_DATA=0x0C, STATUS=0x10, ADDR=0x14, IRQ_FLAG=0x18.

SPI and I2C register maps and bit-field definitions are documented in README.md.

## Verilog Coding Conventions

- **Port naming**: inputs suffixed `_i`, outputs suffixed `_o` (e.g., `clk_i`, `rst_n_i`, `bus_re_o`).
- **Module instantiation**: prefix `u_` (e.g., `u_alu`, `u_ex_top`, `u_interrupt_pipeline`).
- **Active-low reset**: `rst_n_i` is active-low across all modules.
- **Wire/reg naming**: internal wires typically use descriptive names matching the signal path (e.g., `ex_alu_result`, `wb_reg_we_out`).
- **Pipeline stage prefixes**: signals are prefixed by their origin stage — `if_*`, `id_*`, `ex_*`, `mem_*`, `wb_*`.
- **NOP encoding**: `0x00000013` (addi x0, x0, 0) — used for pipeline flush operations.
- **Extended signal naming**: `_for_hazard` suffix on signals routed specifically to the hazard/forwarding units; `pipe_csr_*` prefix for interrupt pipeline CSR update signals; `intr_flush_*` for interrupt-triggered pipeline flushes (distinct from `flush_*` for branch/jump flushes).
- **Configuration**: All design configuration uses Verilog `parameter` (not `` `define `` macros). Configurable parameters: `SHADOW_EN`, `DATA_DEPTH`/`ADDR_WIDTH` (data_ram), `FIFO_DEPTH` (uart_ctrl), `INST_DEPTH` (inst_bram).

## Test Programs

Pre-built instruction ROM test programs are in `soc/mem/test_inst_rom/` (for the legacy `inst_rom.v` format):
- `inst_rom_mul_test.v` — multiply/divide test (**note:** hardware no longer supports M extension; this test is legacy)
- `uart/inst_rom_uart_basic.v` — UART basic TX test
- `gpio/inst_rom_gpio_test.v`, `inst_rom_gpio_interrupt_test.v`, `inst_rom_gpio_input_test.v`, `inst_rom_gpio_output_latency.v` — GPIO tests
- `timer/inst_rom_timer_test.v`, `inst_rom_timer_interrupt_test.v` — timer tests
- `spi/inst_rom_spi.v`, `inst_rom_spi_interrupt.v` — SPI tests
- `i2c/inst_rom_i2c.v` — I2C test

To change the test program for the UVM testbench, copy one of these over `soc/mem/inst_rom.v`. For the SoC simulation, the bootloader in `inst_bram.v` loads programs dynamically via UART or SPI Flash — you don't need to swap ROM files.

Assembly test programs in `mytests/`:
- `test1_vvadd.S` — vector add (143 cycles)
- `test2_fib.S` — Fibonacci (97 cycles)
- `test3_matmul.S` — matrix multiply (23 cycles, **note:** uses `mul` instruction — fails on RV32I hardware)
- `test4_bubble.S` — bubble sort (1081 cycles)
- `test5_lfsr.S` — LFSR (2053 cycles)
- `test6_forwarding.S` — forwarding determinism (50 instr, 33 cycles/iter)
- `test7_branching.S` — control flow determinism (41 instr, 16 cycles/iter)
- `test8_memdep.S` — memory access determinism (60 instr, 41 cycles/iter)
- `test9_interrupt.S` — interrupt latency determinism (ISR: 8 cycles)
- `test9_mixedwork.S` — mixed workload determinism (61 instr, 45 cycles/iter)
- `load_use_test.s` — load-use hazard test

See `mytests/确定性测试说明.md` for detailed descriptions of the deterministic test methodology and results (used for thesis validation).

## Key Design Documents

| Document | Content |
|----------|---------|
| `doc/uart_design.md` | UART architecture, register maps, bus arbiter handshake, code examples |
| `doc/load_use_hazard_analysis.md` | **Known bug:** load-use stall duplicates instructions — missing NOP insertion in ID/EX |
| `doc/load_use_forwarding_optimization.md` | Load-use forwarding optimization analysis |
| `doc/interrupt/shadow_register_guide.md` | Shadow register save/restore mechanism and usage |
| `doc/interrupt/shadow_en_config.md` | SHADOW_EN parameter configuration (and why it's per-module) |
| `doc/interrupt/shadow_save_race_condition.md` | Timing analysis: why shadow_save vs WB write-back has no race |
| `doc/interrupt/interrupt_vector_mode.md` | Direct vs Vectored interrupt mode, mtvec MODE bit, vector table layout |
| `doc/interrupt/interrupt_2cycle_guaranteed.md` | Design analysis for constant 2-cycle interrupt latency |
| `doc/interrupt/interrupt_2cycle_implementation.md` | Implementation record of 2-cycle latency changes (May 2026) |
| `doc/interrupt/interrupt_latency_analysis.md` | Initial interrupt latency analysis |
| `doc/interrupt/thesis_interrupt_and_shadow.md` | Thesis document: interrupt + shadow register design |
| `doc/bram/bram_and_tcm_guide.md` | BRAM and tightly-coupled memory implementation |
| `doc/bram/bram_inference_guide.md` | FPGA BRAM inference techniques |
| `doc/bram/tcm_bram_implementation.md` | TCM + BRAM implementation details |
| `doc/flash_waiting/SPI_Flash_Implementation_Guide.md` | SPI Flash controller implementation guide |
| `doc/flash_waiting/bootloader_uart_loading_plan.md` | Bootloader UART program loading plan |
| `doc/coremark_results.md` | CoreMark benchmark results |
| `doc/fpga_coremark_guide.md` | Guide for running CoreMark on FPGA |
| `doc/ecall_exception_plan.md` | ECALL exception implementation plan |
| `doc/ecall_test_report.md` | ECALL exception test report |
| `doc/auipc_bug_analysis.md` | AUIPC instruction bug analysis |
| `doc/auipc_fix_changelog.md` | AUIPC fix changelog |
| `doc/deterministic_test_progress.md` | Deterministic test development progress |
| `doc/test_classification.md` | Test classification methodology |
| `doc/riscv_test_plan.md` | RISC-V test suite integration plan |
| `doc/riscv_tests_and_uvm_integration.md` | RISC-V tests + UVM integration notes |
| `doc/m_extension_plan.md` | M extension implementation plan (not yet implemented) |
| `mytests/确定性测试说明.md` | Deterministic test suite documentation (forwarding, control flow, memory, interrupt) |
| `FX-RV32.md` | Comprehensive project documentation (83KB, Chinese) |
| `FX-RV32_Experimental_Evaluation.md` | Experimental evaluation data and analysis |
| `image.md` | Mermaid architecture diagram (core pipeline + SoC bus/peripherals) |
| `uvm/README.md` | Full UVM verification environment documentation (including coverage and waveform usage) |

## Key Notes

- **Bus arbiter UART write latching**: The bus arbiter uses a latched mechanism for UART writes — the write is held until the UART reports tx_ready (STATUS[0]), with a 5-cycle timeout. Non-UART peripherals (GPIO, Timer, SPI, I2C, inst_bram) use direct combinational routing.
- `rst_n_i` is active-low across all modules.
- CSR instructions execute in the EX stage; their result is forwarded through the pipeline alongside the ALU result.
- **Peripheral register offsets**: When writing peripheral drivers, use the exact offsets documented in the Peripherals section above. The bus arbiter uses full 32-bit address matching against base addresses (e.g., writing to 0x1000_0008 targets UART CTRL register).
- The `program.hex` file in `sim/` is the binary loaded into instruction memory for Verilator simulation. Generate it with `python/asm_to_hex.py input.s -o sim/program.hex` for assembly sources, or use `mytests/convert_hex.py` to convert Verilog-hex format (with `@` address markers) to plain hex.
- **Design Compiler synthesis is broken** — three Verilog syntax errors block elaboration. The errors involve mixed ordered/named port connections and syntax issues in `core_top.v`, `id_top.v`, and `id_ex_reg.v`. These must be fixed before DC synthesis will succeed. See `syn/report_file_index.md` for available synthesis reports.
- **Known load-use hazard bug** (see `doc/load_use_hazard_analysis.md`): When a load-use stall occurs, the current hazard unit only holds IF/ID and PC but does **not** insert a NOP into ID/EX. This causes both the load and the dependent instruction to be executed twice. For RAM loads this is functionally masked (idempotent reads), but for FIFO peripherals it causes data loss. The fix is to add a `flush_ex` signal from the hazard unit that flushes ID/EX during load-use stalls.
- **`core_top_sim` vs `soc_top`:** `core_top_sim` (`core/core_top_sim.v`) is a standalone simulation wrapper that internally instantiates `data_ram`, `bus_arbiter`, and all peripherals — it does NOT wrap `core_top`. It exposes extensive debug ports for waveform observation. `soc_top` (`soc/top/soc_top.v`) is the real SoC integration that instantiates `core_top`, `inst_bram`, `data_ram`, `bus_arbiter`, and all peripherals — it's used for both simulation (`tb/tb_soc_top.v`) and FPGA synthesis (via `soc_top_fpga`). `soc_top` has internal `core_perf_*` wires connected from `core_top` for CoreMark monitoring.
- **`uvm/rtl_filelist.f`** lists all RTL source files for UVM compilation. If adding/removing RTL files, update this list.
- **Interrupt controller priority:** MEI (external, ID=11) > MTI (timer, ID=7) > SPI (ID=12) > I2C (ID=13) > MSI (software, ID=3).
- **`core_top` module** has no M-extension support (matches directory name "RemoveM"). The `core_top.v` file does not instantiate mul/div units. Any test program using M instructions will fail.
- **data_ram default size is 4KB** (parameter `DATA_DEPTH=1024`, `ADDR_WIDTH=8`). Despite the memory map showing a 64KB range (0x0000_0000–0x0000_FFFF), only the first 4KB are physically implemented by default. Access beyond 4KB returns 0. The `ADDR_WIDTH` parameter controls the address masking.
- **The `scipts/` directory** is empty — this is a typo of "scripts" left in the repo; it is not used by any workflow.
- **Assembler fixes (June 2026):** Three bugs were fixed in `python/riscv_asm7.py` (v16→v16.1):
  1. **`encode_u_type`**: Previously shifted the immediate right by 12 bits, treating it as a full 32-bit value. This broke `lui t0, 0x10001` (standard RISC-V convention: immediate goes in bits[31:12]). Now supports both conventions: values >= 2^20 are treated as full 32-bit (auto-extract bits[31:12]), smaller values are placed directly in bits[31:12].
  2. **`encode_j_type`**: The direct-offset path (e.g., `j 8`) was inconsistent with the label-resolution path (`j target`) for large offsets. Fixed by converting byte offset to halfword first, matching `resolve_label`.
  3. **`la` pseudo-instruction**: Was completely broken — generated `auipc rd, 0` (just PC→rd) instead of loading the symbol address. Now correctly expands to `lui rd, %hi(symbol)` + `addi rd, rd, %lo(symbol)`.

## IF Stage — No Negative-Edge Clocking

The IF stage uses standard positive-edge triggered registers throughout. The PC register (`pc_reg`) updates on `posedge clk`; instruction data flows from ROM → `ifu_top` (pass-through) → IF/ID register on the next rising edge. There are **no** negative-edge registers, no "high/low half-cycle" operations, and no gated clocks in the design. Do not add or describe such mechanisms in the paper or documentation.

## Interrupt Flush — All Pipeline Stages are Flushed

During interrupt acceptance, the hazard unit (`hazard_unit.v`) generates:
- `intr_flush_id_o = 1'b0` — **IF/ID is NOT flushed**. The PC is already redirected to the handler by `intr_take_now`, so the first ISR instruction passes through IF/ID normally. Old program residues are killed by `intr_flush_ex` at the next stage.
- `intr_flush_ex_o/mem_o/wb_o = interrupt_flush_i` — ID/EX, EX/MEM, MEM/WB ARE flushed with NOP to clear old program residues.
- The first ISR instruction enters IF/ID immediately — ROM outputs it combinationally (same cycle), BRAM outputs it 1 cycle later (synchronous read). Both work because IF/ID is not blocked by flush.

## Paper / LaTeX (`bare_jrnl_new_sample4.tex`)

This is the IEEE TVLSI submission. Key formatting notes:

- **Figure placement**: Use `\begin{figure}[tb]` (floating) rather than `\begin{center}` with `\captionof` (non-floating). Non-floating figures anchored mid-text create blank column gaps when there's insufficient space.
- **Spacing**: Use `\emergencystretch=0.3em` for paragraph blocks with `\tt` code snippets (test descriptions) to prevent over-stretched inter-word gaps. Use `\mbox{...}` to lock short labels. Avoid `\raggedright` — it breaks two-column justification.
- **Line-breaking**: For long unbreakable hex/verbatim strings, add `\-` discretionary hyphens (e.g., `0xEDB8\-8320`).
- **Area/power data source**: Tables II & III are based on `syn/report/area/area_hier_en0.rpt` and `syn/report/area/area_hier_sh1.rpt` (area) and `syn/report/power/power_hier_en0.rpt` and `syn/report/power/power_hier_sh1.rpt` (power). Conversion: 1 GE = 1.12 µm².
  - Baseline (SHADOW_EN=0): core_top = 27,879 µm² = 24.89 kGE, 4.020 mW
  - Shadow (SHADOW_EN=1): core_top = 36,252 µm² = 32.37 kGE, 5.838 mW
  - Shadow register delta: +8,360 µm² = +7.46 kGE, +1.82 mW
- **Interrupt latency definition**: Standardized across the paper to match Sophon: "from when the interrupt request is accepted by the core to when the first instruction of the interrupt handler is executed." Do not use alternate definitions (e.g., "external device asserts", "fetch of first instruction").
- **References**: 31 entries (ref1–ref31). Uncited references that were removed: Zaruba CVA6 (ref14 old), EHE (ref24 old), Manor DNN (ref27 old), Manor CORDIC (ref28 old), CURISCV (ref33 old). GitHub projects (PicoRV32 ref29, OpenE902 ref30, CVA6 ref31) use `[Online]. Available: URL` format.
- **Chinese paper** (`FX-RV32.md`) is maintained in parallel. When making substantive changes to content, update both files.
