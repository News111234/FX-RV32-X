# UART 模块设计说明

## 文件结构

| 文件 | 说明 |
|------|------|
| `soc/periph/uart_tx.v` | UART 发送器，实现 8N1 异步串行协议 |
| `soc/periph/uart_ctrl.v` | UART 控制器，含 TX FIFO + 寄存器接口 |

## 硬件架构

```
CPU ──bus_arbiter──> uart_ctrl ──tx_valid/tx_data──> uart_tx ──> TX_PIN
                         │                                 │
                         │<──tx_ready─────────────────────│
                         │                                 │
                      [FIFO]                          (8N1 状态机)
```

- CPU 通过总线写 `TX_DATA` 寄存器，数据进入 `uart_ctrl` 内部的 64 字节 FIFO。
- `uart_ctrl` 检测到 FIFO 非空且 `uart_tx` 空闲时，从 FIFO 取出一字节，发 1 拍脉冲给 `uart_tx`。
- `uart_tx` 锁存数据，按 8N1 协议逐 bit 发出。发送期间 `tx_ready = 0`，完成后 `tx_ready = 1`。
- `uart_ctrl` 看到 `tx_ready` 恢复高电平后，若 FIFO 还有数据则立即启动下一字节。

---

## uart_tx.v — 发送器

标准 UART 8N1（1 起始位 + 8 数据位 + 1 停止位，无校验）发送器。

**状态机**：`IDLE → START → DATA[0..7] → STOP → IDLE`

**握手时序**（发送一个字节 0x48 = 'H' = 0b01001000）：

```
            __      __      __      __      __      __      __      __      __      __      __
clk       _/  \____/  \____/  \____/  \____/  \____/  \____/  \____/  \____/  \____/  \____/  \_
                  ┌────┐                                                                        ┌─
tx_valid  ________|    |________________________________________________________________________|__
                  ──────┐                                                                        ──
tx_data   -------- 0x48 ------------------------------------------------------------------------ 0x00
                        ─┐                                                                        ─┐
tx_ready  ──────────────|_________________________________________________________________________|─
                         ─┐       ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐       ┌─┐
TX_PIN    ───────────────|_______| |_| |_| |_| |_| |_| |_| |_| |_| |_______| |___________________
                           START   0   1   0   0   1   0   0   0   1   STOP
                                  LSB                                 MSB
```

**关键信号**：
- `tx_valid_i`：1 周期脉冲，指示 `tx_data_i` 有效。仅在 `tx_ready_o = 1` 时会被响应。
- `tx_data_i`：要发送的 8 位数据，在 `tx_valid_i = 1` 的周期被锁存。
- `tx_ready_o`：空闲标志。`1` = 可接受新数据，`0` = 正在发送中。

波特率由编译期参数 `CLK_FREQ / BAUD_RATE` 决定。200MHz / 115200 ≈ 1736 个时钟周期/bit。

---

## uart_ctrl.v — 控制器

### 参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `CLK_FREQ` | 200_000_000 | 系统时钟频率 (Hz) |
| `BAUD_RATE` | 115200 | 波特率 |
| `FIFO_DEPTH` | 64 | TX FIFO 深度 |
| `FIFO_ADDR_WIDTH` | 6 | FIFO 地址位宽，须满足 2^N >= FIFO_DEPTH |

**调整 FIFO 深度示例**（如需最长 128 字符的字符串）：

```verilog
// 在 soc_top.v 中修改实例化参数
uart_ctrl #(
    .CLK_FREQ(200_000_000),
    .BAUD_RATE(115200),
    .FIFO_DEPTH(128),
    .FIFO_ADDR_WIDTH(7)     // 2^7 = 128
) u_uart_ctrl (
    ...
);
```

### 寄存器映射

UART 基地址：`0x1000_0000`。

| 偏移 | 寄存器 | 读写 | 说明 |
|------|--------|------|------|
| `0x00` | TX_DATA | W | 写入一字节（bit[7:0]）到发送 FIFO |
| `0x04` | STATUS | R | 发送状态（只读） |
| `0x08` | CTRL | R/W | 控制寄存器 |
| `0x0C` | BAUD_DIV | R/W | 波特率分频系数（保留，实际波特率由编译期参数决定） |

### STATUS 寄存器（偏移 0x04，只读）

```
┌──────────┬──────────────────────────────────────────────────────────────────────────┐
│  bit     │  31  ...  11 │ 10  9  8  7  6  5  4 │  3  │  2  │  1  │  0  │
│  field   │   reserved   │    fifo_count[6:0]   │full │empty│idle │ready│
└──────────┴──────────────────────────────────────────────────────────────────────────┘
```

| 位 | 名称 | 说明 |
|----|------|------|
| `[0]` | **wr_ready** | FIFO 未满，CPU 可写入下一字节。这是发送前必须检查的位。 |
| `[1]` | **tx_idle** | 发送器完全空闲。`1` = FIFO 空且 uart_tx 无正在发送的数据。 |
| `[2]` | fifo_empty | FIFO 为空（无排队数据）。 |
| `[3]` | fifo_full | FIFO 已满（64 字节全部排队）。 |
| `[10:4]` | fifo_count | FIFO 中当前排队的字节数 (0-64)。 |

常用检查模式：
- 写之前：读 STATUS，看 `bit[0]` 是否为 1（FIFO 有空位）。
- 确认发送完成：读 STATUS，看 `bit[1]` 是否为 1（全部发完）。

### CTRL 寄存器（偏移 0x08，读写）

| 位 | 名称 | 默认值 | 说明 |
|----|------|--------|------|
| `[0]` | tx_enable | 1 | 发送使能。`0` = 禁止发送（FIFO 不接受写入且不向外发送）。 |
| `[1]` | irq_enable | 0 | 中断使能（预留，当前未使用）。 |

---

## 使用指南

### 1. 复位后的默认状态

CPU 复位后，UART 模块处于以下初始状态：

- `tx_enable = 1`（发送已使能，无需额外配置即可使用）
- FIFO 为空（`fifo_count = 0`，`fifo_empty = 1`，`fifo_full = 0`）
- `uart_tx` 空闲（`tx_ready = 1`），TX 引脚保持高电平
- STATUS 寄存器读出值为 `0x0000_0007`（bit[0]=1 可写，bit[1]=1 空闲，bit[2]=1 FIFO空）

**最简单的使用场景**：复位后直接写 TX_DATA 即可开始发送，无需任何初始化代码。

### 2. 发送一个字节（最简示例）

```asm
# UART 基地址 = 0x10000000
# 发送单个字符 'H' (0x48)

    li   t0, 0x10000000        # t0 = UART 基地址

wait_ready:
    lw   t1, 4(t0)             # 读 STATUS (偏移 0x04)
    andi t1, t1, 1             # 取 bit[0]: wr_ready
    beqz t1, wait_ready        # 如果 FIFO 没空位，继续等待

    li   t2, 0x48              # 字符 'H'
    sw   t2, 0(t0)             # 写 TX_DATA (偏移 0x00)，数据进入 FIFO
```

执行完这段代码后，'H' 已进入 FIFO，`uart_ctrl` 会自动将其发送出去。不需要等待发送完成即可继续执行其他代码。

### 3. 发送一个字符串

```asm
# 发送字符串 "Hello, World!\n" (14 个字符)
# 字符串数据放在 .data 段

    .section .data
msg:
    .ascii "Hello, World!\n"
msg_end:

    .section .text
    .globl _start
_start:
    li   t0, 0x10000000        # t0 = UART 基地址
    la   t3, msg               # t3 = 字符串起始地址
    la   t4, msg_end           # t4 = 字符串结束地址

send_loop:
    # 1. 等待 FIFO 有空位
wait_fifo:
    lw   t1, 4(t0)             # 读 STATUS
    andi t1, t1, 1             # bit[0]: wr_ready
    beqz t1, wait_fifo

    # 2. 取下一个字符
    lbu  t2, 0(t3)             # 从内存加载一个字节
    addi t3, t3, 1             # 指针后移

    # 3. 写入 FIFO
    sw   t2, 0(t0)             # 写 TX_DATA

    # 4. 判断是否发完
    bltu t3, t4, send_loop     # 还没到末尾，继续

    # 5. 等待全部发送完成（可选）
wait_done:
    lw   t1, 4(t0)             # 读 STATUS
    andi t1, t1, 2             # bit[1]: tx_idle
    beqz t1, wait_done         # 没发完就等

    # 发送完成，继续后续代码...
```

### 4. 禁用和重新启用发送

如果需要在运行中暂停 UART 发送（例如做系统配置），可以操作 CTRL 寄存器：

```asm
# 暂停 UART 发送
    li   t0, 0x10000000
    sw   x0, 8(t0)             # 写 CTRL=0，bit[0]=0 禁用发送

# ... 做一些其他操作 ...

# 重新启用
    li   t1, 1
    sw   t1, 8(t0)             # 写 CTRL=1，bit[0]=1 重新启用
```

禁用后：
- `wr_ready` 变为 0，CPU 无法写入新数据。
- 已在 FIFO 中的数据**不会**被丢弃，但也不会被发送（控制器停在 IDLE）。
- 重新启用后，FIFO 中的数据会自动开始发送。

> **注意**：CTRL 寄存器的写入依赖 `bus_arbiter` 传递正确的偏移地址。当前版本 `bus_arbiter` 固定将地址设为 `UART_BASE`，因此 CTRL 写入实际上不生效。这是待修复的已知限制（见下文）。

### 5. 配合 C 语言使用

```c
#define UART_BASE 0x10000000
#define UART_TXDATA  (*(volatile unsigned int *)(UART_BASE + 0x00))
#define UART_STATUS  (*(volatile unsigned int *)(UART_BASE + 0x04))

// 发送一个字符
void uart_putc(char c) {
    while (!(UART_STATUS & 1));   // 等待 bit[0] wr_ready
    UART_TXDATA = c;
}

// 发送一个字符串
void uart_puts(const char *s) {
    while (*s) {
        uart_putc(*s++);
    }
    while (!(UART_STATUS & 2));   // 等待 bit[1] tx_idle
}
```

### 6. 发送流程时序说明

以下从 CPU 视角展示发送 "Hi" 两个字符的完整流程：

```
时间 →

CPU:  写'H'到 TX_DATA ─┐
                       │ (1周期后，'H'进入FIFO)
STATUS:  fifo_count=1 ─┤
         wr_ready=1 ───┤ (FIFO还有63个空位)
                       │
         uart_tx 取走'H'，开始发送 ──┤ (发送约87μs @115200)
         fifo_count=0 ──────────────┤
                                     │
CPU:  写'i'到 TX_DATA ──────────────┤
                                     │
STATUS:  fifo_count=1 ──────────────┤
         wr_ready=1 ────────────────┤
                                     │
         'H'发送完成 ───────────────┤
         uart_tx 立即取走'i' ───────┤ (背靠背，中间仅1周期间隙)
         fifo_count=0 ──────────────┤
                                     │
         'i'发送完成 ─────────────────────────┤
         tx_idle=1 ───────────────────────────┤ (全部完成)
```

关键点：字符间仅间隔 1 个时钟周期（5ns @ 200MHz），远远小于 1 个 bit 时间（约 8.7μs），对接收端完全不可见。

---

## 状态机详解

```
                         +------------------+
                         |                  |
          !fifo_empty && |   ST_IDLE        |
          tx_ready       |   等待数据        |
          +-------------->                  |
          |               +--------+--------+
          |                        ^
          |                        | tx_ready &&
          |                        | fifo_empty
          |               +--------+--------+
          |               |                  |
          +-------------->   ST_SENDING     |
          tx_ready &&     |   等待发送完成    |
          !fifo_empty     |                  |
                          +------------------+
```

- **ST_IDLE**：
  - `tx_valid = 0`
  - 每个时钟周期检查三个条件：FIFO 非空、`tx_ready = 1`、`tx_enable = 1`。
  - 三个条件同时满足时：读 `fifo_mem[rd_ptr]` → `tx_data_reg`，拉高 `tx_valid` 一拍，读指针 +1，FIFO 计数 -1，进入 `ST_SENDING`。

- **ST_SENDING**：
  - `tx_valid = 0`（确保给 uart_tx 的是单周期脉冲）
  - 等待 `tx_ready` 回到 1（表示 uart_tx 发送完成）。
  - `tx_ready = 1` 时：
    - 若 FIFO 非空且 `tx_enable = 1`：立即取下一字节，拉高 `tx_valid` 一拍，**保持在 ST_SENDING**。
    - 若 FIFO 为空或 `tx_enable = 0`：回到 `ST_IDLE`。

---

## 与 bus_arbiter 的握手机制

`bus_arbiter` 是 CPU 和 UART 之间的桥梁。当 CPU 写 UART 地址（0x1000_0000）时，arbiter 的处理流程：

```
CPU 执行 sw 指令写 UART
        │
        v
bus_arbiter 收到写请求
        │
        ├── uart_we_o 锁存为 1  ──> uart_ctrl.we_i = 1  (第1拍)
        │
uart_ctrl: we_rising 检测到上升沿 ──> 数据写入 FIFO
        │   rdata_o[0] = !fifo_full ──> 返回给 arbiter
        │
bus_arbiter 看到 rdata_o[0] = 1  ──> uart_we_o 锁存清零  (第2拍)
        │
        └── CPU 写事务完成
```

关键设计点：
- arbiter 用 `rdata_o[0]`（wr_ready）作为释放锁存的握手信号。
- uart_ctrl 用 `we_i` 的**上升沿**检测，确保每个 CPU 写事务只向 FIFO 写入一次（即使 we_i 维持多拍）。
- 若 FIFO 已满，`rdata_o[0] = 0`，arbiter 等待 5 周期后超时释放，本次写入丢失。CPU 应提前检查 STATUS 避免此情况。

---

## 已知限制

1. **CTRL 寄存器不可写**：`bus_arbiter` 固定将 `uart_addr_o` 设为 `UART_BASE`（0x10000000），不传递 CPU 发出的偏移地址。因此 CTRL（偏移 8）和 BAUD_DIV（偏移 C）目前无法通过软件写入。`tx_enable` 默认值为 1，对正常使用无影响。

2. **波特率不可运行时修改**：`baud_divider` 寄存器不连接实际硬件。修改波特率需同时修改 `uart_ctrl` 和 `uart_tx` 的实例化参数并重新综合。

3. **无接收（RX）功能**：当前仅实现了 UART 发送端。
