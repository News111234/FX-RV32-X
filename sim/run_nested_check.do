# ============================================================================
# Modelsim 仿真脚本 — FX-RV32 多Bank嵌套中断 (soc_top 顶层)
#
# 用法:
#   cd sim
#   vsim -c -do run_nested_check.do          # 命令行模式
#   vsim -do run_nested_check.do             # GUI模式 (带波形)
#
# 测试程序: nested_test.s (Timer ISR 被 GPIO 抢占)
# 顶层 testbench: tb/tb_nested_check.v (基于 soc_top)
# ============================================================================
cd [file dirname [info script]]

# -------- Step 0: 汇编 nested_test.s --------
puts "==== Step 0: Assembling nested_test.s ===="
exec python ../python/asm_to_hex.py ../sim/nested_test.s -o nested_test.hex
puts "==== Assemble Done ===="

# -------- Step 1: 编译 RTL --------
vlib work
vmap work work

foreach f {
    ../core/ifu/pc_reg.v
    ../core/ifu/ifu_top.v
    ../core/id/decoder.v
    ../core/id/ctrl.v
    ../core/id/imm_gen.v
    ../core/id/regfile.v
    ../core/id/id_top.v
    ../core/exu/alu.v
    ../core/exu/branch.v
    ../core/exu/ex_top.v
    ../core/mem/mem_ctrl.v
    ../core/mem/mem_top.v
    ../core/wbu/wb_mux.v
    ../core/wbu/wb_top.v
    ../core/pipeline/if_id_reg.v
    ../core/pipeline/id_ex_reg.v
    ../core/pipeline/ex_mem_reg.v
    ../core/pipeline/mem_wb_reg.v
    ../core/hazard/hazard_unit.v
    ../core/hazard/forwarding_unit.v
    ../core/csr/csr_regfile.v
    ../core/csr/csr_instructions.v
    ../core/interrupt/interrupt_controller.v
    ../core/interrupt/interrupt_pipeline.v
    ../core/interrupt/bank_controller.v
    ../core/core_top.v
    ../soc/bus/bus_arbiter.v
    ../soc/mem/inst_bram.v ../soc/mem/inst_rom.v
    ../soc/mem/data_ram.v
    ../soc/periph/uart_ctrl.v ../soc/periph/uart_tx.v ../soc/periph/uart_rx.v
    ../soc/periph/gpio.v
    ../soc/periph/timer.v
    ../soc/periph/spi_master.v ../soc/periph/spi_flash_ctrl.v
    ../soc/periph/i2c_master.v
    ../soc/top/soc_top.v
    ../tb/tb_nested_check.v
} { vlog -sv -work work +acc $f }

puts "==== Compile Done ===="

# -------- Step 2: 仿真 --------
# 指令存储器选择: -gUSE_INST_ROM=1 (ROM/2周期延迟) 或 -gUSE_INST_ROM=0 (BRAM/3周期延迟)
vsim -voptargs=+acc -gUSE_INST_ROM=1 work.tb_nested_check

if {[info exists env(GUI_MODE)] && $env(GUI_MODE)} {
    add wave -divider "Clk/Rst"
    add wave /tb_nested_check/clk /tb_nested_check/rst_n /tb_nested_check/gpio_pin0
    add wave -divider "Bank"
    add wave -radix unsigned /tb_nested_check/u_soc_top/u_core/bank_ptr
    add wave /tb_nested_check/u_soc_top/u_core/shadow_save /tb_nested_check/u_soc_top/u_core/shadow_restore
    add wave -divider "Intr"
    add wave /tb_nested_check/u_soc_top/u_core/interrupt_taken_pipe
    add wave /tb_nested_check/u_soc_top/u_core/interrupt_processing_pipe
    add wave /tb_nested_check/u_soc_top/u_core/id_ex_mret
    add wave -divider "CSR"
    add wave -radix hex /tb_nested_check/u_soc_top/u_core/mepc
    add wave -radix hex /tb_nested_check/u_soc_top/u_core/mcause
    add wave -radix hex /tb_nested_check/u_soc_top/u_core/mstatus
    add wave -divider "Memory"
    add wave -radix hex /tb_nested_check/u_soc_top/u_data_ram/mem[64]
    add wave -radix hex /tb_nested_check/u_soc_top/u_data_ram/mem[65]
    add wave -radix hex /tb_nested_check/u_soc_top/u_data_ram/mem[66]
}

run 7us
exit