# FX-RV32 RISC-V CPU 项目说明

> 作者：Yi Fengxin，北京航空航天大学
> 最后更新：2026-06-13
> 版本：RV32I（论文版，无 M 扩展）

---

## 1. 项目概述

FX-RV32 是一个面向硬实时嵌入式系统的五级顺序流水线 RISC-V 处理器，采用 Verilog 编写，只实现 RV32I 基础整数指令集（40 条指令），不含乘除、压缩指令、浮点。

**核心特点：**

| 特性 | 数值 |
|------|------|
| 流水线 | 五级顺序（IF→ID→EX→MEM→WB），无分支预测 |
| 存储架构 | 哈佛结构（指令 ROM + 数据 RAM），完全无缓存 |
| 中断延迟 | 固定 2 个时钟周期（硬件向量模式） |
| GPIO 延迟 | 1 个时钟周期 |
| 影子寄存器 | 31 个，单周期硬件保存/恢复 x1–x31 |
| 基准面积 | 24.89 kGE（SHADOW_EN=0），55nm SMIC |
| 完整面积 | 32.37 kGE（SHADOW_EN=1） |
| 基准功耗 | 4.020 mW（SHADOW_EN=0），200 MHz |
| 完整功耗 | 5.838 mW（SHADOW_EN=1），200 MHz |
| 目标 FPGA | Xilinx Kintex-7 xc7k325tffg900-2，200 MHz |
| 确定执行 | 8 组测试 40 轮运行零抖动 |

---

## 2. 项目目录结构

```
FX-RV32_RemoveM_Custom/
├── core/                  # ★ CPU 核心 RTL（五级流水线 + 中断 + CSR）
│   ├── core_top.v          # 核心顶层，实例化所有流水线模块
│   ├── core_top_sim.v      # 仿真专用顶层（CoreMark 计数器 + 调试信号）
│   ├── ifu/                # 取指单元（IF Stage）
│   │   ├── ifu_top.v       #   IFU 顶层：next_pc 优先级选择
│   │   └── pc_reg.v        #   PC 寄存器（posedge clk 更新）
│   ├── id/                 # 译码单元（ID Stage）
│   │   ├── id_top.v        #   ID 顶层（SHADOW_EN 参数入口）
│   │   ├── decoder.v       #   指令译码器（组合逻辑）
│   │   ├── ctrl.v          #   分支/跳转控制信号生成
│   │   ├── imm_gen.v       #   立即数生成器（I/S/B/U/J 五格式）
│   │   └── regfile.v       #   ★ 寄存器堆：32 GPR + 31 影子寄存器（SHADOW_EN=1 时）
│   ├── exu/                # 执行单元（EX Stage）
│   │   ├── ex_top.v        #   EX 顶层（前递数据多路选择）
│   │   ├── alu.v           #   ALU（8 种 RV32I 运算，单周期组合逻辑）
│   │   └── branch.v        #   分支判断（地址计算 + 条件评估）
│   ├── mem/                # 访存单元（MEM Stage）
│   │   ├── mem_top.v       #   MEM 顶层（地址/数据透传 + 总线请求）
│   │   └── mem_ctrl.v      #   总线请求控制（产生 bus_re_o）
│   ├── wbu/                # 写回单元（WB Stage）
│   │   ├── wb_top.v        #   WB 顶层
│   │   └── wb_mux.v        #   写回数据选择（ALU/MEM/PC+4/CSR 四选一）
│   ├── pipeline/           # 流水线寄存器（全部正沿触发）
│   │   ├── if_id_reg.v     #   IF/ID 寄存器
│   │   ├── id_ex_reg.v     #   ID/EX 寄存器
│   │   ├── ex_mem_reg.v    #   EX/MEM 寄存器
│   │   └── mem_wb_reg.v    #   MEM/WB 寄存器
│   ├── hazard/             # 冒险处理
│   │   ├── hazard_unit.v   #   ★ 冒险检测（Load-Use 停顿、分支冲刷、中断冲刷）
│   │   └── forwarding_unit.v # 数据前递（EX/MEM→EX, MEM/WB→EX）
│   ├── csr/                # CSR 寄存器
│   │   ├── csr_regfile.v   #   CSR 寄存器堆（mstatus/mepc/mcause/mtvec/mie/mip/...）
│   │   └── csr_instructions.v # CSR 指令执行（CSRRW/CSRRS/CSRRC 及立即数变体）
│   └── interrupt/          # ★ 中断系统
│       ├── interrupt_controller.v  # 优先级编码器（MEI>MTI>SPI>I2C>MSI）
│       └── interrupt_pipeline.v    # 中断流水线控制器（2 周期恒定延迟 + 影子寄存器控制）
│
├── soc/                   # SoC 集成（CPU + 存储器 + 外设 + 总线）
│   ├── top/
│   │   ├── soc_top.v       # 仿真顶层
│   │   └── soc_top_fpga.v  # FPGA 顶层（IBUFDS LVDS 时钟 + IOBUF 三态 GPIO）
│   ├── bus/
│   │   └── bus_arbiter.v   # 总线仲裁器（纯组合逻辑地址译码，零等待）
│   ├── mem/
│   │   ├── inst_rom.v      # 指令 ROM（4KB，编译时加载程序）
│   │   └── data_ram.v      # 数据 RAM（64KB，单端口 SRAM）
│   └── periph/             # 外设（全部内存映射，单周期访问）
│       ├── uart_ctrl.v     #   UART 控制器（TX FIFO，FIFO_DEPTH 可配）
│       ├── uart_tx.v       #   UART 发送器（8N1 协议，115200 波特率默认）
│       ├── gpio.v          #   GPIO（32 位双向，边沿/电平中断）
│       ├── timer.v         #   定时器（32 位递减，单次/自动重载）
│       ├── spi_master.v    #   SPI 主机（4 模式 CPOL/CPHA，8/16 位传输）
│       └── i2c_master.v    #   I2C 主机（100kHz/400kHz，7 位地址）
│
├── tb/                    # 传统 Testbench
│   ├── tb_core_top.v       # 核心级 testbench（core_top_sim + GPIO 激励）
│   └── tb_soc_top.v        # SoC 级 testbench（soc_top + tohost 机制）
│
├── sim/                   # Verilator 仿真
│   ├── makefile            # Verilator 构建脚本
│   ├── sim_main.cpp        # C++ 仿真 harness（5ns/半周期 = 100MHz）
│   └── rtl/                # → 符号链接到项目根目录
│
├── uvm/                   # UVM 1.2 验证环境（Modelsim/Questa）
│   ├── uvm_tb_top.sv       # UVM 顶层 testbench（模拟 inst_rom + 64KB data_ram）
│   ├── riscv_uvm_pkg.sv    # UVM 测试包（含 cpu_test_alu/interrupt/hazard/coremark）
│   ├── cpu_if.sv           # CPU 总线接口
│   ├── run_msim.tcl        # Modelsim 自动化 TCL 脚本
│   ├── run_uvm.bat         # Windows 一键启动脚本
│   ├── rtl_filelist.f      # RTL 源文件列表
│   ├── core_top_sim.txt    # ★ core_top_sim.v 的源代码（需复制为 .v 才能仿真）
│   ├── alu_test.s / .hex   # ALU 测试汇编及机器码
│   ├── intr_test.s / .hex  # 中断测试
│   ├── load_use_test.s     # Load-Use 冒险测试
│   ├── store_test.s        # 存储测试
│   ├── test_result_*.md    # UVM 测试结果日志
│   └── README.md           # UVM 环境详细说明
│
├── mytests/               # 确定性测试汇编程序
│   ├── test1_vvadd.S       #   向量加法（143 周期）
│   ├── test2_fib.S         #   递归斐波那契（97 周期）
│   ├── test3_matmul.S      #   矩阵乘法（23 周期）
│   ├── test4_bubble.S      #   冒泡排序（1081 周期）
│   ├── test5_lfsr.S        #   LFSR（2053 周期）
│   ├── test6_forwarding.S  #   前递确定性（33 周期/轮）
│   ├── test7_branching.S   #   控制流确定性（16 周期/轮）
│   ├── test8_memdep.S      #   访存确定性（41 周期/轮）
│   ├── test9_interrupt.S   #   中断确定性（ISR 8 周期）
│   ├── test9_mixedwork.S   #   混合负载确定性（45 周期/轮）
│   ├── load_use_test.s     #   Load-Use 冒险测试
│   ├── test.ld             #   链接脚本（.text@0x0, .data@0x100）
│   ├── convert_hex.py      #   Verilog-hex → plain hex 转换器
│   └── 确定性测试说明.md    #   测试方法论与结果说明（论文用）
│
├── python/                # Python 工具
│   ├── riscv_asm7.py       # ★ 主汇编器（v16，支持标签/伪指令/CSR/%hi/%lo）
│   ├── riscv_arm.py        # 旧版简洁汇编器（交互式）
│   ├── asm_to_hex.py       # 汇编输出 → hex 转换
│   ├── spi_test.s          # SPI 测试汇编示例
│   ├── rom_output/gen_rom.py  # hex → Verilog ROM 格式转换
│   ├── jal_branch_recognize/  # JAL/Branch 识别 + NOP 插入（早期流水线用）
│   └── plot/               # Matplotlib 论文绘图
│       ├── Area/            #   面积对比柱状图
│       ├── Interrupt_latency/ # 中断延迟对比图
│       ├── Synthesis/       #   综合结果图
│       ├── execution time/  #   确定性测试周期数直方图
│       └── Structure/       #   CPU 结构图
│
├── doc/                   # 设计文档
│   ├── interrupt/           # ★ 中断系统系列文档
│   │   ├── shadow_register_guide.md           # 影子寄存器保存/恢复机制
│   │   ├── shadow_en_config.md                # SHADOW_EN 参数配置（三处定义）
│   │   ├── shadow_save_race_condition.md       # shadow_save vs WB 写回竞态分析
│   │   ├── interrupt_vector_mode.md            # Direct vs Vectored 模式
│   │   ├── interrupt_2cycle_guaranteed.md      # 2 周期恒定延迟设计分析
│   │   ├── interrupt_2cycle_implementation.md  # 2 周期延迟实现记录（2026-05）
│   │   ├── interrupt_2cycle_strict_implementation.md
│   │   ├── interrupt_latency_analysis.md       # 初始中断延迟分析
│   │   └── thesis_interrupt_and_shadow.md      # 论文中断+影子寄存器章节
│   ├── uart_design.md      # UART 架构、寄存器映射、总线握手
│   ├── load_use_hazard_analysis.md    # Load-Use 冒险已知 bug（缺少 ID/EX NOP 插入）
│   ├── load_use_forwarding_optimization.md # Load-Use 前递优化分析
│   ├── coremark_results.md # CoreMark 基准测试结果
│   ├── fpga_coremark_guide.md # FPGA CoreMark 运行指南
│   ├── ecall_exception_plan.md    # ECALL 异常实现方案
│   ├── ecall_test_report.md       # ECALL 异常测试报告
│   ├── auipc_bug_analysis.md      # AUIPC 指令 bug 分析
│   ├── auipc_fix_changelog.md     # AUIPC 修复记录
│   ├── deterministic_test_progress.md # 确定性测试开发进度
│   ├── test_classification.md     # 测试分类方法
│   ├── riscv_test_plan.md         # RISC-V 测试套件集成计划
│   ├── riscv_tests_and_uvm_integration.md # RISC-V 测试 + UVM 集成
│   ├── m_extension_plan.md        # M 扩展实施计划（未实现）
│   ├── CCF-A投稿分析.md           # CCF-A 期刊对比分析
│   └── thesis/latex_revision_log.md # LaTeX 论文修改记录
│
├── syn/                   # Design Compiler 综合
│   ├── run_synth.tcl       # 综合脚本（SMIC 55nm, 200MHz, compile_ultra）
│   ├── run_synth_power.tcl # 功耗分析脚本
│   ├── DC_command.txt      # DC 启动命令
│   └── report/
│       ├── area/           # 面积报告
│       │   ├── area_hier_en0.rpt    # SHADOW_EN=0 层次化面积
│       │   └── area_hier_sh1.rpt    # SHADOW_EN=1 层次化面积
│       ├── power/          # 功耗报告
│       │   ├── power_hier_en0.rpt   # SHADOW_EN=0 层次化功耗
│       │   └── power_hier_sh1.rpt   # SHADOW_EN=1 层次化功耗
│       └── report_file_index.md     # 报告文件索引
│
├── vivado/                # Vivado 2022.1 FPGA 工程
│   └── RISCV_TEST/RISCV_TEST.xpr   # Vivado 工程文件
│
├── constraints.xdc        # FPGA 引脚约束（200MHz LVDS, UART, LED, GPIO）
├── README.md              # 外设寄存器定义
├── FX-RV32.md             # ★ 中文论文稿件
├── bare_jrnl_new_sample4.tex # ★ 英文 IEEE TVLSI 投稿 LaTeX
├── 论文排版注意事项.md     # LaTeX 排版陷阱与数据源速查
├── CLAUDE.md              # Claude Code 项目指南
├── A.v / B.v              # （临时文件，空模块）
└── scipts/                # 空目录（typo）
```

---

## 3. CPU 微架构详解

### 3.1 五级流水线

```
IF ──→ ID ──→ EX ──→ MEM ──→ WB
 │       │      │       │       │
if_id   id_ex  ex_mem  mem_wb   regfile
 reg     reg    reg     reg     (write)
```

**IF（取指）**：PC 寄存器→指令 ROM 地址→32 位指令→IF/ID 寄存器锁存。`next_pc` 优先级链：`intr_take_now > interrupt_taken > branch_taken > jump_taken > stall > pc+4`。全正沿触发，无负边沿或门控时钟。

**ID（译码）**：纯组合逻辑。译码器解析 opcode/funct3/funct7/rs1/rs2/rd，立即数生成器产生 32 位立即数（I/S/B/U/J 五种格式），寄存器堆两读端口组合读出操作数。结果锁存到 ID/EX。

**EX（执行）**：ALU 执行 RV32I 全部整数运算（ADD/SUB/SLL/SLT/SLTU/XOR/SRL/SRA/OR/AND/LUI/AUIPC），均为单周期组合逻辑。分支单元在同一周期判断 branch_taken 和计算目标地址。前递单元监测 ID/EX、EX/MEM、MEM/WB 三级 RAW 冒险，必要时从后续阶段直接取操作数。

**MEM（访存）**：访存顶层将地址/数据/控制信号转发至总线仲裁器。仲裁器为纯组合译码——地址在 RAM 范围则路由至 data_ram，否则路由至对应外设。零等待，同周期返回读数据。

**WB（写回）**：四选一多路选择器（ALU 结果/内存读数据/PC+4/CSR 数据），结果写入寄存器堆（rd≠0 时）。

### 3.2 冒险处理

**数据前递（forwarding_unit.v）**：EX/MEM 或 MEM/WB 有有效的寄存器写操作且目标寄存器匹配当前 EX 源寄存器时，ALU 直接从后续阶段取数据，无需停顿。

**Load-Use 冒险（hazard_unit.v）**：EX 阶段有 load 指令且尚未到达 MEM，而 ID 阶段指令读取其目标寄存器时，IF/ID 停顿一个周期，PC 保持不变。**已知 bug**：当前未在 ID/EX 插入 NOP，导致 load 和依赖指令均被重复执行。对 RAM 读功能等效（幂等），对 FIFO 外设会丢数据。

**分支惩罚**：分支/跳转在 EX 阶段解析，`flush_if/flush_id` 清除预取的两条指令（正常 2 周期惩罚）。若分支源寄存器依赖未写回的 load，额外停顿 1 周期（总 3 周期）。

### 3.3 中断系统

#### 中断控制器（interrupt_controller.v）
- 优先级排序（固定）：MEI（ID=11）> MTI（ID=7）> SPI（ID=12）> I2C（ID=13）> MSI（ID=3）
- 支持 Direct 和 Vectored 两种模式（由 `mtvec.MODE` 选择）
- Direct 模式：所有中断跳转 `{mtvec[31:2], 2'b0}`
- Vectored 模式：入口地址 = `BASE + cause[4:0] × 4`（纯组合逻辑计算）

#### 中断流水线（interrupt_pipeline.v）
- 两状态 FSM：`interrupt_accepted` + `interrupt_processed`
- **恒定 2 周期中断延迟**：无论 EX 阶段是否有分支跳转、MEM 是否有未完成 load，中断均在 2 周期内进入 ISR
- T1：`intr_take_now` 组合逻辑立即将 PC 重定向到 handler 地址；同时写入 CSR（mepc/mcause/mstatus）
- T2：`shadow_save` 保存全部 x1–x31 到影子寄存器；ISR 首条指令进入 IF 阶段
- `bus_ready_i` 区分已完成/未完成 MEM load：已完成→mepc=mem_pc+4；未完成→mepc=mem_pc（MRET 后重做）

#### 中断冲刷（hazard_unit.v）
```
intr_flush_id_o  = 1'b0               // ★ IF/ID 不冲刷！ISR首指令直接通过
intr_flush_ex_o  = interrupt_flush_i  // ID/EX 冲刷→NOP (旧程序残留在此处杀死)
intr_flush_mem_o = interrupt_flush_i  // EX/MEM 冲刷→NOP
intr_flush_wb_o  = 1    // MEM/WB 冲刷→NOP
```

### 3.4 影子寄存器（regfile.v）

- 31 个 32 位影子寄存器，对应 x1–x31（x0 硬连线为 0）
- **保存**：中断进入的次周期（T2），`shadow_save` 单周期脉冲将全部 x1–x31 并行快照到影子寄存器
- **恢复**：MRET 在 EX 阶段执行时，`shadow_restore` 脉冲将影子寄存器值并行写回 x1–x31
- **写优先级**：shadow_restore（最高）> 正常 WB 写回 > shadow_save（最低）
- **SHADOW_EN 参数**：在三个位置独立定义（`id_top.v`、`regfile.v`、`interrupt_pipeline.v`），默认均为 1。同步修改。
- 影子寄存器增量：+8,360 µm² = +7.46 kGE，+1.82 mW
- 当前不支持中断嵌套（只有一组影子寄存器），但可扩展为多组堆栈结构

### 3.5 CSR 寄存器

双端口写架构：
- 端口 1：CSR 指令（CSRRW/CSRRS/CSRRC 及立即数变体）——在 EX 阶段执行
- 端口 2：中断响应时 interrupt_pipeline 同步更新 mepc/mcause/mstatus——与端口 1 同一周期可同时有效

实现的 CSR：mstatus、mtvec、mepc、mcause、mie、mip、mscratch、mtval、mcycle、minstret

---

## 4. 存储与外设

### 4.1 内存映射

| 地址范围 | 设备 | 大小 |
|---------|------|------|
| 0x0000_0000 – 0x0000_FFFF | 数据 RAM | 64 KB |
| 0x1000_0000 – 0x1000_0FFF | UART | 4 KB |
| 0x1000_1000 – 0x1000_1FFF | GPIO | 4 KB |
| 0x1000_2000 – 0x1000_2FFF | Timer | 4 KB |
| 0x1000_3000 – 0x1000_3FFF | SPI | 4 KB |
| 0x1000_4000 – 0x1000_4FFF | I2C | 4 KB |

指令 ROM 不在总线地址空间中，由 IF 阶段通过专用接口直接访问。

### 4.2 总线仲裁器（bus_arbiter.v）

- 纯组合逻辑地址译码，零等待
- MEM 阶段发出的地址落在 RAM 范围（[0x0000_0000, 0x0000_FFFF]）则路由至 data_ram
- 否则按高位地址匹配路由至对应外设
- **UART 写入使用锁存机制**：写操作保持到 UART 报告 tx_ready（状态寄存器 bit0），5 周期超时

### 4.3 外设简表

| 外设 | 文件 | 功能 |
|------|------|------|
| UART | `uart_ctrl.v` + `uart_tx.v` | TX-only，115200 波特率，16 字节 FIFO（FIFO_DEPTH 可配），暂不支持 RX |
| GPIO | `gpio.v` | 32 位双向，每 pin 方向可配，边沿/电平触发中断 |
| Timer | `timer.v` | 32 位递减计数器，单次/自动重载模式，作为 MTI 中断源（ID=7） |
| SPI | `spi_master.v` | 4 种模式（CPOL/CPHA），8/16 位传输，MSB/LSB 可配，时钟分频可配 |
| I2C | `i2c_master.v` | 标准 100kHz + 快速 400kHz，7 位寻址 |

---

## 5. 面积与功耗（综合数据）

### 5.1 数据来源

| 数据 | 文件 | 工艺角 |
|------|------|--------|
| 面积（en0） | `syn/report/area/area_hier_en0.rpt` | TT 25°C 1.2V |
| 面积（sh1） | `syn/report/area/area_hier_sh1.rpt` | TT 25°C 1.2V |
| 功耗（en0） | `syn/report/power/power_hier_en0.rpt` | TT 25°C 1.2V，200 MHz |
| 功耗（sh1） | `syn/report/power/power_hier_sh1.rpt` | TT 25°C 1.2V，200 MHz |

转换：1 GE（NAND2 等效门）= 1.12 µm²

### 5.2 面积分解（core_top 层次化）

| 模块 | en0 (µm²) | en0 (kGE) | sh1 (µm²) | sh1 (kGE) | 说明 |
|------|----------|-----------|----------|-----------|------|
| 寄存器堆 | 12,328 | 11.01 | 20,688 | 18.47 | en0: 32×32 GPR；sh1: +31 影子 |
| 流水线寄存器 | 5,098 | 4.55 | 5,095 | 4.55 | IF/ID+ID/EX+EX/MEM+MEM/WB+PC |
| CSR | 4,127 | 3.69 | 4,127 | 3.69 | csr_regfile + csr_instructions |
| 中断系统 | 1,751 | 1.56 | 1,763 | 1.57 | intc + interrupt_pipeline |
| 执行单元+其他 | 4,574 | 4.09 | 4,579 | 4.09 | ALU+branch+fwd+hazard+decode+WB |
| **core_top 总计** | **27,879** | **24.89** | **36,252** | **32.37** | — |
| SoC 总计（含 RAM+外设） | — | — | — | — | 200,445 µm² (en0) |

**影子寄存器净增**：+8,360 µm² = +7.46 kGE

### 5.3 功耗分解（core_top，200 MHz, 1.2V, TT 25°C）

| 模块 | en0 (mW) | sh1 (mW) | 说明 |
|------|---------|---------|------|
| 寄存器堆 | 1.925 | 3.740 | 影子寄存器增量 +1.815 mW |
| 流水线寄存器 | 1.108 | 1.107 | 几乎不变 |
| CSR | 0.690 | 0.690 | 不变 |
| 中断系统 | 0.284 | 0.289 | +0.005 mW |
| 执行+组合逻辑 | 0.013 | 0.012 | 以漏电为主（无开关活动性标注） |
| **core_top 总计** | **4.020** | **5.838** | — |
| SoC 总计 | 37.595 | 39.413 | data_ram 占 ~85% |

**影子寄存器功耗增量**：+1.818 mW（+45%），几乎全部来自寄存器堆

> ⚠️ 执行单元和组合逻辑功耗以漏电为主（综合时未标注开关活动性 —— Warning: unannotated primary inputs/sequential cell outputs），审稿可能被质疑。

---

## 6. 确定性测试程序

| 测试 | 文件 | 类型 | 周期数 | 40 轮抖动 |
|------|------|------|--------|----------|
| Test 1 | `test1_vvadd.S` | 向量加法 | 143 | 0 |
| Test 2 | `test2_fib.S` | 递归斐波那契 fib(8) | 97 | 0 |
| Test 3 | `test3_matmul.S` | 矩阵乘法 | 23 | 0 |
| Test 4 | `test4_bubble.S` | 冒泡排序（逆序最坏） | 1081 | 0 |
| Test 5 | `test5_lfsr.S` | 32 位 LFSR（CRC-32） | 312 | 0 |
| Test 6 | `test6_forwarding.S` | 前递确定性 | 33 | 0 |
| Test 7 | `test7_branching.S` | 控制流确定性 | 16 | 0 |
| Test 8 | `test8_memdep.S` | 访存确定性 | 41 | 0 |
| Test 9 | `test9_interrupt.S` | 中断+影子寄存器 | ISR=8 | 0 |

全部测试 40 轮运行标准差为零，验证了无缓存、无分支预测微架构的完美时间可重复性。

---

## 7. 中断 ID 与向量地址

| ID | 来源 | 说明 |
|----|------|------|
| 3 | MSI（Software） | 软件中断 |
| 7 | MTI（Timer） | 定时器中断 |
| 11 | MEI（External） | GPIO + SPI + I2C 合并的外部中断 |
| 12 | SPI | 独立 SPI 中断（在 SoC 级合并到 ID=11） |
| 13 | I2C | 独立 I2C 中断（在 SoC 级合并到 ID=11） |

SPI 和 I2C 中断在 SoC 级与 GPIO 合并为一个外部中断信号（ID=11），ISR 需轮询各外设状态寄存器来确认实际中断源。

---

## 8. 中断延迟定义

论文统一采用与 Sophon 一致的定义：

> **从核心接受中断请求（interrupt request accepted by the core）到中断服务程序第一条指令被执行（first instruction of the interrupt handler is executed）所经过的时钟周期数。**

FX-RV32 实测：**2 个时钟周期**（1000 次触发无波动）。

完整往返延迟：2 周期（中断进入）+ 1 周期（影子寄存器保存）→ ISR 执行 → 3 周期（MRET 返回）+ 1 周期（影子寄存器恢复）。

---

## 9. Verilog 编码规范

- 端口命名：`_i`（输入）、`_o`（输出），如 `clk_i`、`rst_n_i`
- 模块实例化：前缀 `u_`，如 `u_alu`、`u_interrupt_pipeline`
- 复位：`rst_n_i` 低电平有效
- 流水线阶段前缀：`if_*`、`id_*`、`ex_*`、`mem_*`、`wb_*`
- NOP 编码：`0x00000013`（addi x0, x0, 0）
- 配置：全部使用 Verilog `parameter`（不用 `` `define ``），唯一可配置参数是 `SHADOW_EN`
- 扩展信号命名：`_for_hazard`（送冒险单元）、`pipe_csr_*`（中断流水线 CSR 更新）、`intr_flush_*`（中断冲刷）、`flush_*`（分支冲刷）

---

## 10. 已知问题

| 问题 | 影响 | 状态 |
|------|------|------|
| Load-Use 停顿未在 ID/EX 插入 NOP | 指令重复执行，FIFO 外设丢数据 | 未修复 |
| UART 不支持 RX | 只能发送不能接收 | 设计决定 |
| UART CTRL 寄存器不可写（bus_arbiter 固定输出 UART_BASE） | 无法软件配置波特率 | 未修复 |
| DC 综合 3 个语法错误 | 无法综合（black box） | 未修复 |
| 不支持中断嵌套（单组影子寄存器） | ISR 内不可再响应中断 | 设计决定，可扩展 |

---

## 11. 论文文件索引

| 文件 | 用途 |
|------|------|
| `bare_jrnl_new_sample4.tex` | 英文 IEEE TVLSI 投稿（LaTeX） |
| `FX-RV32.md` | 中文论文稿件 |
| `FX-RV32_Experimental_Evaluation.md` | 实验评估数据与分析 |
| `论文排版注意事项.md` | LaTeX 排版陷阱与数据源速查 |
| `doc/thesis/latex_revision_log.md` | 论文修改记录 |
| `doc/CCF-A投稿分析.md` | CCF-A 期刊对比分析 |
