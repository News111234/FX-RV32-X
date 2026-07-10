# FX-RV32 全代码审查报告

> 日期：2026-06-22
>
> 审查范围：全部 RTL 文件（core/ 26 个 + soc/ 12 个 + 顶层集成 4 个）
>
> 审查方法：4 路并行 agent（core 流水线、CSR/中断、SoC 外设、顶层集成），逐文件阅读，交叉验证

---

## 一、致命 Bug（会导致指令执行错误或外设完全不可用）

### 1. SRL/SRLI、SRA/SRAI 指令产生错误结果

| 文件 | 行号 |
|------|------|
| `core/id/decoder.v` | 90-92, 106 |
| `core/exu/alu.v` | 72-73 |

**问题**：decoder 将 OR( funct3=110 ) 和 SRL( funct3=101, funct7[5]=0 ) 编码为同一个 ALU opcode `4'b0110`；将 AND 和 SRA 编码为 `4'b0111`。但 ALU 对 `4'b0110` 固定输出 `op1 | op2`（或运算），对 `4'b0111` 固定输出 `op1 & op2`（与运算）。

**后果**：SRL/SRLI 输出 `op1 | op2` 而非 `op1 >> op2`；SRA/SRAI 输出 `op1 & op2` 而非算术右移。CPU 不是完全 RV32I 兼容的。

**修复思路**：将 ALU opcode 扩展为 5 位，或给 ALU 增加 `funct3` 输入用于区分 OR/SRL 和 AND/SRA。

---

### 2. LUI/AUIPC 指令产生错误结果

| 文件 | 行号 |
|------|------|
| `core/id/decoder.v` | 119 |
| `core/exu/ex_top.v` | 114-115 |

**问题**：LUI/AUIPC 设置 `alu_src_o=1` 让 ALU 操作数 2 使用立即数，但操作数 1 始终是转发后的 `rs1_data`。没有机制将操作数 1 覆盖为 0（LUI）或 PC（AUIPC）。

**后果**：
- LUI 计算 `rs1 + imm` 而非正确 `0 + imm`
- AUIPC 计算 `rs1 + imm` 而非正确 `PC + imm`
- 由于 U-type 指令的 rs1 字段实际属于立即数的高位，`rs1_data` 读出一个任意值，结果完全错误

**修复思路**：在 `ex_top.v` 中增加 op1 的 MUX：LUI 时选 0，AUIPC 时选 `pc_i`，其他指令选 `op1_selected`。

---

### 3. B-type 分支立即数位序错误

| 文件 | 行号 |
|------|------|
| `core/id/imm_gen.v` | 50-51 |

**问题**：
```verilog
// 当前（错误）：
imm_o = {{20{instr_i[31]}}, instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0};
//                          ^^^^^^^^^^  位置错了
// 正确应为：
imm_o = {{20{instr_i[31]}}, instr_i[30:25], instr_i[11:8], instr_i[7], 1'b0};
```

B-type 立即数位排列为 `{imm[12], imm[10:5], imm[4:1], imm[11]}`。当前代码把 `imm[11]`（对应 `instr_i[7]`）放在了 bit 11 的位置而非 bit 1 的位置。

**后果**：当分支偏移量的 bit 11 为 1 时（偏移量 ≥ 2048 或负数偏移量绝对值 ≥ 2048），分支目标地址计算错误。

**修复**：将 `instr_i[7]` 移到 `instr_i[11:8]` 之后（如上正确版本）。

---

### 4. MRET 指令 mstatus 字段恢复错误

| 文件 | 行号 |
|------|------|
| `core/interrupt/interrupt_pipeline.v` | 206-211 |

**问题**：MRET 应该做 `MIE ← MPIE`（恢复旧中断使能）、`MPIE ← 1`。但代码实现为：
```verilog
csr_mstatus_data_o <= {mstatus_i[31:8],
                       mstatus_i[3],      // ← 这是 old MIE，放在了 MPIE 位置
                       mstatus_i[6:4],
                       1'b1,              // ← 这是常数 1，放在了 MIE 位置
                       mstatus_i[2:0]};
```

**后果**：MRET 后：
- `MIE` 恒为 1（无论中断前是否使能）→ 中断可能在不应该使能的时候被使能
- `MPIE` 被设为 old MIE（而非 1）→ 丢失了"中断前 MIE 为 1"的信息

**修复**：
```verilog
csr_mstatus_data_o <= {mstatus_i[31:8],
                       mstatus_i[7],      // MPIE ← 1（RISC-V spec）
                       // 实际上需要: MPIE←1, MIE←old_MPIE
                       // 正确写法需要重新整理 bit 排列
                       ...};
```
更准确：MPIE bit(7) ← 1, MIE bit(3) ← mstatus_i[7]，其他位保持不变。

---

### 5. 总线仲裁器 UART 地址硬编码为基址

| 文件 | 行号 |
|------|------|
| `soc/bus/bus_arbiter.v` | 141 |

**问题**：
```verilog
assign uart_addr_o = UART_BASE;   // 始终 = 0x1000_0000
```
UART 控制器用 `addr_i[7:0]` 来选择寄存器（TX_DATA=0x00, STATUS=0x04, CTRL=0x08, RX_DATA=0x10, IRQ_FLAG=0x14）。由于传入的地址永远是基址，`addr_i[7:0]` 永远是 0，软件永远无法访问 UART 的任何非零偏移寄存器。

**后果**：
- 无法读 STATUS → 无法判断 TX FIFO 是否就绪
- 无法写 CTRL → 无法使能 RX
- 无法读 RX_DATA → UART 接收功能完全不可用
- 无法写/读 IRQ_FLAG → 无法处理 UART 中断

**修复**：`assign uart_addr_o = mem_addr_i;`（直通实际地址）

---

### 6. GPIO 中断标志写 1 清除永远无效

| 文件 | 行号 |
|------|------|
| `soc/periph/gpio.v` | 105-108 |

**问题**：
```verilog
if (we_i && (addr_i[7:0] == GPIO_IF_ADDR))
    gpio_if <= gpio_if & ~wdata_i;    // 行 106: 清除
gpio_if <= gpio_if | interrupt_cond;  // 行 108: 重新置位（无条件执行）
```
两个 NBA 使用同一个旧值 `gpio_if`。最后一条（行 108）无条件执行，因此行 106 的清除被覆盖，清除操作无效。

**后果**：软件向 GPIO_IF 写 1 无法清除中断标志，GPIO 中断一旦触发就永远挂起。

**修复**：将置位和清除合并为一个表达式，或使用中间组合逻辑信号。

---

### 7. UART 控制器地址解码宽度不一致导致寄存器别名

| 文件 | 行号 |
|------|------|
| `soc/periph/uart_ctrl.v` | 55-60, 175, 183, 197, 210, 249 |

**问题**：写路径用 4 位地址解码（`addr_i[3:0]`），读/IRQ 清除用 8 位地址解码（`addr_i[7:0]`）。导致写入 `0x10`（RX_DATA）被解码为 `0x00`（TX_DATA），向 RX_DATA 写数据会错误地推入 TX FIFO。

**后果**：读取 RX_DATA 的正确行为是"读一个收到的字节"，但对该地址的写操作会意外地往发送 FIFO 里推数据。

**修复**：统一所有地址解码为 8 位（`addr_i[7:0]`）。

---

### 8. SPI Master CPHA=0 模式丢失第一个数据位

| 文件 | 行号 |
|------|------|
| `soc/periph/spi_master.v` | 194-204, 210-216 |

**问题**：CPHA=0 模式下，START 状态没有输出第一个 bit 就跳转到 TRANS；TRANS 状态又显式跳过第一个 bit（注释说"已发送"，实际未发送）。

**后果**：CPHA=0 的所有传输丢失最高位，数据整体左移 1 位。SPI Mode 0 和 Mode 2 完全不可用。

---

### 9. SPI Flash 控制器 MOSI 位索引整体偏移 1

| 文件 | 行号 |
|------|------|
| `soc/periph/spi_flash_ctrl.v` | 169-186, 207, 230, 255 |

**问题**：发送逻辑中 `shift_out[6 - bit_cnt]` 应为 `shift_out[7 - bit_cnt]`，且首 bit 的条件与其他 bit 条件重叠（两条 NBA 都满足时后者覆盖前者），导致实际发送序列整体偏移 1 位。

**后果**：Flash READ 命令 `0x03` 被发送为 `0x06`——Flash 芯片不识别，SPI Flash 读路径完全不可用。

---

### 10. I2C Master START/STOP 条件持续时间远低于规范

| 文件 | 行号 |
|------|------|
| `soc/periph/i2c_master.v` | 182-187, 297-305 |

**问题**：START 条件保持 1 个系统时钟周期（5ns），STOP 条件保持约 2 个周期（10ns）。I2C 标准模式要求 tHD:STA ≥ 4µs，快速模式要求 ≥ 0.6µs。

**后果**：I2C 从设备极大概率无法识别 START/STOP 条件。绝大多数 I2C 外设无法与此控制器通信。

---

### 11. inst_bram 写保护使用字节地址位导致保护范围错误

| 文件 | 行号 |
|------|------|
| `soc/mem/inst_bram.v` | 160 |

**问题**：写保护条件 `bus_addr_i[31:9] != 0` 使用字节地址。512 字 = 2048 字节 = 0x800，边界在 bit 11。使用 bit 9 意味着只保护了前 128 字（字节地址 0x000-0x1FF）。

**后果**：Bootloader 区域（字 0-511）中只有字 0-127 真正被写保护，字 128-511 可被总线写入覆盖。

**修复**：改为 `bus_addr_i[31:2] < 12'd512`（字地址检查）或 `bus_addr_i[31:11] != 0`。

---

## 二、高优先级问题（功能性影响）

### 12. CSR 寄存器中断写入可被 CSR 指令覆盖

| 文件 | 行号 |
|------|------|
| `core/csr/csr_regfile.v` | 132-156 |

中断响应写（mepc/mcause/mstatus）在 always 块中先于 CSR 指令写，但由于 NBA 的最后赋值胜出规则，如果同周期 CSR 指令也写 mstatus/mepc/mcause，CSR 指令的数据会覆盖中断写入。

---

### 13. core_top_sim.v 存在多处端口不匹配

| 文件 | 行号 |
|------|------|
| `core/core_top_sim.v` | 576-578, 625-639, 779, 821, 1027 |

- ifu_top 使用了不存在的 `interrupt_pending_i`/`mtvec_i` 端口，缺少必需的 `instr_i`/`intr_take_now_i`/`intr_target_i`
- id_top 连接了不存在的 `debug_x0_o`–`debug_x14_o` 端口，缺少必需的 `shadow_save_i`/`shadow_restore_i`
- ex_top 连接了不存在的 `ex_result_o` 端口
- `mem_top_fpga` 模块不存在（正确名称是 `mem_top`）
- SPI MISO 错了接到 MOSI 信号
- interrupt_pipeline 缺少 `id_ex_mret` 连接
- 缺少 CSR 转发路径（与 `core_top.v` 不一致）

`core_top_sim.v` 需要全面修复或从 `core_top.v` 的工作版本重建。

---

### 14. Timer 计数器在寄存器写周期不递减

| 文件 | 行号 |
|------|------|
| `soc/periph/timer.v` | 52-105 |

CPU 写定时器寄存器时（we_i=1），整个递减逻辑被跳过（`else if (we_i) ... else begin ... 递减 ...`），每次寄存器写丢失一个计数。

---

### 15. I2C Master irq_enable 只能置位不能清零

| 文件 | 行号 |
|------|------|
| `soc/periph/i2c_master.v` | 327 |

```verilog
if (wdata_i[1] == 1'b1) irq_enable <= 1'b1;  // 只置位，无清零路径
```

一旦使能 I2C 中断，软件无法关闭（只能靠复位）。

---

## 三、中等问题

| # | 文件 | 描述 |
|---|------|------|
| 16 | `interrupt_controller.v:44` | 注释写优先级 MEI>MTI>MSI>SPI>I2C，但实现是 MEI>MTI>SPI>I2C>MSI |
| 17 | `interrupt_pipeline.v:78-86` | `interrupt_condition` 位 1-4 全硬连线为 1，5 位 AND 等于 `intr_pending_i`，整个向量是死代码 |
| 18 | `mem_ctrl.v` | 从未被任何模块实例化，对齐检查功能是死代码 |
| 19 | `data_ram.v:100` | 组合逻辑读（`always @(*)`），可能阻碍 Block RAM 推断，造成仿真/综合不一致 |
| 20 | `core_top.v:176-177,659` | `intr_software`/`intr_timer` 声明并赋值但从未使用 |
| 21 | `soc_top.v:54-59` | `core_perf_*` 6 个 wire 声明但从未驱动或使用 |
| 22 | `interrupt_controller.v:45-47` | `meip/mtip/msip` 双重采样 mip 和 raw input，存在不一致风险 |
| 23 | `csr_regfile.v:108` | MISA 初始化为 `0x40000100`，MXL 字段（bit[1:0]）为 0，RV32 应为 1 |
| 24 | `csr_regfile.v:124` | `minstret` 无条件每周期 +1，而非退休指令计数 |
| 25 | `mem_ctrl.v:12` | 注释写 "LW/SW 按 2 字节对齐"，应为 4 字节对齐 |

---

## 四、低优先级问题（代码质量/死代码/风格）

| # | 文件 | 行号 | 描述 |
|---|------|------|------|
| 26 | `core/exu/branch.v` | 24 | `alu_zero_i` 输入声明但从未使用 |
| 27 | `core/hazard/hazard_unit.v` | 21-22 | 纯组合逻辑模块声明了不需要的 `clk_i`/`rst_n_i` |
| 28 | `core/interrupt/interrupt_pipeline.v` | 102-114 | `selected_stage` 寄存器赋值但从未连接输出 |
| 29 | `core/csr/csr_instructions.v` | 58 | `is_imm_csr` wire 定义但从未使用 |
| 30 | `core/wbu/wb_top.v` | 55 | 注释说 CSR 结果"暂时接地"，实际已正确连接 |
| 31 | `core/ifu/ifu_top.v` | 4 | 注释写 `if_top`，模块名实际是 `ifu_top` |
| 32 | `core/exu/alu.v` | 54-55 | 冗余三元运算符 `(a<b) ? 1'b1 : 1'b0` 等价于 `(a<b)` |
| 33 | `soc/periph/gpio.v` | 62,151 | `gpio_out_all` 声明但从未使用 |
| 34 | `soc/mem/data_ram.v` | 53 | `ADDR_WIDTH=8` 参数声明但从未引用 |
| 35 | `soc/periph/uart_tx.v` | 83,94,111 | START/DATA/STOP 状态波特率计数器比较混用 `>=` 和 `==` |
| 36 | `soc/periph/spi_master.v` | 229 | TRANS→STOP 转换多消耗一个系统时钟周期 |
| 37 | `core/id/id_top.v` | 155 | 非 load/store 指令的 `mem_width_o` 默认设为 word（3'b010），语义不精确 |
| 38 | `core/top/soc_top_fpga.v` | 52 | `rst_counter` 使用初始值 `=0`，DC ASIC 综合不支持 |

---

## 五、修复优先级汇总

| 优先级 | Bug # | 描述 | 影响范围 |
|--------|-------|------|---------|
| **立即修复** | 1 | SRL/SRA 指令错误 | RV32I 兼容性 |
| **立即修复** | 2 | LUI/AUIPC 指令错误 | 几乎所有程序 |
| **立即修复** | 3 | B-type 立即数位序 | 大偏移量分支 |
| **立即修复** | 4 | MRET mstatus 恢复 | 中断返回正确性 |
| **立即修复** | 5 | UART 地址硬编码 | UART 全功能 |
| **立即修复** | 6 | GPIO 中断清除无效 | GPIO 中断 |
| **高优先** | 7 | UART 地址解码混用 | UART RX 损坏 |
| **高优先** | 8 | SPI CPHA=0 | SPI 通信 |
| **高优先** | 9 | SPI Flash 位偏移 | Flash 启动 |
| **高优先** | 10 | I2C START/STOP | I2C 通信 |
| **高优先** | 11 | BRAM 写保护 | Bootloader 安全 |
| **高优先** | 12 | CSR 写入竞争 | 中断/CSR 并发 |
| **中优先** | 13 | core_top_sim.v | Verilator 仿真 |
| **中优先** | 14-15 | Timer/I2C | 外设功能 |

---

> **总结**：扫描全部 42 个 Verilog 源文件，发现 11 个致命 bug（可导致指令错误或外设不可用）、4 个高优先级问题、10 个中等问题、13 个低优先问题。
>
> 最严重的问题集中在：**(a) ALU 操作码空间不足以区分所有 RV32I 指令**（SRL/SRA 被 OR/AND 覆盖，LUI/AUIPC 无专用路径）；**(b) 外设地址解码和时序错误**（UART 寄存器别名、SPI Flash 位偏移、I2C 时序、GPIO 中断标志）。
>
> 好消息是这些问题中绝大多数都是单文件局部修复，不涉及架构级重构。
