# FX-RV32 RV32I 测试分类与确定性验证

> 日期：2026-06-08 | 作者：Yi Fengxin, Beihang University
> 42 个 RV32I 测试，6 个类别，100% 确定性执行（σ=0.0）

## 1. 分类概览

| 图表 | 类别 | 测试 | 数量 | 周期范围 |
|------|------|------|------|----------|
| 1 | Arithmetic & Logical | add, addi, sub, and, andi, or, ori, xor, xori | 9 | 259–567 |
| 2 | Shift | sll, slli, srl, srli, sra, srai | 6 | 302–591 |
| 3 | Comparison | slt, slti, sltu, sltiu | 4 | 298–538 |
| 4 | Branch & Jump | beq, bne, blt, bltu, bge, bgeu, jal, jalr | 8 | 108–453 |
| 5 | Memory Access | lb, lbu, lh, lhu, lw, sb, sh, sw, ld_st, st_ld | 10 | 317–1161 |
| 6 | Special & Upper Imm | lui, auipc, simple, fence_i, ma_data | 5 | 88–551 |
| **合计** | | | **42** | **88–1161** |

## 2. 各类别说明

### 2.1 Arithmetic & Logical（算术与逻辑运算）

包括 R-type 和 I-type 的 ALU 指令，测试基本的整数运算功能。

| 测试 | 周期数 | 指令类型 | 说明 |
|------|--------|----------|------|
| add | 544 | R-type | 寄存器加法 |
| addi | 303 | I-type | 立即数加法 |
| sub | 536 | R-type | 寄存器减法 |
| and | 564 | R-type | 按位与 |
| andi | 259 | I-type | 立即数按位与 |
| or | 567 | R-type | 按位或 |
| ori | 266 | I-type | 立即数按位或 |
| xor | 566 | R-type | 按位异或 |
| xori | 268 | I-type | 立即数按位异或 |

R-type 指令（add/sub/and/or/xor）周期数较高（536–567），因为测试框架包含多个测试用例和结果检查。I-type 指令（addi/andi/ori/xori）周期数较低（259–303），测试用例较少且多数 ALU 操作可在单周期完成。

### 2.2 Shift（移位运算）

| 测试 | 周期数 | 说明 |
|------|--------|------|
| sll | 572 | 逻辑左移（寄存器移位量） |
| slli | 302 | 逻辑左移（立即数移位量） |
| srl | 585 | 逻辑右移（寄存器移位量） |
| srli | 311 | 逻辑右移（立即数移位量） |
| sra | 591 | 算术右移（寄存器移位量） |
| srai | 317 | 算术右移（立即数移位量） |

移位指令的周期数规律：立即数移位（slli/srli/srai）显著低于寄存器移位（sll/srl/sra），差异约 270 周期。SRA 为最高（591 cycles），测试了符号扩展的正确性。

### 2.3 Comparison（比较运算）

| 测试 | 周期数 | 说明 |
|------|--------|------|
| slt | 538 | 有符号小于（寄存器） |
| slti | 298 | 有符号小于（立即数） |
| sltu | 538 | 无符号小于（寄存器） |
| sltiu | 298 | 无符号小于（立即数） |

比较指令的周期数高度对称：slt = sltu = 538，slti = sltiu = 298，说明有符号/无符号比较在硬件实现上无性能差异。立即数版本比寄存器版本约少 240 周期。

### 2.4 Branch & Jump（分支与跳转）

| 测试 | 周期数 | 说明 |
|------|--------|------|
| beq | 392 | 相等分支 |
| bne | 396 | 不等分支 |
| blt | 392 | 有符号小于分支 |
| bltu | 417 | 无符号小于分支 |
| bge | 428 | 有符号大于等于分支 |
| bgeu | 453 | 无符号大于等于分支 |
| jal | 108 | 跳转并链接 |
| jalr | 188 | 间接跳转并链接 |

JAL 周期数最低（108），因为跳转目标固定，无数据依赖。JALR 需要寄存器间接寻址（188 cycles）。条件分支（beq~bgeu）在 392–453 范围内，BGEU 最高（453），测试了无符号比较 + 分支的组合。

### 2.5 Memory Access（内存访问）

Load 和 Store 合并为一个类别，覆盖全部内存操作。

| 测试 | 周期数 | 说明 |
|------|--------|------|
| lb | 317 | 字节加载（有符号） |
| lbu | 317 | 字节加载（无符号） |
| lh | 333 | 半字加载（有符号） |
| lhu | 342 | 半字加载（无符号） |
| lw | 347 | 字加载 |
| sb | 543 | 字节存储 |
| sh | 596 | 半字存储 |
| sw | 603 | 字存储 |
| st_ld | 532 | Store-Load 交互（写后读） |
| ld_st | 1161 | Load-Store 交互（读后写） |

**特点**：
- Load 指令（lb/lbu/lh/lhu/lw）在 317–347 范围，包含 load-use 停顿
- Store 指令（sb/sh/sw）在 543–603 范围，需要总线写操作
- lb 和 lbu 同周期（317），有符号/无符号字节扩展开销相同
- **ld_st（1161 cycles）是全测试集中周期数最高的**，包含复杂的 load-store 数据依赖

### 2.6 Special & Upper Immediate（特殊与高位立即数）

| 测试 | 周期数 | 说明 |
|------|--------|------|
| simple | 88 | 简单指令序列测试 |
| ma_data | 99 | 内存对齐数据测试 |
| auipc | 111 | AUIPC 地址计算 |
| lui | 114 | LUI 加载高位立即数 |
| fence_i | 551 | FENCE.I 指令同步 |

**simple（88 cycles）是全测试集周期数最低的**，仅测试基本的寄存器-寄存器操作。ma_data（99 cycles）验证内存对齐访问。fence_i（551 cycles）经 UVM inst_rom 镜像修复后通过，测试 self-modifying code 的指令同步。

## 3. 确定性验证方法

每个测试独立仿真 5 次，每次从完全相同的初始状态（rst_n 释放，寄存器全 0，PC=0）开始。5 次 cycle 数完全相同 → σ=0.0 → 确定性。

图表中每条水平线代表一个测试。横轴为执行次数（1–40），实心点标记实际测量的 5 次数据，水平线延伸至第 40 次（表示无论执行多少次，结果始终一致）。**所有 42 条线均为水平**，证明 FX-RV32 为完全确定性 CPU。

## 4. 图表文件

| 文件 | 图表 |
|------|------|
| `doc/figures/chart1_arithmetic_logical.png` | Arithmetic & Logical（9 tests） |
| `doc/figures/chart2_shift.png` | Shift（6 tests） |
| `doc/figures/chart3_comparison.png` | Comparison（4 tests） |
| `doc/figures/chart4_branch_jump.png` | Branch & Jump（8 tests） |
| `doc/figures/chart5_memory.png` | Memory Access（10 tests） |
| `doc/figures/chart6_special_upperimm.png` | Special & Upper Imm（5 tests） |

生成脚本：`scripts/plot_tests.py`

## 5. 测试统计

| 指标 | 值 |
|------|-----|
| 总测试数 | 42 |
| 通过率 | 100%（42/42） |
| σ = 0.0 | 100%（42/42） |
| 确定性 | 100% |
| 最低周期数 | 88（simple） |
| 最高周期数 | 1161（ld_st） |
| 验证次数 | 5 次/测试（210 次仿真） |
| 总失败数 | 0 |
