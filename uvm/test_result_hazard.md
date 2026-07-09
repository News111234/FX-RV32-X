# cpu_test_hazard — Load-Use 冒险测试结果

**测试日期**: 2026-06-02（修复后重跑）

**测试程序**: `load_use_test.s` (33 条指令, 含 NOP 填充)

**UVM 测试类**: `cpu_test_hazard`

## 仿真摘要

| 项目 | 数值 |
|------|------|
| 编译结果 | 24 RTL + 3 UVM 文件, 0 error |
| 仿真时长 | 287.5 ns |
| UVM_ERROR | 0 |
| UVM_FATAL | 0 |
| 总体结论 | ✅ **ALL HAZARD TESTS PASSED** |

## 三项子测试结果

| 测试 | 指令序列 | 实际值 | 预期值 | 结果 |
|------|---------|--------|--------|------|
| Test 1 | `lw x1, 0(x4)` → `add x3, x1, x5` | 0xDEADBEF0 | 0xDEADBEF0 | **PASS** |
| Test 2 | `lw x1, 4(x4)` → `addi x6, x1, 0x100` | 0xCAFEBBBE | 0xCAFEBBBE | **PASS** |
| Test 3 | `lw x1, 0(x4)` → `sw x1, 8(x4)` → `lw x7, 8(x4)` | 0xDEADBEEF | 0xDEADBEEF | **PASS** |

## Scoreboard 统计

| 指标 | 数值 | 说明 |
|------|------|------|
| 寄存器写回 (WB) | 17 | 数据通路正常 |
| Store 操作 | 5 | 初始数据写入 + 三次 tohost 写入 |
| Load 操作 | 7 | 数据读取 + tohost 回读 |
| Stall 事件 | 9 | Load-use 停顿正常工作 |
| 最大停顿周期 | 1 cycle | 符合预期 |
| Mismatch | 0 | 无寄存器/内存比对错误 |

## 功能覆盖率

| 覆盖组 | 覆盖率 | 说明 |
|--------|--------|------|
| cg_instr_types | 75% | 6/8 目标寄存器被覆盖 |
| cg_memory_ops | 100% | load 和 store 均已覆盖 |
| cg_stall | 78% | stall_if/stall_id/d1 全部覆盖 |
| cg_forwarding | 83% | EX/MEM 和 MEM/WB 转发均覆盖 |

## 关键 Monitor 日志

```
[MON] [3]  WB: x10 <= 0xdeadc000        ← lui  x10, 0xDEADC
[MON] [4]  WB: x10 <= 0xdeadbeef        ← addi x10, x10, -0x111  (= 完整 li)
[MON] [8]  STORE: [0x100] <= 0xdeadbeef ← 初始数据写入成功
[MON] [9]  WB: x10 <= 0xcafec000        ← li x10, 0xCAFEBABE (part 1)
[MON] [10] WB: x10 <= 0xcafebabe        ← li x10, 0xCAFEBABE (part 2)
[MON] [13] STORE: [0x104] <= 0xcafebabe ← 初始数据写入成功
[MON] [17] STALL_IF asserted, PC=0x44   ← load-use 停顿 (1 cycle)
[MON] [19] LOAD: [0x100] => 0xdeadbeef  ← Test1: lw 正确读回
[MON] [21] WB: x3  <= 0xdeadbef0        ← Test1: add 结果正确
[MON] [23] STALL_IF asserted, PC=0x58   ← load-use 停顿 (1 cycle)
[MON] [25] LOAD: [0x104] => 0xcafebabe  ← Test2: lw 正确读回
[MON] [27] WB: x6  <= 0xcafebbbe        ← Test2: addi 结果正确
[MON] [29] STALL_IF asserted, PC=0x6c   ← load-use 停顿 (1 cycle)

*** ALL HAZARD TESTS PASSED ***
```
