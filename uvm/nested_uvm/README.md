# FX-RV32-X 嵌套中断 UVM 验证环境（论文专用）

本目录包含用于 TVLSI 第二篇论文的 10 项嵌套中断测试的 UVM 验证环境。
与 `uvm/` 目录下的通用 UVM 环境独立，本环境专为多 Bank 影子寄存器论文验证设计。

---

## 环境结构

```
nested_uvm/
├── cpu_if.sv         # UVM interface (GPIO + 软件中断驱动)
├── nested_pkg.sv      # UVM 组件包 (driver/monitor/scoreboard + 10个test类)
├── tb_top.sv          # 顶层 testbench (实例化 soc_top)
├── run_nested.tcl     # 一键运行脚本
└── README.md          # 本文件
```

**DUT**: `soc_top`（含 inst_rom + data_ram + 总线仲裁 + UART/GPIO/Timer/SPI/I2C 全部外设）

---

## 快速开始

### 1. 准备 hex 文件

```bash
cd python
for f in single_intr_test ultra_min_test no_intr_test nested_test \
         overflow_test overflow_minimal context_integrity_test \
         degradation_test tail_chain_test triple_nested_test; do
    python asm_to_hex.py ../sim/${f}.s ../sim/${f}.hex
done
```

将生成的 `.hex` 文件复制到 `uvm/nested_uvm/` 目录下。

### 2. 运行测试

**控制台模式**（无波形）:
```tcl
cd uvm/nested_uvm
vsim -c -do "set TEST test_nested; do run_nested.tcl"
```

**GUI 模式**（含波形）:
```tcl
cd uvm/nested_uvm
vsim -do "set TEST test_nested; set GUI 1; do run_nested.tcl"
```

**指定 Bank 数量**:
```tcl
vsim -c -do "set TEST test_overflow; set BANKS 1; set POL 0; do run_nested.tcl"
vsim -c -do "set TEST test_degradation; set BANKS 1; set POL 1; do run_nested.tcl"
```

---

## 测试列表

| TEST 名称 | 对应测试 | BANKS | POL | 检查点 |
|-----------|---------|:-----:|:---:|--------|
| `test_single_intr` | 单次 Timer 中断 | 4 | 0 | tohost=0 |
| `test_ultra_min` | 最小中断 | 4 | 0 | mem[64]=0x42 |
| `test_no_intr` | 无中断 | 4 | 0 | mem[64]=0x42 |
| `test_nested` | 两级嵌套 Timer→GPIO | 4 | 0 | mem[64]=DEAD0001, mem[65]=BEEF0001 |
| `test_overflow` | Bank溢出 (POL=0) | 1 | 0 | mem[64]=DEAD0001, mem[65]=BEEF0002 |
| `test_overflow_min` | 单Bank最小ISR | 1 | 0 | mem[64]=0x42 |
| `test_context` | 寄存器完整性 | 4 | 0 | tohost=0 |
| `test_degradation` | 降级复用 (POL=1) | 1 | 1 | mem[65]=BEEF0003 |
| `test_tailchain` | 尾链优化 | 4 | 0 | mem[64]=1 |
| `test_triple` | 三级嵌套 SW→Timer→GPIO | 4 | 0 | mem[64]=CAFE0003, mem[65]=DEAD0007, mem[66]=BEEF000B |

---

## 波形信号

GUI 模式下自动添加以下波形组：

| 信号组 | 信号 | 说明 |
|--------|------|------|
| Interrupt | interrupt_taken_pipe, bank_ptr, shadow_save, shadow_restore | 中断接受 + Bank 指针变化 |
| Data RAM | mem[64], mem[65], mem[66] | 各 ISR 写入的 marker 值 |
| GPIO | gpio_pin0 | 外部中断触发时序 |

---

## 与 sim/ 测试的关系

| | `uvm/nested_uvm/` | `sim/` |
|---|---|---|
| DUT | soc_top | soc_top |
| Testbench | UVM 组件化 | 纯 Verilog tb_nested_check.v |
| 适用场景 | 论文正式验证 + 覆盖率 | 快速功能调试 |
| 波形 | UVM 日志 + Wave 窗口 | VCD dump |
| 运行方式 | TCL 脚本 | DO 文件 / bash 脚本 |

两个环境的测试程序和检查点完全一致，结果可直接互相印证。

---

## 与 uvm/ 的关系

`uvm/` 目录下的 UVM 环境采用 `core_top` 作为 DUT，适用于：
- 冒险检测 (load-use hazard)
- ALU 指令验证
- 基础中断测试 (core_top_sim 内部外设)

`uvm/nested_uvm/` 采用 `soc_top` 作为 DUT，专用于：
- 多 Bank 嵌套中断验证
- Bank 溢出/降级复用验证
- 尾链优化验证
- 三级嵌套验证

两者独立编译、独立运行，互不干扰。
