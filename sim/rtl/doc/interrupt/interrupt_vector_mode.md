# 中断向量模式说明

## 修改记录

| 日期 | 修改内容 |
|------|----------|
| 2026-05-26 | 修复中断跳转地址通路：`ifu_top` 不再直接使用 `mtvec`，改为使用 `interrupt_controller` 计算好的 `intr_handler_addr` |

## 修改背景

`interrupt_controller` 原本已经正确实现了 RISC-V 标准的中断向量计算（`BASE + cause*4`），但 `core_top` 中该信号线（`intr_handler_addr`）声明后被悬空。`ifu_top` 直接使用原始 `mtvec` 值作为中断跳转地址。

Direct 模式（MODE=00）下 `mtvec` 低两位为 0，碰巧正确。切换到 Vectored 模式（MODE=01）后 `mtvec` 低两位为 01，直接做跳转地址是错误的，且 `interrupt_controller` 计算好的向量地址未被使用。

## 修改内容

### `core/ifu/ifu_top.v`

端口 `mtvec_i` 更名为 `intr_target_i`，含义从"中断向量基址寄存器"变为"中断跳转目标地址（已由 interrupt_controller 解析完成）"：

```verilog
// 改前
input  wire [31:0] mtvec_i,
...
assign next_pc = (interrupt_pending_i) ? mtvec_i : ...;

// 改后
input  wire [31:0] intr_target_i,
...
assign next_pc = (interrupt_pending_i) ? intr_target_i : ...;
```

### `core/core_top.v`

`u_ifu_top` 实例化端口连接从 `mtvec_i(mtvec)` 改为 `intr_target_i(intr_handler_addr)`：

```verilog
// 改前
.mtvec_i(mtvec),          // 裸 mtvec，含 MODE 位

// 改后
.intr_target_i(intr_handler_addr),  // 中断控制器算好的目标地址
```

`u_interrupt_controller` 的 `mtvec_i` 端口不变，仍连接 `mtvec`，控制器需要 MODE 位来判断使用哪种模式。

## 中断跳转通路

```
                    csr_regfile
                    ┌──────────┐
                    │  mtvec   │──── mtvec ─────────────────────┐
                    │ (CSR寄存器)│                                │
                    └──────────┘                                │
                                                                │
                    interrupt_controller                        │
                    ┌──────────────────────────┐                │
                    │ mtvec_i   ← mtvec ───────┘ (需要 MODE 位)  │
                    │                                          │
                    │ mtvec_mode == 00 (Direct):               │
                    │   handler = {mtvec[31:2], 2'b0}          │
                    │                                          │
                    │ mtvec_mode == 01 (Vectored):             │
                    │   handler = BASE + (cause[4:0] << 2)     │
                    │                                          │
                    │ intr_handler_addr_o ──→ intr_handler_addr│
                    └──────────────────────────┘               │
                                            │                  │
                                            ▼                  │
                    ifu_top                                    │
                    ┌──────────────────────┐                   │
                    │ intr_target_i  ← interrupt_handler_addr  │
                    │                                          │
                    │ interrupt_pending ?                      │
                    │   intr_target_i    : // 控制器算好的地址   │
                    │   branch_target_i  :                     │
                    │   jump_target_i    :                     │
                    │   pc + 4;                                │
                    │                    │                     │
                    │   ┌────────────┐   │                     │
                    │   │   PC_REG   │   │                     │
                    │   └────────────┘   │                     │
                    └────────────────────┘
```

## 两种模式的使用方法

### Direct 模式 (mtvec.MODE = 00)

所有中断跳转到同一入口地址。ISR 内部通过读取 `mcause` 判断中断源，软件二次分发。

```asm
# 配置
li    t0, isr_entry        # 入口地址 (必须 4 字节对齐)
csrw  mtvec, t0            # MODE=00, BASE=isr_entry

# 中断入口
isr_entry:
    csrr  t0, mcause       # 读中断原因
    srli  t0, t0, 1        # 去掉中断位
    # 按 cause 分支跳转...
```

### Vectored 模式 (mtvec.MODE = 01)

硬件根据中断 cause 自动计算跳转地址：`handler = BASE + cause × 4`。

每个向量 slot 占 4 字节，正好放一条 `j` 指令跳转到真正的 handler：

```asm
# 配置
li    t0, vector_table     # 向量表基址 (必须 4 字节对齐)
ori   t0, t0, 0x01         # MODE=01
csrw  mtvec, t0

# 向量表 (每个 slot 4 字节, 放一条 j 指令)
.section .vectors
.balign 4
vector_table:
    j default_handler       # cause=0  保留
    j default_handler       # cause=1  保留
    j default_handler       # cause=2  保留
    j software_handler      # cause=3  软件中断
    j default_handler       # cause=4  保留
    j default_handler       # cause=5  保留
    j default_handler       # cause=6  保留
    j timer_handler         # cause=7  定时器中断
    j default_handler       # cause=8  保留
    j default_handler       # cause=9  保留
    j default_handler       # cause=10 保留
    j external_handler      # cause=11 外部中断
    j spi_handler           # cause=12 SPI 中断
    j i2c_handler           # cause=13 I2C 中断
```

handler 可以放在任意地址，`j` 指令的跳转范围是 ±1MB，完全够用。

### 中断延迟

两种模式的中断延迟均为 **2 个时钟周期**：

| 周期 | 事件 |
|------|------|
| T0 | 中断信号到达 → `interrupt_controller` 组合逻辑输出 `intr_pending=1` |
| T1 时钟沿 | `interrupt_pipeline` 采样 pending，输出 `interrupt_taken=1` |
| T1（组合） | `ifu_top` 看到 `interrupt_pending=1`，`next_pc = intr_target_i` |
| T2 时钟沿 | PC 寄存器更新，第一条 ISR 指令被取指 |

`intr_handler_addr` 在 `interrupt_controller` 中为组合逻辑输出（`always @(*)`），不跨时钟沿，不增加额外延迟。

## 中断 ID 与向量偏移对照表

| 中断源 | Cause | 向量偏移 (MODE=01) | Slot 地址 |
|--------|-------|-------------------|-----------|
| 软件中断 (MSI) | 3 | `BASE + 0x0C` | 第 3 个 slot |
| 定时器中断 (MTI) | 7 | `BASE + 0x1C` | 第 7 个 slot |
| 外部中断 (MEI) | 11 | `BASE + 0x2C` | 第 11 个 slot |
| SPI 中断 | 12 | `BASE + 0x30` | 第 12 个 slot |
| I2C 中断 | 13 | `BASE + 0x34` | 第 13 个 slot |

## 注意事项

1. **向量表基址必须 4 字节对齐**：`mtvec[1:0]` 被 MODE 位占用，BASE 取自 `mtvec[31:2]`

2. **Direct 模式下 BASE 也必须对齐**：控制器内部 `handler = {mtvec[31:2], 2'b0}` 强制清除低两位

3. **中断只响应一次**：`interrupt_pipeline` 在中断被接受后置位 `interrupt_processed`，阻止重复进入，直到执行 MRET 后清零

4. **Vectored 模式下每个 slot 只能放一条 4 字节指令**：通常是一条 `j`。如果需要更长的向量间距（比如直接放完整 ISR），当前设计不支持，可考虑扩展自定义 CSR 实现 stride 向量（见附录）

## 附录：Stride 向量扩展（预留）

如果将来需要配置向量间距（让每个 slot 放多于 1 条指令），可扩展：

- 新增 CSR `0x7C5`（8-bit）：向量间距配置（以 2^N 字为单位）
- `interrupt_controller` MODE=10 时：`handler = BASE + (cause << stride)`

当前版本不需要此扩展，Vectored 模式下每个 slot 一条 `j` 指令已满足所有使用场景。
