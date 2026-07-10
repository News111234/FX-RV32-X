# Load-Use 冒险停顿机制分析

## 1. 问题代码

```asm
lw  x1, 0(x2)    # PC=0x00: load指令
add x3, x1, x4   # PC=0x04: 立即使用x1
```

## 2. 当前硬件行为逐拍推演

### 2.1 无停顿时的错误结果

| 周期 | IF | ID | EX | MEM | WB |
|------|-----|-----|-----|-----|-----|
| 0 | lw | - | - | - | - |
| 1 | add | lw | - | - | - |
| 2 | next | add | **lw** | - | - |
| 3 | next+1 | next | **add** | lw | - |
| 4 | - | - | - | add | **lw** |

周期3：add 在 EX 需要 x1，但 lw 数据在 MEM（尚未写回）。转发单元对 MEM 阶段 load 的转发被显式禁止（`!ex_mem_mem_re_i`），而 MEM/WB 此时还没有 lw 的数据。**add 读到 x1 的旧值，计算结果错误。**

### 2.2 当前停顿机制的时序

hazard_unit 检测到 load-use 冒险（lw 在 EX，add 在 ID，rd=x1 匹配 rs1=x1），置 `stall_if_o=1, stall_id_o=1`。

```
周期2:   IF=next    ID=add      EX=lw       MEM=-       WB=-
         stall_if=1, stall_id=1（组合逻辑，load_use_hazard=1）
         ifu_top: next_pc = pc (stall_i=1, 所以 pc 保持不变)

周期2↑:  pc_reg:   stall=1 → 不更新, PC保持0x04
         IF/ID:    stall=1 → 保持, add仍留在ID
         ID/EX:    stall=1 → 保持, lw仍留在ID/EX
         EX/MEM:   stall=0 → 捕获lw（第一份）

周期3:   IF=add(再次取0x04)  ID=add(保持)  EX=lw(保持!)  MEM=lw(第1份)
         此时 load_in_mem=ex_mem_mem_re_i=1 → !load_in_mem=0
         → load_use_hazard=0, stall_if=0, stall_id=0

周期3↑:  stall释放:
         pc_reg:   PC更新到0x08
         IF/ID:    捕获IF输出(=add, PC之前停在0x04)
         ID/EX:    捕获add（来自周期3中ID输出的add）
         EX/MEM:   捕获lw(第二份! 来自周期3中EX重执行的lw)
         MEM/WB:   捕获第一份lw

周期4:   IF=next(0x08)  ID=add(重新进入!)  EX=add(原始)  MEM=lw(第2份)  WB=lw(第1份)
```

### 2.3 问题一：load 指令被复制

lw 在周期2位于 EX。周期2↑ 时 ID/EX 因 stall 保持，lw 留在 ID/EX 中。周期3 期间 ID/EX 仍输出 lw → EX 再次执行 lw → 周期3↑ 时 EX/MEM 再次捕获 lw。

**结果**：lw 在周期3进入 MEM（第1份），周期4再次进入 MEM（第2份）。总线被触发了**两次读请求**。

对于 RAM（幂等读），两次读返回相同数据，功能上可容忍但浪费一个总线周期。对于 FIFO 类外设（如 UART RX），第二次读会**取走下一笔数据，导致数据丢失**。

### 2.4 问题二：add 指令被复制

周期3↑ stall 释放时，IF/ID 捕获了 IF 的输出——但 PC 在周期2↑ 被冻结在 0x04，周期3 期间 IF 一直在取 0x04（add 本身）。所以 IF/ID 再次捕获了 add。同时 ID/EX 也捕获了周期3 期间 ID 中保持的 add。

**结果**：周期4 中 add 同时出现在 ID 和 EX 两个阶段。周期4↑ 时 EX/MEM 捕获 EX 中的 add，ID/EX 捕获 ID 中的 add。add 指令被执行了**两次**。

## 3. 根因分析

核心问题在于停顿机制只做了"保持"（hold），没有在 load 后方插入"气泡"（NOP）。

教科书式五级流水线的 load-use 停顿方案是：

| 控制信号 | 操作 | 效果 |
|----------|------|------|
| `stall_pc` = 1 | PC 不更新 | ✓ 当前设计已有 |
| `stall_ifid` = 1 | IF/ID 保持 | ✓ 当前设计已有 |
| **`flush_idex`** = 1 | **ID/EX 插入 NOP** | ✗ **当前设计缺失** |

第三项是关键：ID/EX 必须被冲刷为 NOP，而非保持。这样才能：

- 防止 lw 在 EX 中重复执行（NOP 替代了 lw 的第二份）
- 在流水线中制造一个气泡，使 lw 和 add 之间恰好隔开一个周期
- 气泡传递到 MEM 时自然消失，不影响后续指令

下表对比了当前行为与教科书方案的差异：

| | 当前设计（仅 hold） | 教科书方案（hold + NOP插入） |
|---|---|---|
| ID/EX 在 stall 周期的行为 | 保持 lw → EX 重复执行 lw | 插入 NOP → EX 执行 NOP |
| lw 进入 MEM 的次数 | **2 次** | **1 次** |
| add 被执行次数 | **2 次**（周期4 EX + 周期5 EX） | **1 次** |
| 对 RAM load 的影响 | 功能正确（幂等），浪费 1 个总线周期 | 功能正确 |
| 对 FIFO load 的影响 | **数据丢失**（多读走一笔） | 功能正确 |

## 4. 修正方案

### 方案 A：hazard_unit 新增 flush_ex 输出（推荐）

在 `hazard_unit.v` 中新增一个输出 `flush_ex_o`，当检测到 load-use 冒险时置 1。同时在 `core_top.v` 中将此信号连接到 ID/EX 的 flush 控制。

```verilog
// hazard_unit.v 新增
assign flush_ex_o = load_use_hazard;

// core_top.v 修改 id_ex_reg 实例化
id_ex_reg u_id_ex_reg (
    ...
    .flush_i       (flush_id || flush_ex_load_use),  // 合并控制冒险与load-use冲刷
    ...
);
```

注意：`flush_ex` 原本用于分支/跳转冲刷，需要与 load-use 冲刷合并（两者不会同时发生——load-use 发生时 EX 是 load 而非分支）。

### 方案 B：在 ID/EX 的 stall 逻辑中区分停顿类型

修改 `id_ex_reg.v`，在 `stall_i && flush_i` 同时有效时执行冲刷（当前代码中 `flush_i` 优先级高于 `stall_i`，不存在冲突）。只需将 load-use 信号同时接到 stall 和 flush 即可。

## 5. 当前设计在什么情况下能正常工作？

当前 CoreMark 测试程序能正常运行，原因如下：

1. **编译器通常会在 load 和使用者之间插入独立指令**（如 RISC-V 汇编器或 GCC 的 `-O0` 调度），所以 load-use 相邻的情况在实际测试中可能并未触发
2. **即使触发，对 RAM 的重复 load 是幂等的**——读同一地址返回相同数据，add 虽然被执行两次但第二次 add 的 x1 已被第一条 lw 的结果覆盖（通过 WB 写回），且第二次 add 在 EX 时可以从 MEM/WB 转发到正确的新 x1 值
3. **CoreMark 不涉及 FIFO 类外设读取**，不会触发数据丢失

但如果手写汇编故意构造连续的 `lw x1,0(x2); add x3,x1,x4`，并且编译器没有插入任何中间指令，就会触发上述问题。

## 6. 小结

当前的 load-use 停顿机制**方向正确但实现不完整**。停顿 IF/ID 和 PC 是对的，但缺少对 ID/EX 插入 NOP 的操作，导致 load 指令和依赖指令各被执行两次。对于幂等的 RAM 访问，功能上恰好能通过（第二次重复执行的结果覆盖第一次，最终状态一致），但存在总线带宽浪费和 FIFO 类外设访问的数据完整性风险。建议按方案 A 补充 `flush_ex` 信号。
