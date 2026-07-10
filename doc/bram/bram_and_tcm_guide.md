# BRAM 与 TCM 设计指南

> FX-RV32 存储架构参考资料 | 2026-06-17

---

## 目录

1. [BRAM 基础概念](#bram-基础概念)
2. [FX-RV32 当前存储实现](#fx-rv32-当前存储实现)
3. [BRAM vs Distributed RAM：对比与选择](#bram-vs-distributed-ram-对比与选择)
4. [BRAM Verilog 代码模板](#bram-verilog-代码模板)
5. [BRAM 资源估算方法](#bram-资源估算方法)
6. [TCM 概念及其与 BRAM 的关系](#tcm-概念及其与-bram-的关系)
7. [FX-RV32 的 TCM 视角分析](#fx-rv32-的-tcm-视角分析)

---

## BRAM 基础概念

### 什么是 BRAM

**BRAM（Block RAM）** 是 Xilinx FPGA 芯片上硬核集成的专用存储宏单元——它不是用 LUT 拼出来的，而是和乘法器（DSP48）、PLL、收发器（GTX）一样，属于**硅片上预先做好的硬核 IP**。

```
    FPGA 芯片布局示意
┌─────────────────────────────────────────┐
│  ┌──┐  ┌──┐     ┌──┐  ┌──┐            │
│  │BR│  │BR│ ... │BR│  │BR│   ← 散布在  │
│  │AM│  │AM│     │AM│  │AM│     逻辑区之间 │
│  └──┘  └──┘     └──┘  └──┘            │
│  ┌──────────┐ ┌──────────┐             │
│  │  CLB 区域 │ │  CLB 区域 │  ← LUT+FF  │
│  │ (LUT+FF) │ │ (LUT+FF) │             │
│  └──────────┘ └──────────┘             │
│  ┌──┐                       ┌──┐       │
│  │BR│  ......  CLB 区域 ... │BR│       │
│  │AM│                       │AM│       │
│  └──┘                       └──┘       │
└─────────────────────────────────────────┘
```

### Kintex-7 BRAM 参数

| 参数 | 数值 |
|------|------|
| 芯片型号 | xc7k325tffg900-2 |
| BRAM tile 总数 | **445** |
| 每 tile 容量 | **36 Kb**（可拆为 2 × 18 Kb） |
| 总存储容量 | 16,020 Kb ≈ **2,002 KB ≈ 1.96 MB** |
| 每 tile 可配置宽度 | 1/2/4/8/9/16/18/32/36 bit |
| 读延迟 | **1 clock cycle**（同步读，输出端有寄存器） |
| 是否支持 byte write | 36Kb 模式下支持 4-byte 独立 write enable |

### 36Kb BRAM 的常见配置形态

| 配置名称 | 深度 | 数据宽度 | 是否有字节使能 |
|----------|------|----------|:--:|
| 1K × 36 | 1024 | 36 bit | ✅ |
| 2K × 18 | 2048 | 18 bit | ❌ |
| 4K × 9 | 4096 | 9 bit | ❌ |
| 8K × 4 | 8192 | 4 bit | ❌ |
| 16K × 2 | 16384 | 2 bit | ❌ |
| 32K × 1 | 32768 | 1 bit | ❌ |

> **结论**：一块 36Kb BRAM tile 可以完美映射你当前的 inst_rom（1024×32b = 32Kb）或 data_ram（1024×32b = 32Kb）。

---

## FX-RV32 当前存储实现

### 现状

| 模块 | 文件 | 容量 | 读写方式 | 推断的物理实现 |
|------|------|------|----------|:--------------:|
| 指令 ROM | `soc/mem/inst_rom.v` | 1024 × 32b = 4KB | 组合逻辑读 | **Distributed RAM (LUTRAM)** |
| 数据 RAM | `soc/mem/data_ram.v` | 1024 × 32b = 4KB | 组合逻辑读 | **Distributed RAM (LUTRAM)** |
| **合计** | | **8KB / 64Kb** | | |

### 为什么不是 BRAM

两个模块的读操作都使用了：

```verilog
// 组合逻辑读 — 无法映射到 BRAM
always @(*) begin
    data_o = mem[addr];
end
```

Xilinx BRAM 硬核的输出端**自带一个寄存器**（这是 BRAM tile 的物理结构决定的），读操作必须过一个 `posedge clk`。`always @(*)` 组合逻辑读意味着 Vivado 只能选择：

- **Distributed RAM**（每个 bit 用一个 LUT 的 64-bit SRAM 单元拼）
- 或者报 Warning 后绕开

### 当前方案的资源代价评估

7-series LUT 内部的 Distributed RAM 密度：每个 LUT = 64 bit SRAM。

| 存储 | 容量 | 大约消耗 LUT |
|------|------|:-----------:|
| inst_rom (4KB) | 32 Kb | ~512 |
| data_ram (4KB) | 32 Kb | ~512 |
| **合计** | **64 Kb** | **~1024** |

在 xc7k325t 约 203,800 个 LUT 的总量下，**占比 ~0.5%**——完全无需担心。

> 但如果未来 data_ram 扩展到 SoC 地址映射中设计的 64KB，Distributed RAM 方式将消耗 ~16,000 LUT（~8%），此时 BRAM 几乎是必须的。

---

## BRAM vs Distributed RAM：对比与选择

| 维度 | BRAM | Distributed RAM |
|------|------|-----------------|
| **实现方式** | 芯片上的硬核 SRAM 宏单元 | 用 LUT 内部 64-bit SRAM 拼 |
| **容量** | 大（每 tile 36Kb） | 小（每 LUT 64bit） |
| **读延迟** | 1 cycle（同步） | 0 cycle（组合逻辑，可当 wire 用） |
| **写延迟** | 1 cycle（同步） | 1 cycle（同步，也可透明写） |
| **功耗** | 低（专用电路，无 LUT 翻转） | 高（大量 LUT 参与） |
| **布局位置** | 固定在芯片上，布线距离不可控 | 紧贴使用它的逻辑，布线短 |
| **面积效率** | >1Kb 时极高 | <512b 时才划算 |
| **灵活度** | 固定宽度/深度组合 | 任意宽度/深度 |
| **是否需初始化** | 通过 bitstream 内置初值 | 可通过 initial 或 bitstream 初始化 |
| **Xilinx 属性** | `(* ram_style = "block" *)` | `(* ram_style = "distributed" *)` |

### 选择经验法则

```
需要存储的容量
    │
    ├── < 256 bit ──→ reg 数组（综合为 FF）
    │
    ├── 256 bit ~ 2 Kb ──→ Distributed RAM（LUT 拼）
    │
    └── > 2 Kb ──→ BRAM（硬核）
```

> FX-RV32 的 4KB inst_rom 和 4KB data_ram 都落在 BRAM 区间。当前不用 BRAM 的唯一"合理"理由是要保持 **0-cycle 组合逻辑读延迟**（BRAM 本质上必须 1-cycle 同步读）。

---

## BRAM Verilog 代码模板

### 1. 单端口 BRAM（带字节使能）—— 对应 data_ram

```verilog
// BRAM Single-Port RAM with Byte-Write Enable
// 适用场景：data_ram 替代，支持 SB/SH/SW 写，同步读
//
// 延迟特性：
//   - 写：这拍给 addr+din+we=1 → 内存在这拍结束时更新
//   - 读：这拍给 addr → 下一拍 dout 有效（1 cycle read latency）
//
//   对比原 data_ram（组合逻辑读，0 cycle latency）：
//   流水线需要吸收这额外的 +1 cycle 读延迟（通常通过调整 MEM 阶段时序）

module bram_data_ram #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 10            // 1024 words → 4KB
) (
    input  wire                     clk_i,
    input  wire                     rst_n_i,
    // 控制
    input  wire                     we_i,         // 写使能
    input  wire [3:0]               be_i,         // 字节使能 be[3:0] = {byte3, byte2, byte1, byte0}
    input  wire [ADDR_WIDTH-1:0]   addr_i,
    input  wire [DATA_WIDTH-1:0]   wdata_i,
    output reg  [DATA_WIDTH-1:0]   rdata_o
);

    // 显式要求 Vivado 推断为 BRAM
    (* ram_style = "block" *)
    reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

    // ====================================================
    // 单 always @(posedge clk) 实现同步读 + 写
    // 读优先级 > 写（Read-before-Write，Xilinx BRAM 标准行为）
    // ====================================================
    always @(posedge clk_i) begin
        // 同步读：当前周期的 addr 数据，下一拍出现在 rdata_o
        rdata_o <= mem[addr_i];

        // 写操作（字节粒度）
        if (we_i) begin
            if (be_i[0]) mem[addr_i][ 7: 0] <= wdata_i[ 7: 0];
            if (be_i[1]) mem[addr_i][15: 8] <= wdata_i[15: 8];
            if (be_i[2]) mem[addr_i][23:16] <= wdata_i[23:16];
            if (be_i[3]) mem[addr_i][31:24] <= wdata_i[31:24];
        end
    end

endmodule
```

### 2. 简单双端口 BRAM —— 读写端口分离

```verilog
// BRAM Simple Dual-Port (SDP) RAM
// 适用场景：指令存储器（一个端口只读用于 IF，另一个端口只写用于 debug/self-modifying）
//
// Xilinx BRAM 原生支持这种模式——两个独立端口，面积和功耗更优

module bram_sdp #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 10
) (
    input  wire                     clk_i,

    // ==== 写端口（例如：外部 debug 写入）====
    input  wire                     wr_en_i,
    input  wire [ADDR_WIDTH-1:0]   wr_addr_i,
    input  wire [DATA_WIDTH-1:0]   wr_data_i,

    // ==== 读端口（IF 阶段取指）====
    input  wire [ADDR_WIDTH-1:0]   rd_addr_i,
    output reg  [DATA_WIDTH-1:0]   rd_data_o
);

    (* ram_style = "block" *)
    reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

    // 写端口
    always @(posedge clk_i) begin
        if (wr_en_i)
            mem[wr_addr_i] <= wr_data_i;
    end

    // 读端口（独立 always，并行无冲突）
    always @(posedge clk_i) begin
        rd_data_o <= mem[rd_addr_i];
    end

endmodule
```

### 3. BRAM ROM（初始化内容）—— 对应 inst_rom

```verilog
// BRAM-based Instruction ROM
// 适用场景：inst_rom 替代，同步读，启动时预载入程序
//
// 延迟特性：
//   - 0 延迟给出地址 → 1 cycle 后拿到指令
//   - 对比原 inst_rom（组合逻辑 0 cycle 出），IF 阶段需要适应这个 +1 cycle
//   - 实际做法可以是：IF 发 PC → IF/ID 寄存器停在下一拍 → ID 拿到指令（BRAM 的 1 cycle 被 IF/ID 寄存器吸收）

module bram_inst_rom #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 10,           // 1024 words → 4KB
    parameter INIT_FILE  = "program.hex" // 程序 hex 文件路径（$readmemh 格式）
) (
    input  wire                     clk_i,
    input  wire [ADDR_WIDTH-1:0]   addr_i,    // 字地址，addr_i[31:2]
    output reg  [DATA_WIDTH-1:0]   instr_o
);

    (* ram_style = "block" *)
    reg [DATA_WIDTH-1:0] rom [0:(1<<ADDR_WIDTH)-1];

    // ====================================================
    // 初始化方式一：从 hex 文件载入
    // ====================================================
    initial begin
        $readmemh(INIT_FILE, rom);
    end

    // ====================================================
    // 初始化方式二：verilog initial 块逐条赋值
    // （与当前 inst_rom.v 风格一致）
    // ====================================================
    /*
    integer i;
    initial begin
        for (i = 0; i < (1<<ADDR_WIDTH); i = i + 1)
            rom[i] = 32'h00000013;      // default NOP

        // 程序正文
        rom[0]  = 32'h100010b7;
        rom[1]  = 32'h00c08093;
        // ...
    end
    */

    // ====================================================
    // 同步读：addr 这一拍进来，下一拍 instr_o 有效
    // ====================================================
    always @(posedge clk_i) begin
        instr_o <= rom[addr_i];
    end

endmodule
```

> **注意**：FPGA 综合工具会忽略 `$readmemh` 中的仿真路径。Vivado 需要在约束文件中用 `set_property` 或配置 `ASSOCIATED_BUSIF` 来指定 BRAM 初始内容，或直接使用 `initial` 块方式（Vivado 会将 initial 块内容写入 bitstream 当作 BRAM INIT 值）。

### 4. Vivado 约束属性速查

```verilog
// 强制推断为 BRAM
(* ram_style = "block" *)    reg [31:0] mem [0:1023];

// 强制推断为 Distributed RAM (LUTRAM)
(* ram_style = "distributed" *) reg [31:0] mem [0:1023];

// 让 Vivado 自己选（默认行为）
reg [31:0] mem [0:1023];

// ROM 专用属性：强制推断为 BRAM 实现 ROM
(* rom_style = "block" *)    reg [31:0] rom [0:1023];
```

在 XDC 约束文件中：

```tcl
# 强制某个信号相关的 RAM 为 BRAM
set_property RAM_STYLE BLOCK [get_cells u_data_ram/mem_reg[*]]

# 指定 BRAM 级联方式
set_property CASCADE_HEIGHT 1 [get_cells u_data_ram/mem_reg[*]]
```

---

## BRAM 资源估算方法

### 基本公式

```
BRAM tile 数量 = ceil( 总存储位宽 / 36Kb )
```

### 7-series BRAM 容量表

| 配置 | 深度 | 宽度 | 总 Kb | 消耗 Tile |
|------|:---:|:---:|:-----:|:---------:|
| 1K × 36 | 1024 | 36 | 36 | 1 |
| 1K × 32 | 1024 | 32 | 32 | 1（取 1K×36 模式，高 4 bit 不用） |
| 1K × 18 | 1024 | 18 | 18 | 0.5（可用另一半做另一块 RAM） |
| 2K × 18 | 2048 | 18 | 36 | 1 |
| 4K × 9 | 4096 | 9 | 36 | 1 |
| 8K × 4 | 8192 | 4 | 32 | 1 |
| 16K × 2 | 16384 | 2 | 32 | 1 |
| 32K × 1 | 32768 | 1 | 32 | 1 |

### FX-RV32 不同配置的 BRAM 需求估算

| 场景 | 描述 | 存储量 | BRAM Tile | 占芯片 BRAM |
|------|------|:------:|:---------:|:----------:|
| **当前** | inst_rom 4KB + data_ram 4KB | 64 Kb | **2** | 0.45% |
| data_ram 扩展到 16KB | inst_rom 4KB + data_ram 16KB | 160 Kb | **5** | 1.1% |
| data_ram 扩展到 64KB | inst_rom 16KB + data_ram 64KB | 640 Kb | **18** | 4.0% |
| 带上 Shadow Register（额外 ×2） | 两边都各需要双份 | — | 不需要 BRAM（reg file 是 FF） | — |

### 注意事项

1. **宽度不匹配时的浪费**：你的设计用 32-bit 宽度，但 BRAM 36Kb tile 原生是 36-bit。一个 1024×32 的 RAM 必须占一整块 36Kb tile，4Kb 的空间被浪费——但这是无法避免的。

2. **深度超过单片 BRAM 时**：如果 data_ram 超过 2KB（1024×32），就需要多片 BRAM 级联 + 地址译码。Vivado 会自动处理，但布局会更分散。

3. **双端口模式**：如果 inst_rom 需要支持 IF 读 + debug 写（SDP），一块 36Kb BRAM 即可（原生双端口）。不需要两块。

---

## TCM 概念及其与 BRAM 的关系

### 什么是 TCM

**TCM（Tightly Coupled Memory，紧耦合存储器）** 是 ARM 提出的 SoC 架构概念。它的核心特征是：

> CPU 核内部有一条**专用总线**直接连着一块 SRAM，访存路径**不经过 L1 Cache、L2 Cache、Bus Matrix 或任何共享互连**。

```
  典型 ARM Cortex-M 的存储层次
  ┌────────────────────────────────────────────┐
  │               CPU Core                      │
  │  ┌──────────────────┐  ┌─────────────────┐ │
  │  │ 取指单元          │  │ Load/Store 单元  │ │
  │  │  │                │  │  │               │ │
  │  │  ▼                │  │  ▼               │ │
  │  │ ITCM (I-Bus)      │  │ DTCM (D-Bus)     │ │
  │  │ 专用SRAM 0-cycle  │  │ 专用SRAM 0-cycle │ │
  │  └──────────────────┘  └─────────────────┘ │
  │           │                     │           │
  │           └──────┬──────────────┘           │
  │                  ▼                           │
  │         System Bus (AHB/AXI)                │
  │                  │                           │
  └──────────────────┼───────────────────────────┘
                     ▼
          ┌──────────────────┐
          │   Bus Matrix      │
          │  ┌────┬────┬────┐ │
          │  │Flash│SRAM│外设│ │  ← 这些走总线，有延迟、可能冲突
          │  └────┴────┴────┘ │
          └──────────────────┘
```

### TCM 的两个变种

| 类型 | 全称 | 用途 | 典型容量 |
|------|------|------|:--------:|
| **ITCM** | Instruction TCM | 存关键代码（ISR、DSP 循环、RTOS 内核） | 4KB – 64KB |
| **DTCM** | Data TCM | 存关键数据（栈、RTOS TCB、DSP 系数表） | 4KB – 64KB |

### TCM vs Cache vs 普通 SRAM

| 特性 | TCM | Cache | 挂在总线上的 SRAM |
|------|:---:|:-----:|:-----------------:|
| **延迟** | 固定 1 cycle | 命中 1 cycle / Miss 几十 cycle | 可变（受总线仲裁影响） |
| **确定性** | ✅ 完全确定 | ❌ Cache Miss 不可预测 | ❌ 可能被 DMA/其他 Master 阻塞 |
| **实时性** | 适合硬实时 | 不适合硬实时 | 部分适合 |
| **地址空间** | 独立的物理地址段 | 透明，对软件不可见 | 普通的物理地址段 |
| **软件控制** | 程序员手动放数据 | 硬件自动管理 | 程序员手动放数据 |
| **跟 BRAM 的关系** | BRAM 是实现载体 | 也可用 BRAM 实现 tag+data | BRAM 是实现载体 |

### TCM 不是 BRAM，BRAM 不是 TCM

```
TCM = 架构概念 = "CPU 旁边直接挂一块存储器"
BRAM = 物理载体 = "FPGA 上那块硬核 SRAM 用来实现它"

TCM 可以用 BRAM 实现  ——  FPGA SoC 上最常见的方式
TCM 也可以用 ASIC SRAM 实现  ——  商业 MCU（STM32、GD32）的做法
TCM 甚至可以用 Distributed RAM 实现  ——  你的 FX-RV32 现在就是这样
```

一句话：**BRAM 是 FPGA 上的砖，TCM 是用这些砖（或其他砖）在 CPU 旁边搭的一个快取房。**

---

## FX-RV32 的 TCM 视角分析

### 你已经有 TCM 了——只是没这么叫

用 ARM TCM 的定义来衡量 FX-RV32：

| TCM 特征 | FX-RV32 实现 | 匹配？ |
|----------|-------------|:-----:|
| 指令存储直连 CPU，不经总线 | `inst_rom` 直连 IF — IF 绕过 bus_arbiter | ✅ |
| 数据存储直连 CPU，不经总线 | `data_ram` 经 bus_arbiter，但在 0x0000_0000 有最高优先级 | ⚠️ 半匹配 |
| 固定延迟 | inst_rom 组合逻辑 0-cycle，data_ram 组合逻辑 0-cycle | ✅ |
| 独立地址空间 | 0x0000_0000 – 0x0000_FFFF（RAM 段） | ✅ |
| 软件可控放置 | 汇编/链接器指定 `.text` 到 0x0，`.data` 到 0x100 | ✅ |

```
你的 FX-RV32 存储架构（用 TCM 术语描述）

    FX-RV32 Core
    ┌──────────────────────────┐
    │  IF ────→ inst_rom (4KB) │  ← 实质上是 ITCM
    │               │           │     (Distributed RAM 物理实现)
    │               ▼           │
    │          指令进入流水线     │
    │                           │
    │  MEM ──→ bus_arbiter ──→  │
    │           │    │    │     │
    │           ▼    ▼    ▼     │
    │        RAM  UART  GPIO... │  ← RAM 部分 ≈ DTCM
    │       (4KB)               │     (Distributed RAM 物理实现)
    └──────────────────────────┘
```

### 论文里怎么写

如果你在做论文的存储子系统分析，可以使用业界通用术语来提升专业度：

> *"FX-RV32 integrates Tightly Coupled Memories (TCMs) for both instructions and data, providing single-cycle deterministic access. The 4KB ITCM and 4KB DTCM are implemented using FPGA logic resources (Distributed RAM) at the current prototype stage, with a clear migration path to Block RAM for larger configurations. The TCM architecture eliminates cache miss penalties and bus contention, ensuring hard real-time predictability critical for embedded control applications."*

### 什么时候考虑把 TCM 换成 BRAM 实现

| 触发条件 | 原因 |
|----------|------|
| data_ram 扩展到 16KB 以上 | Distributed RAM 的 LUT 消耗开始显著（>2% LUT） |
| 需要降低功耗 | BRAM 的功耗远低于等量 Distributed RAM |
| 需要为其他逻辑腾 LUT | BRAM 释放的 LUT 可用于加速器或更大的 ALU |
| 上板跑 CoreMark/benchmark | BRAM 有足够空间放更大的 benchmark 程序 |

---

## 参考资料

- Xilinx UG473 — 7 Series FPGAs Memory Resources User Guide
- Xilinx UG953 — Vivado Design Suite 7 Series FPGA Libraries Guide (BRAM primitives: `RAMB36E1`, `RAMB18E1`)
- ARM Cortex-M3/M4 Technical Reference Manual — TCM interface chapters
- 本项目的存储模块源码: `soc/mem/inst_rom.v`, `soc/mem/data_ram.v`

---

*Document created for FX-RV32 project. Author: Yi Fengxin, Beihang University.*
