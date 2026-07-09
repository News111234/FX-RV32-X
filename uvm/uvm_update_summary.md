# FX-RV32 UVM 验证环境更新摘要

**日期**: 2026-07-02  
**更新内容**: 适配多 Bank 影子寄存器扩展 + 新增嵌套中断测试 + 波形配置

---

## 1. 新增测试程序

以下测试程序从 `sim/` 同步至 `uvm/`，用于验证多 Bank 影子寄存器功能：

| 测试 | .s 文件 | 验证内容 |
|------|---------|---------|
| nested_test | uvm/nested_test.s | 两级嵌套 (Timer→GPIO) |
| context_integrity_test | uvm/context_integrity_test.s | 嵌套返回后 x1-x31 完整性 |
| degradation_test | uvm/degradation_test.s | 降级复用策略 (POL=1) |
| tail_chain_test | uvm/tail_chain_test.s | 尾链优化 |
| triple_nested_test | uvm/triple_nested_test.s | 三级嵌套 (SW→Timer→GPIO) |
| overflow_test | uvm/overflow_test.s | Bank 溢出 (BANKS=1, POL=0) |

**汇编方法**（在 `python/` 目录下）：
```bash
for f in nested_test context_integrity_test degradation_test tail_chain_test triple_nested_test overflow_test; do
    python asm_to_hex.py ../uvm/${f}.s ../uvm/${f}.hex
done
```

---

## 2. UVM 测试类新增

`riscv_uvm_pkg.sv` 新增以下测试类：

| 测试类 | 对应 HEX_FILE | 参数 |
|--------|-------------|------|
| `cpu_test_nested` | nested_test.hex | BANKS=4 |
| `cpu_test_context` | context_integrity_test.hex | BANKS=4 |
| `cpu_test_degradation` | degradation_test.hex | BANKS=1, POL=1 |
| `cpu_test_tailchain` | tail_chain_test.hex | BANKS=4 |
| `cpu_test_triple` | triple_nested_test.hex | BANKS=4 |
| `cpu_test_overflow` | overflow_test.hex | BANKS=1, POL=0 |

每个测试类的 `main_phase` 负责：
1. 加载 hex 程序到 inst_rom
2. 释放复位
3. 在指定时间触发 GPIO/软件中断
4. 等待 tohost 或超时
5. 比对 data_ram 中的 marker 值

---

## 3. UVM TCL 运行脚本更新

`run_msim.tcl` 新增 TCL 变量：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `SHADOW_BANKS` | 4 | Bank 数量 (1/2/4/8) |
| `OVERFLOW_POLICY` | 0 | 溢出策略 (0=硬限制, 1=降级复用) |

使用示例：
```tcl
set HEX_FILE nested_test.hex
set TEST_NAME cpu_test_nested
set SHADOW_BANKS 4
do run_msim.tcl
```

---

## 4. 波形关键信号组

UVM 仿真自动添加以下波形分组：

| 信号组 | 关键信号 | 观察要点 |
|--------|---------|---------|
| Clock & Reset | clk, rst_n | 200MHz (2.5ns 半周期) |
| Interrupt | intr_pending, intr_take_now, interrupt_taken, bank_ptr, shadow_save/restore | 中断进入/退出边沿 |
| IF Stage | if_pc, if_instr | 中断时 PC 跳转 |
| Pipeline Ctrl | stall_if, flush_if, flush_id, forwardA/B | 中断冲刷期间 flush_if=0 |
| CSR | mstatus_o, mepc_o, mcause_o, mie_o, mip_o | MIE 变化, 中断原因 |
| Data RAM | mem[64]-mem[68] | 各 ISR 写入的 marker |
| GPIO | gpio_pin0, gpio_out, gpio_oe | 外部中断触发时序 |

---

## 5. 文件清单

```
uvm/
├── nested_test.s / .hex                   # 新增
├── context_integrity_test.s / .hex        # 新增
├── degradation_test.s / .hex              # 新增
├── tail_chain_test.s / .hex               # 新增
├── triple_nested_test.s / .hex            # 新增
├── overflow_test.s / .hex                 # 新增
├── riscv_uvm_pkg.sv                       # 修改: 新增6个测试类
├── uvm_tb_top.sv                          # 修改: 新增 SHADOW_BANKS/OVERFLOW_POLICY 参数
├── run_msim.tcl                           # 修改: 新增 SHADOW_BANKS/OVERFLOW_POLICY 变量
├── run_uvm.bat                            # 修改: 新增嵌套/溢出等快速启动
├── uvm_update_summary.md                  # 本文件
├── UVM_USER_GUIDE.md                      # 新增: UVM 使用指南
└── UVM_TUTORIAL.md                        # 新增: UVM 入门教程
```
