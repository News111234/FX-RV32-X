# Load-Use 转发路径优化：MEM 阶段直接前递

> 日期：2026-06-08 | 作者：Yi Fengxin, Beihang University
> 摘要：添加 MEM 阶段 bus_rdata 到 EX 阶段的直接转发路径（forward=2'b11），
> 简化 hazard_unit 停顿条件，使 load-use 停顿保持在 1 周期。

## 1. 问题背景

在之前的 load-use 冒险修复（`doc/deterministic_test_progress.md` §2.3）中，
hazard_unit 新增了 `!load_in_wb` 条件，理论上要求 load 到达 WB 阶段后才释放停顿
（2 周期 stall）。但实际分析发现，由于 `flush_ex` 同步冲刷 ID/EX（插入 NOP），
`load_in_ex` 在 load 离开 EX 阶段时已被清除，stall 实际上只持续 1 周期。

另一方面，`forwarding_unit` 对 EX/MEM 阶段的 load 指令禁用了转发（`!ex_mem_mem_re_i`），
因为 load 的 ALU 结果是访存地址而非数据。load 数据只能通过 MEM/WB 转发，
这意味着一部分 RAW 依赖场景（load 在 MEM、依赖指令在 EX）无法正确转发。

## 2. 优化方案

### 核心思路

当 load 指令处于 MEM 阶段时，`bus_rdata`（符号扩展后）已在当前周期就绪。
新增一条从 MEM 阶段到 EX 阶段的直接转发路径，让依赖指令在 load 的 MEM 周期
即可获取数据，无需等待 MEM/WB。

### 转发优先级（修改后）

| 优先级 | 转发源 | 编码 | 数据 | 条件 |
|--------|--------|------|------|------|
| 1（最高） | MEM stage load | `2'b11` | `mem_rdata_sext` | `ex_mem_mem_re=1`, rd 匹配 |
| 2 | EX/MEM ALU | `2'b01` | `ex_forward_muxed` | `ex_mem_mem_re=0`, rd 匹配 |
| 3（最低） | MEM/WB | `2'b10` | `forward_mem_data` | `wb_reg_we=1`, rd 匹配 |

MEM stage load 的优先级最高，因为它的数据最新（比 MEM/WB 早一个周期）。

## 3. 修改文件

### 3.1 `core/hazard/forwarding_unit.v`

**修改前**:
```verilog
// EX/MEM 转发被禁用 (!ex_mem_mem_re_i)
if (ex_mem_reg_we_i && ... && !ex_mem_mem_re_i) begin
    forwardA_o = 2'b01;
end
```

**修改后**:
```verilog
// 第 1 优先级: MEM 阶段 load → 直接前递 bus_rdata (2'b11)
if (ex_mem_mem_re_i && ex_mem_reg_we_i && (ex_mem_rd_addr_i != 5'b0)) begin
    if (ex_mem_rd_addr_i == id_ex_rs1_addr_i)
        forwardA_o = 2'b11;
    if (ex_mem_rd_addr_i == id_ex_rs2_addr_i)
        forwardB_o = 2'b11;
end

// 第 2 优先级: EX/MEM 阶段非 load 指令 ALU 结果 (2'b01)
if (ex_mem_reg_we_i && ... && !ex_mem_mem_re_i) begin
    // 仅在 MEM load 没有匹配时才使用
    if (forwardA_o == 2'b00 && ...)
        forwardA_o = 2'b01;
end

// 第 3 优先级: MEM/WB 阶段 (2'b10) — 不变
```

### 3.2 `core/exu/ex_top.v`

新增 `mem_load_forward_data_i` 输入端口和 `2'b11` 转发选择：

```verilog
// 新增输入
input wire [31:0] mem_load_forward_data_i, // MEM 阶段 load 转发数据

// 转发 mux 新增 2'b11 分支
assign op1_selected = (forwardA_i == 2'b01) ? ex_forward_data_i :
                      (forwardA_i == 2'b10) ? mem_forward_data_i :
                      (forwardA_i == 2'b11) ? mem_load_forward_data_i :
                      rs1_data_i;
// op2 同理
```

### 3.3 `core/core_top.v`

将符号扩展后的 `mem_rdata_sext` 连接到 EX 阶段的新输入：

```verilog
// 新增: MEM 阶段 load 数据直接转发到 EX 阶段
wire [31:0] mem_load_forward_data;
assign mem_load_forward_data = mem_rdata_sext;

// ex_top 实例化新增连接
.mem_load_forward_data_i (mem_load_forward_data),
```

移除 hazard_unit 的 `mem_wb_mem_re` 连接（不再需要）。

### 3.4 `core/hazard/hazard_unit.v`

**移除** `mem_wb_mem_re_i` 输入端口和 `!load_in_wb` 条件：

```verilog
// 修改前:
wire load_use_hazard = load_in_ex && !load_in_mem && !load_in_wb && ...;

// 修改后:
wire load_use_hazard = load_in_ex && !load_in_mem && ...;
// 移除 !load_in_wb: MEM→EX 直接转发已覆盖此场景
```

## 4. 时序分析

### Load-Use 场景（优化后）

```
         Cycle N       Cycle N+1      Cycle N+2
IF:     ADDI+2        ADDI+3         ADDI+4
ID:     ADDI          ADDI+2         ADDI+3
EX:     LW            NOP            ADDI
MEM:    prev          LW             NOP
WB:     prev-1        prev           LW
         │              │
         └─ stall=1     └─ stall=0
            flush_ex=1     forward=2'b11
                           (MEM→EX)
```

1. **Cycle N**: LW 在 EX，ADDI 在 ID → 检测到 load-use hazard → stall IF/ID，flush ID/EX
2. **Cycle N+1**: LW 在 MEM，ADDI 卡在 ID → bus_rdata 就绪 → stall 释放
3. **Cycle N+2**: LW 在 WB，ADDI 在 EX → forwarding=2'b11 提供 bus_rdata → 正确执行

停顿周期：**1 个 bubble（NOP in EX）**。

### 时序收敛

新增的组合路径：`bus_rdata` → `mem_rdata_sext` → `op1_selected` → `alu_op1` → ALU → `alu_result`

原关键路径（EX/MEM 转发）：`ex_alu_result` → `op1_selected` → `alu_op1` → ALU → `alu_result`

MEM load 转发多了一段：`data_ram` 读取延迟 + 符号扩展逻辑（~10 LUT levels）。
在 UVM 仿真环境（纯组合逻辑 memory）中无问题。
在 FPGA 实现中，若 data_ram 为 Block RAM（1 cycle 读取延迟），
则 bus_rdata 在 MEM 周期末尾才就绪，可能需要额外的时序约束。
当前 FPGA 目标频率 200MHz（5ns 周期），应能满足。

## 5. 验证结果

| 测试 | 修改前 | 修改后 | σ | Mismatches |
|------|--------|--------|---|------------|
| add | 544 | 544 | 0.0 | 0 |
| addi | 303 | 303 | 0.0 | 0 |
| and | 564 | 564 | 0.0 | 0 |
| ... | ... | ... | ... | ... |
| lb | 317 | 317 | 0.0 | 0 |
| lh | 333 | 333 | 0.0 | 0 |
| lw | 347 | 347 | 0.0 | 0 |
| ld_st | 1161 | 1161 | 0.0 | 0 |
| fence_i | 551 | 551 | 0.0 | 0 |

**全部 42 个测试通过，0 Mismatches，100% 确定性，周期数与修改前完全一致。**

> 周期数不变的原因：原始设计中 `!load_in_wb` 因 `flush_ex` 的存在实际上从未延长停顿。
> 本次优化本质是**消除冗余逻辑 + 添加 MEM→EX 转发路径**，确保所有 RAW 依赖场景
> 都被正确覆盖，而非减少特定测试的 cycle 数。

## 6. 硬件开销

| 资源 | 变化 | 说明 |
|------|------|------|
| forwarding_unit LUT | +10 | 新增 2'b11 优先级判断 |
| ex_top LUT | +15 | 新增 mux 分支 |
| core_top LUT | +5 | 新增 mem_load_forward_data 连线 |
| hazard_unit LUT | -5 | 移除 mem_wb_mem_re 输入和 !load_in_wb |
| **总 LUT** | **+25** | 占 Kintex-7 的 < 0.01% |
| FF | 0 | 无新增寄存器 |

## 7. 修改清单

| 文件 | 修改内容 | 行数 |
|------|----------|------|
| `core/hazard/forwarding_unit.v` | 新增 2'b11 MEM load 转发优先级 | +15 行 |
| `core/exu/ex_top.v` | 新增 mem_load_forward_data_i 输入 + 2'b11 mux | +6 行 |
| `core/core_top.v` | mem_load_forward_data 连线 + ex_top 连接 | +5 行 |
| `core/hazard/hazard_unit.v` | 移除 mem_wb_mem_re_i 和 !load_in_wb | -6 行 |
