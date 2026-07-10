# FX-RV32 UVM 使用指南

本文覆盖日常使用 UVM 验证环境的全部操作：编译、运行、切换测试、看波形、查覆盖率。

---

## 0. 前置准备：生成 hex 文件

在 `python/` 目录下执行：

```bash
cd python
for f in alu_test intr_test load_use_test store_test gpio_toggle_test \
         nested_test context_integrity_test degradation_test \
         tail_chain_test triple_nested_test overflow_test; do
    python asm_to_hex.py ../uvm/${f}.s ../uvm/${f}.hex
done
```

---

## 1. 快速启动

### 1.1 方式一：Windows 批处理（最简单）

```cmd
cd uvm
run_uvm.bat nested gui     # 嵌套中断 + 波形
run_uvm.bat triple gui     # 三级嵌套 + 波形
run_uvm.bat hazard gui     # 冒险测试 + 波形
run_uvm.bat intr gui       # 中断测试 + 波形
run_uvm.bat alu gui        # ALU 测试 + 波形
run_uvm.bat overflow gui   # 溢出测试 + 波形
run_uvm.bat tailchain gui  # 尾链测试 + 波形
run_uvm.bat context gui    # 寄存器完整性 + 波形
run_uvm.bat degradation gui # 降级复用 + 波形
```

不带 `gui` 则为命令行模式（无波形窗口）：
```cmd
run_uvm.bat nested
```

### 1.2 方式二：Modelsim TCL（灵活控制参数）

打开 Modelsim，Transcript 中输入：

```tcl
cd uvm
set HEX_FILE nested_test.hex
set TEST_NAME cpu_test_nested
do run_msim.tcl
```

自定义 Bank 数量：
```tcl
set HEX_FILE overflow_test.hex
set TEST_NAME cpu_test_overflow
set SHADOW_BANKS 1
set OVERFLOW_POLICY 0
do run_msim.tcl
```

---

## 2. 测试矩阵

| 测试名（bat 用）| TEST_NAME | HEX_FILE | 参数 | 检查点 |
|:---|:---|:---|:---|---|
| alu | cpu_test_alu | alu_test.hex | — | mem[0]-mem[8] 全部匹配 |
| hazard | cpu_test_hazard | load_use_test.hex | — | x3 无重复递增 |
| intr | cpu_test_interrupt | intr_test.hex | — | tohost=0, mem[64]=DEAD0001 |
| nested | cpu_test_nested | nested_test.hex | BANKS=4 | mem[64]=DEAD0001, mem[65]=BEEF0001 |
| context | cpu_test_context | context_integrity_test.hex | BANKS=4 | tohost=0 (x1-x31 全部恢复) |
| degradation | cpu_test_degradation | degradation_test.hex | BANKS=1 POL=1 | mem[65]=BEEF0003 |
| tailchain | cpu_test_tailchain | tail_chain_test.hex | BANKS=4 | tail_chain flag=1, timer/gpio >=1 |
| triple | cpu_test_triple | triple_nested_test.hex | BANKS=4 | SW+Timer+GPIO 三级 marker |
| overflow | cpu_test_overflow | overflow_test.hex | BANKS=1 POL=0 | mem[64]=DEAD0001, mem[65]=BEEF0002 |
| coremark | cpu_test_coremark | ../sim/program.hex | — | perf_score != 0 |

---

## 3. 波形操作

### 3.1 波形窗口布局

仿真启动后自动打开 Wave 窗口，信号已按功能分组：

```
┌─ Wave ─────────────────────────────────────────────────┐
│ ▼ Clock & Reset                                         │
│   clk         ┌─┐┌─┐┌─┐┌─┐┌─┐┌─┐                       │
│   rst_n       ──────────┘                               │
│ ▼ Interrupt (★ 重点观察)                                 │
│   intr_take_now  ────┐  ┌──                            │
│   interrupt_taken ───┐  ┌── (单周期脉冲)                  │
│   bank_ptr      00   01   02   01   00                   │
│   shadow_save   ────┐  ┌── (与 interrupt_taken 同沿)     │
│   shadow_restore ───────────────┐  ┌──                   │
│ ▼ Pipeline Ctrl                                          │
│   stall_if, flush_if, flush_id                           │
│   forwardA[1:0], forwardB[1:0]                          │
│ ▼ CSR                                                    │
│   mstatus_o, mepc_o, mcause_o, mie_o                    │
│ ▼ Data RAM                                               │
│   mem[64], mem[65], mem[66]                             │
│ ▼ GPIO                                                   │
│   gpio_pin0, gpio_out[0], gpio_oe[0]                    │
└─────────────────────────────────────────────────────────┘
```

### 3.2 关键波形检查点

**中断进入（Timer 为例）**：
1. `intr_take_now` = 1（组合逻辑，持续 1 周期）
2. 下一个时钟沿：`interrupt_taken` = 1（单周期脉冲），`PC` 跳转到 handler
3. 同时：`shadow_save` = 1，`bank_ptr` 递增（0→1）
4. `flush_if` 在中断期间 = 0（IF/ID 不冲刷）

**嵌套中断（GPIO 抢占）**：
5. Timer ISR 执行中 → GPIO rise → `intr_take_now` = 1
6. `bank_ptr` 递增（1→2），`shadow_save` = 1
7. `mcause` 变为 0x8000000B（GPIO ID=11）

**中断返回（MRET）**：
8. `id_ex_mret` = 1（在 EX 阶段持续 1 周期）
9. `shadow_restore` = 1，`bank_ptr` 递减（2→1→0）

### 3.3 操作技巧

| 操作 | 方法 |
|------|------|
| 放大/缩小 | 鼠标滚轮 或 工具栏 🔍➕/🔍➖ |
| 测量时间差 | 鼠标左键拖选 → 看左下角 Δ 值 |
| 搜索信号 | Ctrl+F → 输入信号名 |
| 添加信号 | Objects 窗口拖到 Wave 窗口 |
| 改显示格式 | 右键信号 → Radix → Hexadecimal |
| 保存波形 | File → Save Dataset → 选 `.wlf` |
| 看完整波形 | 工具栏 Zoom Full 按钮 |

---

## 4. 覆盖率

### 4.1 功能覆盖率（UVM）

仿真结束后 Transcript 自动打印：
```
UVM_INFO : ========================================
UVM_INFO :   Functional Coverage Summary
UVM_INFO : ========================================
UVM_INFO :   cg_instr_types:    87%
UVM_INFO :   cg_interrupt:      100%
UVM_INFO :   cg_nesting_depth:  100%
UVM_INFO :   cg_bank_overflow:  100%
UVM_INFO :   cg_tail_chain:     100%
UVM_INFO : ========================================
```

### 4.2 代码覆盖率（Modelsim）

菜单 **Tools → Coverage → Report**，双击任意文件查看行覆盖（绿色=已覆盖，红色=未覆盖）。

---

## 5. 常见问题

**Q: "Cannot open hex file"？**  
先执行第 0 步的汇编命令。

**Q: UVM 库找不到？**
```tcl
set UVM_HOME C:/modeltech/uvm-1.2
```

**Q: 想跑 BRAM 模式怎么弄？**  
`run_msim.tcl` 默认是 inst_rom 模式。改 BRAM 需额外设置 `USE_INST_ROM=0`。
