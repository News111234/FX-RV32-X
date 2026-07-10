# FX-RV32 ecall 异常支持方案

> 给 RV32I CPU 添加 ecall 指令异常处理，使 RISC-V 官方测试框架的 pass/fail 机制正常工作
> 日期：2026-06-07

## 1. 背景

### 问题

RISC-V 官方测试（riscv-tests）通过以下机制报告测试结果：

```
测试通过 → fence; li gp,1; li a7,93; li a0,0; ecall → 陷阱处理器 → write_tohost
测试失败 → fence; ...; slli gp,1; ori gp,1; ecall → 陷阱处理器 → write_tohost
```

`write_tohost` 将 gp 的值写入内存地址 0x1000（通过 AUIPC + SW 指令对），仿真环境通过监控该地址检测测试完成。

**FX-RV32 当前不支持 ecall 异常**。ecall 指令被解码器当作 NOP 处理，测试框架的 pass/fail 报告机制失败。

### 目标

- 添加 ecall 异常支持（仅 M-mode ecall，cause=11）
- 不修改主项目 `FX-RV32_RemoveM_Custom/`（论文用）
- 创建独立副本 `FX-RV32_AddEcall/`（测试用）
- 硬件开销最小化

## 2. 硬件开销估算

### 修改的模块

| 模块 | 变更 | 新增 LUT | 新增 FF |
|------|------|---------|---------|
| `core/id/decoder.v` | 添加 `ecall_o` 输出 | ~5 | 0 |
| `core/interrupt/interrupt_controller.v` | 添加 `ecall_i` 输入，生成 cause=11 | ~10 | 0 |
| `core/core_top.v` | 连接 ecall 信号 | ~5 | 0 |
| `core/pipeline/id_ex_reg.v` | 传递 ecall 标志 | ~0 | 1 |
| **合计** | | **~20** | **~1** |

### 开销分析

- **LUT 增量**：~20（当前 ~3000，+0.7%）
- **FF 增量**：~1（当前 ~1500，+0.07%）
- **对时序的影响**：无（ecall 检测是简单的组合逻辑解码）
- **论文处理**：额外硬件开销极小，论文中可不提及

> 核心洞察：FX-RV32 的中断处理框架（`interrupt_controller` + `interrupt_pipeline`）已经实现了陷阱响应的全部机制（保存 PC→mepc、设置 mcause、更新 mstatus、冲刷流水线、跳转到 mtvec）。ecall 只需作为一个新的"中断源"接入即可，改动量极小。

## 3. 实现方案

### 3.1 数据流

```
decoder.v                     interrupt_controller.v          interrupt_pipeline.v
  │                                │                                │
  │  ecall detected                │  ecall_i=1                     │  intr_pending=1
  │  (opcode=1110011, funct3=000,  │  → intr_pending_o=1            │  → save mepc=ex_pc
  │   imm=0x000)                   │  → intr_cause_o=0x0000000B     │  → save mcause=11
  │  ──────────────────────────▶   │  ──────────────────────────▶   │  → update mstatus
  │                                │                                │  → flush pipeline
  │                                │                                │  → jump to mtvec
```

### 3.2 修改清单

#### `core/id/decoder.v` — 添加 ecall 检测

```verilog
// 新增输出
output wire ecall_o,    // ecall 指令标志

// 新增逻辑（在现有 is_mret 附近）
wire is_ecall = (opcode_o == 7'b1110011) && 
                (funct3_o == 3'b000) && 
                (instr_i[31:20] == 12'h000) && 
                !is_mret;
assign ecall_o = is_ecall;
```

#### `core/interrupt/interrupt_controller.v` — 添加 ecall 中断源

```verilog
// 新增输入
input wire ecall_i,       // ecall 异常（来自 EX 阶段）

// 新增优先级逻辑（ecall 最高优先级，因为它是同步异常）
wire ecall_pending = ecall_i;   // ecall 立刻被视为待处理

// 在优先级编码器中：
//   if (ecall_pending)      intr_cause = {1'b0, 31'd11};  // 异常，优先级最高
//   else if (meip)          intr_cause = {1'b1, 31'd11};  // 外部中断
//   else if (mtip)          ...
```

关键点：ecall 的 intr_cause 使用 `{1'b0, 31'd11}`（bit31=0 表示异常），而不是中断的 `{1'b1, 31'd11}`。这是 RISC-V 规范的要求。

#### `core/core_top.v` — 信号连接

```verilog
// 新增信号
wire id_ecall;
wire id_ex_ecall;

// ID 阶段
id_top u_id_top (
    ...
    .ecall_o (id_ecall),
);

// ID/EX 流水线寄存器（需要传递 ecall 标志）
id_ex_reg u_id_ex_reg (
    ...
    .id_ecall_i (id_ecall),
    .ex_ecall_o (id_ex_ecall),
);

// 连接到中断控制器
interrupt_controller u_interrupt_controller (
    ...
    .ecall_i (id_ex_ecall),   // 在 EX 阶段触发
);
```

#### `core/pipeline/id_ex_reg.v` — 传递 ecall 标志

```verilog
// 新增端口
input  wire id_ecall_i,
output reg  ex_ecall_o,

// 新增寄存器
ex_ecall_o <= (flush_i || intr_flush_i) ? 1'b0 : 
              stall_i ? ex_ecall_o : id_ecall_i;
```

### 3.3 不需要修改的文件

- `core/interrupt/interrupt_pipeline.v` — 无需修改，现有的中断处理逻辑直接复用
- `core/csr/csr_regfile.v` — 无需修改，mepc/mcause 的写入接口已存在
- `core/exu/`、`core/mem/`、`core/wbu/`、`core/hazard/` — 完全不变
- `soc/` — 完全不变

## 4. 对测试框架的影响

### 官方测试适配

添加 ecall 支持后，官方测试的 pass/fail 机制将正常工作：

1. 测试用例执行（所有算术/逻辑/分支/访存测试）
2. 测试通过 → `pass:` 标签 → fence, li gp,1, ecall
3. ecall 触发异常 → CPU 跳转到 mtvec=0x4（trap_handler）
4. trap_handler 识别 mcause=11 → 跳转到 write_tohost
5. write_tohost 将 gp=1 写入 0x1000，将 0 写入 0x1004
6. UVM monitor 捕获到非零 gp 值 → 测试通过 ✅

### 不再需要的适配

之前为规避 ecall 问题而做的繁琐 patch（替换 ecall 为 sw+j、NOP CSR 指令等）将不再需要。标准 hex 文件可直接使用（仅需地址重定位）。

### 精确周期测量

有了 write_tohost 的 gp 写入，可以精确定位测试完成时刻：
- **测试开始**：第一个 WB 事件的时间
- **测试完成**：第一个非零 gp 值写入 0x1000 的时间
- **测试周期数** = (完成时刻 - 开始时刻) / 5ns

每个测试的周期数将反映其实际执行的指令数量（不再被固定的 write_tohost 循环掩盖）。

## 5. 项目结构

```
/home/yifengxin/
├── FX-RV32_RemoveM_Custom/    # 原项目（RV32I，论文用，不变）
├── FX-RV32_AddM/              # M 扩展版本（CoreMark 用）
└── FX-RV32_AddEcall/          # 新增：ecall 异常支持版本（官方测试用）
    ├── core/                  # 修改了 decoder, interrupt_controller, core_top, id_ex_reg
    ├── soc/                   # 不变
    ├── sim/                   # 不变
    ├── uvm/                   # 不变
    ├── riscv_tests/           # 测试适配框架
    └── doc/
```

## 6. 实施步骤

| 步骤 | 内容 | 预计时间 |
|------|------|---------|
| 1 | 从 `FX-RV32_RemoveM_Custom/` 复制到 `FX-RV32_AddEcall/` | 1 分钟 |
| 2 | 修改 `decoder.v` — 添加 ecall_o | 5 分钟 |
| 3 | 修改 `interrupt_controller.v` — 添加 ecall 源 | 10 分钟 |
| 4 | 修改 `core_top.v` — 连接 ecall 信号 | 5 分钟 |
| 5 | 修改 `id_ex_reg.v` — 传递 ecall 标志 | 5 分钟 |
| 6 | 编译 Verilator 验证 | 2 分钟 |
| 7 | 生成官方测试 hex（仅地址重定位，无需其他 patch） | 2 分钟 |
| 8 | UVM 批量运行 42 个测试，记录周期数 | ~10 分钟 |
| **总计** | | **~40 分钟** |

## 7. 预期结果

添加 ecall 支持后：
- ✅ 42 个 RV32I 官方测试全部通过（0 不匹配）
- ✅ 每个测试获得独立的周期数（不再全部相同）
- ✅ 测试框架的 pass/fail 机制正常工作
- ✅ 硬件开销可忽略（~20 LUT, ~1 FF）

## 8. 风险

| 风险 | 缓解 |
|------|------|
| ecall 与现有中断的优先级竞争 | ecall 设为最高优先级（同步异常 > 异步中断） |
| AUIPC bug 影响 write_tohost | 不影响（AUIPC bug 已知，测试结果仍可通过 monitor 捕获） |
| 中断 pipeline 的状态机冲突 | 复用现有逻辑，测试中断在 ecall 测试中不会触发 |

## 9. 与论文的关系

- **RV32I 论文版本**（`FX-RV32_RemoveM_Custom`）：不包含 ecall 支持，展示基础 RV32I 实现。论文中可不提及 ecall 硬件开销。
- **测试版本**（`FX-RV32_AddEcall`）：包含 ecall 支持，用于通过官方测试并获取论文所需的确定性验证数据。
- 两个版本物理上独立，论文可以选择性地描述"通过 RISC-V 官方测试验证了 CPU 的正确性"，而不需要详细讨论 ecall 实现细节。
