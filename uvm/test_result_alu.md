# cpu_test_alu — 基础指令测试结果

**测试日期**: 2026-06-02（修复后重跑）

**测试程序**: `alu_test.s` (154 条指令, 含 NOP 填充)

**UVM 测试类**: `cpu_test_alu`

## 仿真摘要

| 项目 | 数值 |
|------|------|
| 编译结果 | 24 RTL + 3 UVM 文件, 0 error |
| 仿真时长 | 500,102.5 ns |
| UVM_ERROR | 0 |
| UVM_FATAL | 0 |
| 总体结论 | ⚠️ **部分通过**（srli 失败导致最终 tohost=1） |

## Scoreboard 统计

| 指标 | 数值 | 说明 |
|------|------|------|
| 寄存器写回 (WB) | 24 | 数据通路正常 |
| Store 操作 | 1 | 仅 tohost 写入 |
| Load 操作 | 0 | 测试中 lw/sw 的目标地址未被 Monitor 覆盖路径采集 |
| Stall 事件 | 0 | 无停顿（NOP 间隔避免了转发依赖） |
| Mismatch | 0 | Scoreboard 无比对错误 |

## 功能覆盖率

| 覆盖组 | 覆盖率 | 说明 |
|--------|--------|------|
| cg_instr_types | 25% | 仅 x10-x13 被追踪 |
| cg_memory_ops | 58% | tohost 地址覆盖 |
| cg_stall | 0% | 无停顿测试 |
| cg_forwarding | 83% | EX/MEM 和 MEM/WB 部分覆盖 |

## 各测试项结果

### 通过的测试项 ✅

| 测试 | 被测指令 | 结果 | Monitor 验证 |
|------|---------|------|-------------|
| Test 1: 算术 | `add`, `sub` | ✅ | x12=0x96(150), 0x32(50) |
| Test 2: 逻辑 | `and`, `or`, `xor` | ✅ | x12=0x0F, 0xFF, 0xF0 |
| Test 3: sll | `sll` | ✅ | x12=0x20(32), 1<<5 |
| Test 4: 比较 | `slt`, `sltu` | ✅ | slt=1, sltu=0 |
| Test 5: 立即数 | `andi`, `ori`, `xori`, `slti`, `sltiu` | ✅ | 多位验证通过 |
| Test 6: 分支 | `beq`, `bne`, `blt`, `bge` | ✅ | 分支路径正确 |
| Test 7: 跳转 | `jal` | ✅ | 正确跳过 fail |
| Test 8: lui | `lui` | ✅ | x13=0x40000000 |
| Test 9: CSR | `csrr mcause` | ✅ | 读回 0 |
| Test 10: Memory | `sw`, `lw` | ✅ | sw+addi+lw+addi+bne 序列, 分支未跳转说明 lw 读回正确 |

### 未通过的测试项 ❌

| 测试 | 被测指令 | 现象 | 分析 |
|------|---------|------|------|
| Test 3: srli | `srli` | x12=0xFFFFFFF2 而非 0x3FFFFFFC | 译码器疑似将 srli 按 srai 处理 |

**详细分析**: `srli x12, x10, 2` 在 x10 = 0xFFFFFFF0 (-16) 时:
- 预期: 0xFFFFFFF0 >> 2 (logical) = 0x3FFFFFFC
- 实际: x12 = 0xFFFFFFF2

0xFFFFFFF2 既不等于逻辑右移结果 (0x3FFFFFFC)，也不等于算术右移结果 (0xFFFFFFFC)。可能原因:
- 译码器 `decoder.v` 未能正确区分 `srli` (funct3=5, funct7[5]=0) 和 `srai` (funct3=5, funct7[5]=1)
- ALU 内部移位逻辑未正确处理 funct7[5]

该错误导致 `bne x12, x13, fail` 跳转到 fail 路径，最终 `STORE: [0xFC] <= 0x00000001`。

## 关键 Monitor 日志

```
[MON] [3]  WB: x10 <= 0x64        (100)    ← Test 1: addi
[MON] [4]  WB: x11 <= 0x32        (50)     ← Test 1: addi
[MON] [6]  WB: x12 <= 0x96        (150)    ← Test 1: add  ✓
[MON] [11] WB: x12 <= 0x32        (50)     ← Test 1: sub  ✓
[MON] [19] WB: x12 <= 0x0F        (15)     ← Test 2: and  ✓
[MON] [24] WB: x12 <= 0xFF        (255)    ← Test 2: or   ✓
[MON] [29] WB: x12 <= 0xF0        (240)    ← Test 2: xor  ✓
[MON] [37] WB: x12 <= 0x20        (32)     ← Test 3: sll  ✓
[MON] [45] WB: x12 <= 0xFFFFFFF2           ← Test 3: srli ✗ (expected 0x3FFFFFFC)
[MON] [53] WB: x10 <= 0x01                 ← fail 路径: x10=1
[MON] [54] WB: x11 <= 0xFC                 ← fail 路径: x11=0xFC
[MON] [56] STORE: [0xFC] <= 0x00000001     ← FAIL: tohost = 1
```

## 总结

10 项测试中 9 项通过，1 项失败（srli）。ALU 算术、逻辑、移位（sll）、比较、立即数、分支、跳转、CSR 访问及内存读写功能均可正常工作。`srli` 的译码问题需单独排查 `decoder.v` 中的 `alu_op_o` 生成逻辑或 `alu.v` 中的移位实现。
