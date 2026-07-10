# Vivado BRAM 推断指南：为什么当前代码不被识别为 BRAM 以及如何修改

> FX-RV32 存储模块 BRAM 化参考文档 | 2026-06-17

---

## 目录

1. [结论先行](#结论先行)
2. [Xilinx BRAM 硬核的物理约束](#xilinx-bram-硬核的物理约束)
3. [inst_rom.v 分析](#inst_romv-分析)
4. [data_ram.v 分析](#data_ramv-分析)
5. [修改方案：inst_rom.v](#修改方案inst_romv)
6. [修改方案：data_ram.v](#修改方案data_ramv)
7. [对流水线的影响](#对流水线的影响)

---

## 结论先行

**Vivado 不推断 BRAM 的根本原因：读操作使用了组合逻辑（`always @(*)`）。**

Xilinx BRAM 硬核（`RAMB36E1`）的输出端在物理上有一个必选的寄存器。数据从 SRAM 存储阵列读出后必须经过这个寄存器才能到达输出端口。`always @(*)` 要求地址一变、输出立刻跟着变——等于要求信号绕过那个寄存器，这在物理上不可能。

```
BRAM 硬核内部结构（简化）:

  addr ──→ [SRAM 存储阵列] ──→ [Output Register] ──→ dout
                                 ↑
                             clk (posedge)

把 BRAM 想象成一个自带输出寄存器的同步 SRAM。
这个寄存器不是"可选"的——它是 BRAM tile 物理结构的一部分。
因此任何组合逻辑读取模式都无法映射到 BRAM。
```

除此之外，两个模块各自的代码中还有一些辅助性的阻断因素，下面逐一分析。

---

## Xilinx BRAM 硬核的物理约束

### Vivado 推断 BRAM 的必要条件

| 条件 | 说明 |
|------|------|
| **读必须是同步的** | 读写必须在 `always @(posedge clk)` 中。单端口 RAM 要求读写合并在**同一个** always 块中 |
| **输出必须是 reg** | BRAM 的输出寄存器对应 Verilog 的 `reg` 类型，在 always 块中用 `<=` 非阻塞赋值 |
| **数组尺寸在 BRAM 容量范围内** | 7-series 一个 BRAM tile 为 36Kb。1024×32b = 32Kb，刚好一块容纳 |
| **无 `DONT_TOUCH` 等阻止优化的属性** | `(* DONT_TOUCH = "true" *)` 会告诉 Vivado "不要动这个模块"，可能阻止 BRAM 重映射 |

### Vivado 推断 BRAM 的有利条件（加分项，非必需）

| 条件 | 说明 |
|------|------|
| **`(* ram_style = "block" *)`** | 显式告诉 Vivado 优先用 Block RAM |
| **字节使能用 `we[3:0]` 形式** | `mem[addr][7:0] <= din[7:0]` 这样逐 byte 写，Vivado 能映射到 BRAM 的字节使能端口 |
| **读写地址分离** | 简单双端口（SDP）模式 BRAM 原生支持，推断成功率更高 |

---

## inst_rom.v 分析

### 当前代码（2026-06 版本）

```verilog
// soc/mem/inst_rom.v 关键代码段

(* DONT_TOUCH = "true" *)                           // ← 阻断因素 ③
module inst_rom #(parameter INST_DEPTH = 1024) (
    input  wire [31:0] addr_i,                      // ← 注意：没有 clk 端口
    output reg  [31:0] data_o
);
    reg [31:0] rom [0:INST_DEPTH-1];
    // ... initial 初始化 ...

    always @(*) begin                               // ← 阻断因素 ①【致命】
        if (addr_i[31:2] < INST_DEPTH) begin       // ← 阻断因素 ②
            data_o = rom[addr_i[31:2]];
        end else begin
            data_o = 32'h00000013;                  // ← 阻断因素 ② 续
        end
    end
endmodule
```

### 三个阻断因素详解

| # | 代码位置 | 问题 | 为什么阻止 BRAM |
|---|---------|------|----------------|
| ① | 第 58 行 `always @(*)` | **组合逻辑读** | BRAM 输出端必经过寄存器，组合逻辑读在物理上不可能映射到 `RAMB36E1` |
| ② | 第 59 行 `if (addr_i < DEPTH)` | **地址越界检查 + 默认值返回** | 这相当于在 BRAM 输出后加了一个 MUX（选择 `data` 还是 `NOP`），BRAM tile 内部没有这个 MUX。这本身不阻止 BRAM——Vivado 会把 MUX 放在 BRAM 外面——但它让代码模式离 BRAM 模板更远 |
| ③ | 第 3 行 `(* DONT_TOUCH = "true" *)` | **禁止优化属性** | 字面意思：告诉综合工具"别碰这个模块"。它能阻止 Vivado 把 reg 数组重映射为 BRAM 原语 |

### 阻断链条

```
always @(*) 组合读
    │
    └─→ Vivado 判断："这是异步读模式，无法映射到 BRAM"
            │
            └─→ 退化为 Distributed RAM（每个 bit 用一个 LUT 的 64-bit 深度 SRAM 拼出来）

加上 (* DONT_TOUCH = "true" *)
    │
    └─→ Vivado 进一步被限制，即使理论上能做部分优化也被告知不要动
```

---

## data_ram.v 分析

### 当前代码（2026-06 版本）

```verilog
// soc/mem/data_ram.v 关键代码段

module data_ram (
    input  wire        clk_i,       // ← 有 clk（但只用于写）
    input  wire        rst_n_i,
    input  wire        we_i,
    input  wire        re_i,
    input  wire [2:0]  width_i,
    input  wire [31:0] addr_i,
    input  wire [31:0] wdata_i,
    output reg  [31:0] rdata_o,
    output wire        ready_o
);
    reg [31:0] mem [0:DATA_DEPTH-1];

    // ======== 写操作（时序，第 69 行）========
    always @(posedge clk_i) begin           // ← 写是对的 ✅
        if (we_i && (addr_i[31:2] < DATA_DEPTH)) begin
            case (width_i)
                3'b000: // SB — 逐 byte 写
                3'b001: // SH — 逐 half 写
                3'b010: // SW — 整字写
            endcase
        end
    end

    // ======== 读操作（组合逻辑，第 100 行）========
    always @(*) begin                        // ← 阻断因素 ①【致命】
        if (re_i && (addr_i[31:2] < DATA_DEPTH)) begin
            case (width_i)
                3'b000: rdata_o = {{24{mem[addr][7]}}, mem[addr][7:0]};  // LB
                3'b001: rdata_o = {{16{mem[addr][15]}}, mem[addr][15:0]}; // LH
                3'b010: rdata_o = mem[addr];  // LW
                3'b100: rdata_o = {24'b0, mem[addr][7:0]};   // LBU
                3'b101: rdata_o = {16'b0, mem[addr][15:0]};  // LHU
            endcase
        end else begin
            rdata_o = 32'b0;                 // ← 阻断因素 ②
        end
    end
endmodule
```

### 阻断因素详解

| # | 代码位置 | 问题 | 为什么阻止 BRAM |
|---|---------|------|----------------|
| ① | 第 100 行 `always @(*)` | **组合逻辑读** | 同 inst_rom——BRAM 输出端必经过寄存器 |
| ② | 读写分在**两个 always 块** | **模板不匹配** | 单端口 BRAM 要求读和写在同一个 `always @(posedge clk)` 块内（Vivado 需要识别 Read-before-Write 或 Write-before-Read 模式） |
| ③ | `re_i` 门控 + 读无效时 `rdata_o = 0` | **额外 MUX** | BRAM 的 EN 引脚可以 disable 输出，但"输出归零"这个行为是额外 MUX，放在 BRAM 之外 |
| ④ | 读路径中的 `case(addr_i[1:0])` 做字节/半字选择 | **地址相关的数据选择** | 这些 MUX 在 BRAM tile 之外，本身不阻止 BRAM，但与组合读耦合后让代码模式与 BRAM 模板差距更大 |

### 为什么写是对的但整体仍然不被推断

写操作 `always @(posedge clk_i)` 本身是标准 BRAM 写模板。但 Vivado 综合考虑整个模块时，发现：

```
写路径: always @(posedge clk)  → BRAM 兼容 ✅
读路径: always @(*)            → 不兼容 ❌
        ↓
模块整体判定: 不推断 BRAM → 退化为 Distributed RAM
```

### 逻辑结构示意：当前代码 vs BRAM 模板

```
当前代码（Distributed RAM 实现）:
  addr ──→ [reg array / LUTRAM] ──→ [byte/half MUX] ──→ [sign-ext MUX] ──→ rdata_o
                                     (组合逻辑，0 cycle)

BRAM 模板要求的结构:
  addr ──→ [BRAM Array] ──→ [Output Reg] ──→ [byte/half MUX] ──→ [sign-ext MUX] ──→ rdata_o
                               ↑ posedge clk           (组合逻辑，BRAM 外部)
```

---

## 修改方案：inst_rom.v

### BRAM 可推断的写法

```verilog
// BRAM-based Instruction ROM
// 改动点标注为 ← NEW 或 ← CHANGED

// (* DONT_TOUCH = "true" *)    ← CHANGED: 移除，或用 ram_style 替代
module inst_rom #(
    parameter INST_DEPTH = 1024        // 1024 × 32-bit words = 4KB
) (
    input  wire         clk_i,         // ← NEW: 增加时钟输入
    input  wire [31:0]  addr_i,
    output reg  [31:0]  data_o
);

    (* ram_style = "block" *)          // ← NEW: 显式要求 BRAM
    reg [31:0] rom [0:INST_DEPTH-1];

    integer i;
    initial begin
        for (i = 0; i < INST_DEPTH; i = i + 1) begin
            rom[i] = 32'h00000013;     // 默认 NOP
        end
        // 程序内容（与原来完全一致）
        rom[0]  = 32'h100010b7;
        rom[1]  = 32'h00c08093;
        // ... 其余指令保持不变 ...
    end

    // ======== 核心改动：组合读 → 同步读 ========
    always @(posedge clk_i) begin      // ← CHANGED: always @(*) → always @(posedge clk_i)
        data_o <= rom[addr_i[31:2]];   // ← CHANGED: 阻塞赋值 → 非阻塞赋值
    end                                //   CHANGED: 去掉地址越界 if-else
                                       //   （越界保护在 inst_rom 外部处理，或依赖深度天然兜底）

endmodule
```

### 改动清单

| 改动 | 原因 |
|------|------|
| 增加 `clk_i` 端口 | BRAM 必须有时钟 |
| `always @(*)` → `always @(posedge clk_i)` | 满足 BRAM 同步读要求 |
| `data_o = ...` → `data_o <= ...` | 非阻塞赋值对应 BRAM 输出寄存器行为 |
| 去掉 `if (addr < DEPTH) ... else ...` | 边界检查 + 默认 NOP 是额外的 MUX，BRAM 做不了。要么在 inst_rom 外面做，要么靠深度兜底 |
| 去掉 `(* DONT_TOUCH *)`，加上 `(* ram_style = "block" *)` | 主动告诉 Vivado 我们要 BRAM |
| `initial` 块内容**完全不变** | Vivado 会将 initial 值写入 bitstream 作为 BRAM INIT 数据 |

---

## 修改方案：data_ram.v

data_ram 的修改比 inst_rom 复杂，因为需要保留字节/半字读写 + 符号扩展功能。

### 核心思路

```
原来的 data_ram 结构（单块，不可拆分，因为读写共享一个端口）:
  ┌────────────────────────────────────────────┐
  │  [reg array]  ← 写是时序、读是组合逻辑       │
  │  全部功能耦合在一个 always @(*) 中            │
  └────────────────────────────────────────────┘

修改后的结构（拆为两层）:
  ┌──────────────────┐
  │ Layer 1: BRAM    │  ← 纯同步读写，Vivado 推断为 BRAM
  │ 1024 × 32-bit    │  ← 只有整字读写，不管 byte/half
  │ (always @posedge)│  ← 输出经过寄存器，1 cycle 延迟
  └────────┬─────────┘
           │ mem_read_raw[31:0]（已寄存）
           ▼
  ┌──────────────────┐
  │ Layer 2: 提取层   │  ← 组合逻辑，用 LUT 实现
  │ byte/half 选择    │  ← 符号扩展 / 零扩展
  │ (always @*)      │  ← 这部分不能用 BRAM 做
  └──────────────────┘
           │
           ▼
        rdata_o
```

### BRAM 可推断的写法

```verilog
// BRAM-based Data RAM with byte/halfword support
//
// 架构: BRAM（整字同步读写）+ LUT（字节提取 + 符号扩展）
//
// 延迟特性:
//   旧版（Distributed RAM）：addr 给入 → 同一拍 rdata_o 有效（0 cycle）
//   新版（BRAM）          ：addr 给入 → 1 拍后 rdata_o 有效（1 cycle）
//
//   这个 +1 cycle 延迟需要上层 mem_ctrl 或流水线吸收

module data_ram (
    input  wire        clk_i,
    input  wire        rst_n_i,
    input  wire        we_i,
    input  wire        re_i,
    input  wire [2:0]  width_i,
    input  wire [31:0] addr_i,
    input  wire [31:0] wdata_i,
    output reg  [31:0] rdata_o,
    output wire        ready_o
);

    parameter DATA_DEPTH = 1024;

    // ================================================================
    // Layer 1: BRAM — 纯同步整字读写
    // ================================================================
    (* ram_style = "block" *)
    reg [31:0] mem [0:DATA_DEPTH-1];

    // ---- BRAM 输出寄存器 ----
    reg [31:0] mem_read_raw;        // 从 BRAM 读出的原始 32-bit 字（1 cycle 延迟后有效）
    reg        read_active;         // 标记当拍是否有有效读请求

    // ---- 写地址/数据暂存（用于 Read-before-Write 同一地址的 corner case）----
    // 实际上 Vivado BRAM 默认是 Read-before-Write，同一个 always 块内
    // 读 mem[addr] 先于写 mem[addr] <= din 执行，不需要额外处理。

    integer i;
    initial begin
        for (i = 0; i < DATA_DEPTH; i = i + 1)
            mem[i] = 32'h0;
        mem[0] = 32'h12345678;      // 测试数据（与原来一致）
        mem[1] = 32'h87654321;
    end

    // ---- 统一的同步读写块 ----
    always @(posedge clk_i) begin
        if (!rst_n_i) begin
            mem_read_raw <= 32'b0;
            read_active  <= 1'b0;
        end else begin
            // === 写操作（字节/半字/字）===
            if (we_i && (addr_i[31:2] < DATA_DEPTH)) begin
                case (width_i)
                    3'b000: begin // SB
                        case (addr_i[1:0])
                            2'b00: mem[addr_i[31:2]][ 7: 0] <= wdata_i[ 7:0];
                            2'b01: mem[addr_i[31:2]][15: 8] <= wdata_i[ 7:0];
                            2'b10: mem[addr_i[31:2]][23:16] <= wdata_i[ 7:0];
                            2'b11: mem[addr_i[31:2]][31:24] <= wdata_i[ 7:0];
                        endcase
                    end
                    3'b001: begin // SH
                        case (addr_i[1])
                            1'b0: mem[addr_i[31:2]][15:0]  <= wdata_i[15:0];
                            1'b1: mem[addr_i[31:2]][31:16] <= wdata_i[15:0];
                        endcase
                    end
                    3'b010: begin // SW
                        mem[addr_i[31:2]] <= wdata_i;
                    end
                endcase
            end

            // === 读操作（同步：这一拍给地址 → 下一拍 mem_read_raw 有效）===
            if (re_i && (addr_i[31:2] < DATA_DEPTH)) begin
                mem_read_raw <= mem[addr_i[31:2]];
                read_active  <= 1'b1;
            end else begin
                mem_read_raw <= 32'b0;
                read_active  <= 1'b0;
            end
        end
    end

    // ================================================================
    // Layer 2: 字节提取 + 符号扩展（组合逻辑，BRAM 外部）
    // ================================================================
    // 输入: mem_read_raw（来自 BRAM 输出寄存器）
    // 输出: rdata_o（含符号/零扩展的最终结果）
    //
    // 这部分逻辑消耗约 30-50 个 LUT，远小于 Distributed RAM 的 ~512 LUT

    wire [31:0] raw_word;
    wire        active;
    wire [2:0]  rd_width;
    wire [1:0]  rd_byte_offset;

    // 需要在读请求发出的那一拍锁存 width_i 和 addr_i[1:0]
    // 因为 mem_read_raw 是 1 cycle 后才有效的，那时 width_i/addr_i 可能已变化
    reg [2:0]  width_r;
    reg [1:0]  addr_low_r;

    always @(posedge clk_i) begin
        if (re_i && (addr_i[31:2] < DATA_DEPTH)) begin
            width_r    <= width_i;
            addr_low_r <= addr_i[1:0];
        end
    end

    assign raw_word       = mem_read_raw;
    assign active         = read_active;
    assign rd_width       = width_r;
    assign rd_byte_offset = addr_low_r;

    always @(*) begin
        if (active) begin
            case (rd_width)
                // ---- 有符号加载 ----
                3'b000: begin // LB
                    case (rd_byte_offset)
                        2'b00: rdata_o = {{24{raw_word[ 7]}}, raw_word[ 7:0]};
                        2'b01: rdata_o = {{24{raw_word[15]}}, raw_word[15:8]};
                        2'b10: rdata_o = {{24{raw_word[23]}}, raw_word[23:16]};
                        2'b11: rdata_o = {{24{raw_word[31]}}, raw_word[31:24]};
                    endcase
                end
                3'b001: begin // LH
                    case (rd_byte_offset[1])
                        1'b0: rdata_o = {{16{raw_word[15]}}, raw_word[15:0]};
                        1'b1: rdata_o = {{16{raw_word[31]}}, raw_word[31:16]};
                    endcase
                end
                3'b010: begin // LW
                    rdata_o = raw_word;
                end

                // ---- 无符号加载 ----
                3'b100: begin // LBU
                    case (rd_byte_offset)
                        2'b00: rdata_o = {24'b0, raw_word[ 7:0]};
                        2'b01: rdata_o = {24'b0, raw_word[15:8]};
                        2'b10: rdata_o = {24'b0, raw_word[23:16]};
                        2'b11: rdata_o = {24'b0, raw_word[31:24]};
                    endcase
                end
                3'b101: begin // LHU
                    case (rd_byte_offset[1])
                        1'b0: rdata_o = {16'b0, raw_word[15:0]};
                        1'b1: rdata_o = {16'b0, raw_word[31:16]};
                    endcase
                end

                default: rdata_o = 32'b0;
            endcase
        end else begin
            rdata_o = 32'b0;
        end
    end

    assign ready_o = 1'b1;

endmodule
```

### 改动清单

| 改动 | 原因 |
|------|------|
| 读和写合并到**同一个** `always @(posedge clk_i)` | Vivado 需要识别单端口 BRAM 的 Read-before-Write 模式 |
| `always @(*)` 读 → `mem_read_raw <= mem[addr]` 同步读 | 满足 BRAM 同步输出要求 |
| 增加 `(* ram_style = "block" *)` | 显式要求 BRAM |
| 字节提取/符号扩展移到**独立的组合逻辑 always** | 这部分 MUX 逻辑不属于 BRAM，用 LUT 实现（~30-50 LUT） |
| 增加 `width_r` / `addr_low_r` 锁存 | 因为 `mem_read_raw` 比 `addr_i`/`width_i` 晚一拍，需要把读请求的属性也延迟一拍对齐 |

---

## 对流水线的影响

### 总结表

| 模块 | 改动前延迟 | 改动后延迟 | 对流水线的影响 |
|------|:---------:|:---------:|---------------|
| **inst_rom** | 0 cycle（组合） | 1 cycle（同步） | IF 阶段地址发出 → 下一拍 IF/ID 寄存器捕获指令。**流水线已有的 IF/ID 寄存器恰好吸收这个 1-cycle 延迟，大概率无需额外修改** |
| **data_ram** | 0 cycle（组合） | 1 cycle（同步） | MEM 阶段发出 load 地址 → 数据在 WB 阶段才有效。这相当于把 load 的 latency 从 1 cycle 变成 2 cycle。**forwarding 路径和 stall 逻辑可能需要调整** |

### inst_rom 影响分析（无影响的可能性大）

```
改动前（Distributed RAM，0-cycle）:
  cycle N:   IF 发 PC ──→ inst_rom 组合输出指令 ──→ IF/ID 捕获
             (一个 cycle 内完成 addr→data→寄存器建立)

改动后（BRAM，1-cycle）:
  cycle N:   IF 发 PC ──→ BRAM 接收地址
  cycle N+1: BRAM 输出指令 ──→ IF/ID 捕获
             (BRAM 的 1 cycle 延迟恰好对应 IF/ID 寄存器的那一拍)

结论: 对于标准的 IF→IF/ID 流水线，BRAM 的 1 cycle 读延迟
      被 IF/ID 流水线寄存器自然地"吸收"了。PC 和指令之间
      本来就是差一个 IF/ID 寄存器——无论是组合 ROM 还是 BRAM。
```

### data_ram 影响分析（需要注意）

```
改动前（Distributed RAM，0-cycle）:
  cycle N:   MEM 发 load addr ──→ data_ram 组合输出数据 ──→ MEM/WB 捕获
  cycle N+1: WB 拿到数据，写回寄存器
            load-to-use latency = 1 cycle (可以从 MEM/WB forwarding 到下一指令的 EX)

改动后（BRAM，1-cycle）:
  cycle N:   MEM 发 load addr ──→ BRAM 接收地址
  cycle N+1: BRAM 输出数据 ──→ WB 阶段拿到（但 MEM/WB 寄存器这一拍已过）
  cycle N+2: 数据可用
            load-to-use latency = 2 cycles

影响:
  - 原来 load 结果在 MEM/WB 就可以 forward 给下一指令的 EX
  - 现在需要额外 stall 1 cycle，或让 forwarding 从 WB 再绕一级
  - load-use hazard 的处理逻辑可能需要调整
```

---

## 附：如何用 Vivado 验证推断结果

综合完成后，在 Tcl Console 中执行：

```tcl
# 查看所有推断出的 BRAM
report_ram_utilization

# 查看某个具体模块用了什么原语
report_utilization -cells [get_cells u_inst_rom]

# 在综合日志中搜索 BRAM 相关信息
# 如果看到以下消息说明推断成功:
#   "INFO: [Synth 8-4480] RAM <mem_reg> is being modeled as a Block RAM"
# 如果推断为 Distributed RAM:
#   "INFO: [Synth 8-4480] RAM <mem_reg> is being modeled as a Distributed RAM"

# 打开综合后 schematic 可视化确认
open_run synth_1
```

---

*Document created for FX-RV32 project. Author: Yi Fengxin, Beihang University.*
