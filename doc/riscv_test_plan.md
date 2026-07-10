# FX-RV32 官方测试集适配方案

> 基于 RISC-V 官方 riscv-tests 验证 RV32I CPU 确定性
> 日期：2026-06-06

## 1. 测试集来源

RISC-V 官方测试集：`/home/yifengxin/riscv-tests/`

测试采用 Physical memory 版本（`-p` 后缀），适合无 MMU 的裸机 CPU。

## 2. 可用测试清单（43 个，全部采用 ✅）

所有测试来自 `isa/rv32ui/` 目录，已编译为 ELF 可执行文件，覆盖 RV32I 全部指令。

### 2.1 算术运算（9 个）

| 测试 | 指令 | 说明 |
|------|------|------|
| `rv32ui-p-add` | ADD | 加法，含边界值、符号扩展测试 |
| `rv32ui-p-addi` | ADDI | 立即数加法 |
| `rv32ui-p-sub` | SUB | 减法 |
| `rv32ui-p-lui` | LUI | 加载高位立即数 |
| `rv32ui-p-auipc` | AUIPC | PC 相对地址（⚠️ 已知 AUIPC bug 可能影响） |

### 2.2 逻辑运算（6 个）

| 测试 | 指令 |
|------|------|
| `rv32ui-p-and` | AND |
| `rv32ui-p-andi` | ANDI |
| `rv32ui-p-or` | OR |
| `rv32ui-p-ori` | ORI |
| `rv32ui-p-xor` | XOR |
| `rv32ui-p-xori` | XORI |

### 2.3 移位运算（6 个）

| 测试 | 指令 |
|------|------|
| `rv32ui-p-sll` | SLL（逻辑左移） |
| `rv32ui-p-slli` | SLLI（立即数逻辑左移） |
| `rv32ui-p-srl` | SRL（逻辑右移） |
| `rv32ui-p-srli` | SRLI（立即数逻辑右移） |
| `rv32ui-p-sra` | SRA（算术右移） |
| `rv32ui-p-srai` | SRAI（立即数算术右移） |

### 2.4 比较运算（8 个）

| 测试 | 指令 |
|------|------|
| `rv32ui-p-slt` | SLT（有符号小于置位） |
| `rv32ui-p-slti` | SLTI |
| `rv32ui-p-sltu` | SLTU（无符号小于置位） |
| `rv32ui-p-sltiu` | SLTIU |

### 2.5 分支指令（6 个）

| 测试 | 指令 |
|------|------|
| `rv32ui-p-beq` | BEQ（相等分支） |
| `rv32ui-p-bne` | BNE（不等分支） |
| `rv32ui-p-blt` | BLT（有符号小于分支） |
| `rv32ui-p-bltu` | BLTU（无符号小于分支） |
| `rv32ui-p-bge` | BGE（有符号大于等于分支） |
| `rv32ui-p-bgeu` | BGEU（无符号大于等于分支） |

### 2.6 跳转指令（3 个）

| 测试 | 指令 |
|------|------|
| `rv32ui-p-jal` | JAL（跳转并链接） |
| `rv32ui-p-jalr` | JALR（间接跳转） |
| `rv32ui-p-fence_i` | FENCE.I（指令同步，简单测试） |

### 2.7 访存指令（10 个）

| 测试 | 指令 | 说明 |
|------|------|------|
| `rv32ui-p-lb` | LB（字节加载，有符号） |
| `rv32ui-p-lbu` | LBU（字节加载，无符号） |
| `rv32ui-p-lh` | LH（半字加载，有符号） |
| `rv32ui-p-lhu` | LHU（半字加载，无符号） |
| `rv32ui-p-lw` | LW（字加载） |
| `rv32ui-p-sb` | SB（字节存储） |
| `rv32ui-p-sh` | SH（半字存储） |
| `rv32ui-p-sw` | SW（字存储） |
| `rv32ui-p-ld_st` | LW+SW 综合测试 |
| `rv32ui-p-st_ld` | SW+LW 综合测试 |

### 2.8 其他（2 个）

| 测试 | 说明 |
|------|------|
| `rv32ui-p-simple` | 简单冒烟测试（先跑这个验证框架） |
| `rv32ui-p-ma_data` | 访存数据辅助 |

---

## 3. 不采用的测试

以下所有测试均**排除**，原因如下：

### rv32mi 全部排除 ❌

| 测试 | 排除原因 | 所需硬件 |
|------|---------|---------|
| `rv32mi-p-breakpoint` | 需调试支持 | - |
| `rv32mi-p-sbreak` | 需调试支持 | - |
| `rv32mi-p-scall` | 需 S 模式 | S 模式 CSR (~400 LUT) |
| `rv32mi-p-illegal` | 需异常处理 | 异常检测+CSR (~500 LUT) |
| `rv32mi-p-ma_addr` | 需异常处理 | 同上 |
| `rv32mi-p-ma_fetch` | 需异常处理 | 同上 |
| `rv32mi-p-lh-misaligned` | 需异常处理 | 同上 |
| `rv32mi-p-lw-misaligned` | 需异常处理 | 同上 |
| `rv32mi-p-sh-misaligned` | 需异常处理 | 同上 |
| `rv32mi-p-sw-misaligned` | 需异常处理 | 同上 |
| `rv32mi-p-shamt` | 需异常处理（捕获取消移位量 bit5） | 同上 |
| `rv32mi-p-csr` | 重定向到 rv64si/csr.S（需 S 模式） | S 模式 CSR (~400 LUT) |
| `rv32mi-p-mcsr` | 测试大量机器 CSR | - |
| `rv32mi-p-pmpaddr` | 需 PMP 硬件 | PMP (~300 LUT) |
| `rv32mi-p-instret_overflow` | 需 64 位计数器溢出 | - |
| `rv32mi-p-zicntr` | 需 Zicntr 扩展 | - |

### 其他扩展全部排除 ❌

| 扩展 | 排除原因 |
|------|---------|
| rv32um (M) | 需要硬件乘除法器 |
| rv32ua (A) | 需要原子操作 + 缓存一致性协议 |
| rv32uf/ud (F/D) | 需要 FPU |
| rv32uc (C) | 需要压缩指令解码器 |
| rv32uz* (Zba/Zbb/...) | 位操作扩展，非标准 RV32I |
| rv32si (Supervisor) | 需要 S 模式 |

**总计**：43 个测试采用，16 个 rv32mi + 全部其他扩展排除。

---

## 4. 适配方案

### 核心问题

官方测试编译时链接到 `0x80000000`，使用 ecall + tohost 协议报告结果。FX-RV32 需要：

| 问题 | 解决方案 |
|------|---------|
| 基址 0x80000000 → 0x00000000 | `objcopy --change-addresses` 重定位 |
| ecall 退出 | 替换为 `sw gp, 0x3FC(x0); j .` |
| tohost 地址 0x80001000 | 替换为 0x000003FC |
| PMP/Delegate CSR 初始化 | 启动代码中移除 |

### 自动化流程

```
官方 ELF (0x80000000)
    │
    ▼ reloc_test.py
适配 ELF (0x00000000, 内存映射结果)
    │
    ▼ objcopy
program.hex
    │
    ▼ UVM 批量运行
测试结果 (PASS/FAIL/gp值)
    │
    ▼ 生成报告
论文用确定性验证结果
```

### 不再需要修改硬件

以上 43 个 rv32ui-p 测试**全部可以在当前 RV32I CPU 上运行**，不需要增加任何异常处理、S 模式、PMP 等硬件。仅需软件层面适配地址空间和结果报告机制。

---

## 5. 文件结构

```
FX-RV32_RemoveM_Custom/
├── riscv_tests/                    # 新增：测试适配框架
│   ├── adapter/
│   │   ├── reloc_test.py           # ELF 重定位脚本
│   │   └── run_all_tests.py        # 批量 UVM 运行器
│   ├── hex/                        # 适配后的 hex 文件（43 个）
│   │   ├── add.hex
│   │   ├── ...
│   │   └── xor.hex
│   └── results/                    # 测试结果
│       ├── add.log
│       └── summary.txt             # 汇总报告
```

---

## 6. 预计工作量

| 步骤 | 内容 | 时间 |
|------|------|------|
| 编写 reloc_test.py | ELF 地址重定位 + ecall 替换 | 1-2 小时 |
| 批量生成 hex | 43 个测试 × 自动转换 | 5 分钟 |
| UVM 批量运行 | 43 个测试 × ~1 分钟/个 | ~1 小时 |
| 结果汇总 | 通过率统计 | 15 分钟 |
| **总计** | | **2-3 小时** |

---

## 7. 结论

- ✅ **43 个 rv32ui-p 测试全部可用**，覆盖 RV32I 所有指令
- ❌ **0 个 rv32mi 测试可用**（均需额外硬件）
- 📝 不需要修改 CPU 硬件，仅需适配脚本
- 🎓 测试结果可直接用于论文确定性验证
