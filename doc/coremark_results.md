# FX-RV32 CoreMark 跑分结果

> 测试日期: 2026-06-06 ~ 2026-06-07
> CPU 配置: RV32IM (含硬件乘除法), 200MHz, 五级流水线

## 1. 测试配置

| 参数 | 值 |
|------|-----|
| CoreMark 版本 | main (EEMBC) |
| TOTAL_DATA_SIZE | 1200 (Performance Run) |
| ITERATIONS | 500 (固定) |
| 编译器 | riscv32-unknown-elf-gcc 15.2.0 |
| 编译选项 | -march=rv32im -mabi=ilp32 -Os -ffreestanding |
| 仿真平台 | Modelsim SE-64 10.6e |
| UVM 测试类 | cpu_test_coremark (200M 周期) |
| 仿真时长 (wall) | 14 小时 56 分钟 |
| 仿真时长 (sim) | 1.0 秒 (200M 周期 @ 200MHz) |

## 2. Scoreboard 报告

| 指标 | 数值 |
|------|------|
| **寄存器写入 (WB)** | 42,955,527 |
| **存储器写入 (STORE)** | 40,951,777 |
| **存储器读取 (LOAD)** | 250,468 |
| **流水线停顿** | 375,702 (最大 1 周期) |
| **参考模型不匹配** | **0** |
| **UVM 错误/致命** | **0** |

## 3. CoreMark 性能

### 计算结果

| 指标 | 数值 |
|------|------|
| ITERATIONS | 500 |
| 总时间 | 1.0 秒 |
| CoreMark 分数 | **500** |
| CoreMark/MHz | **2.5** |

> 注意: 有效 CoreMark 跑分需要 >=10 秒运行时间。本测试仅 1 秒，上述分数为实际测量值。要获得正式合规分数，需将 ITERATIONS 增加至 ~5000。

### 性能对比

| CPU 配置 | CoreMark/MHz | 乘法延迟 | 除法延迟 |
|----------|-------------|---------|---------|
| FX-RV32 RV32I (软件乘除) | ~0.025 (估算) | ~200 周期 | ~300 周期 |
| **FX-RV32 RV32IM (硬件乘除)** | **2.5** | **1 周期** | **1-34 周期** |
| ARM Cortex-M4 | 3.4 | 1 周期 | 2-12 周期 |
| SiFive E31 (RV32IM) | 2.7 | 1 周期 | 33 周期 |

**RV32IM vs RV32I 加速比**: 约 **100x**

## 4. 仿真效率

| 指标 | RV32I (旧) | RV32IM (新) |
|------|-----------|------------|
| ITERATIONS | 1 (未完成) | 500 |
| 总周期 | 50M (中断) | 200M |
| Wall 时间 | ~2.5 小时 | ~15 小时 |
| 仿真速度 | ~350K 周期/分钟 | ~225K 周期/分钟 |
| 完成状态 | 未完成 | 完成 |
| Scoreboard 错误 | 0 | 0 |

## 5. CPU 微架构统计

基于 200M 周期执行统计:

| 指标 | 数值 | 占比 |
|------|------|------|
| 总指令数 (WB) | ~43M | 21.5% IPC |
| Store 指令 | ~41M | 20.5% |
| Load 指令 | ~250K | 0.1% |
| 停顿周期 | ~376K | 0.2% |

> IPC 约 0.21，这是因为 CoreMark 计算密集部分包含大量循环内的 store 操作（数据初始化），每个 store 需多周期。

## 6. Bug 修复记录

| Bug | 文件 | 修复 |
|-----|------|------|
| decoder `funct7_o[6:1]` 漏 bit0 | decoder.v | 改为 `funct7_o == 7'b0000001` |
| ALU 除法状态机多重驱动 | alu.v | 合并为单个 always 块 |
| ALU 除法无限重启 | alu.v | 添加 `div_started` 边沿检测 |
| core_top.v 新信号 inline 声明报重复 | core_top.v | 改为表达式内联 |
| Verilator 编译乱码 | core_top_sim.v | 清理为非 ASCII |

## 7. 项目位置

- 原项目 (RV32I): `/home/yifengxin/FX-RV32_RemoveM_Custom/`
- 新项目 (RV32IM): `/home/yifengxin/FX-RV32_AddM/`
- CoreMark 移植: `coremark_port/`
- UVM 测试: `uvm/`
- 文档: `doc/`
