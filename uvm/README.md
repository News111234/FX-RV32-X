# FX-RV32 UVM 验证环境 — 使用指南

## 0. 前置准备（只需做一次）

### 生成 hex 测试文件

打开终端，进 `python` 目录，把三个汇编文件转成 hex：

```bash
cd python
python riscv_asm7.py ../uvm/alu_test.s     > ../uvm/alu_test.hex
python riscv_asm7.py ../uvm/intr_test.s     > ../uvm/intr_test.hex
python riscv_asm7.py ../uvm/load_use_test.s > ../uvm/load_use_test.hex
```

三个 hex 文件生成在 `uvm/` 目录下就对了。

---

## 1. 图形界面操作（全程点按钮）

### 1.1 打开 Modelsim

双击 Modelsim 图标，看到主窗口：

```
┌─────────────────────────────────────────────────┐
│ 菜单栏: File  Edit  View  Compile  Simulate ... │
├─────────────────────────────────────────────────┤
│                                                 │
│   Workspace 区域                                │
│   (Project / Library / sim 标签页)               │
│                                                 │
├─────────────────────────────────────────────────┤
│  Transcript 窗口                                │
│  ModelSim> _                                    │
└─────────────────────────────────────────────────┘
```

### 1.2 切换工作目录

在 **Transcript** 窗口底部输入：

```
cd uvm
```

就是把当前目录切到 `uvm/` 文件夹。

### 1.3 一键运行

在 **Transcript** 输入：

```
do run_msim.tcl
```

这会自动完成：编译 RTL → 编译 UVM 环境 → 启动仿真。

如果想跑不同的测试，先设置变量再 `do`：

```
set TEST_NAME cpu_test_interrupt
set HEX_FILE intr_test.hex
do run_msim.tcl
```

或者用 Windows 批处理（退出 Modelsim，在 cmd 里跑）：

```cmd
cd uvm
run_uvm.bat hazard gui
```

### 1.4 仿真运行中你会看到什么

Transcript 窗口开始刷 UVM 日志：

```
# UVM_INFO @ 0: reporter [RNTST] Running test cpu_test_hazard...
# UVM_INFO @ 100: uvm_tb_top.u_dut [MON] [25] STALL_IF asserted, PC=0x...
# UVM_INFO @ 150: uvm_tb_top.u_dut [MON] [30] WB: x3 <= 0xDEADBEF0
# ...
```

同时自动弹出 **Wave** 波形窗口，信号已经分组好：

```
┌─ Wave ──────────────────────────────────────────┐
│ ▼ Clock & Reset                                 │
│   clk        ┌─┐┌─┐┌─┐┌─┐                       │
│   rst_n      ──────┘                            │
│ ▼ IF Stage                                      │
│   if_pc      0x00  0x04  0x08                   │
│   if_instr   0x... 0x... 0x...                   │
│ ▼ ID Stage                                      │
│   ...                                           │
│ ▼ Pipeline Ctrl    ◀── 重点看这里!               │
│   stall_if   ──────┐  ┌──────                   │
│   stall_id   ──────┘  └──────                   │
│   forwardA   00   01   10                        │
└─────────────────────────────────────────────────┘
```

### 1.5 仿真结束后看结果

Transcript 窗口最后几行会打印测试结论：

```
# UVM_INFO : Test1 (lw+add):  got=0xDEADBEF0 expected=0xDEADBEF0 [PASS]
# UVM_INFO : Test2 (lw+addi): got=0xCAFEBBBE expected=0xCAFEBBBE [PASS]
# UVM_INFO : Test3 (lw+sw):   got=0xDEADBEEF expected=0xDEADBEEF [PASS]
# UVM_INFO : *** ALL HAZARD TESTS PASSED ***
```

---

## 2. 怎么看覆盖率

### 2.1 功能覆盖率（UVM 自己统计的）

仿真跑完后，Transcript 里会自动打印：

```
# UVM_INFO : ========================================
# UVM_INFO :   Functional Coverage Summary
# UVM_INFO : ========================================
# UVM_INFO :   cg_instr_types:  87%
# UVM_INFO :   cg_memory_ops:   100%
# UVM_INFO :   cg_stall:        100%
# UVM_INFO :   cg_forwarding:   66%
# UVM_INFO : ========================================
```

- `cg_stall: 100%` → load-use 停顿被触发过了
- `cg_forwarding: 66%` → 可能 MEM/WB 转发没覆盖到（正常，取决于测试程序）
- `cg_instr_types: 87%` → 还有些目标寄存器没被写过

### 2.2 代码覆盖率（Modelsim 自带的）

这是更详细的覆盖率，看每一行 Verilog 代码是否被执行过。

**步骤**：

**①** 菜单栏点 **Tools** → **Coverage** → **Report**

```
Tools → Coverage → Report
```

**②** 弹出的窗口里什么都不用改，直接点 **OK**

**③** Modelsim 会打开一个 Coverage 查看窗口，左侧是文件树：

```
┌─ Coverage Report ───────────────────────────────┐
│ 文件                    语句   分支   条件   翻转  │
│ core_top.v              87%    72%    65%    58% │
│ hazard_unit.v           100%   100%   100%   -   │
│ forwarding_unit.v       100%   100%   -      -   │
│ interrupt_pipeline.v    45%    30%    -      -   │
│ ...                                             │
└─────────────────────────────────────────────────┘
```

**④** 双击任意文件（比如 `hazard_unit.v`），可以看到源代码窗口里每行代码用颜色标记：绿色=覆盖过，红色=从未执行。

---

## 3. 三种测试快速切换

| 你想跑什么 | Transcript 输入 |
|-----------|----------------|
| 基础指令测试 | `set TEST_NAME cpu_test_alu; do run_msim.tcl` |
| 中断测试 | `set HEX_FILE intr_test.hex; set TEST_NAME cpu_test_interrupt; do run_msim.tcl` |
| 冒险测试 | `set HEX_FILE load_use_test.hex; set TEST_NAME cpu_test_hazard; do run_msim.tcl` |

每次切换测试前，建议先清掉上次的编译结果：

```
vdel -all
```

### 或者用 Windows 批处理（更简单）

关掉 Modelsim，打开 cmd：

```cmd
cd uvm
run_uvm.bat hazard gui      ← 冒险测试 + 波形
run_uvm.bat intr gui        ← 中断测试 + 波形
run_uvm.bat alu gui         ← 基础测试 + 波形
```

---

## 4. 波形窗口怎么操作

| 你想做什么 | 怎么操作 |
|-----------|---------|
| 放大/缩小 | 工具栏 🔍➕ / 🔍➖ 按钮，或鼠标滚轮 |
| 看完整波形 | 点工具栏 **Zoom Full** 按钮（一个方框里有四个箭头） |
| 测量时间差 | 鼠标左键点起点 → 拖到终点 → 看左下角显示的 Δ 值 |
| 搜信号 | Ctrl+F → 输入信号名 → 回车 |
| 添加信号到波形 | 在左侧 Objects 窗口找到信号 → 拖到 Wave 窗口 |
| 改变显示格式 | 右键信号 → **Radix** → 选 Hexadecimal / Decimal / Binary |
| 保存波形配置 | File → Save Dataset → 下次直接打开 `.wlf` 文件 |

---

## 5. 常见问题

**Q: 输入 `do run_msim.tcl` 后报 "Cannot open hex file"？**

先做第 0 步——用 Python 汇编器生成 `.hex` 文件放到 `uvm/` 目录下。

**Q: UVM 库找不到？**

在 Transcript 里先设置环境变量：
```
set UVM_HOME C:/modeltech/uvm-1.2
```
然后再 `do run_msim.tcl`。

**Q: 仿真跑了很久不结束？**

可能是程序死循环了。点工具栏 **Break** 按钮停止，检查测试程序的跳转逻辑。
