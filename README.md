<p align="center">
  <a href="#english">🇬🇧 English</a> &nbsp;|&nbsp;
  <a href="#中文">🇨🇳 中文</a>
</p>

---

<h1 id="english">FX-RV32-X</h1>

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

The assembler (`riscv_asm7.py`, v16) supports RV32I instructions, pseudo-instructions, labels, data directives, and CSR instructions. See `python/asm_to_hex.py --help` for options.

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

## Peripherals

### UART
- Configurable baud rate (default 115200)
- Transmit FIFO (16 bytes depth)
- Interrupt support

### GPIO
- 32-bit bidirectional I/O
- Per-pin direction control
- Level/edge-triggered interrupt, per-pin interrupt enable

### Timer
- 32-bit down counter
- One-shot / auto-reload modes
- Programmable interrupt

### SPI Master Controller
- 4 SPI modes (configurable CPOL/CPHA)
- Configurable clock divider: SCK = f_sys / (2×(clk_div+1))
- 8-bit / 16-bit data transfer
- MSB-first / LSB-first configurable
- Interrupt support (TX complete / RX complete)

**SPI Register Map:**

| Offset | Register | Function |
|--------|----------|----------|
| 0x00 | SPI_CTRL | Control (enable, int, mode, start) |
| 0x04 | SPI_CLK_DIV | Clock divider |
| 0x08 | SPI_DATA | Transmit / Receive data |
| 0x0C | SPI_STATUS | Status (busy, tx_ready, rx_ready) |
| 0x10 | SPI_IRQ_FLAG | Interrupt flags |

**SPI Control Register Bits:**

| Bit | Function |
|-----|----------|
| bit0 | SPI enable |
| bit1 | Interrupt enable |
| bit2 | CPOL (clock polarity) |
| bit3 | CPHA (clock phase) |
| bit4 | LSB first (1 = LSB first) |
| bit5 | 16-bit mode (1 = 16-bit transfer) |
| bit6 | Start transfer (write 1, auto-clear) |

### I2C Master Controller
- Standard (100 kHz) and Fast (400 kHz) modes
- 7-bit device addressing
- Open-drain outputs with tri-state control
- Interrupt support (TX complete / RX complete / NACK error)

**I2C Register Map:**

| Offset | Register | Function |
|--------|----------|----------|
| 0x00 | I2C_CTRL | Control (enable, int, start, stop, r/w) |
| 0x04 | I2C_CLK_DIV | Clock divider |
| 0x08 | I2C_TX_DATA | Transmit data |
| 0x0C | I2C_RX_DATA | Receive data |
| 0x10 | I2C_STATUS | Status (busy, tx_ready, rx_ready, ack) |
| 0x14 | I2C_ADDR | Slave address |
| 0x18 | I2C_IRQ_FLAG | Interrupt flags |

**I2C Control Register Bits:**

| Bit | Function |
|-----|----------|
| bit0 | I2C enable |
| bit1 | Interrupt enable |
| bit2 | Start transfer (write 1) |
| bit3 | Stop transfer (write 1) |
| bit4 | Read/Write (0=write, 1=read) |
| bit5 | ACK enable (send ACK on receive) |

**I2C Status Register Bits:**

| Bit | Function |
|-----|----------|
| bit0 | Busy flag |
| bit1 | TX ready |
| bit2 | RX ready |
| bit3 | ACK flag (0=ACK, 1=NACK) |

## SPI Flash Controller

Dedicated read-only controller for S25FL256S SPI Flash. Issues READ command (0x03) + 24-bit address, reads 4 bytes, assembles into 32-bit word. Used by the `inst_bram` bootloader for program loading. Default SPI frequency: 10 MHz.

## Bootloader

The hardcoded bootloader in `inst_bram` (at addresses 0x000–0x1FF, write-protected) supports two program-loading modes:

1. **UART mode**: Enables UART RX, polls for data (~10 ms timeout), receives program size then program words, writes to BRAM starting at address 0x200.
2. **SPI Flash mode**: Reads from SPI Flash at `0x3000_0000` via `spi_flash_ctrl`. Checks for magic number `0x46585256` ("FXRV"), reads program size, copies code to BRAM starting at 0x200.

After loading, jumps to address 0x200 (user program entry). Addresses 0x000–0x1FF are write-protected.

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

---

<p align="center">
  <a href="#english">⬆ Back to English</a>
</p>

---

<h1 id="中文">FX-RV32-X</h1>

一款 RISC-V 处理器，采用**多体影子寄存器（Multi-Bank Shadow Register）**实现基于优先级的嵌套中断，**各级嵌套均保持恒定 2 周期中断延迟**。

FX-RV32-X 在 [FX-RV32](https://github.com/News111234/FX-RV32) 基线架构的基础上，将单组影子寄存器扩展为由纯组合逻辑 Bank 控制器管理的 $N$ 组 Bank 阵列。所有 Bank 管理工作——分配、释放、抢占判定、尾链优化、溢出处理——均由硬件自主完成，无需任何软件干预，也不增加任何 ISA 扩展。

## 核心特性

| 特性 | 说明 |
|---------|-------------|
| **多体影子寄存器** | $N$ 组独立 Bank（默认 $N=4$），每组 31×32 位，支持 $N-1$ 级中断嵌套 |
| **恒定 2 周期延迟** | 中断入口延迟固定为 2 个时钟周期，与嵌套深度无关 |
| **零周期上下文保存** | 每级嵌套在单周期内并行锁存全部 31 个通用寄存器 |
| **Bank 控制器** | 纯组合逻辑——抢占判定零额外延迟 |
| **尾链优化** | 硬件检测背靠背中断，跳过冗余的上下文恢复操作 |
| **可配置溢出策略** | 两种策略：硬限制（保留所有上下文）与降级复用（保障新中断准入） |
| **软件透明** | 无需 ISA 扩展、无需自定义指令、无需新增 CSR |
| **五级流水线** | IF → ID → EX → MEM → WB，配备数据前推与冲突检测 |
| **丰富外设** | UART、GPIO、定时器、SPI 主控制器、SPI Flash 控制器、I2C 主控制器 |

## 架构总览

```
                    ┌─────────────────────────────────┐
                    │        FX-RV32-X 核心            │
                    │                                  │
  外部中断 ──────►  │  中断控制器    ┌──────────────┐  │
  (定时器/GPIO/     │  (优先级       │ Bank 控制器   │  │
   SPI/I2C/软件)    │   编码器)      │ (纯组合逻辑)   │  │
                    │               │ 抢占 / 溢出 /  │  │
                    │               │ 尾链           │  │
                    │               └──────┬───────┘  │
                    │                      │           │
                    │  ┌───────────────────┘           │
                    │  ▼                               │
                    │  中断流水线控制器                  │
                    │  (无条件接受 + CSR 写)             │
                    │  │                                │
                    │  ▼                               │
                    │  寄存器文件                        │
                    │  ┌──────┬──────┬──────┬──────┐   │
                    │  │Bank 0│Bank 1│Bank 2│Bank N│   │
                    │  │x1-31 │x1-31 │x1-31 │x1-31 │   │
                    │  └──────┴──────┴──────┴──────┘   │
                    └─────────────────────────────────┘
```

## 快速开始

### 环境要求

- **仿真**：Modelsim / QuestaSim，或 Verilator + GCC
- **FPGA 综合**：Vivado 2022.2+（Xilinx Kintex-7 xc7k325tffg900-2）
- **ASIC 综合**：Synopsys Design Compiler（SMIC 55nm）
- **汇编开发**：Python 3.6+

### Verilator 仿真

```bash
cd sim
make          # 编译仿真可执行文件
make run      # 编译 + 运行 program.hex
make clean    # 清理编译产物
```

仿真顶层模块（`core_top_sim`）内部实例化了 CPU 核心、数据 RAM、总线仲裁器及所有外设。测试程序从 `sim/program.hex` 加载（每行一个 32 位字，纯十六进制格式）。

### 汇编测试程序

```bash
# 将汇编源码转换为十六进制
cd python
python asm_to_hex.py input.s -o ../sim/program.hex

# 或生成 Verilog ROM 格式
python asm_to_hex.py input.s --rom
```

汇编器（`riscv_asm7.py`，v16 版本）支持 RV32I 指令集、伪指令、标签、数据伪指令及 CSR 指令。使用 `python/asm_to_hex.py --help` 查看完整选项。

### UVM 验证（Modelsim/Questa）

```bash
cd uvm/nested_uvm
# 运行指定测试（共 10 项）
vsim -c -do "set TEST test_nested; do run_nested.tcl"
# GUI 波形模式
vsim -do "set TEST test_triple; set GUI 1; do run_nested.tcl"
# 配置 Bank 数量和溢出策略
vsim -c -do "set TEST test_overflow; set BANKS 1; set POL 0; do run_nested.tcl"
```

**UVM 测试列表：**

| # | 测试名称 | BANKS | 说明 |
|---|------|:-----:|-------------|
| 1 | `test_single_intr` | 4 | 单一定时器中断 |
| 2 | `test_ultra_min` | 4 | 最简中断入口/退出 |
| 3 | `test_no_intr` | 4 | 无中断基线测试 |
| 4 | `test_nested` | 4 | 两级嵌套（定时器 → GPIO） |
| 5 | `test_overflow` | 1 | Bank 溢出 — 硬限制策略 |
| 6 | `test_overflow_min` | 1 | 单 Bank 最小测试 |
| 7 | `test_context` | 4 | 全 31 寄存器上下文完整性 |
| 8 | `test_degradation` | 1 | 降级复用策略 |
| 9 | `test_tailchain` | 4 | 尾链优化 |
| 10 | `test_triple` | 4 | 三级嵌套（软件 → 定时器 → GPIO） |

### Vivado FPGA 综合

```bash
cd vivado
# 批量综合 Banks=1/2/4/8
run_synth_banks.bat           # 仅综合（约 20 分钟）
run_synth_banks.bat impl      # 综合 + 布局布线（约 2 小时）
# 或打开 GUI 项目
run_synth_banks.bat gui
```

结果保存至 `vivado/synth_results/fpga_summary.md`。

## 地址映射

| 地址范围 | 设备 | 容量 |
|---|---|---|
| `0x0000_0000` – `0x0000_0FFF` | 数据 RAM | 4 KB（可配置） |
| `0x1000_0000` – `0x1000_0FFF` | UART | 4 KB |
| `0x1000_1000` – `0x1000_1FFF` | GPIO | 4 KB |
| `0x1000_2000` – `0x1000_2FFF` | 定时器 | 4 KB |
| `0x1000_3000` – `0x1000_3FFF` | SPI 主控制器 | 4 KB |
| `0x1000_4000` – `0x1000_4FFF` | I2C 主控制器 | 4 KB |
| `0x2000_0000` – `0x2000_7FFF` | 指令 BRAM | 32 KB |
| `0x3000_0000` – `0x30FF_FFFF` | SPI Flash（只读） | 16 MB |

## 中断系统

### 中断源与优先级

| ID | 中断源 | 优先级 | 说明 |
|:--:|--------|:--:|------|
| 3 | 软件中断 | 最低 | 软件触发中断 |
| 7 | 定时器中断 | 中 | 定时器中断 |
| 11 | 外部中断 | 最高 | GPIO / SPI / I2C（或逻辑合并） |

> **注意**：当前硬件优先级为硬编码（`interrupt_controller.v` 中 `localparam` 定义），排序为：MEI(ID=11) > MTI(ID=7) > SPI(ID=12) > I2C(ID=13) > MSI(ID=3)。软件可通过 `mie`/`mip` CSR 屏蔽特定中断源，但无法在运行时动态重排优先级顺序。

**向量模式**：中断处理入口地址 = `mtvec_base + cause × 4`。  
**恒定延迟**：从中断接受到首条 ISR 指令进入 EX 阶段，各级嵌套均固定为 2 周期。  
**上下文保存**：31 个寄存器（x1–x31）在单周期内并行锁存至影子 Bank。

### 可配置参数

| 参数名 | 默认值 | 说明 |
|-----------|:------:|-------------|
| `SHADOW_BANKS` | 4 | 影子寄存器 Bank 数量（支持 `BANKS-1` 级嵌套） |
| `OVERFLOW_POLICY` | 0 | Bank 溢出策略：0 = 硬限制，1 = 降级复用 |
| `SHADOW_EN` | 1 | 使能/关闭影子寄存器硬件 |
| `DATA_DEPTH` | 1024 | 数据 RAM 深度（字） |
| `FIFO_DEPTH` | 16 | UART TX FIFO 深度 |
| `INST_DEPTH` | 8192 | 指令 BRAM 深度（字） |

## 外设详情

### UART
- 波特率可配置（默认 115200）
- 发送 FIFO（16 字节深度）
- 支持中断

### GPIO
- 32 位双向输入/输出
- 每引脚独立方向配置
- 电平/边沿触发中断，每引脚独立中断使能

### 定时器
- 32 位递减计数器
- 单次/自动重载模式
- 可编程中断

### SPI 主控制器
- 支持 4 种 SPI 模式（CPOL/CPHA 可配置）
- 可配置时钟分频：SCK = f_sys / (2×(clk_div+1))
- 8 位/16 位数据传输
- MSB 优先 / LSB 优先可配置
- 支持中断（发送完成 / 接收完成）

**SPI 寄存器映射：**

| 偏移地址 | 寄存器 | 功能 |
|--------|----------|----------|
| 0x00 | SPI_CTRL | 控制寄存器（使能、中断、模式、启动传输） |
| 0x04 | SPI_CLK_DIV | 时钟分频寄存器 |
| 0x08 | SPI_DATA | 数据寄存器（发送/接收） |
| 0x0C | SPI_STATUS | 状态寄存器（忙、发送就绪、接收就绪） |
| 0x10 | SPI_IRQ_FLAG | 中断标志寄存器 |

**SPI 控制寄存器位域：**

| 位 | 功能 |
|-----|----------|
| bit0 | SPI 使能 |
| bit1 | 中断使能 |
| bit2 | CPOL（时钟极性） |
| bit3 | CPHA（时钟相位） |
| bit4 | LSB 优先（1 = 低位先发） |
| bit5 | 16 位模式（1 = 16 位传输） |
| bit6 | 启动传输（写 1 启动，自动清零） |

### I2C 主控制器
- 支持标准模式（100 kHz）与快速模式（400 kHz）
- 7 位设备地址
- 开漏输出，三态控制
- 支持中断（发送完成 / 接收完成 / NACK 错误）

**I2C 寄存器映射：**

| 偏移地址 | 寄存器 | 功能 |
|--------|----------|----------|
| 0x00 | I2C_CTRL | 控制寄存器（使能、中断、起始、停止、读/写） |
| 0x04 | I2C_CLK_DIV | 时钟分频寄存器 |
| 0x08 | I2C_TX_DATA | 发送数据寄存器 |
| 0x0C | I2C_RX_DATA | 接收数据寄存器 |
| 0x10 | I2C_STATUS | 状态寄存器（忙、发送就绪、接收就绪、应答） |
| 0x14 | I2C_ADDR | 从设备地址寄存器 |
| 0x18 | I2C_IRQ_FLAG | 中断标志寄存器 |

**I2C 控制寄存器位域：**

| 位 | 功能 |
|-----|----------|
| bit0 | I2C 使能 |
| bit1 | 中断使能 |
| bit2 | 起始传输（写 1 启动） |
| bit3 | 停止传输（写 1 停止） |
| bit4 | 读/写（0=写，1=读） |
| bit5 | 应答使能（接收时发送 ACK） |

**I2C 状态寄存器位域：**

| 位 | 功能 |
|-----|----------|
| bit0 | 忙标志 |
| bit1 | 发送就绪 |
| bit2 | 接收就绪 |
| bit3 | 应答标志（0=ACK，1=NACK） |

## SPI Flash 控制器

专用只读控制器，支持 S25FL256S SPI Flash。发送 READ 命令（0x03）+ 24 位地址，读取 4 字节并拼装为 32 位字。供 `inst_bram` 引导加载器从 Flash 加载程序使用。默认 SPI 频率 10 MHz。

## 引导加载器

`inst_bram` 中的硬编码引导加载器（位于地址 0x000–0x1FF，写保护）支持两种程序加载模式：

1. **UART 模式**：使能 UART RX，轮询接收数据（约 10 ms 超时），先接收程序大小再接收程序字，写入 BRAM 地址 0x200 起始处。
2. **SPI Flash 模式**：通过 SPI Flash 控制器从 `0x3000_0000` 读取。检查魔数 `0x46585256`（"FXRV"），读取程序大小，将代码复制至 BRAM 地址 0x200 起始处。

加载完成后跳转至地址 0x200（用户程序入口）。地址 0x000–0x1FF 区域写保护。

## 仓库结构

```
FX-RV32-X/
├── core/                  # CPU 核心 RTL
│   ├── ifu/               # 取指单元（PC + 下一条 PC 多路选择器）
│   ├── id/                # 译码单元（译码器、寄存器文件、立即数生成、控制单元）
│   ├── exu/               # 执行单元（ALU、分支）
│   ├── mem/               # 访存单元（mem_ctrl、mem_top）
│   ├── wbu/               # 写回单元（wb_mux、wb_top）
│   ├── pipeline/          # 流水线寄存器（IF/ID、ID/EX、EX/MEM、MEM/WB）
│   ├── hazard/            # 冲突检测单元 + 数据前推单元
│   ├── csr/               # CSR 寄存器文件 + CSR 指令逻辑
│   ├── interrupt/         # 中断控制器 + 流水线控制器 + Bank 控制器
│   └── core_top.v         # CPU 顶层
├── soc/                   # SoC 集成
│   ├── top/               # soc_top（仿真）+ soc_top_fpga（FPGA）
│   ├── mem/               # inst_bram、data_ram
│   ├── bus/               # 总线仲裁器
│   └── periph/            # UART、GPIO、定时器、SPI、SPI Flash、I2C
├── sim/                   # Verilator 仿真
│   ├── rtl/               # 仿真构建用 RTL 副本
│   ├── sim_main.cpp       # C++ 测试框架
│   └── Makefile
├── tb/                    # Verilog 测试平台
├── uvm/                   # UVM 1.2 验证环境
│   └── nested_uvm/        # 嵌套中断测试套件（10 项测试）
├── python/                # 汇编器与工具
│   ├── riscv_asm7.py      # 完整 RISC-V 汇编器（v16）
│   ├── asm_to_hex.py      # CLI 汇编器前端
│   └── riscv_arm.py       # 交互式汇编器
├── mytests/               # 汇编测试程序
├── vivado/                # Vivado 工程 + 批量综合脚本
│   ├── create_project.tcl
│   ├── synth_fpga_banks.tcl
│   └── run_synth_banks.bat
├── constraints.xdc        # FPGA 引脚约束（Kintex-7）
└── README.md
```

## 引用

若在研究中使用了 FX-RV32-X，请引用：

```bibtex
@article{yi2025fxrv32x,
  title={FX-RV32-X: A Multi-Bank Shadow Register Extension for Priority-Based
         Nested Interrupts with Constant 2-Cycle Latency},
  author={Yi, Fengxin},
  journal={submitted to IEEE Trans. Very Large Scale Integr. (VLSI) Syst.},
  year={2025}
}
```

基线 FX-RV32 处理器请引用：

```bibtex
@article{yi2025fxrv32,
  title={FX-RV32: A Lightweight, Deterministic and Low Latency RISC-V
         Processor for Hard Real-Time Embedded Systems},
  author={Yi, Fengxin},
  journal={IEEE Trans. Very Large Scale Integr. (VLSI) Syst.},
  note={submitted for publication}
}
```

## 许可证

本项目仅用于教育及研究目的。

## 作者

**Fengxin Yi**（易逢鑫）  
北京航空航天大学 杭州国际创新研究院  
杭州，中国  
📧 1596215367@buaa.edu.cn

---

<p align="center">
  <a href="#中文">⬆ 回到顶部（中文）</a> &nbsp;|&nbsp;
  <a href="#english">⬆ Back to English</a>
</p>
