# RISC-V-CPU

一个基于 RISC-V 指令集的五级流水线 CPU 设计，支持中断、UART、GPIO、定时器、SPI 和 I2C 外设。

## 特点

- **五级流水线**：取指(IF)、译码(ID)、执行(EX)、访存(MEM)、写回(WB)
- **RISC-V 基础整数指令集 (RV32I)** + **乘法扩展 (M)**
- **中断支持**：完整的中断响应与返回机制
- **外设支持**：
  - UART 串口通信
  - GPIO（输入/输出/中断）
  - 可编程定时器（中断）
  - **SPI 主机控制器（中断）**
  - **I2C 主机控制器（中断）**
- **仿真与验证**：
  - Modelsim 仿真，可直接观察波形
  - Vivado 综合与烧录，可部署到 FPGA

## 开发环境

| 工具 | 用途 |
|------|------|
| Modelsim | 仿真验证，观察波形 |
| Vivado | 综合、烧录 FPGA |
| Verilog | 硬件描述语言 |
| Python | 汇编转机器码工具 |

## 外设详细说明

### UART
- 波特率可配置（默认 115200）
- 发送 FIFO（16 字节）
- 中断支持

### GPIO
- 32 位输入/输出
- 每个引脚可独立配置输入/输出方向
- 电平/边沿触发中断

### 定时器
- 32 位递减计数器
- 单次/自动重载模式
- 可编程中断

### SPI 主机控制器
- 支持 4 种 SPI 模式（CPOL/CPHA 可配置）
- 可配置时钟分频（SPI 时钟 = 系统时钟 / (2 × clk_divider)）
- 8 位/16 位数据传输
- MSB 优先/LSB 优先可配置
- 中断支持（发送完成/接收完成）

**SPI 寄存器映射**：

| 偏移地址 | 寄存器 | 功能 |
|---------|--------|------|
| 0x00 | SPI_CTRL | 控制寄存器（使能、中断、模式、启动） |
| 0x04 | SPI_CLK_DIV | 时钟分频寄存器 |
| 0x08 | SPI_DATA | 数据寄存器（发送/接收） |
| 0x0C | SPI_STATUS | 状态寄存器（忙、发送就绪、接收就绪） |
| 0x10 | SPI_IRQ_FLAG | 中断标志寄存器 |

**SPI 控制寄存器位定义**：

| 位 | 功能 |
|----|------|
| bit0 | SPI 使能 |
| bit1 | 中断使能 |
| bit2 | CPOL（时钟极性） |
| bit3 | CPHA（时钟相位） |
| bit4 | LSB 优先（1=低位先发） |
| bit5 | 16 位模式（1=16 位传输） |
| bit6 | 启动传输（写 1 启动，自动清零） |

### I2C 主机控制器
- 支持标准模式（100kHz）和快速模式（400kHz）
- 7 位设备地址
- 中断支持（发送完成/接收完成/NACK 错误）

**I2C 寄存器映射**：

| 偏移地址 | 寄存器 | 功能 |
|---------|--------|------|
| 0x00 | I2C_CTRL | 控制寄存器（使能、中断、启动、停止、读写） |
| 0x04 | I2C_CLK_DIV | 时钟分频寄存器 |
| 0x08 | I2C_TX_DATA | 发送数据寄存器 |
| 0x0C | I2C_RX_DATA | 接收数据寄存器 |
| 0x10 | I2C_STATUS | 状态寄存器（忙、就绪、应答标志） |
| 0x14 | I2C_ADDR | 从设备地址寄存器 |
| 0x18 | I2C_IRQ_FLAG | 中断标志寄存器 |

**I2C 控制寄存器位定义**：

| 位 | 功能 |
|----|------|
| bit0 | I2C 使能 |
| bit1 | 中断使能 |
| bit2 | 启动传输（写 1 启动） |
| bit3 | 停止传输（写 1 停止） |
| bit4 | 读/写（0=写，1=读） |
| bit5 | 应答使能（接收时是否发送 ACK） |

**I2C 状态寄存器位定义**：

| 位 | 功能 |
|----|------|
| bit0 | 忙标志 |
| bit1 | 发送就绪 |
| bit2 | 接收就绪 |
| bit3 | 应答标志（0=ACK，1=NACK） |

## 地址映射

| 外设 | 基地址 | 大小 |
|------|--------|------|
| RAM | 0x0000_0000 | 64KB |
| UART | 0x1000_0000 | 4KB |
| GPIO | 0x1000_1000 | 4KB |
| TIMER | 0x1000_2000 | 4KB |
| **SPI** | **0x1000_3000** | **4KB** |
| **I2C** | **0x1000_4000** | **4KB** |

## 中断分配

| 中断源 | 中断 ID | 说明 |
|--------|---------|------|
| 软件中断 | 3 | 本地中断 |
| 定时器中断 | 7 | 本地中断 |
| 外部中断 | 11 | GPIO/SPI/I2C 共用 |
| SPI 中断 | 12 | 已合并到外部中断 |
| I2C 中断 | 13 | 已合并到外部中断 |

**注意**：SPI 和 I2C 中断在顶层模块中合并到外部中断（ID=11），中断服务程序中需要读取外设状态寄存器来区分中断来源。

## 汇编转机器码工具

`python/riscv_arm.py` 是一个用 Python 编写的 RISC-V 汇编转机器码工具。

### 支持指令集

| 扩展 | 指令 |
|------|------|
| **RV32I** | add, sub, addi, slt, slti, sltu, sltiu, and, or, xor, andi, ori, xori, sll, srl, sra, slli, srli, srai, beq, bne, blt, bge, bltu, bgeu, jal, jalr, lb, lh, lw, lbu, lhu, sb, sh, sw, lui, auipc |
| **RV32M** | mul, mulh, mulhsu, mulhu, div, divu, rem, remu |
| **RV32A** | lr.w, sc.w, amoswap.w, amoadd.w, amoand.w, amoor.w, amoxor.w, amomin.w, amomax.w, amominu.w, amomaxu.w |
| **RV32F** | flw, fsw, fadd.s, fsub.s, fmul.s, fdiv.s, fmin.s, fmax.s, fsqrt.s, fmadd.s, fmsub.s, fnmadd.s, fnmsub.s, feq.s, flt.s, fle.s, fcvt.w.s, fcvt.s.w, fcvt.wu.s, fcvt.s.wu |
| **RV32D** | fld, fsd, fadd.d, fsub.d, fmul.d, fdiv.d, fmin.d, fmax.d, fsqrt.d, fmadd.d, fmsub.d, fnmadd.d, fnmsub.d, feq.d, flt.d, fle.d, fcvt.w.d, fcvt.d.w, fcvt.wu.d, fcvt.d.wu |
| **RV32C** | c.nop, c.addi, c.li, c.lui, c.srli, c.srai, c.andi, c.add, c.sub, c.lw, c.sw, c.j, c.jr, c.jalr, c.beqz, c.bnez |
| **伪指令** | nop, li, la, mv, not, neg, negw, sext.w, seqz, snz, sltz, sgtz, bgt, ble, bgtu, bleu, beqz, bnez, blez, bgez, bltz, bgtz, call, tail, ret, jr, j, jal |
| **系统指令** | ecall, ebreak, mret, sret, wfi, fence, fence.i |

### 使用方法

```bash
cd python
python riscv_arm.py

操作步骤：

逐条输入汇编指令，每输入一条按一次回车

如需结束输入，再按一次回车（不输入任何内容）

程序会提示输入起始地址（默认 0），直接回车或输入数字

程序输出连续格式的机器码，可直接复制粘贴到指令存储器（inst_rom_hello.v）

请输入汇编指令 (直接回车结束):
> addi x1, x0, 10
> sw x1, 0(x0)
> 
请输入起始地址 (默认 0): 0

机器码 (可直接复制到指令存储器):
32'h00a00093,
32'h00102023,

文件结构:
Basic-RISC-V-CPU/
├── rtl/               # 所有 RTL 源文件
│   ├── bus/           # 总线仲裁器
│   ├── csr/           # CSR 寄存器
│   ├── exu/           # 执行单元
│   ├── hazard/        # 冒险检测与前递
│   ├── id/            # 译码阶段
│   ├── ifu/           # 取指阶段
│   ├── interrupt/     # 中断控制器
│   ├── mem/           # 访存阶段
│   ├── periph/        # 外设（UART/GPIO/Timer/SPI/I2C）
│   ├── pipeline/      # 流水线寄存器
│   └── top/           # 顶层模块
├── python/            # 汇编转机器码工具
│   └── riscv_arm.py
├── tb/                # 测试平台
└── docs/              # 文档


联系方式
作者：Yi Fengxin

单位：北京航空航天大学

邮箱：

1596215367@qq.com

1596215367@buaa.edu.cn

许可证
本项目仅供学习交流使用。


```markdown
# RISC-V-CPU

A 5-stage pipeline RISC-V CPU design with interrupt support, UART, GPIO, Timer, SPI, and I2C peripherals.

## Features

- **5-Stage Pipeline**: IF, ID, EX, MEM, WB
- **RISC-V Base Integer Instruction Set (RV32I)** + **Multiplication Extension (M)**
- **Interrupt Support**: Complete interrupt handling and return mechanism
- **Peripherals**:
  - UART Serial Communication
  - GPIO (Input/Output/Interrupt)
  - Programmable Timer (Interrupt)
  - **SPI Master Controller (Interrupt)**
  - **I2C Master Controller (Interrupt)**
- **Simulation & Deployment**:
  - Modelsim simulation for waveform observation
  - Vivado synthesis and FPGA programming

## Development Environment

| Tool | Purpose |
|------|---------|
| Modelsim | Simulation and waveform observation |
| Vivado | Synthesis and FPGA programming |
| Verilog | Hardware description language |
| Python | Assembly to machine code converter |

## Peripheral Details

### UART
- Configurable baud rate (default 115200)
- Transmit FIFO (16 bytes)
- Interrupt support

### GPIO
- 32-bit input/output
- Individual pin direction configuration
- Level/edge triggered interrupt

### Timer
- 32-bit down counter
- One-shot / auto-reload mode
- Programmable interrupt

### SPI Master Controller
- Supports 4 SPI modes (configurable CPOL/CPHA)
- Configurable clock divider (SPI clock = system clock / (2 × clk_divider))
- 8-bit/16-bit data transfer
- Configurable MSB-first/LSB-first
- Interrupt support (transmit complete / receive complete)

**SPI Register Map**:

| Offset | Register | Function |
|--------|----------|----------|
| 0x00 | SPI_CTRL | Control register (enable, interrupt, mode, start) |
| 0x04 | SPI_CLK_DIV | Clock divider register |
| 0x08 | SPI_DATA | Data register (transmit/receive) |
| 0x0C | SPI_STATUS | Status register (busy, tx ready, rx ready) |
| 0x10 | SPI_IRQ_FLAG | Interrupt flag register |

**SPI Control Register Bits**:

| Bit | Function |
|-----|----------|
| bit0 | SPI enable |
| bit1 | Interrupt enable |
| bit2 | CPOL (clock polarity) |
| bit3 | CPHA (clock phase) |
| bit4 | LSB first (1=LSB first) |
| bit5 | 16-bit mode (1=16-bit transfer) |
| bit6 | Start transfer (write 1 to start, auto-cleared) |

### I2C Master Controller
- Supports Standard mode (100kHz) and Fast mode (400kHz)
- 7-bit device addressing
- Interrupt support (transmit complete / receive complete / NACK error)

**I2C Register Map**:

| Offset | Register | Function |
|--------|----------|----------|
| 0x00 | I2C_CTRL | Control register (enable, interrupt, start, stop, read/write) |
| 0x04 | I2C_CLK_DIV | Clock divider register |
| 0x08 | I2C_TX_DATA | Transmit data register |
| 0x0C | I2C_RX_DATA | Receive data register |
| 0x10 | I2C_STATUS | Status register (busy, ready, ack flag) |
| 0x14 | I2C_ADDR | Slave address register |
| 0x18 | I2C_IRQ_FLAG | Interrupt flag register |

**I2C Control Register Bits**:

| Bit | Function |
|-----|----------|
| bit0 | I2C enable |
| bit1 | Interrupt enable |
| bit2 | Start transfer (write 1 to start) |
| bit3 | Stop transfer (write 1 to stop) |
| bit4 | Read/Write (0=write, 1=read) |
| bit5 | Acknowledge enable (send ACK on receive) |

**I2C Status Register Bits**:

| Bit | Function |
|-----|----------|
| bit0 | Busy flag |
| bit1 | Transmit ready |
| bit2 | Receive ready |
| bit3 | Acknowledge flag (0=ACK, 1=NACK) |

## Memory Map

| Peripheral | Base Address | Size |
|------------|--------------|------|
| RAM | 0x0000_0000 | 64KB |
| UART | 0x1000_0000 | 4KB |
| GPIO | 0x1000_1000 | 4KB |
| TIMER | 0x1000_2000 | 4KB |
| **SPI** | **0x1000_3000** | **4KB** |
| **I2C** | **0x1000_4000** | **4KB** |

## Interrupt Assignment

| Interrupt Source | Interrupt ID | Description |
|-----------------|--------------|-------------|
| Software Interrupt | 3 | Local interrupt |
| Timer Interrupt | 7 | Local interrupt |
| External Interrupt | 11 | Shared by GPIO/SPI/I2C |
| SPI Interrupt | 12 | Merged into external interrupt |
| I2C Interrupt | 13 | Merged into external interrupt |

**Note**: SPI and I2C interrupts are merged into the external interrupt (ID=11) at the top level. The interrupt service routine should read peripheral status registers to distinguish the interrupt source.

## Assembly to Machine Code Converter

`python/riscv_arm.py` is a Python tool that converts RISC-V assembly to machine code.

### Supported Instruction Sets

| Extension | Instructions |
|-----------|--------------|
| **RV32I** | add, sub, addi, slt, slti, sltu, sltiu, and, or, xor, andi, ori, xori, sll, srl, sra, slli, srli, srai, beq, bne, blt, bge, bltu, bgeu, jal, jalr, lb, lh, lw, lbu, lhu, sb, sh, sw, lui, auipc |
| **RV32M** | mul, mulh, mulhsu, mulhu, div, divu, rem, remu |
| **RV32A** | lr.w, sc.w, amoswap.w, amoadd.w, amoand.w, amoor.w, amoxor.w, amomin.w, amomax.w, amominu.w, amomaxu.w |
| **RV32F** | flw, fsw, fadd.s, fsub.s, fmul.s, fdiv.s, fmin.s, fmax.s, fsqrt.s, fmadd.s, fmsub.s, fnmadd.s, fnmsub.s, feq.s, flt.s, fle.s, fcvt.w.s, fcvt.s.w, fcvt.wu.s, fcvt.s.wu |
| **RV32D** | fld, fsd, fadd.d, fsub.d, fmul.d, fdiv.d, fmin.d, fmax.d, fsqrt.d, fmadd.d, fmsub.d, fnmadd.d, fnmsub.d, feq.d, flt.d, fle.d, fcvt.w.d, fcvt.d.w, fcvt.wu.d, fcvt.d.wu |
| **RV32C** | c.nop, c.addi, c.li, c.lui, c.srli, c.srai, c.andi, c.add, c.sub, c.lw, c.sw, c.j, c.jr, c.jalr, c.beqz, c.bnez |
| **Pseudo** | nop, li, la, mv, not, neg, negw, sext.w, seqz, snz, sltz, sgtz, bgt, ble, bgtu, bleu, beqz, bnez, blez, bgez, bltz, bgtz, call, tail, ret, jr, j, jal |
| **System** | ecall, ebreak, mret, sret, wfi, fence, fence.i |

### Usage

```bash
cd python
python riscv_arm.py
Steps:

Enter assembly instructions one by one, press Enter after each instruction

Press Enter again (without typing anything) to finish input

Enter the starting address (default is 0) or press Enter to accept default

The tool outputs continuous machine code format, ready to copy into inst_rom_hello.v

Enter assembly instruction (press Enter to finish):
> addi x1, x0, 10
> sw x1, 0(x0)
> 
Enter starting address (default 0): 0

Machine code (ready to copy into instruction memory):
32'h00a00093,
32'h00102023,

File Structure
Basic-RISC-V-CPU/
├── rtl/               # All RTL source files
│   ├── bus/           # Bus arbiter
│   ├── csr/           # CSR registers
│   ├── exu/           # Execution unit
│   ├── hazard/        # Hazard detection & forwarding
│   ├── id/            # Instruction decode
│   ├── ifu/           # Instruction fetch
│   ├── interrupt/     # Interrupt controller
│   ├── mem/           # Memory access
│   ├── periph/        # Peripherals (UART/GPIO/Timer/SPI/I2C)
│   ├── pipeline/      # Pipeline registers
│   └── top/           # Top module
├── python/            # Assembly to machine code converter
│   └── riscv_arm.py
├── tb/                # Testbench
└── docs/              # Documentation

Contact
Author: Yi Fengxin

Affiliation: Beihang University

Email:

1596215367@qq.com

1596215367@buaa.edu.cn

License
This project is for educational purposes only.