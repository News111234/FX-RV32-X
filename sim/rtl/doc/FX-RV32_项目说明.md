# FX-RV32 RISC-V CPU 项目说明

> 作者：Yi Fengxin, 北京航空航天大学
> 最后更新：2026-06-06

---

## 1. 项目概述

FX-RV32 是一个五级流水线 RISC-V CPU，采用 Verilog 硬件描述语言编写，目标 FPGA 为 Xilinx Kintex-7 xc7k325tffg900-2，主频 200MHz。

项目提供**两个版本**，分别用于不同目的：

| 版本 | 路径 | ISA | 用途 |
|------|------|-----|------|
| **RV32I** | `/home/yifengxin/FX-RV32_RemoveM_Custom/` | RV32I（基础整数指令集） | 📝 **论文写作**、面积/功耗分析 |
| **RV32IM** | `/home/yifengxin/FX-RV32_AddM/` | RV32IM（含硬件乘除法） | 🏎️ **CoreMark 性能测试** |

> ⚠️ **重要**：两个版本相互独立，修改一个不会影响另一个。

---

## 2. 两个版本的定位

### 2.1 RV32I 版本（论文用）

- **目录**：`/home/yifengxin/FX-RV32_RemoveM_Custom/`
- **指令集**：仅 RV32I（40 条基础整数指令）
- **乘除法**：通过软件库 `soft_muldiv.c` 模拟（__mulsi3/__udivsi3 等）
- **特点**：
  - 硬件面积最小（无乘法器/DSP）
  - 适合论文中的面积、功耗、时序分析
  - 可用于 Design Compiler / Vivado 综合对比
- **论文相关设计文档**：
  - `doc/interrupt/` — 中断系统设计（2 周期延迟、影子寄存器等）
  - `doc/uart_design.md` — UART 外设设计
  - `doc/load_use_hazard_analysis.md` — Load-Use 冒险分析

### 2.2 RV32IM 版本（CoreMark 测试用）

- **目录**：`/home/yifengxin/FX-RV32_AddM/`
- **指令集**：RV32IM（RV32I + M 扩展 8 条乘除法指令）
- **乘除法**：硬件实现（MUL 单周期，DIV 33 周期恢复除法）
- **特点**：
  - 乘除法性能大幅提升（乘法 200×，除法 10-300×）
  - 适合跑 CoreMark 等基准测试
  - 综合面积较大（需 DSP 硬核）
- **M 扩展设计文档**：
  - `doc/m_extension_plan.md` — M 扩展实施方案
  - `doc/coremark_results.md` — CoreMark 跑分结果

---

## 3. 目录结构

两个版本的文件结构**完全相同**，只有 RTL 代码内容不同。以下是 `FX-RV32_AddM/` 的结构（`FX-RV32_RemoveM_Custom/` 同理）：

```
FX-RV32_AddM/
├── core/                              # CPU 核心 RTL
│   ├── core_top.v                     # 核心顶层（实例化所有流水线模块）
│   ├── ifu/                           # 取指单元
│   │   ├── ifu_top.v                  # IFU 顶层（PC 选择逻辑）
│   │   └── pc_reg.v                   # PC 寄存器
│   ├── id/                            # 译码单元
│   │   ├── id_top.v                   # ID 顶层
│   │   ├── decoder.v                  # 指令译码器（生成 ALU 操作码）
│   │   ├── ctrl.v                     # 分支/跳转控制
│   │   ├── imm_gen.v                  # 立即数生成器
│   │   └── regfile.v                  # 寄存器堆（32 通用 + 31 影子寄存器）
│   ├── exu/                           # 执行单元
│   │   ├── ex_top.v                   # EX 顶层
│   │   ├── alu.v                      # ★ ALU（RV32I: 8 种运算 / RV32IM: 16 种运算）
│   │   └── branch.v                   # 分支判断单元
│   ├── mem/                           # 访存单元
│   │   ├── mem_top.v                  # MEM 顶层
│   │   └── mem_ctrl.v                 # 总线请求控制
│   ├── wbu/                           # 写回单元
│   │   ├── wb_top.v                   # WB 顶层
│   │   └── wb_mux.v                   # 写回数据选择
│   ├── pipeline/                      # 流水线寄存器
│   │   ├── if_id_reg.v
│   │   ├── id_ex_reg.v                # ★ alu_op 位宽: RV32I=4bit, RV32IM=5bit
│   │   ├── ex_mem_reg.v
│   │   └── mem_wb_reg.v
│   ├── hazard/                        # 冒险处理
│   │   ├── hazard_unit.v              # Load-Use 检测 + 控制冒险
│   │   └── forwarding_unit.v          # 数据转发
│   ├── csr/                           # CSR 寄存器
│   │   ├── csr_regfile.v
│   │   └── csr_instructions.v
│   └── interrupt/                     # 中断系统
│       ├── interrupt_controller.v     # 中断优先级（MEI>MTI>SPI>I2C>MSI）
│       └── interrupt_pipeline.v       # 2 周期恒定延迟中断响应
│
├── soc/                               # SoC 集成
│   ├── top/
│   │   ├── soc_top.v                  # 仿真顶层（CPU + 外设 + 总线）
│   │   └── soc_top_fpga.v             # FPGA 顶层（LVDS 时钟 + 三态 GPIO）
│   ├── mem/
│   │   ├── inst_rom.v                 # 指令 ROM（仿真时 $readmemh 加载 hex）
│   │   └── data_ram.v                 # 数据 RAM（64KB）
│   ├── bus/
│   │   └── bus_arbiter.v             # 总线仲裁器（地址路由）
│   └── periph/                        # 外设
│       ├── uart_ctrl.v                # UART 控制器（TX FIFO + 寄存器）
│       ├── uart_tx.v                  # UART 发送器（8N1 协议）
│       ├── gpio.v                     # GPIO（32 位双向，中断）
│       ├── timer.v                    # 定时器（32 位递减，自动重载）
│       ├── spi_master.v               # SPI 主机
│       └── i2c_master.v               # I2C 主机
│
├── sim/                               # Verilator 仿真
│   ├── makefile                       # Verilator 构建脚本
│   ├── sim_main.cpp                   # C++ 仿真 harness
│   └── program.hex                    # 加载到 inst_rom 的机器码
│
├── uvm/                               # UVM 验证环境（Modelsim）
│   ├── uvm_tb_top.sv                  # UVM 顶层 testbench
│   ├── riscv_uvm_pkg.sv              # UVM 测试包（含 cpu_test_coremark）
│   ├── cpu_if.sv                      # CPU 总线接口
│   ├── run_msim.tcl                   # Modelsim 自动化脚本
│   ├── run_coremark.tcl               # CoreMark 启动脚本
│   ├── rtl_filelist.f                 # RTL 源文件列表
│   ├── COREMARK_GUIDE.md             # CoreMark 运行指南
│   └── coremark.hex                   # CoreMark 机器码
│
├── coremark_port/                     # CoreMark 移植文件
│   ├── Makefile                       # ★ 交叉编译（RV32I: -march=rv32i / RV32IM: -march=rv32im）
│   ├── link.ld                        # 链接脚本（哈佛架构）
│   ├── startup.s                      # 启动代码（crt0）
│   ├── core_portme.h                  # 平台配置头文件
│   ├── core_portme.c                  # UART + 定时器 + 板级初始化
│   ├── ee_printf.c                    # 轻量级 printf
│   ├── bin2hex.py                     # ELF → hex 格式转换
│   ├── soft_muldiv.c                  # ★ 仅 RV32I 版本有此文件（软件乘除法）
│   ├── program.hex                    # 生成的机器码（输出）
│   └── coremark.dis                   # 反汇编（调试用）
│
├── tb/                                # 传统 Testbench（非 UVM）
│   ├── tb_core_top.v                  # CPU 核心级 testbench
│   └── tb_soc_top.v                   # SoC 级 testbench
│
├── doc/                               # 文档
│   ├── FX-RV32_项目说明.md            # ★ 本文件
│   ├── m_extension_plan.md            # M 扩展实施方案
│   ├── coremark_results.md            # CoreMark 跑分结果
│   ├── uart_design.md                 # UART 设计说明
│   ├── load_use_hazard_analysis.md    # Load-Use 冒险分析
│   └── interrupt/                     # 中断系统文档
│       ├── shadow_register_guide.md
│       ├── shadow_en_config.md
│       ├── shadow_save_race_condition.md
│       ├── interrupt_vector_mode.md
│       ├── interrupt_2cycle_guaranteed.md
│       ├── interrupt_2cycle_implementation.md
│       ├── interrupt_latency_analysis.md
│       └── thesis_interrupt_and_shadow.md
│
├── mytests/                           # 汇编测试程序
├── python/                            # Python 工具（汇编器、hex 转换等）
├── vivado/                            # Vivado 工程
├── constraints.xdc                    # FPGA 引脚约束
└── README.md
```

**RV32I 独有文件**：
- `coremark_port/soft_muldiv.c` — 软件乘除法实现

**RV32IM 独有文件**：
- 无（通过修改 RTL 实现，文件结构相同）

**两个版本共用的外部依赖**：
- `/home/yifengxin/coremark_test/coremark-main/` — CoreMark 官方源码
- `/home/yifengxin/riscv/` — RISC-V GNU 工具链

---

## 4. 两个版本的关键差异

### 4.1 RTL 差异

| 模块 | RV32I | RV32IM |
|------|-------|--------|
| `core/exu/alu.v` | 8 种运算 (4bit alu_op) | 16 种运算 (5bit alu_op)，含 MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU |
| `core/id/decoder.v` | `alu_op_o` [3:0] | `alu_op_o` [4:0]，解码 M 指令 (funct7=0x01) |
| `core/exu/ex_top.v` | 无 bus 信号 | 新增 `alu_busy_o` 端口 |
| `core/core_top.v` | `stall_ex = 0` | `stall_ex = ex_alu_busy`，DIV 时自动停顿流水线 |
| `core/pipeline/id_ex_reg.v` | `alu_op` [3:0] | `alu_op` [4:0] |

### 4.2 CoreMark 编译差异

| 选项 | RV32I | RV32IM |
|------|-------|--------|
| `ARCH_FLAGS` | `-march=rv32i` | `-march=rv32im` |
| 乘法 | 软件 (~200 周期) | 硬件 (1 周期) |
| 除法 | 软件 (~300 周期) | 硬件 (1-34 周期) |
| libgcc 依赖 | 不需要（自带 soft_muldiv.c） | 需要 `-lgcc` |
| CoreMark 单次迭代 | ~200M 周期 | ~2-5M 周期 |
| CoreMark 加速比 | 基准 (1×) | **50-100×** |

### 4.3 面积/功耗差异（预估）

| 指标 | RV32I | RV32IM | 增量 |
|------|-------|--------|------|
| LUT | ~3,000 | ~4,500 | +50% |
| DSP | 0 | 4 | +4 |
| FF | ~1,500 | ~2,000 | +33% |
| 最大频率 | 200 MHz | 200 MHz | 不变 |

---

## 5. 如何运行

### 5.1 编译 CoreMark

```bash
# === RV32I 版本 ===
cd /home/yifengxin/FX-RV32_RemoveM_Custom/coremark_port
make clean && make ITERATIONS=1     # 快速验证（~200M 周期，仿真需数小时）
make sim                            # 复制到 ../sim/program.hex

# === RV32IM 版本 ===
cd /home/yifengxin/FX-RV32_AddM/coremark_port
make clean && make ITERATIONS=500   # 正式跑分（~2-5M 周期）
make sim                            # 复制到 ../sim/program.hex
```

### 5.2 Verilator 仿真

```bash
cd /home/yifengxin/FX-RV32_AddM/sim          # 或 FX-RV32_RemoveM_Custom/sim
ln -s .. rtl                                   # 首次需创建符号链接
cp ../uvm/core_top_sim.txt ../core/core_top_sim.v  # 首次需复制 wrapper
cp ../coremark_port/program.hex .
make clean && make && make run
```

### 5.3 Modelsim UVM 仿真（推荐用于跑分）

```bash
# 1. 准备 Windows 可访问路径
cp -r /home/yifengxin/FX-RV32_AddM /mnt/d/FX-RV32_AddM

# 2. Windows 命令行运行
cd /d D:\FX-RV32_AddM\uvm
D:\modeltech64_10.6e\win64\vsim.exe -c -do run_coremark.tcl

# 3. 查看结果
findstr "SCOREBOARD Mismatches" transcript
```

详细说明参见 `uvm/COREMARK_GUIDE.md`。

### 5.4 使用其他测试程序

```bash
# 不跑 CoreMark，用已有测试程序
cd /home/yifengxin/FX-RV32_RemoveM_Custom/uvm

# 基础指令测试
vsim -c -do "set HEX_FILE alu_test.hex; set TEST_NAME cpu_test_alu; do run_msim.tcl"

# 中断测试
vsim -c -do "set HEX_FILE intr_test.hex; set TEST_NAME cpu_test_interrupt; do run_msim.tcl"

# 冒险测试
vsim -c -do "set HEX_FILE load_use_test.hex; set TEST_NAME cpu_test_hazard; do run_msim.tcl"
```

---

## 6. 快速参考

### 常用命令速查

```bash
# === 编译工具链 ===
/home/yifengxin/riscv/bin/riscv32-unknown-elf-gcc --version

# === CoreMark 编译 ===
cd coremark_port && make ITERATIONS=500   # 编译
cd coremark_port && make sim              # 复制 hex 到 sim/

# === Verilator 仿真 ===
cd sim && make run                        # 构建并运行

# === Modelsim UVM ===
# Windows 上运行：D:\FX-RV32_AddM\uvm\run_coremark.tcl

# === 查看项目文档 ===
ls doc/                                   # 所有文档
cat doc/FX-RV32_项目说明.md               # 本文件
cat doc/m_extension_plan.md               # M 扩展方案
cat doc/coremark_results.md               # 跑分结果
```

### 内存映射

| 外设 | 基地址 | 大小 |
|------|--------|------|
| RAM | 0x0000_0000 | 64KB |
| UART | 0x1000_0000 | 4KB |
| GPIO | 0x1000_1000 | 4KB |
| Timer | 0x1000_2000 | 4KB |
| SPI | 0x1000_3000 | 4KB |
| I2C | 0x1000_4000 | 4KB |

### 中断 ID

| ID | 来源 |
|----|------|
| 3 | 软件中断 |
| 7 | 定时器中断 |
| 11 | 外部中断 (GPIO/SPI/I2C) |

---

## 7. 已知问题

| 问题 | 影响 | 版本 |
|------|------|------|
| AUIPC 在 PC≠0 时计算偏差 | BSS 边界偏移 16 字节 | 两个版本均有 |
| UART 地址偏移不转发 | 无法读取 STATUS/CTRL 寄存器 | 两个版本均有 |
| Load-Use 停顿不插入 NOP | 指令重复执行 | 两个版本均有 |
| DC 综合有 3 个语法错误 | 无法综合 | 两个版本均有 |
| Verilator 仿真极慢 | CoreMark 难以跑完 | RV32I 版本尤甚 |

---

## 8. 版本历史

| 日期 | 事件 |
|------|------|
| 2026-05 | 初始 RV32I 版本（论文用） |
| 2026-06-05 | 创建 RV32IM 版本，添加 M 扩展 |
| 2026-06-05 | CoreMark 移植完成，UVM 仿真流程建立 |
| 2026-06-06 | M 扩展 RTL 验证通过（Modelsim） |
| 2026-06-06 | CoreMark 跑分启动中 |
