# FX-RV32 FPGA CoreMark 跑分指南

> 目标: 在 Kintex-7 FPGA 上运行 ITERATIONS=5000 的 CoreMark 并获取正式跑分
> 作者: Yi Fengxin, Beihang University

## 1. 为什么需要上 FPGA 跑

RTL 仿真和 FPGA 实跑的速度对比：

| 方式 | 速度 | 跑 CoreMark 5000 iterations |
|------|------|---------------------------|
| Modelsim 仿真 | ~225K 周期/分钟 | ~150 小时（6 天） |
| Verilator 仿真 | ~5-10M 周期/分钟 | ~3-7 小时 |
| **FPGA 实跑** | **200M 周期/秒（真实速度）** | **10 秒** |

仿真（无论 Modelsim 还是 Verilator）是用软件逐周期模拟硬件行为，比真实硬件慢数万倍。UVM 仿真已经验证了 CPU 逻辑正确性（Scoreboard Mismatches = 0），下一步直接上 FPGA 获取正式跑分。

**CoreMark 官方规则要求**：有效跑分需要运行时间 >= 10 秒。当前 ITERATIONS=500 只跑了 1 秒，需要增加到 ~5000 才能合规。如果在 Modelsim 里跑 5000 iterations，需要约 6 天——FPGA 只需要 10 秒。

## 2. 硬件准备

| 设备 | 说明 |
|------|------|
| **Kintex-7 FPGA 开发板** | Xilinx xc7k325tffg900-2 |
| **USB-to-UART 适配器** | 3.3V TTL 电平（如 FT232、CH340、CP2102） |
| **杜邦线** | 3 根（GND、TX） |
| **Micro-USB 下载线** | 用于 JTAG 下载 bitstream |

### 接线

```
FPGA 引脚 Y23 (uart_tx_o)  ────  USB-UART 适配器的 RX
FPGA GND 引脚              ────  USB-UART 适配器的 GND
```

> **注意**: FX-RV32 的 UART 是 **TX-only**（只发不收）。不需要接 RX 线。波特率 115200，8N1。

## 3. 软件准备

### 3.1 编译 CoreMark（ITERATIONS=5000）

```bash
cd /home/yifengxin/FX-RV32_AddM/coremark_port

# 编译 CoreMark，ITERATIONS=5000
make clean
make ITERATIONS=5000

# 确认生成的文件
ls -l coremark.elf coremark.bin program.hex
```

产物说明：
- `coremark.elf` — ELF 可执行文件（含调试信息）
- `coremark.bin` — 原始二进制
- `program.hex` — 32-bit 十六进制文本（用于仿真）

### 3.2 转换为 Verilog ROM 格式

FPGA 综合时 `$readmemh` 被忽略，必须将程序硬编码到 `inst_rom.v` 的 initial 块中。

```bash
cd /home/yifengxin/FX-RV32_AddM/coremark_port

# Step 1: bin → hex（32位每行）
python3 bin2hex.py coremark.bin program.hex

# Step 2: hex → Verilog ROM 格式（rom[i]=32'hXXXXXXXX;）
python3 /home/yifengxin/FX-RV32_RemoveM_Custom/python/rom_output/gen_rom.py program.hex > /tmp/coremark_rom.txt
```

生成的 `/tmp/coremark_rom.txt` 内容示例：
```
rom[0]=32'h000012B7;
rom[1]=32'h80000113;
rom[2]=32'h000011B7;
...
```

### 3.3 替换 inst_rom.v

编辑 `/home/yifengxin/FX-RV32_AddM/soc/mem/inst_rom.v`，将 `initial` 块中的默认程序替换为 CoreMark：

```verilog
initial begin
    // Initialize all entries to NOP
    for (i = 0; i <= 8191; i = i + 1) begin
        rom[i] = 32'h00000013; // NOP: addi x0, x0, 0
    end

    // ========== CoreMark 程序（从 /tmp/coremark_rom.txt 粘贴） ==========
    rom[   0] = 32'h000012B7;
    rom[   1] = 32'h80000113;
    // ... 粘贴 gen_rom.py 输出的全部行 ...
end
```

> **快速操作**: 用 `gen_rom.py` 输出替换 `initial` 块中旧的 `rom[...]` 赋值语句即可。保留 NOP 初始化的 for 循环。

## 4. Vivado 综合与下载

### 4.1 工程位置

Vivado 工程位于 `vivado/RISCV_TEST/RISCV_TEST.xpr`。如果没有 AddM 的 Vivado 工程，需要从 RemoveM_Custom 复制一份并更新源文件路径。

**注意**: `soc_top_fpga.v` 中实例化了带 `perf_*` 端口的 `soc_top`，AddM 项目的 `soc_top.v` 已包含这些端口（`core_perf_total_time`, `core_perf_score` 等）。如果用 RemoveM_Custom 的 `soc_top.v`，需要先添加这些端口。

### 4.2 约束文件

管脚约束文件 `constraints.xdc`（位于仓库根目录）已配置：

| 信号 | FPGA 引脚 | 说明 |
|------|----------|------|
| `clk_p_i` / `clk_n_i` | AD12 / AD11 | 200MHz LVDS 差分时钟 |
| `uart_tx_o` | Y23 | UART TX，接 USB-UART 的 RX |
| `led0_o` ~ `led7_o` | T28/V19/U30/U29/V20/V26/W24/W23 | LED 指示灯 |

### 4.3 综合与实现

```tcl
# 在 Vivado Tcl Console 中执行：

# 1. 打开工程
open_project vivado/RISCV_TEST/RISCV_TEST.xpr

# 2. 综合
launch_runs synth_1 -jobs 8
wait_on_run synth_1

# 3. 实现
launch_runs impl_1 -jobs 8
wait_on_run impl_1

# 4. 生成 bitstream
launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1
```

也可以在 Vivado GUI 中点击 "Generate Bitstream" 一键完成全部流程。

综合时间参考（根据设计规模）：
- 综合: ~5-15 分钟
- 实现: ~10-30 分钟
- 总计: ~15-45 分钟

### 4.4 下载到 FPGA

```tcl
# Vivado Tcl Console:
open_hw_manager
connect_hw_server
open_hw_target
set_property PROBES.FILE {} [get_hw_devices xc7k325t_0]
set_property FULL_PROBES.FILE {} [get_hw_devices xc7k325t_0]
set_property PROGRAM.FILE {vivado/RISCV_TEST/RISCV_TEST.runs/impl_1/soc_top_fpga.bit} [get_hw_devices xc7k325t_0]
program_hw_devices [get_hw_devices xc7k325t_0]
```

## 5. 读取 UART 输出

FPGA 下载完成后，CPU 立即开始执行 CoreMark。通过 USB-UART 适配器在 PC 上接收输出。

### 5.1 确定串口号

**Linux (WSL)**:
```bash
# 查看 USB-UART 设备
ls /dev/ttyUSB*
# 通常为 /dev/ttyUSB0

# 在 WSL 中，USB 设备需要 usbipd 映射，建议直接在 Windows 上打开串口终端
```

**Windows**:
- 设备管理器 → 端口 (COM & LPT) → 找到 "USB Serial Port (COMx)"
- 记下 COM 号（如 COM3）

### 5.2 打开串口终端

**Windows — PuTTY**:
1. 打开 PuTTY
2. Connection type: Serial
3. Serial line: COM3（替换为实际 COM 号）
4. Speed: 115200
5. 点击 Open

**Windows — 串口调试助手**（如 SSCOM、UartAssist）:
- 波特率: 115200
- 数据位: 8
- 停止位: 1
- 校验: None
- 勾选 "显示时间戳"（可选，便于测量运行时长）

**Linux**:
```bash
# 使用 screen（波特率 115200）
screen /dev/ttyUSB0 115200

# 或使用 minicom
minicom -D /dev/ttyUSB0 -b 115200

# 或使用 picocom
picocom -b 115200 /dev/ttyUSB0
```

### 5.3 预期输出

CoreMark 运行结束后，UART 会打印类似以下输出：

```
2K performance run parameters for coremark.
CoreMark Size    : 666
Total ticks      : 10000
Total time (secs): 10
Iterations/Sec   : 500.000000
Iterations       : 5000
Compiler version : GCC15.2.0
Compiler flags   : -Os -ffreestanding
Memory location  : STACK
seedcrc          : 0xe9f5
[0]crclist       : 0xe714
[0]crcmatrix     : 0x1fd7
[0]crcstate      : 0x8e3a
[0]crcfinal      : 0x4983
Correct operation validated. See README.md for run and reporting rules.
CoreMark 1.0 : 500.000000 / GCC15.2.0 -Os -ffreestanding / STACK
```

## 6. LED 指示灯说明

FPGA 板上的 8 个 LED 用于判断系统运行状态：

| LED | 信号 | 含义 |
|-----|------|------|
| `led0` | `rst_n_internal` | **复位状态**: 亮 = 已释放复位，正常运行 |
| `led1` | `led_counter[26]` | **心跳**: 约 0.75Hz 闪烁 = 时钟正常 |
| `led2` | `\|debug_if_instr\|` | **指令有效**: 亮 = 当前指令非 NOP |
| `led3` | `uart_ctrl.we_i` | **UART 写使能**: 闪动 = 正在发送数据 |
| `led4` | `\|debug_if_pc\|` | **PC 非零**: 亮 = 程序在运行 |
| `led5` | `ex_branch_taken` | **分支跳转**: 闪动 = 分支指令执行中 |
| `led6` | `ex_jump_taken` | **JAL/JALR**: 闪动 = 跳转指令执行中 |
| `led7` | `1'b1` | **电源指示**: 常亮 |

**上电后观察**:
1. `led0` 亮 → 复位释放
2. `led1` 闪烁 → 时钟运行
3. `led4` 亮 → 程序开始执行
4. `led3` 闪动 → CoreMark 完成，正在通过 UART 输出结果
5. 所有 LED 静默（仅 led0/led1/led7 亮）→ 程序结束（`j .` 死循环）

## 7. 快速验证流程（小规模测试）

在大规模跑分前，建议先用小的 ITERATIONS 验证整个流程：

```bash
# 1. 编译小规模测试（ITERATIONS=10，约 0.02 秒）
cd /home/yifengxin/FX-RV32_AddM/coremark_port
make clean && make ITERATIONS=10

# 2. 转换为 ROM 格式
python3 bin2hex.py coremark.bin program.hex
python3 /home/yifengxin/FX-RV32_RemoveM_Custom/python/rom_output/gen_rom.py program.hex > /tmp/coremark_rom.txt

# 3. 替换 inst_rom.v（手动编辑）

# 4. Vivado 综合 → 下载 → 观察 LED 和 UART 输出
```

验证要点：
- UART 能收到完整的 CoreMark 输出
- LED 指示灯符合预期
- 输出中 `Correct operation validated` 出现

小规模验证通过后，再编译 ITERATIONS=5000，只需重新生成 ROM 内容并重新综合下载（RTL 不变，综合时间会短很多）。

## 8. 常见问题

### 8.1 UART 没有输出

1. **检查接线**: TX (Y23) → USB-UART 的 RX，GND → GND。FX-RV32 是 TX-only，不需要接 RX
2. **检查波特率**: 终端设为 115200 8N1
3. **检查 LED**: led0 亮=复位释放，led1 闪烁=时钟运行，led4 亮=PC 非零
4. **检查 USB-UART 驱动**: Windows 设备管理器中确认 COM 口存在

### 8.2 UART 输出乱码

1. 确认终端波特率为 115200（不是 9600）
2. 检查 `uart_tx.v` 的 `BAUD_RATE` 参数是否为 115200
3. 检查 `CLK_FREQ` 参数是否为 200_000_000（200MHz 时钟）
4. 如果时钟频率不同，BAUD_DIV = CLK_FREQ / 115200 需要调整

### 8.3 LED 全部不亮

1. 确认 bitstream 下载成功
2. 检查 FPGA 供电
3. 检查时钟输入（LVDS 差分对 AD12/AD11）

### 8.4 综合失败

常见问题：
- `soc_top` 缺少 `perf_*` 端口：确保使用 AddM 项目的 `soc_top.v`（已包含这些端口）
- `soc_top_fpga.v` 层次访问信号名不匹配：检查 `u_soc_top.u_core.ex_branch_taken` 等信号的层次路径
- `inst_rom.v` 初始化行数超出 ROM 容量（8192 行）：确认 CoreMark 程序不超过 32KB

### 8.5 CoreMark 运行不正确

如果 UVM 仿真已经通过（Scoreboard Mismatches = 0）但 FPGA 结果不对：
1. 检查编译器选项是否一致（`-march=rv32im`）
2. 检查 ITERATIONS 宏是否正确设置
3. 检查 `link.ld` 内存布局与 `inst_rom.v` 是否匹配
4. 用小的 ITERATIONS（如 10）先在 FPGA 上验证

## 9. 完整流程总结

```
┌──────────────────────────────────────────────────────────────┐
│  1. 编译 CoreMark                                            │
│     cd coremark_port && make ITERATIONS=5000                 │
│                                                              │
│  2. 转换格式                                                 │
│     bin → hex → Verilog ROM (gen_rom.py)                     │
│                                                              │
│  3. 更新 inst_rom.v                                          │
│     粘贴 CoreMark 机器码到 initial 块                        │
│                                                              │
│  4. Vivado 综合 + 实现 + 生成 bitstream                      │
│     ~30-45 分钟                                              │
│                                                              │
│  5. 下载到 FPGA                                              │
│     通过 JTAG 编程                                           │
│                                                              │
│  6. 连接 USB-UART                                            │
│     Y23 → RX, GND → GND                                     │
│                                                              │
│  7. 打开串口终端 (115200 8N1)                                │
│     观察 CoreMark 输出                                       │
│                                                              │
│  8. 记录跑分结果                                             │
│     CoreMark/MHz = Iterations/Sec ÷ 200                      │
└──────────────────────────────────────────────────────────────┘
```

**预计总耗时（含首次综合）**: 约 1-1.5 小时
**后续迭代**（仅改 ROM 内容）: ROM 数据在 `inst_rom.v` 中改变 → 只需重新综合，约 15-30 分钟
