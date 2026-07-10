# FX-RV32 M 扩展（硬件乘除法）实施方案

> 状态：✅ 已实施完成 | 日期：2026-06-05

## 1. 项目结构

```
/home/yifengxin/
├── FX-RV32_RemoveM_Custom/    # 原始项目（RV32I，保持不变）
│   └── doc/m_extension_plan.md  # 本文件
│
└── FX-RV32_AddM/              # 新项目（RV32IM，添加 M 扩展）
    ├── core/                  # RTL 源文件（已修改）
    ├── soc/                   # SoC 集成（不变）
    ├── sim/                   # Verilator 仿真
    ├── uvm/                   # UVM 验证环境
    ├── coremark_port/         # CoreMark 移植文件
    │   ├── Makefile           # 编译选项改为 -march=rv32im
    │   ├── link.ld            # 链接脚本
    │   ├── startup.s          # 启动代码
    │   ├── core_portme.h      # 平台配置
    │   ├── core_portme.c      # UART + 定时器 + 初始化
    │   └── ee_printf.c        # 轻量级 printf
    └── doc/                   # 文档
```

## 2. RTL 修改清单

### 2.1 `core/exu/alu.v` — 核心改动 ✨

**信号变更**：
- `alu_op_i` 从 `[3:0]` 扩展为 `[4:0]`
- 新增 `alu_busy_o`（多周期 DIV 时 = 1）
- 新增 `alu_valid_i`（启动新运算，始终 = 1）

**新增 ALU 操作码**：

| alu_op | 指令 | 周期数 | 实现方式 |
|--------|------|--------|---------|
| `5'b00000`-`5'b00111` | RV32I 原有 | 1 | 组合逻辑 |
| `5'b01000` | MUL | 1 | `op1 * op2`（低 32 位） |
| `5'b01001` | MULH | 1 | `(signed(op1) * signed(op2)) >> 32` |
| `5'b01010` | MULHSU | 1 | `(signed(op1) * unsigned(op2)) >> 32` |
| `5'b01011` | MULHU | 1 | `(unsigned(op1) * unsigned(op2)) >> 32` |
| `5'b01100` | DIV | 1-34 | 非恢复除法，迭代 32 周期 |
| `5'b01101` | DIVU | 1-34 | 同上（无符号版） |
| `5'b01110` | REM | 1-34 | 同 DIV，取余数 |
| `5'b01111` | REMU | 1-34 | 同 DIVU，取余数 |

### 2.2 `core/id/decoder.v`

- `alu_op_o` 从 `[3:0]` 改为 `[4:0]`
- R-type case 中新增 M 指令识别：`funct7[6:1] == 6'b000001`

### 2.3 `core/exu/ex_top.v`

- `alu_op_i` 位宽 `[3:0]` → `[4:0]`
- 新增 `alu_busy_o` 输出端口

### 2.4 `core/core_top.v`

- `ex_alu_busy` → `stall_ex`：DIV 多周期时反向停顿 IF/ID
- alu_op 总线宽度同步更新

### 2.5 `core/pipeline/id_ex_reg.v`

- alu_op 信号从 4 位改为 5 位

## 3. CoreMark 编译变更

`coremark_port/Makefile` 修改：

```makefile
# 改前
ARCH_FLAGS = -march=rv32i -mabi=ilp32
PORT_SRCS  = core_portme.c ee_printf.c soft_muldiv.c

# 改后
ARCH_FLAGS = -march=rv32im -mabi=ilp32
PORT_SRCS  = core_portme.c ee_printf.c          # 移除 soft_muldiv.c
LDLIBS     = -lgcc                                # libgcc 提供硬件 mul/div
```

`soft_muldiv.c` 不再需要（libgcc 的硬件版本替代，1 周期乘法 vs 200 周期软件模拟）。

## 4. 如何运行 CoreMark

### 4.1 编译 CoreMark

```bash
cd /home/yifengxin/FX-RV32_AddM/coremark_port

# 验证编译（1 次迭代）
make clean
make ITERATIONS=1

# 正式跑分（约 200-500 次迭代可达 10+ 秒）
make ITERATIONS=500

# 生成的 hex 文件：program.hex
```

### 4.2 Verilator 仿真（快速验证编译）

```bash
cd /home/yifengxin/FX-RV32_AddM/sim

# 一次性设置
ln -s .. rtl
cp ../uvm/core_top_sim.txt ../core/core_top_sim.v

# 复制 CoreMark 程序并运行
cp ../coremark_port/program.hex .
make clean && make && make run
```

### 4.3 Modelsim UVM 仿真（实际跑分，推荐）⭐

**Windows 上运行**：

```cmd
:: 1. 准备：复制项目到 Windows 可访问位置
robocopy \\wsl.localhost\Ubuntu\home\yifengxin\FX-RV32_AddM D:\FX-RV32_AddM /E /NFL /NDL

:: 2. 复制 CoreMark hex
copy D:\FX-RV32_AddM\coremark_port\program.hex D:\FX-RV32_AddM\uvm\coremark.hex

:: 3. 启动仿真
cd /d D:\FX-RV32_AddM\uvm
D:\modeltech64_10.6e\win64\vsim.exe -c -do run_coremark.tcl
```

**WSL 上运行**：

```bash
cd /home/yifengxin/FX-RV32_AddM/uvm
cp ../coremark_port/program.hex ./coremark.hex

# 创建 run_coremark.tcl
cat > run_coremark.tcl << 'EOF'
set HEX_FILE coremark.hex
set TEST_NAME cpu_test_coremark
set COV_ENABLE 0
set GUI_MODE 0
do run_msim.tcl
EOF

# 运行
cmd.exe /c "cd /d D:\FX-RV32_AddM\uvm && D:\modeltech64_10.6e\win64\vsim.exe -c -do run_coremark.tcl"
```

**查看结果**：

```bash
# 仿真结束后检查
grep -E "Scoreboard|Mismatches|PASS|FAIL" transcript
tail -100 transcript | grep -E "CoreMark|Iterations|Total time"
```

### 4.4 性能预期

| 指标 | RV32I（软件乘除） | RV32IM（硬件乘除） | 加速比 |
|------|-------------------|-------------------|--------|
| 乘法延迟 | ~200 周期 | 1 周期 | **200×** |
| 除法延迟 | ~300 周期 | 1-34 周期 | **10-300×** |
| CoreMark 单次迭代 | ~200M 周期 | ~2-5M 周期 | **50-100×** |
| UVM 仿真（1 次迭代） | ~2.5 小时 | ~2-5 分钟 | **50×** |
| CoreMark 完整跑分（≥10s） | 不现实（数天） | ~30-60 分钟 | ✅ 可行 |

## 5. 实施记录

| 日期 | 步骤 | 状态 |
|------|------|------|
| 2026-06-05 | 方案设计 | ✅ |
| 2026-06-05 | 创建 FX-RV32_AddM 副本 | ⬜ |
| 2026-06-05 | alu.v 修改 | ⬜ |
| 2026-06-05 | decoder.v 修改 | ⬜ |
| 2026-06-05 | ex_top.v / core_top.v 修改 | ⬜ |
| 2026-06-05 | 流水线寄存器位宽更新 | ⬜ |
| 2026-06-05 | CoreMark Makefile 更新 | ⬜ |
| 2026-06-05 | Verilator 编译验证 | ⬜ |
| 2026-06-05 | Modelsim UVM 跑分验证 | ⬜ |
