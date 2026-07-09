# cpu_test_interrupt — 中断测试结果

**测试日期**: 2026-06-02（修复后重跑）

**测试程序**: `intr_test.s` (40 条指令)

**硬件配置**: `SHADOW_EN = 1` (id_top.v + interrupt_pipeline.v)

**UVM 测试类**: `cpu_test_interrupt`

## 仿真摘要

| 项目 | 数值 |
|------|------|
| 编译结果 | 24 RTL + 3 UVM 文件, 0 error |
| 仿真时长 | 260,107.5 ns |
| UVM_ERROR | 0 |
| UVM_FATAL | 0 |
| 总体结论 | ✅ **INTERRUPT TEST PASSED** |

## Scoreboard 统计

| 指标 | 数值 | 说明 |
|------|------|------|
| 寄存器写回 (WB) | 684 | 含轮询循环的大量写回 |
| Store 操作 | 3 | 清零标志 + ISR 置标志 + tohost 写入 |
| Load 操作 | 664 | 主循环轮询读取 [0x200] |
| Stall 事件 | 999 | Load-use 停顿（轮询循环产生） |
| 最大停顿周期 | 1 cycle | 符合预期 |
| Mismatch | 0 | 无寄存器/内存比对错误 |

## 功能覆盖率

| 覆盖组 | 覆盖率 | 说明 |
|--------|--------|------|
| cg_instr_types | 75% | 6/8 目标寄存器被覆盖 |
| cg_memory_ops | 83% | load 和 store 均已大量覆盖 |
| cg_stall | 78% | stall_if/stall_id/d1 全部覆盖 |
| cg_forwarding | 83% | EX/MEM 和 MEM/WB 转发均覆盖 |

## 测试流程验证

| 阶段 | Monitor 日志 | 状态 |
|------|-------------|------|
| 初始化 | `WB: x1..x5 <= 0xA1..0xA5` | ✅ |
| 清零标志 | `STORE: [0x200] <= 0x00000000` | ✅ |
| 中断向量 | `x6 <= 0x78` → `csrw mtvec, x6` | ✅ |
| 中断使能 | `x7 <= 0x80` (mie), `x8 <= 0x8` (mstatus) | ✅ |
| 等待中断 | `LOAD: [0x200] => 0x00000000` (轮询) | ✅ |
| 中断注入 | `Injecting timer interrupt pulse` @ ~2020 周期 | ✅ |
| ISR 写入标志 | `STORE: [0x200] <= 0x00000001` | ✅ |
| 主循环检测 | `LOAD: [0x200] => 0x00000001` | ✅ |
| 寄存器恢复 | 检查 x1..x5 == 0xA1..0xA5 | ✅ |
| 写入 tohost | `STORE: [0xFC] <= 0x00000000` (PASS) | ✅ |

## 关键 Monitor 日志

```
[MON] [8]    STORE: [0x200] <= 0x00000000     ← 清零中断标志
[MON] [16]   LOAD:  [0x200] => 0x00000000     ← 等待中断...
[MON] [2012] STORE: [0x200] <= 0x00000001     ← ISR 置标志 (中断已发生!)
[MON] [2016] LOAD:  [0x200] => 0x00000001     ← 主循环检测到中断
[MON] [2031] STORE: [0xFC]   <= 0x00000000     ← PASS: tohost = 0

*** INTERRUPT TEST PASSED — shadow registers correctly restored ***
```

## 验证结论

- ✅ 中断向量跳转正确（mtvec → ISR 入口 0x78）
- ✅ 定时器中断注入和响应正常（2 周期恒定延迟）
- ✅ 影子寄存器保存/恢复正常（x1-x5 在 MRET 后恢复为原始值 0xA1-0xA5）
- ✅ ISR→主循环内存通信机制正常（[0x200] 标志位）
- ✅ Store/load 数据通路正常
