# SPI Flash 扩展实现说明

> 基于 `bootloader_uart_loading_plan.md` 方案实施
> 实施日期: 2026-06-20

## 1. 概述

为 FX-RV32 添加了 SPI Flash 程序加载能力，实现"一次综合、多次加载"：

- **inst_bram**：双端口 BRAM 替代 inst_rom，Port A 取指 + Port B 总线写
- **Bootloader**：固化在 inst_bram 低 2KB，支持 UART 和 SPI Flash 双模式加载
- **UART RX**：新增 UART 接收功能，PC 可通过串口发送程序
- **SPI Flash 读取**：bootloader 通过 `lw 0x3000_XXXX` 从 Flash 读取用户程序

## 2. 文件清单

### 新建文件

| 文件 | 说明 |
|------|------|
| `soc/mem/inst_bram.v` | 双端口 BRAM (32KB)，固化 68 指令 bootloader，写保护 0x000-0x1FF |
| `soc/periph/uart_rx.v` | UART 接收模块，16× 过采样，115200 bps 8N1 |
| `soc/periph/spi_flash_ctrl.v` | **SPI Flash 控制器**，硬件状态机处理 Flash READ 协议，总线读接口 |
| `python/bootloader.s` | RISC-V 汇编 bootloader v2 (lw 0x3000_XXXX 读 Flash) |
| `python/uart_load.py` | PC 端串口加载脚本 |

### 修改文件

| 文件 | 变更内容 |
|------|----------|
| `soc/periph/uart_ctrl.v` | 集成 uart_rx；新增 RX_DATA(0x10)、IRQ_FLAG(0x14)；STATUS[2]=rx_ready；CTRL[1]=rx_enable |
| `soc/bus/bus_arbiter.v` | 新增 inst_bram(0x2000_0000) + Flash(0x3000_0000) 地址空间 |
| `soc/top/soc_top.v` | inst_rom→inst_bram；uart_rx_i；spi_flash_ctrl 接管 SPI 引脚 |
| `soc/top/soc_top_fpga.v` | 新增 uart_rx_i 端口 |
| `constraints.xdc` | UART RX=AB22；SPI Flash: R23(SCK), P24(MOSI), R25(MISO), R24(CS) |
| `uvm/rtl_filelist.f` | 新增 soc 层 RTL 文件 |

### 未修改

`core/` 下所有 CPU 核心模块不变。

## 3. 地址映射

| 地址范围 | 设备 | 说明 |
|----------|------|------|
| 0x0000_0000 - 0x0000_FFFF | data_ram | 64KB 数据 RAM |
| 0x1000_0000 - 0x1000_0FFF | UART | 新增 RX_DATA(0x10), IRQ_FLAG(0x14) |
| 0x1000_1000 - 0x1000_1FFF | GPIO | 不变 |
| 0x1000_2000 - 0x1000_2FFF | Timer | 不变 |
| 0x1000_3000 - 0x1000_3FFF | SPI (spi_master) | 通用 SPI 外设，寄存器接口 |
| 0x1000_4000 - 0x1000_4FFF | I2C | 不变 |
| **0x2000_0000 - 0x2000_7FFF** | **inst_bram (总线窗口)** | **新增** |
| **0x3000_0000 - 0x30FF_FFFF** | **SPI Flash (直读窗口)** | **新增, spi_flash_ctrl** |

### UART 寄存器

| 偏移 | 寄存器 | 位 | 说明 |
|------|--------|-----|------|
| 0x00 | TX_DATA | [7:0] | 写: 推入 TX FIFO |
| 0x04 | STATUS | [0]=tx_wr_ready, [1]=tx_idle, [2]=rx_ready, [3]=fifo_full, [10:4]=fifo_count | |
| 0x08 | CTRL | [0]=tx_enable, [1]=rx_enable | |
| 0x0C | BAUD_DIV | [15:0] | 分频系数 (200MHz/baud) |
| 0x10 | RX_DATA | [7:0] | 只读, 读后自动清除 rx_ready |
| 0x14 | IRQ_FLAG | [0]=tx_done, [1]=rx_done | 写 1 清除 |

## 4. 从 Verilog 到 Flash 芯片的完整链路

这是理解整个 Flash 通信的关键。S25FL256S 是焊接在 Genesys 2 板子上的真实芯片，FPGA 通过 4 根 PCB 走线直接和它连接：

```
┌─────────────────── FPGA (Kintex-7) ───────────────────┐
│                                                         │
│  CPU 执行 lw 0x30000000                                 │
│       │                                                 │
│       ▼                                                 │
│  bus_arbiter (地址译码: 0x3000_0000 → Flash)            │
│       │                                                 │
│       ▼                                                 │
│  spi_flash_ctrl.v  ← 硬件状态机, 自动生成 SPI 波形      │
│       │                                                 │
│       │ flash_sclk_o  ←── 10MHz 时钟                    │
│       │ flash_mosi_o  ←── 命令/地址 输出                │
│       │ flash_miso_i  ──→ 数据 输入                     │
│       │ flash_cs_o    ←── 片选 (低有效)                 │
│       │                                                 │
│       ▼  constraints.xdc 把信号映射到物理引脚            │
│       │                                                 │
│     ┌─┴──────────────┐                                  │
│     │  FPGA 引脚       │  constraints.xdc:               │
│     │  R23 = SCLK     │    PACKAGE_PIN R23               │
│     │  P24 = MOSI     │    PACKAGE_PIN P24               │
│     │  R25 = MISO     │    PACKAGE_PIN R25               │
│     │  R24 = CS       │    PACKAGE_PIN R24               │
│     └─┬──────────────┘                                  │
└───────┼─────────────────────────────────────────────────┘
        │  PCB 走线 (板子出厂已焊好, 不需要你做任何事)
        │
┌───────┼────────── S25FL256S Flash 芯片 ────────────────┐
│       │                                                  │
│     ┌─┴──────────────┐                                  │
│     │  Flash 引脚      │                                 │
│     │  SCK  ◄── R23   │  时钟                           │
│     │  SDI  ◄── P24   │  命令/地址 输入                 │
│     │  SDO  ──→ R25   │  数据 输出                      │
│     │  CS#  ◄── R24   │  片选 (低电平选中)              │
│     └────────────────┘                                  │
│                                                         │
│  内部: 32MB NOR Flash 存储阵列                          │
│  上电后即处于 SPI 从机模式, 等待 FPGA 发命令            │
└─────────────────────────────────────────────────────────┘
```

### SPI 波形 (spi_flash_ctrl 硬件自动产生)

当 CPU 执行 `lw x1, 0x30000000(x0)` 时，spi_flash_ctrl 状态机在 SPI 引脚上产生如下波形：

```
          ┌─── CMD=0x03 ──┬─ ADDR[23:16] ─┬─ ADDR[15:8] ─┬─ ADDR[7:0] ─┬─── READ 4 Bytes ───────────┐
CS:   ───┘▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔───
SCLK: ▁▁▁/▔▔\▁▁/▔▔\ ...  8 个时钟  ... 8 个时钟 ... 8 个时钟 ... 8 个时钟 ... × 4 字节
MOSI: ▁▁▁▁/ 0 0 0 0 0 0 1 1 \▁▁/ addr[23:16] \▁▁/ addr[15:8] \▁▁/ addr[7:0] \▁▁▁▁▁▁▁▁▁▁▁▁▁
MISO: ▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁/ D7 D6 D5 D4 D3 D2 D1 D0 \▁▁ / 下一字节 ...
```

- FPGA 输出 4 根线: CS、SCLK、MOSI
- Flash 芯片输出 1 根线: MISO (FPGA 端是 input)
- Flash 芯片根据收到的命令+地址，自己把对应存储单元的数据驱动到 MISO 上
- **不需要任何中间芯片、IP 核、或 Flash 仿真模型**——芯片已经在板子上了

## 5. spi_master 与 spi_flash_ctrl 的区别

这是两个不同层次的模块，功能完全不同：

| | spi_master (通用 SPI 外设) | spi_flash_ctrl (Flash 控制器) |
|------|------|------|
| 接口类型 | 寄存器读写 (CTRL/DATA/STATUS) | 存储器映射 (一条 lw 即可) |
| CPU 操作 | 每字节写 4-5 条指令 (写DATA→写CTRL→等STATUS→读DATA) | 每 word 一条 lw 指令 |
| CS 管理 | 每次传输后自动拉高 | 整个事务期间保持低 |
| 每次传输量 | 1 字节或 2 字节 | 固定 4 字节 (一个 32-bit word) |
| 用途 | 任意 SPI 设备 | 只读 Flash (READ 0x03) |
| 总线地址 | 0x1000_3000 (外设区) | 0x3000_0000 (存储区) |
| 能否读 Flash | 能, 但需要 bootloader 逐字节编程, 非常繁琐 | 专为此设计, 硬件自动处理 |

**关系**：`spi_flash_ctrl` 是对 Flash 读取操作的高层封装。如果把 `spi_master` 比作 UART 单字节收发，那 `spi_flash_ctrl` 就是把整个 Flash 读流程硬化成状态机，对 CPU 暴露成普通存储器——一条 `lw` 就完成全部操作，和读 data_ram 一样简单。

## 6. Bootloader 工作流程

```
上电/复位
    │
    ▼
初始化 UART RX enable
    │
    ▼
轮询 UART RX (超时 ~10ms)
    │
    ├── 有数据 ──→ UART 加载模式
    │               │
    │               ├─ 接收 4 字节 size (big-endian)
    │               ├─ 循环接收 size 条指令, 写入 inst_bram 0x20000200
    │               └─ fence.i → 跳转 0x200
    │
    └── 超时 ──→ SPI Flash 加载模式
                    │
                    ├─ lw 0x30000000 → 检查 Magic Number
                    │   └─ 不匹配 → 回到 UART 轮询
                    ├─ lw 0x30000004 → 读程序大小
                    ├─ 循环: lw 0x30000008+N*4 → sw 0x20000200+N*4
                    └─ fence.i → 跳转 0x200
```

对比旧方案的 Flash 加载模式（bootloader 通过 spi_master 逐字节操作），新方案每条指令从十几条汇编缩减到一条 `lw`，bootloader 从 144 指令减少到 68 指令。

## 7. 通信协议

### UART 协议 (PC → FPGA)

```
Byte 0-3: program size in words (big-endian)
Byte 4-7: instr[0] (big-endian)
Byte 8-11: instr[1]
...
```

### SPI Flash 数据格式 (Flash 内偏移 0x01000000)

```
偏移    大小      内容
0x00    4 bytes   Magic Number: 0x46585256 ("FXRV")
0x04    4 bytes   Program Size (word count, big-endian)
0x08    N×4       Program data (每条指令 4 字节, big-endian)
```

每次 `lw` 耗时约 1280 周期 (6.4μs @ 200MHz)。对于 1KB 程序，Flash 加载耗时约 1.6ms。

## 8. 使用方法

### 8.1 两条加载路径：UART 和 SPI Flash 各司其职

bootloader 有两种工作模式，分别对应两条不同的数据传输路径：

```
场景 A: 开发调试 (换测试程序)                场景 B: 独立运行 (部署后)
                                            
  PC ──UART串口──→ FPGA                       FPGA ──SPI──→ Flash 芯片
  (USB线, 你坐在电脑前)                       (板子上的PCB走线, 不需要PC)
```

**UART（场景 A）**：你写了一个新测试程序，在 PC 端汇编后通过串口发给 FPGA。PC 是主动方，FPGA 是接收方。

**SPI（场景 B）**：FPGA 脱离 PC 独立运行。上电后 bootloader 自己通过 SPI 总线去读板子上的 Flash 芯片，把程序加载到 inst_bram。FPGA 是主动方（SPI 主设备），Flash 芯片是被动方（SPI 从设备）。

> SPI 体现在场景 B——FPGA 内部 `spi_flash_ctrl.v` 产生 SPI 时序波形，通过 4 根引脚（SCLK/MOSI/MISO/CS）和焊接在板子上的 S25FL256S Flash 芯片通信。这和 PC 串口是两个独立的通信通道。

两条路都不会经过 Vivado。程序都是**运行时**通过总线写入 inst_bram，这就是"换程序不需要重综合"的根本原因。

### 8.2 环境说明

整个操作在 **PC + FPGA 板子** 之间完成：

```
┌── PC ───────────────────────────┐     ┌── FPGA (Genesys 2) ──────────┐
│                                  │     │                              │
│  python riscv_asm7.py test.s    │     │  soc_top_fpga                │
│    → test.hex (机器码)           │     │    │                         │
│                                  │     │    ├─ inst_bram (含bootloader)│
│  python uart_load.py test.hex   │ USB │    ├─ spi_flash_ctrl ←──┐    │
│    COM3                         │─────│→ UART_RX                │    │
│    → 串口发送 (场景A)            │     │    ├─ bus_arbiter       │    │
│                                  │     │    └─ ...              │    │
│  串口终端 (PuTTY/Serial)        │ USB │                         │    │
│    ← 观察 FPGA 输出              │←────│ UART_TX                │    │
│                                  │     │                        │    │
└──────────────────────────────────┘     │  SPI 引脚 ─────────────┼────┘
                                         │  R23/R24/P24/R25       │
                                         │                        ▼
                                         │              S25FL256S Flash
                                         │              (场景B: FPGA自读)
                                         └──────────────────────────────┘
```

### 8.3 首次部署（只做一次）

```bash
# 1. 确认 inst_bram.v 已包含 bootloader 机器码 (68 条指令)
grep "mem\[67\]" soc/mem/inst_bram.v

# 2. Vivado: 综合 → 实现 → 生成比特流 → 烧录 FPGA
#    烧录完成后不要断电，FPGA 开始运行 bootloader
```

### 8.4 日常开发换程序（每次换测试程序的操作）

假设 FPGA 已经烧录好正在运行（bootloader 在里面跑着）。现在你写了一个新的测试程序 `mytest.s`，想让 FPGA 执行它：

```bash
# ===== 在 PC 端执行 (不需要碰 Vivado) =====

cd python

# 步骤 1: 汇编新程序
python riscv_asm7.py mytest.s > mytest.hex

# 步骤 2: 先运行串口发送脚本 (它会等待发送)
#         然后立刻按下 FPGA 的复位键
python uart_load.py mytest.hex COM3
```

**为什么是这个顺序？**

bootloader 上电后只轮询 UART 约 10ms。如果 10ms 内没收到数据，它就切到 SPI Flash 模式了。所以正确操作是：

```
PC 端:  启动 uart_load.py ──→ 脚本打开串口, 开始发送数据
FPGA 端:    └── 按下复位键 ──→ bootloader 从头执行, 检测到 UART 有数据
                                   ↓
                              进入 UART 加载模式
                                   ↓
                              接收程序 → 写入 inst_bram → 跳转执行
```

如果 Flash 里也没有有效程序，bootloader 会循环回 UART 轮询模式，这时不按复位也能收到。

### 8.5 固化到 SPI Flash 后（独立运行，无需 PC）

如果你已经通过某种方式把程序写入了 SPI Flash（偏移 0x01000000，Magic Number 为 "FXRV"）：

```
FPGA 上电 / 按复位
    ↓
bootloader 运行
    ↓
轮询 UART 10ms, 无数据
    ↓
自动从 Flash 读取程序 → 写入 inst_bram → 跳转执行
    ↓
完全独立，不需要 PC 连接
```

### 8.6 修改 Bootloader 后重新固化

```bash
cd python

# 1. 修改 bootloader.s
# 2. 汇编
echo 0 | python riscv_asm7.py bootloader.s > /tmp/bootloader_out.txt

# 3. 提取 rom[] 行，粘贴到 soc/mem/inst_bram.v 的 initial 块中

# 4. Vivado 重新综合 + 烧录 (仅此一次)
```

## 9. 资源占用估算

| 资源 | 用量 | 说明 |
|------|------|------|
| BRAM36 | ~8 tiles | inst_bram 32KB 真双端口 |
| FF/LUT | +~400 | spi_flash_ctrl + uart_rx |
| 引脚 | +1 | uart_rx_i (AB22) |
| SPI Flash | 用户区 16MB | 偏移 0x01000000 起, 与 FPGA 比特流不冲突 |

## 10. 注意事项

1. **FENCE.I**: FX-RV32 无指令缓存，`fence.i` 作为 NOP 执行，保留以备扩展
2. **Port A 同步读**: 取指比原 inst_rom 异步读多 1 周期延迟。若仿真发现时序问题，可改 Port A 为组合逻辑读
3. **Bootloader 写保护**: inst_bram Port B 忽略对 0x000-0x1FF 的写操作，防止用户程序覆写 bootloader
4. **用户程序入口**: 固定从 0x200 开始。中断向量表需在用户程序中自行设置（mtvec）
5. **程序上限**: 30KB（32KB BRAM - 2KB bootloader）。可增大 INST_DEPTH 扩展
6. **Flash 比特流共存**: S25FL256S 共 32MB，FPGA 比特流约 11MB (0x00000000)，用户程序从 16MB (0x01000000) 起，不冲突
7. **Flash 读延迟**: 每次 lw 耗时 ~1280 周期，CPU 在此期间被 bus_arbiter 的 ready 信号暂停，读完成后自动继续

## 11. 相关文件

启动 Flash 传输涉及的所有文件，按数据流顺序排列：

```
bootloader.s ──汇编──→ inst_bram.v (initial 块)
                            │
                  ┌─────────┴──────────┐
                  │ CPU 执行 bootloader │
                  │ lw 0x30000000(x0)  │
                  └────────┬──────────┘
                           │
              ┌────────────┴─────────────┐
              │ bus_arbiter.v            │ ← 地址译码: 0x3000_0000 → Flash
              │ (soc/bus/bus_arbiter.v)  │
              └────────────┬─────────────┘
                           │
              ┌────────────┴─────────────┐
              │ spi_flash_ctrl.v         │ ← SPI 时序状态机
              │ (soc/periph/)            │
              └────────────┬─────────────┘
                           │ flash_sclk_o / flash_mosi_o / flash_cs_o
                           │ flash_miso_i
              ┌────────────┴─────────────┐
              │ soc_top.v                │ ← 模块互连
              │ (soc/top/)               │
              └────────────┬─────────────┘
                           │
              ┌────────────┴─────────────┐
              │ soc_top_fpga.v           │ ← FPGA 顶层 (IBUFDS, IOBUF)
              │ (soc/top/)               │
              └────────────┬─────────────┘
                           │
              ┌────────────┴─────────────┐
              │ constraints.xdc          │ ← 引脚映射: R23/R24/P24/R25
              │ (项目根目录)              │
              └────────────┬─────────────┘
                           │ PCB 走线
                           ▼
                   S25FL256S Flash 芯片
```

| 文件 | 路径 | 作用 |
|------|------|------|
| `bootloader.s` | `python/` | 汇编源码，Flash 加载逻辑 (`lw 0x3000_XXXX`) |
| `riscv_asm7.py` | `python/` | 汇编器，将 bootloader.s → 机器码 |
| `inst_bram.v` | `soc/mem/` | 指令 BRAM，initial 块中固化 bootloader 机器码，Port B 可被总线写入 |
| `bus_arbiter.v` | `soc/bus/` | 地址译码，将 0x3000_0000 范围路由到 spi_flash_ctrl |
| `spi_flash_ctrl.v` | `soc/periph/` | Flash 控制器硬件状态机，产生 SPI 波形，处理 READ(0x03) 协议 |
| `soc_top.v` | `soc/top/` | SoC 顶层，实例化并连接以上所有模块 |
| `soc_top_fpga.v` | `soc/top/` | FPGA 专用顶层，添加 IBUFDS/IOBUF |
| `constraints.xdc` | 项目根目录 | 引脚约束，将 FPGA 信号映射到 R23/P24/R25/R24 |

## 12. 新旧流程对比：为什么换程序不需要重新综合？

### 12.1 旧流程：程序硬编码在 FPGA 配置中

旧方案中，测试程序直接写在 `inst_rom.v` 的 `initial` 块里：

```verilog
// soc/mem/inst_rom.v  ← FPGA 综合的对象
initial begin
    rom[0] = 32'h100010b7;   // 用户程序第一条指令
    rom[1] = 32'h00c08093;   // 用户程序第二条指令
    rom[2] = 32'h00100113;
    // ... 用户所有指令
end
```

这个 `initial` 块是 FPGA 配置数据的一部分。**Vivado 综合器把 rom 数组的内容编译进了 FPGA 的查找表/BRAM 的初始值中**。所以每次换程序，`inst_rom.v` 的文件内容变了，Vivado 必须重新综合、重新实现、重新生成比特流。

```
┌── 旧流程：每次换程序 ──────────────────────────────────────────┐
│                                                                  │
│  修改 inst_rom.v initial 块                                       │
│       │                                                          │
│       ▼  文件内容变了, Vivado 必须重跑                            │
│  Vivado 综合 (10+ 分钟)                                          │
│       │                                                          │
│       ▼                                                          │
│  Vivado 实现 (10+ 分钟)                                          │
│       │                                                          │
│       ▼                                                          │
│  生成比特流 (2 分钟)                                             │
│       │                                                          │
│       ▼                                                          │
│  烧录 FPGA (1 分钟)                                              │
│       │                                                          │
│       ▼                                                          │
│  观察结果                                                        │
│                                                                  │
│  总计: ≈ 23 分钟/次                                              │
└──────────────────────────────────────────────────────────────────┘
```

**根本原因**：用户程序 = FPGA 硬件配置的一部分，换程序 = 换硬件。

### 12.2 新流程：程序通过总线在运行时写入

新方案中，FPGA 硬件部分（inst_bram + bootloader + spi_flash_ctrl + bus_arbiter）只综合一次。用户程序不再是硬件配置的一部分——它是**运行时数据**，通过 CPU 总线写入 inst_bram。

```
┌── 新流程：仅第一次 ─────────────────────────────────────────────┐
│                                                                  │
│  inst_bram.v initial 块: 只固化 bootloader (68 条指令, 不变)     │
│  spi_flash_ctrl.v: Flash 控制器 (硬件, 不变)                     │
│  bus_arbiter.v: 地址映射 (硬件, 不变)                            │
│       │                                                          │
│       ▼  这些文件内容永远不变, 只综合一次                         │
│  Vivado 综合 → 实现 → 生成比特流 → 烧录 FPGA                     │
│                                                                  │
│  总计: ≈ 23 分钟 (只做一次)                                      │
└──────────────────────────────────────────────────────────────────┘

┌── 新流程：每次换程序 ──────────────────────────────────────────┐
│                                                                  │
│  1. python riscv_asm7.py test.s → test.hex    (1 秒)            │
│       │                                                          │
│       ▼                                                          │
│  2. python uart_load.py test.hex COM3          (1 秒)            │
│       │  PC 通过串口把程序发给 FPGA                               │
│       │  FPGA 内部的 bootloader 接收数据                          │
│       │  bootloader 通过总线把程序写入 inst_bram Port B          │
│       │  (地址 0x2000_0200 → inst_bram 内部 0x200)              │
│       ▼                                                          │
│  3. bootloader 跳转到 0x200, 用户程序开始执行                     │
│       │                                                          │
│       ▼                                                          │
│  4. 按复位键 → bootloader 从 Flash 自动加载 → 执行              │
│                                                                  │
│  总计: < 30 秒/次                                                │
└──────────────────────────────────────────────────────────────────┘
```

### 12.3 关键区别：inst_bram.v 里固化了什么？

同一个文件 `inst_bram.v`，新旧方案存放的内容完全不同：

```
inst_bram 32KB 内部布局:

  旧方案 (inst_rom.v):
  ┌──────────────────────────────────────┐
  │ 0x000 ~ 0x1FF                         │
  │ 用户测试程序 (每次换程序都要改这个文件) │
  │ ↓ 文件内容变化 → Vivado 必须重综合    │
  │ ...                                  │
  │ ... 全部是用户程序 ...                │
  │ ...                                  │
  └──────────────────────────────────────┘

  新方案 (inst_bram.v):
  ┌──────────────────────────────────────┐
  │ 0x000 - 0x1FF (512 words = 2KB)     │
  │ Bootloader (固化, 永远不变)           │ ← 这部分在 initial 块里, 综合进硬件
  │   - 初始化 UART                       │
  │   - 轮询 UART / 读 SPI Flash          │
  │   - 把收到的程序写入 0x200 区域       │
  │   - 跳转到 0x200                      │
  ├──────────────────────────────────────┤
  │ 0x200 - 0x1FFF (30KB)               │
  │ 用户程序区                            │ ← 这部分 initial 块里全是 NOP
  │ (运行时由 bootloader 通过总线写入)     │    运行时动态填充, 不经过 Vivado
  │ (从 UART 接收 或 从 SPI Flash 读取)   │
  └──────────────────────────────────────┘
```

**inst_bram.v 的 initial 块只包含 bootloader 的 68 条指令 + 其余全 NOP。这个文件永远不变，所以 Vivado 只需要综合一次。**

用户程序通过完全不同的路径进入指令存储器：

```
用户程序路径 (旧):
  inst_rom.v initial 块 → Vivado 综合 → 比特流 → FPGA 配置

用户程序路径 (新):
  PC 串口 ──→ UART_RX ──→ bootloader ──sw──→ inst_bram Port B (总线写 0x2000_0200)
  或
  SPI Flash ──lw──→ CPU ──sw──→ inst_bram Port B
```

### 12.4 每个文件在"换程序不重综合"中扮演的角色

| 文件 | 需要重综合？ | 原因 |
|------|:-----------:|------|
| `inst_bram.v` | **否** | initial 块只固化 bootloader (永远不变)，用户程序区全是 NOP，运行时通过 Port B 写入 |
| `spi_flash_ctrl.v` | **否** | 纯硬件状态机，和程序内容无关 |
| `bus_arbiter.v` | **否** | 地址映射表，和程序内容无关 |
| `soc_top.v` | **否** | 模块连线，和程序内容无关 |
| `uart_ctrl.v` | **否** | UART 控制器，和程序内容无关 |
| `constraints.xdc` | **否** | 引脚分配，和程序内容无关 |
| `bootloader.s` | **否** | 已汇编固化进 inst_bram.v，换用户程序时不改动 |
| **用户测试程序 .s** | **否** | 由 PC 端 `riscv_asm7.py` 汇编后通过串口发送，不经过 Vivado |
| **SPI Flash 内容** | **否** | 通过 UART 或编程器写入，不经过 Vivado。FPGA 上电后 bootloader 用 `lw 0x3000_XXXX` 读取 |

**核心**：整个 FPGA 工程中没有任何文件的内容随着换用户测试程序而变化。用户程序是纯运行时数据，走的是 CPU 总线（`sw` 写入 inst_bram Port B），不是 Vivado 综合流程。

## 13. 参考

- `bootloader_uart_loading_plan.md` — 原始设计方案
- `python/bootloader.s` — bootloader 汇编源码
- `python/uart_load.py` — PC 端加载脚本

//
spi_flash_ctrl 就是一个专用 SPI 主设备，和 spi_master 是同一种东西——都是产生 SPI
  波形去和外部芯片通信。区别只在于：

  ┌────────┬───────────────────────────┬──────────────────────┐
  │        │        spi_master         │    spi_flash_ctrl    │
  ├────────┼───────────────────────────┼──────────────────────┤
  │ 命令   │ CPU 通过寄存器指定        │ 硬编码为 0x03 (READ) │
  ├────────┼───────────────────────────┼──────────────────────┤
  │ 数据量 │ 1 或 2 字节               │ 固定 4 字节          │
  ├────────┼───────────────────────────┼──────────────────────┤
  │ 接口   │ 寄存器 (CTRL/DATA/STATUS) │ 总线地址 (lw 即可)   │
  ├────────┼───────────────────────────┼──────────────────────┤
  │ CS     │ 每字节自动拉高            │ 整个事务保持低       │
  └────────┴───────────────────────────┴──────────────────────┘

  底层都是同一套 SPI 协议：CS 拉低 → SCLK 发时钟 → MOSI 发命令和地址 → MISO 收数据 → CS 拉高。

  接口对应关系——spi_flash_ctrl 的端口和 Flash 芯片引脚一一对应：

  spi_flash_ctrl.v              S25FL256S Flash 芯片
    flash_sclk_o  ──── R23 ──── SCK   (时钟)
    flash_mosi_o  ──── P24 ──── SDI   (FPGA → Flash)
    flash_miso_i  ◄──── R25 ──── SDO   (Flash → FPGA)
    flash_cs_o    ──── R24 ──── CS#   (片选)

  中间那列 R23/P24/R25/R24 就是 constraints.xdc 里的引脚约束——它告诉 Vivado 把这 4 个 Verilog 信号绑定到 FPGA 的哪 4
  个物理引脚上，而这些引脚刚好经过 PCB 走线连到了 Flash 芯片。你换一块板子（Flash 连在不同的 FPGA 引脚上），只需要改
  constraints.xdc 的 4 行 PACKAGE_PIN，Verilog 代码完全不用动。