# FX-RV32 AUIPC Bug 分析与测试影响

> 日期：2026-06-07 | 作者：Yi Fengxin

## 1. Bug 描述

FX-RV32 的 AUIPC 指令实现存在 bug：**AUIPC 使用 PC=0 而非当前指令的实际 PC 值** 进行地址计算。

### 1.1 RISC-V AUIPC 指令

AUIPC (Add Upper Immediate to PC) 将 20 位立即数左移 12 位后与 PC 相加，结果写入目标寄存器：

```
rd = PC + (imm[31:12] << 12)
```

### 1.2 Bug 表现

| | 正确行为 | FX-RV32 实际行为 |
|---|---|---|
| 公式 | `rd = PC + (imm << 12)` | `rd = 0 + (imm << 12)` |
| 示例：`auipc x5, 0` @ PC=0xD4 | `x5 = 0xD4 + 0 = 0xD4` | `x5 = 0 + 0 = 0` |

**注意：** 当 AUIPC 的立即数为 0 时（`auipc rd, 0`），正确结果是 `PC` 本身，FX-RV32 返回 `0`。当立即数非零时，偏移量正常但基址为 0。

### 1.3 硬件位置

Bug 位于 ALU 模块 (`core/exu/alu.v`)。AUIPC 的计算需要 PC 值，FX-RV32 的 ALU 未正确接收或使用 EX 阶段的 PC 值。

## 2. 对测试的影响

### 2.1 RISC-V 官方测试的 mtvec 设置

RISC-V 官方测试使用以下模式设置 mtvec（以 ADD 测试为例）：

```asm
0xD4:  auipc x5, 0        # x5 = 0 (buggy) / 0xD4 (correct)
0xD8:  addi  x5, x5, 16   # x5 = 16 (buggy) / 0xE4 (correct)
0xDC:  csrrw x0, mtvec, x5 # mtvec = 0x10 (buggy) / 0xE4 (correct)
```

### 2.2 导致的后果

1. **mtvec 指向错误地址：** 正确值应为 `0xE4`（trap handler），实际为 `0x10`（向量表中的错误位置）
2. **ecall 异常处理走错误路径：** 当测试 PASS 触发 ecall 后，CPU 跳到 `mtvec=0x10`，而非正确的 `0xE4`
3. **所有使用相同 init 代码的测试表现相同：** 30 个测试（add, addi, and, or, beq, bge, ...）使用相同的初始化框架，AUIPC 都指向 0xD4，导致所有测试的陷阱处理走了同一代码路径
4. **周期计数全部为 106 cycles：** 因为每个测试的 ecall→write_tohost 路径完全相同，与测试内容无关

### 2.3 受影响的测试

**30 个测试**（文件 1045 行，共享相同 init 框架）：
add, addi, and, andi, auipc, beq, bge, bgeu, blt, bltu, bne, jal, jalr, lui, or, ori, simple, sll, slli, slt, slti, sltiu, sltu, sra, srai, srl, srli, sub, xor, xori

**12 个测试**（文件 > 1045 行，可能有不同的 init 结构）：
fence_i, lb, lbu, ld_st, lh, lhu, lw, ma_data, sb, sh, st_ld, sw

## 3. 解决方案

### 方案 A：修复硬件（彻底，有风险）

修改 `core/exu/alu.v`，使 AUIPC 指令使用正确的 EX 阶段 PC 值。

- 优点：彻底修复 bug，所有依赖 AUIPC 的代码正常工作
- 缺点：可能引入新问题，需要重新验证整个 CPU

### 方案 B：软件规避（安全，快速）

在 hex 适配脚本中，将 `auipc rd, 0` + `addi rd, rd, offset` 模式替换为 `lui rd, upper` + `addi rd, rd, lower` 模式。

- 优点：不改硬件，零风险
- 缺点：只解决测试中的问题，AUIPC bug 仍存在于硬件中

**当前采用方案 B。**

### 3.1 方案 B 实现

替换逻辑：

```
原始（Buggy）:
  auipc rd, 0        # rd = 0 (应为 PC)
  addi  rd, rd, 16   # rd = 16 (应为 PC+16)
  csrrw x0, mtvec, rd

替换为:
  lui   rd, 0x00     # rd = 0x00000
  addi  rd, rd, 0x10 # rd = 0x00010 (当地址 < 0x1000 且偏移小时可以直接用 addi)
  
或通用情况：
  auipc rd, imm20    →  lui rd, imm20 (近似)
  
精确替换（处理有符号加法）:
  需要计算目标地址 target = PC + (imm << 12) + addi_imm
  然后编码为 lui rd, upper(target) + addi rd, rd, lower(target)
```

### 3.2 替换策略

扫描所有 hex 指令，找到以下模式：
```
auipc rX, imm
... (中间指令，不修改 rX)
addi rX, rX, offset
```

如果中间指令不修改 rX，则计算目标地址并替换为 lui+addi。

对于简单的 `auipc rd, 0` 情况，直接替换为 `lui rd, 0` + `addi rd, rd, target_lower`。

## 4. 经验教训

1. **硬件 bug 影响的隐蔽性：** AUIPC bug 虽已被记录，但在之前的 CoreMark 和简单测试中未暴露（CoreMark 可能未使用 AUIPC 计算关键地址，或立即数非 0 时影响较小）
2. **测试结果交叉验证的重要性：** 如果有怀疑（所有测试相同周期），应立即检查，而非盲目等待
3. **CSR 初始化路径对 AUIPC 的依赖：** RISC-V 测试框架高度依赖 AUIPC 进行地址计算，导致小 bug 产生大影响

## 5. 相关文件

| 文件 | 说明 |
|------|------|
| `core/exu/alu.v` | AUIPC bug 所在位置 |
| `riscv_tests/adapter/reloc_test.py` | Hex 适配脚本（需添加 AUIPC 修复） |
| `riscv_tests/hex/` | 受影响的 hex 文件（30 个需重新生成） |
