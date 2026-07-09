# run_nested_test_gui.do — 嵌套中断测试 (GUI 波形调试)
# 使用方法:
#   Windows 命令行: vsim -do sim/run_nested_test_gui.do
#   ModelSim GUI:   Tools → Tcl → Execute Script → 选择此文件
#   VS Code 终端:   vsim -do sim/run_nested_test_gui.do
#
# ═══════ 指令存储器切换 ═══════
# 默认使用 inst_rom (组合读, 2周期中断延迟)。
# 要切换到 inst_bram (同步读, 3周期延迟, FPGA上板用):
#   方法1: 修改下行 vsim 的 -gUSE_INST_ROM=1 → -gUSE_INST_ROM=0
#   方法2: 命令行直接 vsim -gUSE_INST_ROM=0 -do run_nested_test_gui.do
#
# 波形观测差异:
#   ROM模式: 指令存储器在 u_soc_top/gen_inst_rom/u_inst_rom/rom[]
#   BRAM模式: 指令存储器在 u_soc_top/gen_inst_bram/u_inst_bram/mem[]
#   核心观测信号 (if_pc, if_instr_i, if_id_instr) 在两种模式下通用。
# ═══════════════════════════════

vlib work
vmap work work

# 编译所有 RTL 源文件 (与 run_nested_test.do 相同)
foreach f {
    core/ifu/pc_reg.v core/ifu/ifu_top.v
    core/id/decoder.v core/id/ctrl.v core/id/imm_gen.v core/id/regfile.v core/id/id_top.v
    core/exu/alu.v core/exu/branch.v core/exu/ex_top.v
    core/mem/mem_ctrl.v core/mem/mem_top.v
    core/wbu/wb_mux.v core/wbu/wb_top.v
    core/pipeline/if_id_reg.v core/pipeline/id_ex_reg.v
    core/pipeline/ex_mem_reg.v core/pipeline/mem_wb_reg.v
    core/hazard/hazard_unit.v core/hazard/forwarding_unit.v
    core/csr/csr_regfile.v core/csr/csr_instructions.v
    core/interrupt/interrupt_controller.v
    core/interrupt/interrupt_pipeline.v
    core/interrupt/bank_controller.v
    core/core_top.v
    soc/bus/bus_arbiter.v soc/mem/inst_bram.v soc/mem/inst_rom.v soc/mem/data_ram.v
    soc/periph/uart_ctrl.v soc/periph/uart_tx.v soc/periph/uart_rx.v
    soc/periph/gpio.v soc/periph/timer.v
    soc/periph/spi_master.v soc/periph/spi_flash_ctrl.v
    soc/periph/i2c_master.v
    soc/top/soc_top.v
    tb/tb_nested_check.v
} { vlog -sv -work work +acc $f }
puts "==== Compile Done ===="

# 启动仿真 (不优化, 保留所有信号用于波形)
# 指令存储器选择: -gUSE_INST_ROM=1 (ROM/2周期延迟) 或 -gUSE_INST_ROM=0 (BRAM/3周期延迟)
vsim -voptargs=+acc -gUSE_INST_ROM=1 work.tb_nested_check

# ====================================================================
# 波形窗口配置
# ====================================================================

# (波形窗口初始为空, 无需清除)

# --- 中断相关信号 (核心观测组) ---
add wave -group "Interrupt" -hex \
    -label "intr_taken_pipe" /tb_nested_check/u_soc_top/u_core/interrupt_taken_pipe \
    -label "id_ex_mret"      /tb_nested_check/u_soc_top/u_core/id_ex_mret
add wave -group "Interrupt" -unsigned \
    -label "bank_ptr"        /tb_nested_check/u_soc_top/u_core/bank_ptr
add wave -group "Interrupt" \
    -label "shadow_save"     /tb_nested_check/u_soc_top/u_core/shadow_save \
    -label "shadow_restore"  /tb_nested_check/u_soc_top/u_core/shadow_restore

# --- 流水线 PC ---
add wave -group "Pipeline_PC" -hex \
    -label "if_pc"           /tb_nested_check/u_soc_top/u_core/if_pc \
    -label "if_id_pc"        /tb_nested_check/u_soc_top/u_core/if_id_pc \
    -label "id_ex_pc"        /tb_nested_check/u_soc_top/u_core/id_ex_pc \
    -label "ex_mem_pc_plus4" /tb_nested_check/u_soc_top/u_core/ex_mem_pc_plus4

# --- 指令 ---
add wave -group "Pipeline_Instr" -hex \
    -label "if_instr"        /tb_nested_check/u_soc_top/u_core/if_instr_i \
    -label "if_id_instr"     /tb_nested_check/u_soc_top/u_core/if_id_instr

# --- 流水线控制 ---
add wave -group "Control" \
    -label "flush_if"        /tb_nested_check/u_soc_top/u_core/flush_if \
    -label "flush_id"        /tb_nested_check/u_soc_top/u_core/flush_id \
    -label "stall_if"        /tb_nested_check/u_soc_top/u_core/stall_if \
    -label "stall_id"        /tb_nested_check/u_soc_top/u_core/stall_id \
    -label "ex_branch_taken" /tb_nested_check/u_soc_top/u_core/ex_branch_taken \
    -label "ex_jump_taken"   /tb_nested_check/u_soc_top/u_core/ex_jump_taken

# --- 中断 CSR ---
add wave -group "CSR" -hex \
    -label "mepc"            /tb_nested_check/u_soc_top/u_core/u_csr_regfile/mepc \
    -label "mcause"          /tb_nested_check/u_soc_top/u_core/u_csr_regfile/mcause \
    -label "mstatus"         /tb_nested_check/u_soc_top/u_core/u_csr_regfile/mstatus \
    -label "mie"             /tb_nested_check/u_soc_top/u_core/u_csr_regfile/mie \
    -label "mip"             /tb_nested_check/u_soc_top/u_core/u_csr_regfile/mip

# --- 外设 ---
add wave -group "Periph_Timer" -hex \
    -label "timer_enable"    /tb_nested_check/u_soc_top/u_timer/enable \
    -label "timer_load"      /tb_nested_check/u_soc_top/u_timer/load_value \
    -label "timer_count"     /tb_nested_check/u_soc_top/u_timer/counter \
    -label "timer_irq"       /tb_nested_check/u_soc_top/u_timer/interrupt_o

add wave -group "Periph_GPIO" -hex \
    -label "gpio_in"         /tb_nested_check/u_soc_top/u_gpio/gpio_in_i \
    -label "gpio_ie"         /tb_nested_check/u_soc_top/u_gpio/gpio_ie \
    -label "gpio_edge"       /tb_nested_check/u_soc_top/u_gpio/gpio_edge \
    -label "gpio_if"         /tb_nested_check/u_soc_top/u_gpio/gpio_if \
    -label "gpio_irq"        /tb_nested_check/u_soc_top/u_gpio/interrupt_o

# --- 寄存器 (t0/t1/t3, 用于跟踪 ISR 代码) ---
add wave -group "Regs" -hex \
    -label "x5_t0"           /tb_nested_check/u_soc_top/u_core/u_id_top/u_regfile/registers\[5\] \
    -label "x6_t1"           /tb_nested_check/u_soc_top/u_core/u_id_top/u_regfile/registers\[6\] \
    -label "x28_t3"          /tb_nested_check/u_soc_top/u_core/u_id_top/u_regfile/registers\[28\]

# --- 总线 ---
add wave -group "Bus" -hex \
    -label "bus_addr"        /tb_nested_check/u_soc_top/core_bus_addr \
    -label "bus_wdata"       /tb_nested_check/u_soc_top/core_bus_wdata \
    -label "bus_we"          /tb_nested_check/u_soc_top/core_bus_we

# --- 指令存储器 (根据 USE_INST_ROM 切换观测路径) ---
# ROM 模式 (USE_INST_ROM=1, 默认): 组合读, rom[] 数组
# BRAM 模式 (USE_INST_ROM=0):      同步读, mem[] 数组
# 切换: 修改上方 vsim 行的 -gUSE_INST_ROM= 值, 并注释/取消注释对应行
set USE_INST_ROM 1
if {$USE_INST_ROM} {
    # ---- ROM 模式: 观测 inst_rom 内部信号 ----
    add wave -group "InstMem_ROM" -hex \
        -label "rom_addr"    /tb_nested_check/u_soc_top/gen_inst_rom/u_inst_rom/addr_i \
        -label "rom_data"    /tb_nested_check/u_soc_top/gen_inst_rom/u_inst_rom/data_o
} else {
    # ---- BRAM 模式: 观测 inst_bram 内部信号 ----
    add wave -group "InstMem_BRAM" -hex \
        -label "bram_addr"   /tb_nested_check/u_soc_top/gen_inst_bram/u_inst_bram/if_addr_i \
        -label "bram_instr"  /tb_nested_check/u_soc_top/gen_inst_bram/u_inst_bram/if_instr_o \
        -label "bram_bus_we" /tb_nested_check/u_soc_top/gen_inst_bram/u_inst_bram/bus_we_i
}

# --- 测试结果 ---
add wave -group "Results" -hex \
    -label "mem63_tohost"  {/tb_nested_check/u_soc_top/u_data_ram/mem[63]} \
    -label "mem64_timer"   {/tb_nested_check/u_soc_top/u_data_ram/mem[64]} \
    -label "mem65_gpio"    {/tb_nested_check/u_soc_top/u_data_ram/mem[65]} \
    -label "mem66_preempt" {/tb_nested_check/u_soc_top/u_data_ram/mem[66]}

# ====================================================================
# 配置波形显示
# ====================================================================
configure wave -namecolwidth 180
configure wave -valuecolwidth 120
configure wave -signalnamewidth 1

# ====================================================================
# 运行仿真
# ====================================================================
puts "==== Starting simulation ===="
puts "  Watching for: Timer ISR entry (~C226), GPIO preemption (~C304)"
puts ""

run 10us

# ====================================================================
# 结果检查
# ====================================================================
puts ""
puts "============================================"
set tohost      [examine -hex {u_soc_top/u_data_ram/mem[63]}]
set timer_cnt   [examine -hex {u_soc_top/u_data_ram/mem[64]}]
set gpio_cnt    [examine -hex {u_soc_top/u_data_ram/mem[65]}]
set preempted   [examine -hex {u_soc_top/u_data_ram/mem[66]}]
puts "  tohost        = $tohost"
puts "  timer_count   = $timer_cnt"
puts "  gpio_count    = $gpio_cnt"
puts "  preempted     = $preempted"
if {$tohost == "00000000"} {
    puts "  PASS"
} else {
    puts "  FAIL"
}
puts "============================================"
puts ""
puts "=== 波形导航提示 (近似值, ROM 模式下可能 ±5 周期) ==="
puts "  在波形窗口中按 Ctrl+G 跳转到以下时间点:"
puts "  ~1233ns (C226): Timer 中断进入"
puts "  ~1283ns (C236): Timer ISR marker 写入"
puts "  ~1623ns (C304): GPIO 抢占 (嵌套!)"
puts "  ~1673ns (C314): GPIO ISR marker 写入"
puts "  ~1688ns (C317): GPIO ISR MRET 返回"
puts "  ~1898ns (C359): Timer ISR MRET 返回"
puts "  ~6650ns:        仿真结束, 结果检查"
