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

The simulation C++ harness (`sim/sim_main.cpp`) toggles clk every 5ns (100MHz effective), resets for 100ns, then runs until CoreMark `perf_score != 0` or 30ms timeout. The top module is `core_top_sim` (a CoreMark-instrumented wrapper of `core_top`, instantiated in `tb/tb_core_top.v`).

**Critical setup step — `core_top_sim.v`:** The `core_top_sim` module source is stored as `uvm/core_top_sim.txt` — it is **not** a `.v` file. Before building with Verilator, you must:
```bash
cp uvm/core_top_sim.txt core/core_top_sim.v   # or copy to wherever `find rtl` will discover it
```

**Before first build:** The sim Makefile references an `rtl/` directory via `find rtl -name "*.v"`, but the actual RTL lives in `core/` and `soc/`. Fix with one of:
```bash
# Option A: symlink (recommended, one-time)
cd sim && ln -s .. rtl   # Linux/WSL
# or: mklink /D rtl ..   # Windows (admin)

# Option B: edit Makefile SOURCES line to include both core/ and soc/
```

The Makefile suppresses several Verilator warnings (`PINMISSING`, `MULTIDRIVEN`, `LATCH`, `WIDTHTRUNC`, `WIDTHEXPAND`, `CASEINCOMPLETE`, `UNSIGNED`) — these are expected given the design style; do not "fix" them unless you've verified a real issue.

The simulation reads `sim/program.hex` (plain hex, one 32-bit word per line) as the binary program. To generate this from assembly, use the assembler + `convert_hex.py` flow:

```bash
cd python && python riscv_asm7.py input.s > /tmp/machine_code.txt
cd mytests && python convert_hex.py /tmp/machine_code.txt ../sim/program.hex
```

### Python Assembler (convert RISC-V assembly to machine code)

```bash
cd python && python riscv_asm7.py              # interactive mode
cd python && python riscv_asm7.py input.s      # assemble a file
cd python && python riscv_asm7.py input.s > output.hex  # save to file
```

**`riscv_asm7.py`** is the primary assembler (v16). It supports labels, pseudo-instructions, data directives (`.section`, `.ascii`, `.word`, `.byte`, `.globl`, `.balign`), CSR instructions, `%hi()`/`%lo()` address modifiers, and character constants. Output is 32-bit hex machine code suitable for pasting into instruction ROM `.v` files or feeding to `convert_hex.py`.

**`riscv_arm.py`** is an older, simpler interactive assembler. Use it for quick one-off instruction encoding.

An SPI test example is at `python/spi_test.s`.

**Additional Python utilities:**
- `python/rom_output/gen_rom.py` — Converts hex machine code to Verilog `rom[i]=32'hXXXXX;` format for pasting into `inst_rom.v`.
- `python/asm_to_hex.py` — Alternative hex conversion utility.
- `python/jal_branch_recognize/recognize_jal_branch.py` — Parses RISC-V hex and inserts 2 NOPs after every JAL/B-type instruction (useful for early pipeline versions without hardware hazard handling).
- `python/plot/` — Matplotlib scripts for generating paper/thesis figures. Subdirectories: `Area/` (area comparison), `Interrupt_latency/` (interrupt latency comparison), `Synthesis/` (synthesis results), `execution time/` (deterministic test execution time), `Structure/` (CPU structure diagram).
- `mytests/convert_hex.py` — Converts Verilog-hex format (with `@` address markers) to plain hex (one 32-bit word per line) for `sim/program.hex`. See `mytests/test.ld` for the linker script (`.text` at 0x0, `.data` at 0x100).

### UVM Verification (Modelsim/Questa)

The `uvm/` directory contains a UVM 1.2 verification environment for the CPU core (`core_top` level):

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

**UVM test assembly files** (in `uvm/`): `alu_test.s`, `intr_test.s`, `load_use_test.s`, `store_test.s` — each has a corresponding `.hex` output.

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

The UVM testbench (`uvm/uvm_tb_top.sv`) instantiates `core_top` with simulated instruction ROM (4096×32bit) and data RAM (64KB). The instruction ROM is loaded from the hex file by the UVM driver. See `uvm/README.md` for full architecture details, including the agent/monitor/scoreboard structure and reference model comparison.

UVM test result logs are in `uvm/test_result_alu.md`, `uvm/test_result_hazard.md`, and `uvm/test_result_interrupt.md`. Additional UVM documentation (Chinese): `uvm/UVM_仿真指南.md`, `uvm/问题修复记录.md`.

### Modelsim Simulation (manual, without UVM)

Load `tb/tb_soc_top.v` (SoC-level — full system with peripherals) or `tb/tb_core_top.v` (core-level — CPU core only with debug signal breakout) as the top-level testbench and run in Modelsim GUI/console. No TCL scripts are provided for non-UVM Modelsim — set up the project manually.

**Testbench details:**
- `tb/tb_core_top.v` — instantiates `core_top_sim`. Breaks out internal debug signals: pipeline stage states, register file x0-x14, UART FIFO, CSR registers, hazard/forwarding, interrupt pipeline signals. Includes GPIO stimulus and monitors CoreMark completion at address 0x3F4.
- `tb/tb_soc_top.v` — instantiates full `soc_top`. Uses a `tohost` mechanism at address 0x000000FC (write 0 = PASS, non-zero = FAIL). Provides GPIO external input stimulus and SPI/I2C signal monitoring.

### Vivado Synthesis / FPGA Bitstream

Use the Vivado project in `vivado/RISCV_TEST/RISCV_TEST.xpr`. The top module is `soc_top_fpga` (`soc/top/soc_top_fpga.v`) with pin constraints in `constraints.xdc` at the repo root (200MHz LVDS clock on AD12/AD11, UART TX on Y23, 8 LEDs on T28/V19/U30/U29/V20/V26/W24/W23). SPI and I2C pins exist in the top module but their pin constraints are commented out in the XDC file.

### Design Compiler Synthesis

`source DC_command.txt` which sources Synopsys environment and runs `syn/run_synth.tcl`. The TCL targets SMIC 55nm library, reads all RTL files via `analyze`, sets a 200MHz clock constraint, and compiles.

**Synthesis reports** are in `syn/` — area reports, power reports, and comparison analyses (ROM vs SRAM, shadow SRAM power, 4KB upgrade). Key reference documents: `syn/report_file_index.md` (index of all reports), `syn/memory_compiler_usage_guide.md`, `syn/sram_area_power_reading_guide.md`, `syn/power_report_reading_guide.md`. A power analysis script is at `syn/run_synth_power.tcl`.

**Known issues:** Three Verilog syntax errors block elaboration — all submodules become black boxes. The specific errors were previously logged in `error.md` (now deleted). The errors involve mixed ordered/named port connections and syntax issues in `core_top.v`, `id_top.v`, and `id_ex_reg.v`. These must be fixed before DC synthesis will succeed.

## Architecture

### Pipeline: IF → ID → EX → MEM → WB

- **IF** (`core/ifu/`): PC register and instruction fetch. `ifu_top.v` selects next PC among `intr_target > intr_taken(hold) > branch_target > jump_target > pc+4` (Bug #5: interrupt_taken holds PC). External instruction comes from `inst_rom` in SoC.
- **ID** (`core/id/`): Decoder, control unit, immediate generator, register file (32 regs + 31 shadow regs). The `id_top.v` instantiates all ID submodules and routes `shadow_save_i`/`shadow_restore_i` to the register file.
- **EX** (`core/exu/`): ALU, branch unit. Also multiplexes forwarded data from MEM/WB stages. CSR instructions execute here and their result is forwarded alongside the ALU result.
- **MEM** (`core/mem/`): Memory access control — issues bus requests to the SoC bus arbiter.
- **WB** (`core/wbu/`): Write-back mux selecting ALU result, memory data, PC+4, or CSR result.

Pipeline registers: `if_id_reg`, `id_ex_reg`, `ex_mem_reg`, `mem_wb_reg` in `core/pipeline/`.

### Hazard Handling

- **Load-use hazard** (`core/hazard/hazard_unit.v`): When a load is in EX but not yet in MEM, and the next instruction reads its destination register, the pipeline stalls IF/ID for one cycle. Also handles control hazard flushes: ROM=1-cycle, BRAM=2-cycle via SYNC_INST_MEM param + `intr_flush_*` signals.
- **Forwarding** (`core/hazard/forwarding_unit.v`): Resolves RAW hazards by forwarding ALU results from EX/MEM or MEM/WB back to EX inputs, avoiding stalls for non-load dependencies.

### Interrupt System

- **interrupt_controller** (`core/interrupt/interrupt_controller.v`): Priority encoder (MEI > MTI > SPI > I2C > MSI). Supports direct and vectored modes via `mtvec.MODE`. Computes `intr_handler_addr` — in Direct mode it's `{mtvec[31:2], 2'b0}`, in Vectored mode it's `BASE + cause×4`.
- **interrupt_pipeline** (`core/interrupt/interrupt_pipeline.v`): Coordinates interrupt acceptance timing. As of May 2026, the design implements **constant 2-cycle interrupt latency** (see `doc/interrupt/interrupt_2cycle_implementation.md`): EX branch/jump and MEM load no longer block interrupt acceptance. The `bus_ready_i` input port distinguishes completed vs pending MEM loads — completed loads are allowed to finish (mepc = mem_pc+4), pending loads are cancelled (mepc = mem_pc, bus_re_o killed). EX branch/jump instructions have mepc = ex_pc so they re-execute after MRET.
- **CSR** (`core/csr/`): CSR register file (`mstatus`, `mepc`, `mcause`, `mtvec`, `mie`, `mip`) and CSR instruction execution (CSRRW, CSRRS, CSRRC, etc.).

### Shadow Registers (Hardware Context Save/Restore)

On interrupt entry, the register file (`core/id/regfile.v`) saves x1-x31 to 31 internal shadow registers in a single cycle. On MRET, it restores them. This eliminates software push/pop in ISRs. Write priority: shadow_restore > normal WB > shadow_save. See `doc/interrupt/shadow_register_guide.md` for details.

**SHADOW_EN parameter** (`doc/interrupt/shadow_en_config.md`): Controls whether shadow register hardware is active. Defined in three locations with the same default:
- `core/id/id_top.v` line 18: `parameter SHADOW_EN = 1`
- `core/id/regfile.v` line 14: `parameter SHADOW_EN = 1` (overridden by id_top's `.SHADOW_EN(SHADOW_EN)` at instantiation)
- `core/interrupt/interrupt_pipeline.v` line 22: `parameter SHADOW_EN = 1`

**Current defaults: all `1`** (enabled). To disable, change all three to `0`, or override at instantiation in `core/core_top.v`. The id_top and interrupt_pipeline parameters are logically independent — changing one without the other results in partial operation (shadow save/restore signals generated but register file ignores them, or vice versa).

### SoC Integration (`soc/`)

```
soc_top (soc/top/soc_top.v)           — simulation top: CPU + memories + peripherals
soc_top_fpga (soc/top/soc_top_fpga.v) — FPGA top: adds IBUFDS for LVDS clock, IOBUF for GPIO, LED heartbeat
bus_arbiter (soc/bus/bus_arbiter.v)   — routes CPU bus requests by address
inst_rom (soc/mem/inst_rom.v)          — instruction ROM (compile-time program)
data_ram (soc/mem/data_ram.v)          — 64KB data RAM
```

### Memory Map

| Range | Device | Size |
|---|---|---|
| 0x0000_0000 - 0x0000_FFFF | RAM | 64KB |
| 0x1000_0000 - 0x1000_0FFF | UART | 4KB |
| 0x1000_1000 - 0x1000_1FFF | GPIO | 4KB |
| 0x1000_2000 - 0x1000_2FFF | Timer | 4KB |
| 0x1000_3000 - 0x1000_3FFF | SPI | 4KB |
| 0x1000_4000 - 0x1000_4FFF | I2C | 4KB |

### Interrupt IDs

| ID | Source |
|----|--------|
| 3 | Software |
| 7 | Timer |
| 11 | External (GPIO / SPI / I2C OR-ed together) |

SPI (ID 12) and I2C (ID 13) interrupts are merged into external interrupt (ID 11) at the SoC level. The ISR must poll each peripheral's status register to determine the actual source.

### Peripherals (`soc/periph/`)

- **UART** (`uart_ctrl.v`, `uart_tx.v`): 115200 baud default, TX FIFO (16-byte default depth, configurable via `FIFO_DEPTH` parameter; parameter width supports up to 64), configurable via register writes. Full design doc at `doc/uart_design.md`.
- **GPIO** (`gpio.v`): 32-bit bidirectional, per-pin direction control, level/edge-triggered interrupt.
- **Timer** (`timer.v`): 32-bit down counter, one-shot or auto-reload modes.
- **SPI master** (`spi_master.v`): 4 modes (CPOL/CPHA), 8/16-bit transfer, configurable MSB/LSB first, clock divider.
- **I2C master** (`i2c_master.v`): Standard (100kHz) and fast (400kHz) modes, 7-bit addressing.

SPI and I2C register maps and bit-field definitions are documented in README.md.

## Verilog Coding Conventions

- **Port naming**: inputs suffixed `_i`, outputs suffixed `_o` (e.g., `clk_i`, `rst_n_i`, `bus_re_o`).
- **Module instantiation**: prefix `u_` (e.g., `u_alu`, `u_ex_top`, `u_interrupt_pipeline`).
- **Active-low reset**: `rst_n_i` is active-low across all modules.
- **Wire/reg naming**: internal wires typically use descriptive names matching the signal path (e.g., `ex_alu_result`, `wb_reg_we_out`).
- **Pipeline stage prefixes**: signals are prefixed by their origin stage — `if_*`, `id_*`, `ex_*`, `mem_*`, `wb_*`.
- **NOP encoding**: `0x00000013` (addi x0, x0, 0) — used for pipeline flush operations.
- **Extended signal naming**: `_for_hazard` suffix on signals routed specifically to the hazard/forwarding units; `pipe_csr_*` prefix for interrupt pipeline CSR update signals; `intr_flush_*` for interrupt-triggered pipeline flushes (distinct from `flush_*` for branch/jump flushes).
- **Configuration**: All design configuration uses Verilog `parameter` (not `` `define `` macros). The only configurable parameter is `SHADOW_EN`.

## Test Programs

Pre-built instruction ROM test programs are in `soc/mem/test_inst_rom/`:
- `inst_rom_mul_test.v` — multiply/divide test (**note:** hardware no longer supports M extension; this test is legacy)
- `uart/inst_rom_uart_basic.v` — UART basic TX test
- `gpio/inst_rom_gpio_test.v`, `inst_rom_gpio_interrupt_test.v`, `inst_rom_gpio_input_test.v`, `inst_rom_gpio_output_latency.v` — GPIO tests
- `timer/inst_rom_timer_test.v`, `inst_rom_timer_interrupt_test.v` — timer tests
- `spi/inst_rom_spi.v`, `inst_rom_spi_interrupt.v` — SPI tests
- `i2c/inst_rom_i2c.v` — I2C test

To change the test program, copy one of these over `soc/mem/inst_rom.v`, or use the Python assembler to generate new machine code and paste it into `inst_rom.v`. Alternatively, use `python/rom_output/gen_rom.py` to convert hex output directly to Verilog ROM format.

Assembly test programs in `mytests/`:
- `test1_vvadd.S` — vector add (143 cycles)
- `test2_fib.S` — Fibonacci (97 cycles)
- `test3_matmul.S` — matrix multiply (23 cycles)
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

- The bus arbiter uses a **latched mechanism for UART writes** — the write is held until the UART reports tx_ready (bit0 of status), with a 5-cycle timeout.
- `rst_n_i` is active-low across all modules.
- CSR instructions execute in the EX stage; their result is forwarded through the pipeline alongside the ALU result.
- **UART is TX-only**: No receive (RX) functionality is implemented. The CTRL register (offset 0x08) is not writable via software due to the bus arbiter not forwarding address offsets — it always drives `uart_addr_o = UART_BASE` (see `doc/uart_design.md`).
- **Peripheral register addresses**: When writing peripheral drivers, use the exact offsets documented in README.md. The bus arbiter uses full 32-bit address matching against base addresses.
- The `program.hex` file in `sim/` is the binary loaded into instruction memory for Verilator simulation. It's generated from assembly via the `mytests/convert_hex.py` converter, which takes Verilog-hex format (with `@` address markers) and outputs plain 32-bit hex words.
- **Design Compiler synthesis is broken** — three Verilog syntax errors block elaboration. The errors involve mixed ordered/named port connections and syntax issues in `core_top.v`, `id_top.v`, and `id_ex_reg.v`. These must be fixed before DC synthesis will succeed. See `syn/report_file_index.md` for available synthesis reports.
- **Known load-use hazard bug** (see `doc/load_use_hazard_analysis.md`): When a load-use stall occurs, the current hazard unit only holds IF/ID and PC but does **not** insert a NOP into ID/EX. This causes both the load and the dependent instruction to be executed twice. For RAM loads this is functionally masked (idempotent reads), but for FIFO peripherals it causes data loss. The fix is to add a `flush_ex` signal from the hazard unit that flushes ID/EX during load-use stalls.
- **`core_top_sim` vs `soc_top`:** `core_top_sim` (source at `uvm/core_top_sim.txt`) is the simulation-only wrapper with CoreMark performance counters (`perf_score`, `perf_total_time`, etc.) and debug signal breakout. `soc_top` does **not** have these CoreMark ports. `soc_top_fpga.v` references them but expects a version of `soc_top` that includes them — this may cause synthesis errors.
- **`uvm/rtl_filelist.f`** lists all RTL source files for UVM compilation. If adding/removing RTL files, update this list.
- **Interrupt controller priority:** MEI (external, ID=11) > MTI (timer, ID=7) > SPI (ID=12) > I2C (ID=13) > MSI (software, ID=3).
- **`core_top` module** has no M-extension support (matches directory name "RemoveM"). The `core_top.v` file does not instantiate mul/div units. Any test program using M instructions will fail.
- **The `scipts/` directory** is empty — this is a typo of "scripts" left in the repo; it is not used by any workflow.
