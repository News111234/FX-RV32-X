# Bootloader + UART/SPI Flash 程序加载方案

> 替代"每次修改 inst_rom initial 块 → 综合 → 实现 → 烧录"的 FPGA 测试流程
> 目标平台：Genesys 2 (XC7K325T + S25FL256S 256Mbit QSPI Flash)

## 1. 问题与目标

### 1.1 当前痛点

目前 FX-RV32 的 FPGA 测试流程：

```
修改 inst_rom.v 的 initial 块 → Vivado 综合(10+ min) → 实现(10+ min) → 生成比特流 → 烧录 FPGA
```

每换一个测试程序就要重走整个 FPGA 工具链，耗时 20 分钟以上。

### 1.2 解决目标

- **一次综合，多次加载**：inst_rom 中固化一个 bootloader（只综合一次），之后换程序不用重综合
- **秒级切换**：通过 UART 把新程序从 PC 发送到 FPGA，bootloader 写入指令 RAM 后跳转执行
- **硬件改动最小**：不修改 CPU 核心，仅改 SoC 层

---

## 2. 核心架构

### 2.1 为什么不能直接从 data_ram 执行

FX-RV32 是哈佛架构：

```
CPU IF 端口 ──→ inst_rom (只读, 取指)
CPU MEM 端口 ──→ bus_arbiter ──→ data_ram + 外设
```

两条路径物理分离。CPU 不能从 data_ram 取指，也不能向 inst_rom 写数据。所以需要 **让指令存储器具备总线可写能力**。

### 2.2 方案：双端口指令 BRAM + UART + SPI Flash 混合加载

```
┌─────────────────────────────────────────────────────────────────┐
│  FPGA (Genesys 2)                                                │
│                                                                  │
│  ┌───────────┐      ┌──────────────────────┐                    │
│  │ CPU Core  │ ────>│ inst_bram (32KB)     │                    │
│  │ IF port   │      │ Port A: 取指(只读)    │                    │
│  │           │      │ Port B: 总线读写       │<──┐               │
│  │ MEM port  │ ──┐  └──────────────────────┘   │               │
│  └───────────┘   │                              │               │
│                  │  ┌──────────────────────┐    │               │
│                  ├─>│ bus_arbiter           │    │               │
│                  │  │ 0x0000_0000: data_ram │    │               │
│                  │  │ 0x1000_0000: UART     │    │               │
│                  │  │ 0x1000_1000: GPIO     │    │               │
│                  │  │ 0x1000_3000: SPI      │────┤──────────┐    │
│                  │  │ 0x2000_0000: inst_bram│────┘          │    │
│                  │  └──────────────────────┘               │    │
│                  │                                         │    │
│  ┌───────────┐   │     ┌─────────────────────────┐        │    │
│  │ UART TX   │<──┘     │ S25FL256S QSPI Flash    │        │    │
│  │ UART RX   │──> pin  │ 256Mbit (32MB)          │        │    │
│  └───────────┘         │ CS/SCK/MOSI/MISO        │<───────┘    │
│                        └─────────────────────────┘             │
│  UART_RX <─── PC 串口 (USB转TTL, 开发调试用)                   │
└─────────────────────────────────────────────────────────────────┘
```

**核心改动**：
1. `inst_rom.v` → `inst_bram.v`：真双端口 BRAM，Port A 给 CPU 取指，Port B 接总线供 bootloader 写入
2. UART 新增 RX 功能，bootloader 通过 UART 接收程序（开发调试）
3. SPI 控制器驱动板载 S25FL256S Flash，bootloader 可从 Flash 读程序（独立运行）
4. bus_arbiter 新增 inst_bram 地址映射 `0x2000_0000`

**不动 CPU 核心**（core_top 及以下所有模块不变）。

---

## 3. 地址映射

### 3.1 新增地址空间

| 地址范围 | 设备 | 方向 | 说明 |
|----------|------|------|------|
| `0x0000_0000 - 0x0000_7FFF` | inst_bram (取指) | CPU IF 直读 | 与原 inst_rom 一致 |
| `0x0000_0000 - 0x0000_FFFF` | data_ram | 数据读写 | 不变 |
| `0x1000_0000 - 0x1000_0FFF` | UART | 读写 | 新增 RX 寄存器 |
| `0x1000_1000 - 0x1000_1FFF` | GPIO | 读写 | 不变 |
| `0x1000_2000 - 0x1000_2FFF` | Timer | 读写 | 不变 |
| `0x1000_3000 - 0x1000_3FFF` | SPI | 读写 | 不变 |
| `0x1000_4000 - 0x1000_4FFF` | I2C | 读写 | 不变 |
| **`0x2000_0000 - 0x2000_7FFF`** | **inst_bram (总线窗口)** | **读写** | **新增：bootloader 写指令** |

### 3.2 inst_bram 内部布局

```
inst_bram 内部 (32KB = 8192 × 32-bit)
┌──────────────────────────────────────┐
│ 0x000 - 0x1FF (512 words = 2KB)     │ ← Bootloader (固化在 initial 块)
├──────────────────────────────────────┤
│ 0x200 - 0x1FFF (7680 words = 30KB)  │ ← 用户程序区 (bootloader 加载目标)
└──────────────────────────────────────┘

CPU 取指地址 = inst_bram 内部地址 (直接映射)
总线写地址 0x2000_0200 → inst_bram 内部地址 0x200
```

Bootloader 加载用户程序到 `0x200` 起始位置后，跳转到 `0x0000_0200`（即 `jal x0, 0x200`），CPU 从该地址取指执行。

---

## 4. 各模块详细设计

### 4.1 inst_bram.v（新建）

替换 `inst_rom.v`。真双端口 BRAM，让 Vivado 能推断为 Block RAM。

```verilog
// soc/mem/inst_bram.v
// 真双端口 Block RAM — 同时支持 CPU 取指和总线写入
// Port A: CPU 取指 (只读, 同步读)
// Port B: 总线接口 (读写, 同步读) — bootloader 通过此端口写程序

module inst_bram #(
    parameter INST_DEPTH = 8192    // 8192 × 32-bit = 32KB
) (
    // ===== Port A: CPU 取指 =====
    input  wire        clk_i,
    input  wire [31:0] if_addr_i,       // CPU 的 if_pc
    output reg  [31:0] if_instr_o,      // 送到 CPU 的指令

    // ===== Port B: 总线接口 =====
    input  wire        bus_we_i,        // 写使能
    input  wire        bus_re_i,        // 读使能
    input  wire [31:0] bus_addr_i,      // 总线地址
    input  wire [31:0] bus_wdata_i,     // 写数据
    output reg  [31:0] bus_rdata_o,     // 读数据
    output wire        bus_ready_o
);

    (* ram_style = "block" *) reg [31:0] mem [0:INST_DEPTH-1];
    
    // 初始化: bootloader 固化在低地址
    initial begin
        // ... bootloader 机器码 ...
    end
    
    // Port A: 取指 (同步读)
    always @(posedge clk_i) begin
        if (if_addr_i[31:2] < INST_DEPTH)
            if_instr_o <= mem[if_addr_i[31:2]];
        else
            if_instr_o <= 32'h00000013;  // NOP
    end
    
    // Port B: 总线读写 (同步读)
    always @(posedge clk_i) begin
        if (bus_we_i && (bus_addr_i[31:2] < INST_DEPTH))
            mem[bus_addr_i[31:2]] <= bus_wdata_i;
    end
    
    always @(posedge clk_i) begin
        if (bus_re_i && (bus_addr_i[31:2] < INST_DEPTH))
            bus_rdata_o <= mem[bus_addr_i[31:2]];
        else
            bus_rdata_o <= 32'h0;
    end
    
    assign bus_ready_o = 1'b1;

endmodule
```

**关键设计要点**：

- **同步读**（`always @(posedge clk_i)`）：Port A 和 Port B 都用同步读，满足 Vivado BRAM 推断要求
- **`(* ram_style = "block" *)`**：显式告诉 Vivado 用 Block RAM
- **无需 `DONT_TOUCH`**：与原 inst_rom 不同，去掉 `(* DONT_TOUCH = "true" *)` 让 Vivado 自由优化
- **Port A 不做写**：CPU 取指端口只读，确保指令不会被错误修改
- **Bootloader 固化在 initial 块**：与原来一样的方式预置 bootloader 机器码

**BRAM 资源估算**（32KB 真双端口）：
- Kintex-7 BRAM tile: 36 Kb = 4.5 KB
- 32KB × 2 ports → 需要额外 BRAM tile 支持双端口
- 32 KB / 4.5 KB ≈ 8 个 BRAM36 tile (双端口模式)

### 4.2 UART RX 模块（新建）

目前 UART 只有 TX。需要新增一个简单的 RX 模块。

```verilog
// soc/periph/uart_rx.v
// UART 接收模块 — 115200 bps, 8N1
// 过采样: 16× 波特率 (200MHz / 115200 ≈ 1736 → 实际采样计数器 ÷ 108)

module uart_rx #(
    parameter CLK_FREQ   = 200_000_000,
    parameter BAUD_RATE  = 115200
) (
    input  wire        clk_i,
    input  wire        rst_n_i,
    input  wire        rx_pin_i,         // UART RX 引脚
    output wire [7:0]  rx_data_o,        // 接收到的字节
    output wire        rx_valid_o        // 接收完成脉冲 (1 周期)
);
    // 状态机: IDLE → START → DATA[0..7] → STOP → IDLE
    // 16× 过采样, 在每位中间点采样
    // ...
endmodule
```

**集成到 uart_ctrl**：
- 在 `uart_ctrl.v` 中实例化 `uart_rx`
- 新增寄存器 `RX_DATA`（偏移 `0x10`，只读）
- STATUS 寄存器新增 bit2 = `rx_ready`（有数据可读）

**UART 寄存器扩展**：

| 偏移 | 寄存器 | 位 | 说明 |
|------|--------|-----|------|
| 0x00 | CTRL | [0] TX enable, [1] RX enable | 新增 RX enable |
| 0x04 | STATUS | [0] tx_ready, [2] rx_ready | 新增 rx_ready |
| 0x08 | TX_DATA | [7:0] | 不变 |
| **0x10** | **RX_DATA** | **[7:0]** | **新增：接收数据（只读）** |

### 4.3 bus_arbiter 修改

新增 inst_bram 的地址译码和路由。

```verilog
// 新增地址空间
localparam INST_BRAM_BASE = 32'h2000_0000;
localparam INST_BRAM_SIZE = 32'h0000_8000;  // 32KB

wire is_inst_bram = (mem_addr_i >= INST_BRAM_BASE) && 
                    (mem_addr_i < INST_BRAM_BASE + INST_BRAM_SIZE);

// 新增 inst_bram 接口信号
output wire        inst_bram_we_o,
output wire        inst_bram_re_o,
output wire [31:0] inst_bram_addr_o,
output wire [31:0] inst_bram_wdata_o,
input  wire [31:0] inst_bram_rdata_i,
input  wire        inst_bram_ready_i,

// 组合逻辑路由
assign inst_bram_we_o   = mem_we_i && is_inst_bram;
assign inst_bram_re_o   = mem_re_i && is_inst_bram;
assign inst_bram_addr_o = mem_addr_i - INST_BRAM_BASE;  // 去偏移
assign inst_bram_wdata_o = mem_wdata_i;

// 读数据多路选择 (在 mem_rdata_o 的 always @(*) 中增加)
if (is_inst_bram)
    mem_rdata_o = inst_bram_rdata_i;

// ready 信号
assign mem_ready_o = is_ram ? ram_ready_i : 
                     is_inst_bram ? inst_bram_ready_i : 1'b1;
```

### 4.4 soc_top 修改

```verilog
// 替换 inst_rom 为 inst_bram
inst_bram u_inst_bram (
    .clk_i        (clk_i),
    .if_addr_i    (core_if_pc),
    .if_instr_o   (core_if_instr),
    .bus_we_i     (bus_inst_bram_we),
    .bus_re_i     (bus_inst_bram_re),
    .bus_addr_i   (bus_inst_bram_addr),
    .bus_wdata_i  (bus_inst_bram_wdata),
    .bus_rdata_o  (bus_inst_bram_rdata),
    .bus_ready_o  (bus_inst_bram_ready)
);
```

---

## 5. Bootloader 程序设计

### 5.1 混合启动流程（UART + SPI Flash）

```
上电/复位
    │
    ▼
初始化 SPI (模式0, 10MHz, 8-bit)
初始化 UART (使能 RX)
    │
    ▼
检查 UART RX 是否有字节等待 (超时 ~100ms)
    │
    ├── 有 ──→ UART 加载模式 (开发调试)
    │           │
    │           ├─ 接收程序
    │           ├─ 写入 inst_bram
    │           ├─ 可选: 同步写入 SPI Flash
    │           └─ 跳转执行
    │
    └── 无 ──→ SPI Flash 加载模式 (独立运行)
                │
                ├─ 读 Flash 固定偏移, 检查 magic number
                │   ├─ 有效 → 从 Flash 加载到 inst_bram
                │   └─ 无效 → LED 闪烁等待 UART
                └─ 跳转执行
```

### 5.2 SPI Flash 加载流程

```
SPI Flash 加载模式
    │
    ▼
发送 READ 命令 (0x03), 地址 = FLASH_PROG_OFFSET
    │
    ▼
读 4 字节 → 检查 Magic Number (0x46585256 = "FXRV")
    ├─ 不匹配 → LED 快闪, 等待 UART
    └─ 匹配
        │
        ▼
    读 4 字节 → 程序大小 (word 数)
        │
        ▼
    ┌─────────────────────┐
    │ 循环:               │
    │  SPI 读 4 字节       │
    │  拼成 32-bit word    │
    │  sw 写入 inst_bram   │  ← 总线地址 0x2000_0200+N*4
    │  直到读完全部 word    │
    └─────────────────────┘
        │
        ▼
    FENCE.I → jal x0, 0x200
```

### 5.3 通信协议

**UART 协议**（PC → FPGA）：

```
Byte 0: size[31:24]   ─┐
Byte 1: size[23:16]    ├─ 程序大小 (big-endian, 单位: word)
Byte 2: size[15:8]     │
Byte 3: size[7:0]     ─┘
Byte 4: instr[0][31:24] ─┐
Byte 5: instr[0][23:16]  ├─ 第 1 条指令
Byte 6: instr[0][15:8]   │
Byte 7: instr[0][7:0]   ─┘
... (每条指令 4 字节)
```

**SPI Flash 数据格式**（存储在 Flash 固定偏移处）：

```
偏移    大小     内容
0x00    4 bytes  Magic Number: 0x46585256 ("FXRV")
0x04    4 bytes  Program Size (word count, big-endian)
0x08    N×4      Program data (每条指令 4 字节, big-endian)
```

### 5.4 RISC-V 汇编伪代码（混合 bootloader）

```asm
# bootloader.s — UART + SPI Flash 混合加载器
# 占 inst_bram 0x000-0x1FF

.equ UART_BASE,     0x10000000
.equ UART_STATUS,   0x10000004
.equ UART_RX_DATA,  0x10000010
.equ SPI_BASE,      0x10003000
.equ INST_BRAM,     0x20000200      # inst_bram 总线窗口 + 0x200 偏移
.equ FLASH_OFFSET,  0x00400000      # SPI Flash 程序存储偏移 (4MB)
.equ MAGIC_NUM,     0x46585256      # "FXRV"

_start:
    # 1. 初始化 SPI (模式0, clk_div=9 → 10MHz)
    lui  x1, 0x10003
    li   x2, 9
    sw   x2, 4(x1)          # CLK_DIV = 9
    li   x2, 0x01
    sw   x2, 0(x1)          # CTRL: enable=1, mode0

    # 2. 初始化 UART RX
    lui  x1, 0x10000
    lw   x2, 0(x1)
    ori  x2, x2, 2           # bit1 = RX enable
    sw   x2, 0(x1)

    # 3. 检测 UART 是否有数据 (轮询 ~100ms)
    li   x3, 0
    li   x4, 2000000          # 超时计数 (约 100ms @ 200MHz)
uart_poll:
    lw   x5, 4(x1)           # UART STATUS
    andi x5, x5, 4            # bit2: rx_ready
    bne  x5, x0, uart_mode    # 有数据 → UART 加载
    addi x3, x3, 1
    blt  x3, x4, uart_poll
    j    flash_mode           # 超时 → Flash 加载

# ────────── UART 加载模式 ──────────
uart_mode:
    # (同之前 UART 流程: 收大小 → 循环收指令 → sw 写 inst_bram)
    # ...
    j    done

# ────────── SPI Flash 加载模式 ──────────
flash_mode:
    # 1. 发送 READ 命令 + 地址
    lui  x5, 0x10003
    li   x6, 0x03             # SPI Flash READ command
    jal  ra, spi_tx_byte      # 发命令

    # 发送 24-bit 地址 (FLASH_OFFSET = 0x400000)
    lui  x8, 0x40             # 地址高 8 位
    srli x6, x8, 16
    jal  ra, spi_tx_byte
    srli x6, x8, 8
    jal  ra, spi_tx_byte
    andi x6, x8, 0xFF
    jal  ra, spi_tx_byte

    # 2. 读并检查 Magic Number
    jal  ra, spi_rx_byte
    slli x9, x10, 24          # byte0
    jal  ra, spi_rx_byte
    slli x11, x10, 16
    or   x9, x9, x11          # byte1
    jal  ra, spi_rx_byte
    slli x11, x10, 8
    or   x9, x9, x11          # byte2
    jal  ra, spi_rx_byte
    or   x9, x9, x10          # byte3
    li   x12, 0x46585256
    bne  x9, x12, no_program  # Magic 不匹配

    # 3. 读程序大小
    jal  ra, spi_rx_byte; slli x13, x10, 24
    jal  ra, spi_rx_byte; slli x14, x10, 16; or x13, x13, x14
    jal  ra, spi_rx_byte; slli x14, x10, 8;  or x13, x13, x14
    jal  ra, spi_rx_byte; or   x13, x13, x10   # x13 = word count

    # 4. 循环加载
    li   x14, 0               # 已读 word 计数
    lui  x15, 0x20000
    addi x15, x15, 0x200      # inst_bram 目标地址
flash_load_loop:
    beq  x14, x13, done
    # 读 4 字节拼成 word
    jal  ra, spi_rx_byte; slli x16, x10, 24
    jal  ra, spi_rx_byte; slli x17, x10, 16; or x16, x16, x17
    jal  ra, spi_rx_byte; slli x17, x10, 8;  or x16, x16, x17
    jal  ra, spi_rx_byte; or   x16, x16, x10
    sw   x16, 0(x15)          # 写入 inst_bram
    addi x15, x15, 4
    addi x14, x14, 1
    j    flash_load_loop

no_program:
    # Flash 无程序 → LED 快闪等待 UART (或死循环等待复位)
    j    uart_mode

done:
    fence.i
    jal  x0, 0x200

# ──────── SPI 子程序 ────────
spi_tx_byte:   # 发送 x6[7:0], 轮询 tx_ready
    # 写 DATA → 置 start_tx=1 → 等 STATUS.tx_ready=1 → 返回
    ret
spi_rx_byte:   # 接收 1 字节到 x10
    # 发 dummy byte (0xFF) → 等 rx_ready → 读 DATA → 返回
    ret
uart_rx_byte:  # (同上节)
    ret
```

### 5.5 关键说明

- **SPI 模式**：S25FL256S 支持 Mode 0 (CPOL=0, CPHA=0) 和 Mode 3。默认使用 Mode 0。
- **读取命令**：使用标准 READ (0x03)，最大 50MHz。10MHz 在 200MHz 系统时钟下分频系 9，完全安全。
- **CS 控制**：每次 SPI 操作前后需要拉低/拉高 CS。bootloader 需要手动写 SPI CTRL 或增加 GPIO 控制 CS。
- **Flash 偏移**：`FLASH_OFFSET = 0x400000` (4MB)，在 FPGA 比特流之后。S25FL256S 共 32MB，4MB 起留给用户程序足够安全。

---

## 6. PC 端 Python 脚本

```python
# python/uart_load.py
"""
UART 程序加载器 — 将 .hex 文件发送到 FPGA bootloader

用法: python uart_load.py <hex_file> <serial_port> [baudrate]

示例: python uart_load.py mytest.hex COM3
      python uart_load.py mytest.hex /dev/ttyUSB0 115200
"""

import sys
import serial
import time

def load_hex(filepath):
    """读取 .hex 文件, 返回 32-bit word 列表"""
    words = []
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('@') or line.startswith('//'):
                continue
            # 每行一个 32-bit hex word
            words.append(int(line, 16))
    return words

def send_program(ser, words):
    """发送程序到 FPGA bootloader"""
    size = len(words)
    print(f"程序大小: {size} words ({size*4} bytes)")

    # 1. 发送程序大小 (4 字节, big-endian)
    ser.write(size.to_bytes(4, 'big'))

    # 2. 逐 word 发送 (每个 word 4 字节, big-endian)
    for i, w in enumerate(words):
        ser.write(w.to_bytes(4, 'big'))
        if (i + 1) % 256 == 0:
            print(f"  已发送: {i+1}/{size} words")
    
    print(f"发送完成, 共 {size} 条指令")
    print("FPGA bootloader 将自动跳转执行...")

def main():
    if len(sys.argv) < 3:
        print("用法: python uart_load.py <hex_file> <serial_port> [baudrate]")
        sys.exit(1)

    hex_file = sys.argv[1]
    port = sys.argv[2]
    baudrate = int(sys.argv[3]) if len(sys.argv) > 3 else 115200

    words = load_hex(hex_file)
    if not words:
        print(f"错误: {hex_file} 中没有有效指令")
        sys.exit(1)

    ser = serial.Serial(port, baudrate, timeout=1)
    print(f"连接到 {port} @ {baudrate} bps")
    time.sleep(0.1)  # 等待串口稳定

    send_program(ser, words)
    ser.close()

if __name__ == '__main__':
    main()
```

---

## 7. 开发流程对比

### 旧流程（当前）

```
修改 inst_rom.v initial 块
        │
        ▼  (每次都要)
  Vivado 综合     ≈ 10 分钟
        │
        ▼
  Vivado 实现     ≈ 10 分钟
        │
        ▼
  生成比特流      ≈ 2 分钟
        │
        ▼
  烧录 FPGA       ≈ 1 分钟
        │
        ▼
  观察结果 (LED / UART)
────────────────────────────
  总计: ≈ 23 分钟/次
```

### 新流程（bootloader）

```
──────── 第一次（仅此一次）────────
  固化 bootloader 到 inst_bram initial 块
  Vivado 综合 → 实现 → 烧录
──────────────────────────────────

──────── 之后每次换程序 ─────────
  python riscv_asm7.py test.s → test.hex
  python uart_load.py test.hex COM3
  按 FPGA 复位键
  观察结果
──────────────────────────────────
  总计: < 30 秒/次
```

**效率提升约 50 倍**。

---

## 8. 需要改动的文件清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `soc/mem/inst_bram.v` | **新建** | 双端口 BRAM，替代 inst_rom.v |
| `soc/periph/uart_rx.v` | **新建** | UART 接收模块 |
| `soc/periph/uart_ctrl.v` | **修改** | 集成 uart_rx，新增 RX_DATA 和 STATUS 位 |
| `soc/bus/bus_arbiter.v` | **修改** | 新增 inst_bram 地址空间 0x2000_0000 |
| `soc/top/soc_top.v` | **修改** | inst_rom → inst_bram, 新增总线连线 |
| `soc/top/soc_top_fpga.v` | **修改** | 新增 uart_rx 引脚 |
| `constraints.xdc` | **修改** | 新增 UART RX 引脚 + **SPI Flash 引脚约束 (R23/P24/R25/R24)** |
| `python/bootloader.s` | **新建** | RISC-V bootloader 汇编源码 (UART + SPI Flash 双模式) |
| `python/uart_load.py` | **新建** | PC 端程序发送脚本 |
| `uvm/rtl_filelist.f` | **修改** | 新增 RTL 文件到 UVM 文件列表 |

**不动 CPU 核心**：`core/` 下所有模块无需修改。

---

## 9. Genesys 2 板载 SPI Flash 详细设计

### 9.1 硬件概况

Genesys 2 板载一片 **S25FL256SAGMFI00** QSPI Flash：

| 参数 | 值 |
|------|-----|
| 型号 | Cypress/Infineon S25FL256S |
| 容量 | 256 Mbit = **32 MB** |
| 接口 | SPI / QSPI (单线/四线) |
| 最高时钟 | 133 MHz (Fast Read) |
| 典型用途 | FPGA 配置 + 用户数据存储 |
| 与 FPGA 连接 | Bank 14 多功能引脚 (配置后变普通 IO) |

### 9.2 原理图引脚映射

从 Genesys 2 原理图（Sheet 15/22）：

| Flash 引脚 | Flash 功能 | FPGA 引脚 | FPGA 功能 (配置后) |
|------------|-----------|-----------|-------------------|
| 15 (DQ0) | SDI/MOSI | P24 | IO_L1P_T0_D00_MOSI_14 |
| 8 (DQ1) | SDO/MISO | R25 | IO_L1N_T0_D01_DIN_14 |
| 16 (SCK) | SCK | R23 | IO_L3P_T0_DQS_PUDC_B_14 |
| 7 (CS#) | CS# | R24 | IO_L3N_T0_DQS_EMCCLK_14 |
| 9 (DQ2) | WP# | U19 | IO_L6P_T0_FCS_B_14 |
| 1 (DQ3) | HOLD# | — | (上拉 1.5K 到 VCC3V3) |

**约束文件需要绑定的引脚**（对应现有 spi 接口）：

| 信号 | FPGA 引脚 | IOSTANDARD |
|------|-----------|------------|
| `spi_sclk_o` | R23 | LVCMOS33 |
| `spi_mosi_o` | P24 | LVCMOS33 |
| `spi_miso_i` | R25 | LVCMOS33 |
| `spi_cs_o` | R24 | LVCMOS33 |

**注意**：这些引脚与 FPGA 配置引脚复用（Bank 14）。在 Vivado 中设置为普通 IO 即可，因为配置完成后这些引脚自动释放。

### 9.3 Flash 存储布局

S25FL256S 共 32MB，划分为 512 个 64KB Sector（或 256 个 128KB Sector）。

```
S25FL256S 32MB 地址空间
┌────────────────────────────────────────┐  0x0000_0000
│                                        │
│  FPGA 比特流 (.bit)                     │  ~11 MB (XC7K325T)
│  由 Vivado 烧录时写入                    │  ← 这部分绝不能动
│                                        │
├────────────────────────────────────────┤  0x00C0_0000 (12MB, 安全边界)
│                                        │
│  FX-RV32 用户程序存储区                  │  从 FLASH_PROG_OFFSET 开始
│  - 程序 1 (可存多个程序)                 │  推荐 0x0100_0000 (16MB)
│  - 程序 2                              │  到 0x01FF_FFFF (32MB)
│  - ...                                 │  共 ~16MB 可用
│                                        │
└────────────────────────────────────────┘  0x0200_0000
```

**推荐 `FLASH_PROG_OFFSET = 0x0100_0000` (16MB)**，留足 FPGA 比特流空间，绝不冲突。

### 9.4 S25FL256S 关键命令

bootloader 需要使用的几条 SPI 命令：

| 命令 | 操作码 | 说明 |
|------|--------|------|
| READ | `0x03` | 标准读 (≤50MHz), 3 字节地址 |
| RDSR | `0x05` | 读状态寄存器 (检查 WIP 位) |
| WREN | `0x06` | 写使能 (擦除/编程前必须发) |
| SE | `0xD8` | 64KB Sector Erase |
| PP | `0x02` | 页编程 (最多 256 字节/页, 或 512 字节) |

**读操作流程**（READ 0x03）：
```
CS拉低 → 发 0x03 → 发 24-bit 起始地址 [23:16][15:8][7:0]
       → 读 N 字节 (地址自动递增) → CS拉高
```

**写操作流程**（PP 0x02）：
```
CS拉低 → 发 WREN(0x06) → CS拉高   // 写使能
CS拉低 → 发 RDSR(0x05) → 读 1 字节, 检查 bit0=1 (WEL) → CS拉高
CS拉低 → 发 0x02 → 发 24-bit 地址 → 发 ≤256 字节数据 → CS拉高
CS拉低 → 发 RDSR(0x05) → 读 1 字节, 等待 bit0=0 (WIP清零) → CS拉高
```

### 9.5 SPI 控制器配置

现有 `spi_master.v` 寄存器回顾：

| 偏移 | 寄存器 | 关键位 |
|------|--------|--------|
| 0x00 | CTRL | [0] enable, [2] cpol, [3] cpha, [5] data_16bit, [6] start_tx |
| 0x04 | CLK_DIV | [15:0] 分频系数 |
| 0x08 | DATA | [15:0] TX/RX 数据 |
| 0x0C | STATUS | [0] tx_ready, [1] rx_ready, [2] tx_busy |
| 0x10 | IRQ_FLAG | [0] tx_done, [1] rx_done |

**S25FL256S 配合设置**：
- Mode 0: CPOL=0, CPHA=0（S25FL256S 默认支持 Mode 0 和 Mode 3）
- 8-bit 传输: `data_16bit = 0`
- 10MHz 时钟: `CLK_DIV = 9`（200MHz / (2×(9+1)) = 10MHz）
- MSB 优先: `lsb_first = 0`

**SPI CS 控制**：当前 `spi_master.v` 的 CS 信号由状态机自动管理（传输期间自动拉低）。但连续多字节的 READ 操作需要 CS 在整个读过程中保持低电平——需要确认现有 `spi_master.v` 是否支持连续传输。如果不支持，bootloader 可以改用 GPIO 直接控制 CS。

**建议**：另外加一个简单的 GPIO 位来控制 Flash CS，这样读多字节时更灵活：

```c
// bootloader 伪代码中的 Flash 读操作
gpio_set_cs(0);           // CS 拉低
spi_tx_byte(0x03);        // READ 命令
spi_tx_byte(addr >> 16);  // 地址 [23:16]
spi_tx_byte(addr >> 8);   // 地址 [15:8]
spi_tx_byte(addr);        // 地址 [7:0]
for (i = 0; i < n; i++)
    data[i] = spi_rx_byte(); // 读数据 (每次发 dummy 0xFF)
gpio_set_cs(1);           // CS 拉高
```

### 9.6 Flash 编程工具

**方案 A — FPGA 内编程（bootloader 支持）**：

Bootloader 在 UART 接收程序的同时，将其写入 SPI Flash：

```
PC ──UART──> FPGA bootloader
                │
                ├──> inst_bram (sw 写入, 供执行)
                └──> SPI Flash (先擦除 Sector, 再 Page Program)
```

**方案 B — PC 直接编程（需要额外硬件）**：

如果 PC 有 SPI 编程器（或使用 FT2232 等），可以直接写 Flash：
- 省去 UART 传输
- 适合批量部署

**推荐方案 A**，因为不需要额外硬件，一次 UART 传输同时完成加载和固化。

### 9.7 SPI Flash 编程流程（bootloader 中实现）

```
UART 接收完程序后:
    │
    ▼
检查是否需要写入 Flash (由 UART 协议的第一字节指令决定: 0x01=仅加载, 0x02=加载+固化)
    │
    ▼ (仅 mode=0x02 时)
擦除目标 Sector (SE 0xD8, 64KB)
    │
    ▼
循环: Page Program (PP 0x02, 每页 256 字节)
  写使能(WREN) → 编程(PP) → 等待完成(WIP=0)
    │
    ▼
验证: 读回前 4 字节, 确认 Magic Number 正确写入
    │
    ▼
跳转到加载的程序
```

---

## 10. SPI Flash 相关问题

### 10.1 FPGA 配置时的引脚复用

Bank 14 的引脚在 FPGA 配置过程中被用作配置接口（D00/D01/DQS/FCS_B）。配置完成后，这些引脚自动切换为普通 IO。**不需要特殊处理**，Vivado 会自动管理。

但需要注意：**配置期间 SPI Flash 被 Vivado 的配置逻辑访问，bootloader 不能在配置期间操作 Flash**。由于 bootloader 是 FPGA 配置完成后才运行，天然不会冲突。

### 10.2 比特流与用户程序共存

同一片 Flash 同时存储 FPGA 比特流和用户程序，存在风险：
- Vivado 烧录 `.bit` 时**默认会擦除整个 Flash 再写入**
- 如果用户程序也在同一片 Flash 中，会被清除

**解决方案**：
1. Vivado 烧录时使用 `.mcs` 文件，将比特流和用户程序合并后一次烧录
2. 或者：Vivado 只烧比特流（不影响用户程序区），确认 Vivado 的烧录范围不覆盖 `FLASH_PROG_OFFSET` 之后
3. 最安全：FPGA 比特流存在 0x000000~0x00BFFFFF，用户程序在 0x01000000 之后

**验证方法**：烧录比特流后，用 bootloader 的 SPI 读功能验证 0x01000000 处的内容是否被破坏。

### 10.3 S25FL256S 特性

- **写前必须擦除**：Flash 只能将 bit 从 1 写为 0。编程前必须先擦除（全部置 1）。最小擦除单位 = Sector (64KB)。
- **WIP 轮询**：编程/擦除命令发出后，需要轮询状态寄存器 bit0 (WIP) 直到为 0。
- **写保护**：S25FL256S 上电后可能处于写保护状态。需要检查状态寄存器 bit7 (SRWD) 和发送 WREN 解除。

### 9.8 constraints.xdc 需要添加的引脚

```tcl
# ========== SPI Flash (S25FL256S on Genesys 2) ==========
set_property PACKAGE_PIN R23 [get_ports spi_sclk_o]     ;# SCK
set_property PACKAGE_PIN P24 [get_ports spi_mosi_o]     ;# MOSI/SDI
set_property PACKAGE_PIN R25 [get_ports spi_miso_i]     ;# MISO/SDO
set_property PACKAGE_PIN R24 [get_ports spi_cs_o]       ;# CS#

set_property IOSTANDARD LVCMOS33 [get_ports {spi_sclk_o spi_mosi_o spi_miso_i spi_cs_o}]
set_property SLEW FAST [get_ports {spi_sclk_o spi_mosi_o spi_cs_o}]
set_property DRIVE 8 [get_ports {spi_sclk_o spi_mosi_o spi_cs_o}]

# ========== UART (Genesys 2 USB-UART) ==========
# UART TX — 已存在 (Y23), 不变
set_property PACKAGE_PIN AB22 [get_ports uart_rx_i]     ;# UART RX (来自 FT2232)
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx_i]
```

### 9.9 soc_top_fpga 需要修改的端口

```verilog
// soc_top_fpga.v 顶层端口新增
input  wire        uart_rx_i,        // UART RX (新增)
```

并在 `soc_top` 实例化中连接 `uart_rx_i` 到 `soc_top` 的对应端口。

---

## 11. 风险与注意事项

1. **FENCE.I**：RISC-V 规范要求修改指令存储器后执行 `fence.i` 指令，确保指令缓存同步。当前 FX-RV32 没有指令缓存，`fence.i` 作为 NOP 执行即可，但保留以备将来扩展。

2. **取指延迟**：Port A 是同步读（`posedge clk_i`），意味着 IF 阶段的取指会比原来异步读多 1 个时钟周期延迟。需要确认这不会破坏流水线时序。**替代方案**：Port A 保持组合逻辑读（`always @(*)`），只有 Port B 用同步读写；Vivado 仍可推断 BRAM（因为有一个端口是同步的），但需要验证。

3. **BRAM 推断验证**：综合后必须检查 Vivado 的 `report_ram_utilization` 确认 inst_bram 被正确推断为 Block RAM。

4. **Bootloader 地址空间**：bootloader 本身占用 inst_bram 的 0x000-0x1FF。用户程序从 0x200 开始。如果用户程序需要中断向量表（mtvec 默认指向 0x000），需要在 0x200 开始的程序里自己设置 mtvec。

5. **UART 波特率误差**：200MHz / 115200 ≈ 1736.11，实际分频系数 1736，误差约 0.006%，在可接受范围内（< 2%）。

6. **程序大小上限**：32KB inst_bram，扣除 2KB bootloader，用户程序最大 30KB（7680 条指令）。如需更大空间，增大 `INST_DEPTH` 参数即可（Kintex-7 有 445 个 BRAM36 tile，资源充裕）。

7. **SPI Flash 共用风险**：同一片 Flash 同时存 FPGA 比特流和用户程序，Vivado 烧录 `.bit` 时可能擦除整个 Flash。必须确认 Vivado 的烧录地址范围不覆盖 `FLASH_PROG_OFFSET` 之后的区域。建议首次使用时用逻辑分析仪或 Flash 读命令验证。

8. **Flash 写寿命**：S25FL256S 每个 Sector 擦除寿命约 100,000 次。频繁的"加载+固化"操作应尽量写到不同 Sector（磨损均衡）。仅加载不固化的场景无此问题。

9. **SPI CS 控制**：现有 `spi_master.v` 的 CS 由状态机自动管理（每次传输自动拉低/拉高）。连续多字节的 Flash READ 需要 CS 在整个读过程中保持低电平。如果 `spi_master.v` 不支持，bootloader 需要用 GPIO 手动控制 CS，或者修改 `spi_master.v` 增加"连续传输模式"。

---

## 12. 可选优化

### 11.1 写保护

在 bus_arbiter 中增加写保护逻辑，防止用户程序意外覆写 bootloader 区域（0x2000_0000 - 0x2000_01FF）。或者更简单：inst_bram 的 Port B 写逻辑中直接硬编码忽略对低 512 字的写操作。

```verilog
// inst_bram.v Port B 写保护
always @(posedge clk_i) begin
    if (bus_we_i && (bus_addr_i[31:2] < INST_DEPTH) && (bus_addr_i[31:9] != 0))
        mem[bus_addr_i[31:2]] <= bus_wdata_i;
end
// bus_addr_i[31:9] != 0 确保地址 >= 0x200 (跳过 bootloader 区域)
```

### 11.2 程序校验

在通信协议中增加简单的校验（如 XOR checksum），bootloader 接收完所有数据后验证，错误则通过 LED 指示。

### 11.3 自动复位跳转

Bootloader 加载完成后不立即跳转，而是等待用户按下某个 GPIO 按钮再跳转，方便调试确认加载成功。
