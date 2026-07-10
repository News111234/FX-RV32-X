# OpenE902 CLIC 嵌套中断实测指南

> **用途**: 在 Linux 机器上搭建 OpenE902 仿真环境，运行嵌套中断测试，实测 CLIC 硬件压栈方案在嵌套场景下的延迟和累计开销。
> **目标**: 获取表 IV（论文 `bare_jrnl_new_sample4_v2.tex`）中 CLIC 嵌套开销的实测数据，替代当前基于文献的理论推算值。
> **用法**: 把本文档提供给 Linux 上的 Claude Code，让它按照步骤依次完成环境搭建、测试编写、仿真运行和数据收集。

---

## 1. 背景

### 1.1 我们要测什么

| 测试 | 说明 | 测量指标 |
|------|------|---------|
| 单次中断延迟 | Timer 中断，无嵌套 | 从 int_pending 到 ISR 第一条指令执行的周期数 |
| 两级嵌套延迟 | Timer ISR 执行中触发 GPIO 抢占 | 每层的 entry 延迟 + 累计开销 |
| 三级嵌套延迟 | SW → Timer → GPIO 三级 | 每层的 entry 延迟 + 累计开销 |
| 上下文完整性 | 嵌套后 31 寄存器的恢复情况 | tohost 寄存器值 (0 = PASS) |

### 1.2 已有数据（用于对比）

我们的 FX-RV32-X 数据：

| 嵌套深度 | Entry 延迟 | Exit 延迟 | 累计开销 |
|:--:|:--:|:--:|:--:|
| 1 层 | 2 cycles | 3 cycles | 5 cycles |
| 2 层 | 2 cycles | 3 cycles | 10 cycles |
| 3 层 | 2 cycles | 3 cycles | 15 cycles |

CLIC 理论推算（来自 Mao et al. 文献）：

| 嵌套深度 | Entry 延迟 | Exit 延迟 | 累计开销 |
|:--:|:--:|:--:|:--:|
| 1 层 | ~13 cycles | ~11 cycles | ~24 cycles |
| 2 层 | ~13 cycles | ~11 cycles | ~48 cycles |
| 3 层 | ~13 cycles | ~11 cycles | ~72 cycles |

> 注意：CLIC 的 entry 延迟 = 2（流水线冲刷+向量跳转）+ 11（串行硬件压栈 x1-x10） ≈ 13 cycles，来自文献数据。Exit 延迟为推测值（弹栈与压栈对称）。本指南的目的是**实测验证**这些数字。

### 1.3 关于 OpenE902

- T-Head Semiconductor 开源的 RISC-V 核（RV32E/RV32I 兼容）
- 实现了 CLIC (Core-Local Interrupt Controller) 规范
- 2 级流水线（IF → EX/MEM/WB）
- 硬件向量中断模式：`mtvec.MODE = 1`（vectored）时，硬件自动跳转到 `mtvec_base + cause × 4`
- 内置 CLIC 硬件压栈/弹栈状态机
- GitHub: https://github.com/T-Head-Semi/opene902
- 仿真工具：iverilog（开源）或 VCS/QuestaSim（商业）

---

## 2. 环境搭建

### 2.1 基础依赖

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y git build-essential iverilog python3 python3-pip

# RISC-V GCC 工具链 (用于编译测试程序)
# 方式 A: 下载预编译版本 (推荐)
cd ~
wget https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v13.2.0-2/xpack-riscv-none-elf-gcc-13.2.0-2-linux-x64.tar.gz
tar xzf xpack-riscv-none-elf-gcc-13.2.0-2-linux-x64.tar.gz
export PATH="$HOME/xpack-riscv-none-elf-gcc-13.2.0-2/bin:$PATH"
echo 'export PATH="$HOME/xpack-riscv-none-elf-gcc-13.2.0-2/bin:$PATH"' >> ~/.bashrc

# 验证
riscv-none-elf-gcc --version
```

### 2.2 克隆 OpenE902

```bash
cd ~
git clone https://github.com/T-Head-Semi/opene902.git
cd opene902

# 查看目录结构
ls -la
# 关键目录:
#   rtl/          — RTL 源码
#   tb/           — 测试平台 (testbench)
#   tests/        — 测试程序
#   tools/        — 编译/仿真脚本
#   smart_run/    — 一键仿真脚本
```

### 2.3 确认仿真可以跑通

```bash
cd ~/opene902/smart_run

# 先跑一个自带的基础测试确认环境正常
make clean
make run CASE=hello_world 2>&1 | tee ~/e902_baseline.log

# 检查结果
grep -i "pass\|fail\|tohost" ~/e902_baseline.log || echo "Check the log for test results"
```

> **注意**: 不同版本的 OpenE902 仿真入口可能不同。如果 `smart_run/` 目录不存在或 Makefile 规则不同，请查看项目 README.md 或 `doc/` 目录下的说明文档。核心是找到如何用 iverilog 编译 RTL + 加载 hex 程序 + 运行仿真的方法。

---

## 3. 测试程序编写

### 3.1 中断向量表布局 (OpenE902 CLIC)

OpenE902 的 CLIC 使用标准 RISC-V 中断 ID：

| 中断源 | ID | 优先级 | 向量偏移 |
|--------|:--:|:--:|:--:|
| Software | 3 | 最低 | 0x0C |
| Timer | 7 | 中 | 0x1C |
| External (GPIO) | 11 | 最高 | 0x2C |

CLIC 向量模式：`mtvec = 0x200 | 0x01`（base=0x200, vectored mode），则：
- Software handler @ 0x200 + 3×4 = 0x20C
- Timer handler @ 0x200 + 7×4 = 0x21C
- External handler @ 0x200 + 11×4 = 0x22C

### 3.2 测试程序模板

测试程序用汇编编写，编译为 hex 文件加载到 OpenE902 的指令存储器中。

#### 模板: 单次中断延迟测试 (test1_single_intr.S)

```assembly
# test1_single_intr.S — OpenE902 CLIC 单次中断延迟测试
# 测量 Timer 中断从触发到 ISR 第一条指令的 cycle 数
# 编译: riscv-none-elf-gcc -march=rv32imac -mabi=ilp32 -nostdlib -T link.ld -o test1.elf test1_single_intr.S
# 转换: riscv-none-elf-objcopy -O verilog test1.elf test1.hex

.section .text
.globl _start

_start:
    # 初始化 mtvec: base=0x200, vectored mode
    la    t0, vector_table
    csrw  mtvec, t0

    # 初始化 mstatus: 使能全局中断 (MIE=1)
    li    t0, 0x00000008
    csrw  mstatus, t0

    # 初始化 mie: 使能 Timer 中断 (bit 7)
    li    t0, 0x00000080
    csrw  mie, t0

    # 初始化 Timer: 设置 LOAD 值, 使能 auto-reload
    # (具体寄存器地址取决于 E902 SoC 外设映射, 这里用伪代码示意)
    # 假设 Timer 基址 0x10002000
    li    t0, 0x10002000
    li    t1, 200          # 200 个周期后超时
    sw    t1, 4(t0)        # LOAD = 200
    li    t1, 3            # enable + auto_reload
    sw    t1, 0(t0)        # CTRL = 3

    # 主循环: 死循环等待中断
main_loop:
    wfi                    # Wait For Interrupt
    j    main_loop

# ============================================================
# 中断向量表
# ============================================================
.align 6  # 64-byte alignment (CLIC 规范可能要求)
vector_table:
    # cause 0-2: 保留
    j default_handler       # 0x00
    j default_handler       # 0x04
    j default_handler       # 0x08
    j software_handler      # 0x0C — Software (ID=3)
    j default_handler       # 0x10
    j default_handler       # 0x14
    j default_handler       # 0x18
    j timer_handler         # 0x1C — Timer (ID=7)
    j default_handler       # 0x20
    j default_handler       # 0x24
    j default_handler       # 0x28
    j external_handler      # 0x2C — External/GPIO (ID=11)

# ============================================================
# Default Handler (cause 0-2, 4-6, 8-10)
# ============================================================
default_handler:
    csrr t0, mcause
    sw   t0, 0x80(s0)       # 记录 mcause 到 data RAM
    mret

# ============================================================
# Timer ISR (cause=7)
# ============================================================
timer_handler:
    # === 立即读 mcycle 作为 entry 时间戳 ===
    csrr t0, mcycle
    sw   t0, 0x40(s0)       # mem[64] = Timer entry mcycle

    # 清除 Timer 中断源
    li   t1, 0x10002000
    sw   zero, 0(t1)        # CTRL = 0 (disable timer)

    # 重新使能 MIE (CLIC 硬件可能会自动关 MIE, 需确认)
    li   t1, 0x00001888
    csrw mstatus, t1

    # 写 marker 到 data RAM
    li   t1, 0xDEAD0001
    sw   t1, 0x44(s0)       # mem[65] = 0xDEAD0001

    # 读 mcycle 作为 exit 时间戳
    csrr t0, mcycle
    sw   t0, 0x48(s0)       # mem[66] = Timer exit mcycle

    mret

# ============================================================
# Software ISR (cause=3)
# ============================================================
software_handler:
    csrr t0, mcycle
    sw   t0, 0x00(s0)       # mem[64] = SW entry mcycle

    li   t1, 0xCAFE0003
    sw   t1, 0x04(s0)       # mem[65] = marker

    # 清除软件中断
    csrci mip, 8            # 清除 MSIP bit

    csrr t0, mcycle
    sw   t0, 0x08(s0)       # mem[66] = SW exit mcycle
    mret

# ============================================================
# External / GPIO ISR (cause=11, 最高优先级)
# ============================================================
external_handler:
    csrr t0, mcycle
    sw   t0, 0x70(s0)       # mem[72] = GPIO entry mcycle

    li   t1, 0xBEEF0001
    sw   t1, 0x74(s0)       # mem[73] = marker

    # 清除 GPIO 中断标志
    li   t1, 0x10003000     # GPIO 基址
    li   t2, 1
    sw   t2, 0x14(t1)       # IF = 1 (write 1 to clear)

    csrr t0, mcycle
    sw   t0, 0x78(s0)       # mem[74] = GPIO exit mcycle
    mret

# ============================================================
# 数据段
# ============================================================
.section .data
.align 4
.globl s0
s0:
    .word 0x10000000  # data RAM 基址 (用于存放测量结果)
```

### 3.3 两级嵌套测试 (test2_nested.S)

在 Timer ISR 执行过程中（MIE 重新使能后），触发 GPIO 嵌套：

```assembly
# test2_nested.S — 两级嵌套中断测试 (Timer → GPIO)

# ... (前面和 test1 一样, 在 timer_handler 中增加以下逻辑) ...

timer_handler:
    csrr t0, mcycle
    sw   t0, 0x40(s0)       # mem[64] = Timer entry mcycle

    # 清除 Timer
    li   t1, 0x10002000
    sw   zero, 0(t1)

    # 重新使能 MIE (允许 GPIO 嵌套)
    li   t1, 0x00001888
    csrw mstatus, t1

    # 写 marker
    li   t1, 0xDEAD0001
    sw   t1, 0x44(s0)       # mem[65] = Timer marker

    # === 嵌套窗口: 延时等待 GPIO 触发 ===
    li   t2, 50
timer_delay:
    addi t2, t2, -1
    bnez t2, timer_delay
    # === GPIO 在此时触发 (测试平台在约 300 周期后拉高 GPIO) ===

    csrr t0, mcycle
    sw   t0, 0x48(s0)       # mem[66] = Timer exit mcycle
    mret

external_handler:
    csrr t0, mcycle
    sw   t0, 0x50(s0)       # mem[72] = GPIO entry mcycle

    li   t1, 0xBEEF0001
    sw   t1, 0x54(s0)       # mem[73] = GPIO marker

    # 清除 GPIO
    li   t1, 0x10003000
    li   t2, 1
    sw   t2, 0x14(t1)

    csrr t0, mcycle
    sw   t0, 0x58(s0)       # mem[74] = GPIO exit mcycle
    mret
```

### 3.4 三级嵌套测试 (test3_triple.S)

SW → Timer → GPIO 三级嵌套：

```assembly
# test3_triple.S — 三级嵌套: Software → Timer → GPIO

_start:
    # ... 初始化 mtvec, mstatus, mie ...

    # 触发软件中断 (写 MSIP)
    li   t0, 8
    csrs mip, t0             # 设置 MSIP bit → 触发 Software 中断

main_loop:
    wfi
    j    main_loop

software_handler:
    csrr t0, mcycle
    sw   t0, 0x00(s0)       # mem[64] = SW entry mcycle

    li   t1, 0xCAFE0003
    sw   t1, 0x04(s0)       # mem[65] = SW marker

    # 清除软件中断
    csrci mip, 8

    # 使能 MIE + 使能 Timer (Timer 会在 SW ISR 内超时)
    li   t1, 0x00001888
    csrw mstatus, t1
    li   t1, 0x10002000
    li   t2, 200
    sw   t2, 4(t1)
    li   t2, 3
    sw   t2, 0(t1)           # Timer 启动, 200 周期后超时

    # 延时等待 Timer 超时
    li   t2, 300
sw_delay:
    addi t2, t2, -1
    bnez t2, sw_delay

    csrr t0, mcycle
    sw   t0, 0x08(s0)       # mem[66] = SW exit mcycle
    mret

timer_handler:
    csrr t0, mcycle
    sw   t0, 0x40(s0)       # mem[72] = Timer entry (nested in SW)

    li   t1, 0xDEAD0007
    sw   t1, 0x44(s0)       # mem[73] = Timer marker

    # 清除 Timer, 使能 MIE, 等待 GPIO
    li   t1, 0x10002000
    sw   zero, 0(t1)
    li   t1, 0x00001888
    csrw mstatus, t1

    # 延时等 GPIO
    li   t2, 100
timer_delay2:
    addi t2, t2, -1
    bnez t2, timer_delay2

    csrr t0, mcycle
    sw   t0, 0x48(s0)       # mem[74] = Timer exit mcycle
    mret

external_handler:
    csrr t0, mcycle
    sw   t0, 0x70(s0)       # mem[80] = GPIO entry (nested in Timer)

    li   t1, 0xBEEF000B
    sw   t1, 0x74(s0)       # mem[81] = GPIO marker

    li   t1, 0x10003000
    li   t2, 1
    sw   t2, 0x14(t1)       # 清除 GPIO

    csrr t0, mcycle
    sw   t0, 0x78(s0)       # mem[82] = GPIO exit mcycle
    mret
```

### 3.5 编译与转换

```bash
# 编译
cd ~/opene902/tests
riscv-none-elf-gcc -march=rv32imac -mabi=ilp32 -nostdlib \
    -T ../tools/link.ld -o test1_single_intr.elf test1_single_intr.S

# 转为 hex (verilog 格式, @ 地址标记)
riscv-none-elf-objcopy -O verilog test1_single_intr.elf test1_single_intr.hex

# 如果 OpenE902 使用纯 hex (无 @ 标记):
riscv-none-elf-objcopy -O binary test1_single_intr.elf test1_single_intr.bin
# 然后用 xxd 或 od 转 hex
xxd -p -c 4 test1_single_intr.bin > test1_single_intr.hex
```

---

## 4. 仿真运行

### 4.1 修改 testbench 以触发中断

OpenE902 的 testbench 需要加入 GPIO 和软件中断的时序触发：

```verilog
// tb/e902_tb.v — 在 testbench 中添加以下内容

// 软件中断触发 (约 100 周期后)
initial begin
    #10000;  // 100 个时钟周期 @ 10ns = 1000ns
    tb.u_e902.u_core.sw_intr = 1;
    #100;
    tb.u_e902.u_core.sw_intr = 0;
end

// GPIO 外部中断触发 (约 300 周期后)
initial begin
    #30000;  // 300 个时钟周期
    tb.u_e902.u_core.gpio_intr = 1;
    #100;
    tb.u_e902.u_core.gpio_intr = 0;
end
```

> **关键**: 具体的信号名和路径取决于 E902 的 RTL 层次结构。需要通过 `grep -r "intr" rtl/` 找到软件中断和外部中断的输入端口名称，然后在 testbench 中添加对应驱动。

### 4.2 运行仿真

```bash
cd ~/opene902/smart_run

# 单次中断
make clean && make run CASE=test1_single_intr HEX=../tests/test1_single_intr.hex \
    2>&1 | tee ~/e902_test1.log

# 两级嵌套
make clean && make run CASE=test2_nested HEX=../tests/test2_nested.hex \
    2>&1 | tee ~/e902_test2.log

# 三级嵌套
make clean && make run CASE=test3_triple HEX=../tests/test3_triple.hex \
    2>&1 | tee ~/e902_test3.log
```

### 4.3 提取 mcycle 测量值

仿真 log 中搜索 data RAM 地址的写入（或使用 VCD dump）：

```bash
# 从 VCD 波形中提取
# 或者修改 testbench 在仿真结束时打印 data RAM 区域
# 或者在 Makefile 中加入 monitor 语句

# 检查 marker 值确认测试通过
grep -E "0xDEAD|0xBEEF|0xCAFE" ~/e902_test3.log
```

---

## 5. 数据收集表格

完成所有测试后，将结果填入以下表格：

### 单次中断延迟

| 测试项 | mcycle 值 | 说明 |
|--------|:--:|------|
| Timer ISR entry | | 从中断触发到 ISR 第一条指令的 cycle |
| Timer ISR exit | | 从 MRET 到主程序恢复的 cycle |
| Marker mem[65] | 0xDEAD0001 | 确认 ISR 正确执行 |

### 两级嵌套 (Timer → GPIO)

| 测试项 | mcycle 值 | 说明 |
|--------|:--:|------|
| Timer entry mcycle | | 第一层 ISR 入口 |
| GPIO entry mcycle | | 嵌套层 ISR 入口 |
| Delta (Timer→GPIO) | | GPIO entry − Timer entry |
| GPIO exit mcycle | | GPIO ISR MRET |
| Timer exit mcycle | | Timer ISR MRET |
| Cumulative overhead | | 从 Timer entry 到 Timer exit 的周期差 |

### 三级嵌套 (SW → Timer → GPIO)

| 测试项 | mcycle 值 | 说明 |
|--------|:--:|------|
| SW entry / Timer entry / GPIO entry | | 三级 ISR 入口 |
| 每层 entry 间隔 | | 验证 entry 延迟是否恒定 |
| Cumulative overhead | | 从第一层 entry 到最后层 exit |

---

## 6. 与 FX-RV32-X 对比

测试完成后，将实测数据填入论文 Table IV 的 CLIC 列（替换当前的理论推算值），并更新对比结论。

FX-RV32-X 实测数据（供对比）：

| 嵌套深度 | Entry 延迟 | Exit 延迟 | 累计 |
|:--:|:--:|:--:|:--:|
| 1 层 (SW) | 2 cycles | 3 cycles | 5 cycles |
| 2 层 (+Timer) | 2 cycles | 3 cycles | 10 cycles |
| 3 层 (+GPIO) | 2 cycles | 3 cycles | 15 cycles |

---

## 7. 常见问题

### Q1: OpenE902 仿真跑不起来

- 检查 iverilog 版本 ≥ 10.0
- 确认 RTL 文件列表完整（`smart_run/filelist.f` 或类似文件）
- 某些版本可能需要 VCS/QuestaSim 而不是 iverilog；如果只有商业仿真器，改 Makefile 中的 SIMULATOR 变量

### Q2: 找不到中断输入信号

- `grep -r "intr\|irq" rtl/e902/core/` 找外部中断端口
- E902 的中断控制器通常在 `rtl/e902/core/cpu_core.v` 或独立的 `clic_top.v`

### Q3: mcycle CSR 读不出来

- E902 可能用 csr `mcycle` 也可能用 `cycle`。试试 `csrr t0, cycle`。
- 如果 E902 没有硬件 mcycle，换成 `rdcycle t0` 伪指令

### Q4: 编译报错 (riscv-none-elf-gcc)

- 确保 `-march=rv32imac` 匹配 E902 支持的 ISA
- link.ld 需要定义正确的内存布局。如果默认的没有，用最简单的：
  ```
  SECTIONS { . = 0x00000000; .text : { *(.text) } . = 0x10000000; .data : { *(.data) } }
  ```

---

## 8. 期待的输出

最后请将以下内容整理到一个文件中（如 `~/e902_nested_results.md`）：

1. 环境信息（OS, 仿真器版本）
2. 是否成功跑通全部 3 个测试
3. 每个测试的 mcycle 测量值
4. CLIC 嵌套延迟的计算结果
5. 与 FX-RV32-X 的对比

这些数据将用于更新论文 `bare_jrnl_new_sample4_v2.tex` 的 Table IV。
