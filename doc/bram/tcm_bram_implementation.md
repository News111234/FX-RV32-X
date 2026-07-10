# TCM 用 BRAM 实现：从架构到 Vivado 识别

> FX-RV32 ITCM/DTCM BRAM 实现完整指南 | 2026-06-17

---

## 目录

1. [前置概念：TCM 和 BRAM 的分工](#前置概念tcm-和-bram-的分工)
2. [FX-RV32 当前的存储架构](#fx-rv32-当前的存储架构)
3. [目标架构：真正的 TCM + BRAM 实现](#目标架构真正的-tcm--bram-实现)
4. [ITCM 模块：BRAM 指令存储器](#itcm-模块bram-指令存储器)
5. [DTCM 模块：BRAM 数据紧耦合存储器](#dtcm-模块bram-数据紧耦合存储器)
6. [SoC 集成：把 ITCM/DTCM 接入 FX-RV32](#soc-集成把-itcmdtcm-接入-fx-rv32)
7. [Vivado 如何识别为 BRAM](#vivado-如何识别为-bram)
8. [验证与确认](#验证与确认)

---

## 前置概念：TCM 和 BRAM 的分工

在开始写代码之前，先把两个概念的位置摆清楚：

```
抽象层级:
  ┌──────────────────────────────────────────────┐
  │  TCM (Tightly Coupled Memory)                │
  │  "CPU 旁边直接挂一块存储器"                      │
  │  是一个 架构 概念——描述的是 怎么连接、怎么用       │
  │  ├── ITCM: 存指令，直连取指单元                   │
  │  └── DTCM: 存数据，直连 Load/Store 单元          │
  └──────────────────────────────────────────────┘
                        │
                        │ 在 FPGA 上用什么实现？
                        ▼
  ┌──────────────────────────────────────────────┐
  │  BRAM (Block RAM)                            │
  │  FPGA 芯片上的硬核 SRAM 宏单元                    │
  │  是一个 物理 概念——描述的是 用什么电路资源          │
  └──────────────────────────────────────────────┘

TCM 是需求，BRAM 是实现。
你的 Verilog 代码（怎么描述读写时序）决定 Vivado 把它映射成什么。
你的 SoC 连线（怎么把存储器挂到 CPU 上）决定它是不是 TCM。
```

### 一条指令的旅程：TCM 视角

```
非 TCM（经过总线）:
  CPU → Bus Request → Arbiter 仲裁 → 总线传输 → SRAM → 原路返回
  延迟: 不确定（可能被其他 Master 阻塞）

TCM:
  CPU → 直接一根线过去 → SRAM → 直接一根线回来
  延迟: 固定 1 cycle（BRAM 同步读）或 0 cycle（Distributed RAM 组合读）
```

---

## FX-RV32 当前的存储架构

从 `soc/top/soc_top.v` 可以看到当前的连接方式：

```verilog
// ===== 指令路径（第 135-138 行）=====
inst_rom u_inst_rom (
    .addr_i (core_if_pc),        // IF 阶段的 PC 直接连到 ROM
    .data_o (core_if_instr)      // ROM 输出直接连回 CPU 的指令输入
);
// → 这已经是 ITCM 的连接方式！但没有 clk，是 Distributed RAM。

// ===== 数据路径（第 143-176 行）=====
data_ram u_data_ram (
    .clk_i   (clk_i),
    .addr_i  (bus_ram_addr),     // ← 经过 bus_arbiter
    .rdata_o (bus_ram_rdata),    // ← 经过 bus_arbiter 回到 CPU
    // ...
);

bus_arbiter u_bus_arbiter (
    .mem_addr_i  (core_bus_addr), // CPU 的总线请求先到仲裁器
    .ram_addr_o  (bus_ram_addr),  // 仲裁器再转发给 data_ram
    // ...
);
// → 数据通路经过了 bus_arbiter。有仲裁就有延迟不确定性。
//   虽然 bus_arbiter 对 RAM 访问通常不阻塞，但它不是严格的 TCM 直连。
```

### 当前状态总结

| | ITCM（指令） | DTCM（数据） |
|---|---|---|
| **连接方式** | 直连 CPU IF 端口 ✅ | 经过 bus_arbiter ❌（不是严格 TCM） |
| **物理实现** | Distributed RAM ❌ | Distributed RAM ❌ |
| **读延迟** | 0 cycle（组合） | 0 cycle（组合） |

---

## 目标架构：真正的 TCM + BRAM 实现

```
                FX-RV32 Core
  ┌─────────────────────────────────────────────┐
  │                                              │
  │  ┌──────┐     ┌──────────────────────────┐  │
  │  │  IF  │────→│  ITCM (BRAM, 同步读)      │  │
  │  │      │←────│  4KB, 1-cycle read latency │  │
  │  └──────┘     └──────────────────────────┘  │
  │                                              │
  │  ┌──────┐     ┌──────────────────────────┐  │
  │  │ MEM  │────→│  DTCM (BRAM, 同步读)      │  │
  │  │(LSU) │←────│  4KB, 1-cycle read latency │  │
  │  └──────┘     └──────────────────────────┘  │
  │       │                                      │
  │       │  (地址 >= DTCM 范围时)                 │
  │       ▼                                      │
  │  ┌──────────────────────────────────────┐   │
  │  │  Bus Arbiter → UART/GPIO/Timer/...   │   │
  │  └──────────────────────────────────────┘   │
  └─────────────────────────────────────────────┘
```

关键改动：
1. **ITCM**：`inst_rom` 增加 clk 端口，改为同步读 → Vivado 推断为 BRAM
2. **DTCM**：`data_ram` 从 `bus_arbiter` 后面挪到 CPU 直连 → 真正的 DTCM + 同步读 → Vivado 推断为 BRAM
3. CPU 的 LSU（MEM 阶段）在访问地址落在 DTCM 范围内时直连 DTCM，超出范围时走 bus_arbiter 访问外设

---

## ITCM 模块：BRAM 指令存储器

### 完整 Verilog 代码

```verilog
// soc/mem/itcm_bram.v — BRAM-based Instruction TCM
//
// 功能：
//   - 存储 CPU 指令（上电时从 initial 块或 hex 文件初始化）
//   - 同步读（1 cycle latency），Vivado 推断为 BRAM
//   - 直接连接 CPU 的 IF 阶段，不经过总线仲裁器
//
// TCM 特性：
//   - 固定 1-cycle 读延迟（BRAM 物理特性）
//   - 无总线竞争，无仲裁延迟
//   - 独占 CPU 取指接口
//
// Vivado BRAM 推断关键点：
//   ① always @(posedge clk_i) — 同步读
//   ② (* ram_style = "block" *) — 显式属性
//   ③ 无 DONT_TOUCH — 允许 Vivado 优化/重映射
//   ④ 无地址越界检查 — 纯 BRAM 阵列

module itcm_bram #(
    parameter DEPTH = 1024,          // 1024 words = 4KB
    parameter INIT_FILE = ""         // 可选：从 hex 文件加载程序
) (
    input  wire        clk_i,        // 时钟（必须，BRAM 要求）
    input  wire        en_i,         // 使能（高有效，接 1'b1 表示常使能）
    input  wire [31:0] addr_i,       // 字节地址，取 addr_i[31:2] 为字地址
    output wire [31:0] instr_o       // 指令输出（1 cycle 后有效）
);

    // ================================================================
    // BRAM 阵列
    // ================================================================
    (* ram_style = "block" *)        // 显式告诉 Vivado：用 Block RAM
    reg [31:0] bram [0:DEPTH-1];

    // ================================================================
    // 输出寄存器（这是 BRAM 输出端寄存器的 RTL 建模）
    // ================================================================
    reg [31:0] instr_r;

    // ================================================================
    // 初始化程序内容
    // ================================================================
    integer i;
    initial begin
        // 方式一：全部填充 NOP
        for (i = 0; i < DEPTH; i = i + 1)
            bram[i] = 32'h00000013;      // NOP

        // 方式二：从文件加载（二选一）
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, bram);

        // 方式三：逐条赋值（当前 inst_rom.v 的方式）
        // bram[0]  = 32'h100010b7;
        // bram[1]  = 32'h00c08093;
        // ...
    end

    // ================================================================
    // 同步读 —— 这是 BRAM 推断的 核心
    // ================================================================
    always @(posedge clk_i) begin
        if (en_i)
            instr_r <= bram[addr_i[31:2]];
    end

    assign instr_o = instr_r;

endmodule
```

### 时序行为

```
cycle N:   addr_i 给出 PC ──→ BRAM 内部锁存地址
cycle N+1: instr_o 输出对应指令
           ↑
           └── 这 1 cycle 延迟被 IF/ID 流水线寄存器自然吸收

IF 阶段原有流水线:
  PC → (IF stage) → IF/ID register → ID stage
       ↑                              ↑
       组合逻辑读取 inst_rom           指令在这里被使用

BRAM ITCM 下的流水线:
  PC → (IF stage) → IF/ID register → ID stage
       ↑                              ↑
       BRAM 在这里接收地址             BRAM 的数据刚好在这一拍稳定
       下一条指令在这里锁存             (IF/ID 寄存器正好吸收 1 cycle)
```

---

## DTCM 模块：BRAM 数据紧耦合存储器

### 完整 Verilog 代码

```verilog
// soc/mem/dtcm_bram.v — BRAM-based Data TCM
//
// 功能：
//   - 紧耦合数据存储器，直连 CPU LSU
//   - 支持 SB/SH/SW 写，LB/LH/LW/LBU/LHU 读
//   - 同步读写（1 cycle read latency），Vivado 推断为 BRAM
//   - 地址落在 TCM 范围外时，CPU 应转而访问总线外设
//
// TCM 特性：
//   - 固定 1-cycle 读延迟（BRAM 物理特性）+ 1 cycle 字节提取
//   - 无总线仲裁：CPU 发出地址 → 固定 2 cycles 后数据回到 WB
//   - 与传统 Cache 不同：程序员显式控制 TCM 地址空间的代码/数据放置
//
// 架构：拆为两层
//   Layer 1: BRAM（整字同步读写，always @posedge）
//   Layer 2: 字节提取 + 符号扩展（组合逻辑，LUT）
//
// Vivado BRAM 推断关键点：
//   ① 读和写在 同一个 always @(posedge clk_i) 块内
//   ② 读用非阻塞赋值 mem_read_raw <= mem[addr]
//   ③ (* ram_style = "block" *) 显式约束
//   ④ 字节使能写 mem[addr][7:0] <= din[7:0] 这种形式 Vivado 能识别

module dtcm_bram #(
    parameter DEPTH = 1024           // 1024 words = 4KB
) (
    input  wire        clk_i,
    input  wire        rst_n_i,

    // ---- 控制信号 ----
    input  wire        we_i,         // 写使能
    input  wire        re_i,         // 读使能
    input  wire [2:0]  width_i,      // 访问宽度: 000=byte, 001=half, 010=word
    input  wire [31:0] addr_i,       // 字节地址
    input  wire [31:0] wdata_i,      // 写数据

    // ---- 输出 ----
    output wire [31:0] rdata_o,      // 读数据（含符号扩展）
    output wire        ready_o       // 就绪信号
);

    // ================================================================
    // Layer 1: BRAM 阵列 + 同步读写
    // ================================================================
    (* ram_style = "block" *)
    reg [31:0] bram [0:DEPTH-1];

    // BRAM 输出寄存器
    reg [31:0] mem_read_raw;         // 从 BRAM 读出的原始 32-bit 字（1 cycle 延迟）
    reg        read_valid;           // 标记 mem_read_raw 是否有效

    // 地址/宽度锁存 —— 必须锁存因为 rdata 比 addr 晚 1 cycle
    reg [2:0]  width_r;
    reg [1:0]  addr_low_r;

    // ================================================================
    // 单 always 块：读 + 写
    // Vivado 会识别为 Read-before-Write 单端口 BRAM
    // ================================================================
    always @(posedge clk_i) begin
        if (!rst_n_i) begin
            mem_read_raw <= 32'b0;
            read_valid   <= 1'b0;
            width_r      <= 3'b0;
            addr_low_r   <= 2'b0;
        end else begin
            // === 写操作 ===
            if (we_i) begin
                case (width_i)
                    3'b000: begin // SB
                        case (addr_i[1:0])
                            2'b00: bram[addr_i[31:2]][ 7: 0] <= wdata_i[ 7:0];
                            2'b01: bram[addr_i[31:2]][15: 8] <= wdata_i[ 7:0];
                            2'b10: bram[addr_i[31:2]][23:16] <= wdata_i[ 7:0];
                            2'b11: bram[addr_i[31:2]][31:24] <= wdata_i[ 7:0];
                        endcase
                    end
                    3'b001: begin // SH
                        case (addr_i[1])
                            1'b0: bram[addr_i[31:2]][15:0]  <= wdata_i[15:0];
                            1'b1: bram[addr_i[31:2]][31:16] <= wdata_i[15:0];
                        endcase
                    end
                    3'b010: bram[addr_i[31:2]] <= wdata_i; // SW
                    default: ;
                endcase
            end

            // === 读操作（同步）===
            if (re_i) begin
                mem_read_raw <= bram[addr_i[31:2]];   // ← 这一拍给 addr，下一拍才有效
                read_valid   <= 1'b1;
                width_r      <= width_i;
                addr_low_r   <= addr_i[1:0];
            end else begin
                read_valid   <= 1'b0;
            end
        end
    end

    // ================================================================
    // Layer 2: 字节/半字提取 + 符号扩展（组合逻辑，在 BRAM 外部）
    //
    // 这部分用 LUT 实现，消耗约 30-50 个 LUT。
    // 对比：不用 BRAM 时整个 data_ram 都是 LUT → 约 512 LUT。
    // ================================================================
    reg [31:0] rdata_ext;

    always @(*) begin
        if (read_valid) begin
            case (width_r)
                // 有符号加载
                3'b000: begin // LB
                    case (addr_low_r)
                        2'b00: rdata_ext = {{24{mem_read_raw[ 7]}}, mem_read_raw[ 7:0]};
                        2'b01: rdata_ext = {{24{mem_read_raw[15]}}, mem_read_raw[15:8]};
                        2'b10: rdata_ext = {{24{mem_read_raw[23]}}, mem_read_raw[23:16]};
                        2'b11: rdata_ext = {{24{mem_read_raw[31]}}, mem_read_raw[31:24]};
                    endcase
                end
                3'b001: begin // LH
                    case (addr_low_r[1])
                        1'b0: rdata_ext = {{16{mem_read_raw[15]}}, mem_read_raw[15:0]};
                        1'b1: rdata_ext = {{16{mem_read_raw[31]}}, mem_read_raw[31:16]};
                    endcase
                end
                3'b010: rdata_ext = mem_read_raw; // LW

                // 无符号加载
                3'b100: begin // LBU
                    case (addr_low_r)
                        2'b00: rdata_ext = {24'b0, mem_read_raw[ 7:0]};
                        2'b01: rdata_ext = {24'b0, mem_read_raw[15:8]};
                        2'b10: rdata_ext = {24'b0, mem_read_raw[23:16]};
                        2'b11: rdata_ext = {24'b0, mem_read_raw[31:24]};
                    endcase
                end
                3'b101: begin // LHU
                    case (addr_low_r[1])
                        1'b0: rdata_ext = {16'b0, mem_read_raw[15:0]};
                        1'b1: rdata_ext = {16'b0, mem_read_raw[31:16]};
                    endcase
                end
                default: rdata_ext = 32'b0;
            endcase
        end else begin
            rdata_ext = 32'b0;
        end
    end

    assign rdata_o = rdata_ext;
    assign ready_o = 1'b1;

endmodule
```

### 时序行为

```
Load 指令的时序（BRAM DTCM）:
  cycle N:   EX 阶段计算地址 → MEM 阶段发 re_i=1, addr_i
             BRAM 接收读地址
  cycle N+1: mem_read_raw 有效（BRAM 输出寄存器更新）
             Layer 2 组合逻辑提取字节/半字
             rdata_o 有效
  cycle N+2: WB 阶段写入寄存器

对比原来的 Distributed RAM DTCM:
  cycle N:   EX 计算地址 → MEM 发 re_i=1 → rdata_o 组合有效 → MEM/WB 捕获
  cycle N+1: WB 阶段写入寄存器

结论: BRAM DTCM 增加 1 cycle load latency。
     对这额外 1 cycle 的处理见下文"对流水线的影响"。
```

---

## SoC 集成：把 ITCM/DTCM 接入 FX-RV32

### 方案一：最小改动（只改存储器内部，不改连线）

如果你不想改 `core_top` 的端口和 `soc_top` 的连线结构，只是想把 Distributed RAM 替换成 BRAM：

```verilog
// soc/top/soc_top.v 中的改动

// ===== ITCM: inst_rom 替换为 itcm_bram =====
// 原来:
//   inst_rom u_inst_rom (
//       .addr_i (core_if_pc),
//       .data_o (core_if_instr)
//   );
//
// 改为:
itcm_bram #(
    .DEPTH(1024)
) u_itcm (
    .clk_i   (clk_i),
    .en_i    (1'b1),              // 常使能
    .addr_i  (core_if_pc),
    .instr_o (core_if_instr)
);

// ===== DTCM: data_ram 替换为 dtcm_bram（仍在 bus_arbiter 后面）=====
// 原来:
//   data_ram u_data_ram (
//       .clk_i   (clk_i),
//       ...
//   );
//
// 改为:
dtcm_bram #(
    .DEPTH(16384)                 // 可扩展到 64KB
) u_dtcm (
    .clk_i   (clk_i),
    .rst_n_i (rst_n_i),
    .we_i    (bus_ram_we),
    .re_i    (bus_ram_re),
    .width_i (bus_ram_width),
    .addr_i  (bus_ram_addr),
    .wdata_i (bus_ram_wdata),
    .rdata_o (bus_ram_rdata),
    .ready_o (bus_ram_ready)
);
```

> 注意：方案一中 DTCM 仍在 bus_arbiter 后面，**不是严格的 TCM**（有仲裁延迟）。但如果 bus_arbiter 对 RAM 范围总是直通（不与非 RAM Master 共享），则行为上近似 TCM。

### 方案二：真正的 TCM（DTCM 绕过总线仲裁器）

这是 **架构层面的改动**——让 CPU 的 LSU 直接区分 TCM 地址和外设地址：

```verilog
// soc/top/soc_top.v — TCM 架构的 SoC 集成

// ===== ITCM: 直连 IF（与原来 inst_rom 的连接方式一致）=====
itcm_bram #(.DEPTH(1024)) u_itcm (
    .clk_i   (clk_i),
    .en_i    (1'b1),
    .addr_i  (core_if_pc),
    .instr_o (core_if_instr)
);

// ===== DTCM: 直连 CPU LSU，不经过 bus_arbiter =====
//
// 地址译码逻辑（组合逻辑）:
//   DTCM 范围: 0x0000_0000 ~ 0x0000_0FFF (4KB)
//   在此范围内 → DTCM 直连，固定延迟
//   在此范围外 → bus_arbiter → 外设

wire        tcm_access;           // 当前访问是否落在 DTCM 范围
wire [31:0] dtcm_rdata;
wire        dtcm_ready;

// DTCM 地址范围: 0x0000_0000 - 0x0000_0FFF (= 4KB)
assign tcm_access = (core_bus_addr < 32'h00001000);

// DTCM 直连
dtcm_bram #(.DEPTH(1024)) u_dtcm (
    .clk_i   (clk_i),
    .rst_n_i (rst_n_i),
    .we_i    (core_bus_we  & tcm_access),
    .re_i    (core_bus_re  & tcm_access),
    .width_i (core_bus_width),
    .addr_i  (core_bus_addr),
    .wdata_i (core_bus_wdata),
    .rdata_o (dtcm_rdata),
    .ready_o (dtcm_ready)
);

// 总线仲裁器（只处理外设访问）
bus_arbiter u_bus_arbiter (
    .clk_i          (clk_i),
    .rst_n_i        (rst_n_i),
    // CPU 侧——只在外设地址时有效
    .mem_re_i       (core_bus_re  & ~tcm_access),
    .mem_we_i       (core_bus_we  & ~tcm_access),
    .mem_addr_i     (core_bus_addr),
    .mem_wdata_i    (core_bus_wdata),
    .mem_width_i    (core_bus_width),
    .mem_rdata_o    (core_bus_rdata),
    .mem_ready_o    (core_bus_ready),
    // 外设侧——不变
    // ...
);

// TCM 返回数据 MUX
// 当 DTCM 有响应时用 DTCM 数据，否则等 bus_arbiter
```

> 方案二的改动量更大，需要确保 `core_top` 的 bus 接口在 TCM hit 和 TCM miss 两种情况下都能正确处理返回数据。

---

## Vivado 如何识别为 BRAM

### 推断条件速查表

| 条件 | ITCM | DTCM | 说明 |
|------|:----:|:----:|------|
| `always @(posedge clk)` | ✅ | ✅ | 读写必须都在时序块内 |
| 读写在同一 always 块 | N/A（只读） | ✅ | 单端口 BRAM 要求；SDP 可分开 |
| 输出用 `<=` 非阻塞赋值 | ✅ | ✅ | 建模 BRAM 输出寄存器 |
| `(* ram_style = "block" *)` | ✅ | ✅ | 显式约束，放在 reg 数组声明前 |
| 无 `(* DONT_TOUCH *)` | ✅ | ✅ | 这个属性阻止优化 |
| 地址简单（无越界 if-else） | ✅ | ✅ | BRAM 阵列之外可以有 MUX，但阵列本身要干净 |
| 字节使能 `mem[addr][7:0] <= din[7:0]` | N/A | ✅ | Vivado 能识别 byte-write 模式并映射到 BRAM WE 引脚 |
| 深度/宽度在 BRAM 范围内 | ✅ | ✅ | 7-series: ≤36Kb/tile, 深度×宽度 ≤ 36Kb |

### Vivado 推断的完整流程

```
Verilog 代码
    │
    ▼
Vivado Synthesis (synth_design)
    │
    ├── 检测 reg 数组声明上的 (* ram_style = "block" *)
    │
    ├── 分析 always 块的读写模式
    │   ├── 同步读 + 同步写（同一 always 块）→ 候选 BRAM
    │   ├── 同步写 + 组合读 → 候选 Distributed RAM
    │   └── 只有组合读 → 候选 ROM（仍可以是 BRAM ROM）
    │
    ├── 检查深度 × 宽度是否 > 阈值（Vivado 默认 > 2Kb 优选用 BRAM）
    │
    ├── 如果可以映射到 RAMB36E1/RAMB18E1 原语 → 推断为 BRAM
    │   └── 对应日志: "INFO: [Synth 8-4480] RAM <bram> is being modeled as a Block RAM"
    │
    └── 如果不满足条件 → 推断为 Distributed RAM
        └── 对应日志: "INFO: [Synth 8-4480] RAM <mem> is being modeled as a Distributed RAM"
```

### 综合后的网表结构

推断成功后，Vivado 会在综合网表中生成类似这样的原语实例：

```
ITCM (1024×32 ROM):
  RAMB36E1 #(
    .READ_WIDTH_A(36),      // 36-bit 模式，高 4 bit 不用
    .WRITE_WIDTH_A(36),
    .RAM_MODE("ROM"),       // 或 "TDP" 用于简单双端口
    .INIT_FILE("...")       // 来自 initial 块的初始化数据
  ) u_itcm_bram_inst (...);

DTCM (1024×32 RAM with byte write):
  RAMB36E1 #(
    .READ_WIDTH_A(36),
    .WRITE_WIDTH_A(36),
    .WRITE_MODE_A("READ_FIRST"),  // Read-before-Write
    .BYTE_SIZE(8),                // 字节使能粒度
    .BYTE_WRITE_ENABLE(4)         // 4 条字节使能线
  ) u_dtcm_bram_inst (...);
```

### 如果推断失败——排查清单

| 现象 | 可能原因 | 检查方法 |
|------|---------|---------|
| 综合日志显示 "Distributed RAM" | 读是组合逻辑 | 确认 `always @(posedge clk)` |
| 资源报告里全是 LUT | 没有 `ram_style` 属性或属性位置不对 | 确认属性在 `reg ... bram [0:N-1]` 声明前 |
| BRAM 推断出来但读数据不对 | 时序：addr 和 data 差了 1 cycle | 检查流水线是否适应了这 1 cycle 延迟 |
| 多个 BRAM tile 被消耗 | 宽度/深度不匹配导致拆分 | 报告 `report_ram_utilization` 看实际用了几个 tile |

---

## 验证与确认

### 综合阶段检查

在 Vivado Tcl Console 中执行：

```tcl
# 1. 打开综合后的设计
open_run synth_1

# 2. 查看 BRAM 使用情况
report_ram_utilization
# 期望输出:
#   Block RAM: 2 (ITCM 1 tile + DTCM 1 tile)
#   Distributed RAM: 0

# 3. 查看具体模块用了什么
report_utilization -cells [get_cells u_itcm]
report_utilization -cells [get_cells u_dtcm]

# 4. 在综合日志中搜索
# 在 Vivado Messages 窗口搜索 "RAM"
# 期望看到:
#   "RAM <bram_reg> is being modeled as a Block RAM"

# 5. 如果推断为 Distributed RAM，查看原因
# 搜索 Vivado 日志中的 "RAM" 相关 WARNING
```

### 实现阶段检查

```tcl
# 实现后检查 BRAM 的物理位置和时序
open_run impl_1

# BRAM 位置
report_ram_utilization -detail

# BRAM 时序
report_timing -from [get_cells u_itcm/*] -to [get_cells ...]

# BRAM 功耗
report_power
```

### 用 Schematic 可视化确认

打开综合后的 Schematic（GUI 操作）：
1. Flow Navigator → Synthesis → Open Synthesized Design → Schematic
2. 找到 `u_itcm` 或 `u_dtcm` 模块
3. 如果看到 `RAMB36E1` 原语符号 → BRAM 推断成功
4. 如果看到一大堆 LUT 和 MUX → 推断失败，仍是 Distributed RAM

---

## 附录：ITCM/DTCM 地址空间划分建议

```
FX-RV32 内存映射（TCM 架构版本）:

  ┌─────────────────────────┐ 0xFFFF_FFFF
  │       未使用              │
  ├─────────────────────────┤ 0x1000_5000
  │  I2C       (4KB)        │ ← bus_arbiter
  │  SPI       (4KB)        │ ← bus_arbiter
  │  Timer     (4KB)        │ ← bus_arbiter
  │  GPIO      (4KB)        │ ← bus_arbiter
  │  UART      (4KB)        │ ← bus_arbiter
  ├─────────────────────────┤ 0x1000_0000
  │       未使用              │
  ├─────────────────────────┤ 0x0000_2000 (8KB)
  │  DTCM 扩展区（可选）      │
  ├─────────────────────────┤ 0x0000_1000 (4KB)
  │  DTCM      (4KB)        │ ← 直连 LSU，固定延迟
  ├─────────────────────────┤ 0x0000_0000
  │
  │  ITCM 的地址也是 0x0000_0000 开始，但走独立的指令总线
  │  与 DTCM 不冲突（哈佛架构：I-Bus 和 D-Bus 分离）
```

---

*Document created for FX-RV32 project. Author: Yi Fengxin, Beihang University.*
