# run_nested_test_rom.do — ROM 模式 (inst_rom) 嵌套中断测试 (GUI 波形)
# 从项目根目录运行:
#   vsim -do sim/run_nested_test_rom.do         # GUI 模式
#   vsim -c -do sim/run_nested_test_rom.do      # 命令行模式
#
# 和 BRAM 版本使用相同的测试程序 (nested_test.s), 仅 -gUSE_INST_ROM=1
# ROM: 2周期中断延迟, BRAM: 3周期中断延迟
#
# 切换:
#   vsim -do sim/run_nested_test_gui.do         # BRAM 模式 (GUI)
#   vsim -c -do sim/run_nested_test.do          # BRAM 模式 (命令行)

# ---- Step 0: 汇编测试程序 ----
cd [file dirname [info script]]
puts "==== Assembling nested_test.s ===="
exec python ../python/asm_to_hex.py nested_test.s nested_test.hex
puts "==== Assemble Done ===="

# ---- Step 1: 编译 RTL ----
vlib work
vmap work work

foreach f {
    ../core/ifu/pc_reg.v ../core/ifu/ifu_top.v
    ../core/id/decoder.v ../core/id/ctrl.v ../core/id/imm_gen.v ../core/id/regfile.v ../core/id/id_top.v
    ../core/exu/alu.v ../core/exu/branch.v ../core/exu/ex_top.v
    ../core/mem/mem_ctrl.v ../core/mem/mem_top.v
    ../core/wbu/wb_mux.v ../core/wbu/wb_top.v
    ../core/pipeline/if_id_reg.v ../core/pipeline/id_ex_reg.v
    ../core/pipeline/ex_mem_reg.v ../core/pipeline/mem_wb_reg.v
    ../core/hazard/hazard_unit.v ../core/hazard/forwarding_unit.v
    ../core/csr/csr_regfile.v ../core/csr/csr_instructions.v
    ../core/interrupt/interrupt_controller.v
    ../core/interrupt/interrupt_pipeline.v
    ../core/interrupt/bank_controller.v
    ../core/core_top.v
    ../soc/bus/bus_arbiter.v ../soc/mem/inst_bram.v ../soc/mem/inst_rom.v ../soc/mem/data_ram.v
    ../soc/periph/uart_ctrl.v ../soc/periph/uart_tx.v ../soc/periph/uart_rx.v
    ../soc/periph/gpio.v ../soc/periph/timer.v
    ../soc/periph/spi_master.v ../soc/periph/spi_flash_ctrl.v
    ../soc/periph/i2c_master.v
    ../soc/top/soc_top.v
    ../tb/tb_nested_check.v
} { vlog -sv -work work +acc $f }
puts "==== Compile Done (ROM mode) ===="

# ---- Step 2: 仿真 (ROM 模式) ----
vsim -voptargs=+acc -gUSE_INST_ROM=1 work.tb_nested_check

# ---- 波形窗口 ----
add wave -group "Interrupt" -hex \
    -label "intr_taken"      /tb_nested_check/u_soc_top/u_core/interrupt_taken_pipe \
    -label "id_ex_mret"      /tb_nested_check/u_soc_top/u_core/id_ex_mret
add wave -group "Interrupt" -unsigned \
    -label "bank_ptr"        /tb_nested_check/u_soc_top/u_core/bank_ptr
add wave -group "Interrupt" \
    -label "shadow_save"     /tb_nested_check/u_soc_top/u_core/shadow_save \
    -label "shadow_restore"  /tb_nested_check/u_soc_top/u_core/shadow_restore

add wave -group "Pipeline_PC" -hex \
    -label "if_pc"           /tb_nested_check/u_soc_top/u_core/if_pc \
    -label "if_id_pc"        /tb_nested_check/u_soc_top/u_core/if_id_pc \
    -label "id_ex_pc"        /tb_nested_check/u_soc_top/u_core/id_ex_pc

add wave -group "Pipeline_Instr" -hex \
    -label "if_instr"        /tb_nested_check/u_soc_top/u_core/if_instr_i \
    -label "if_id_instr"     /tb_nested_check/u_soc_top/u_core/if_id_instr

add wave -group "CSR" -hex \
    -label "mepc"            /tb_nested_check/u_soc_top/u_core/u_csr_regfile/mepc \
    -label "mcause"          /tb_nested_check/u_soc_top/u_core/u_csr_regfile/mcause \
    -label "mstatus"         /tb_nested_check/u_soc_top/u_core/u_csr_regfile/mstatus

add wave -group "ROM" -hex \
    -label "rom_addr"        /tb_nested_check/u_soc_top/gen_inst_rom/u_inst_rom/addr_i \
    -label "rom_data"        /tb_nested_check/u_soc_top/gen_inst_rom/u_inst_rom/data_o

add wave -group "Periph" -hex \
    -label "timer_irq"       /tb_nested_check/u_soc_top/u_timer/interrupt_o \
    -label "gpio_irq"        /tb_nested_check/u_soc_top/u_gpio/interrupt_o \
    -label "gpio_in0"        /tb_nested_check/gpio_pin0

add wave -group "Results" -hex \
    -label "mem63_tohost"  {/tb_nested_check/u_soc_top/u_data_ram/mem[63]} \
    -label "mem64_timer"   {/tb_nested_check/u_soc_top/u_data_ram/mem[64]} \
    -label "mem65_gpio"    {/tb_nested_check/u_soc_top/u_data_ram/mem[65]} \
    -label "mem66_preempt" {/tb_nested_check/u_soc_top/u_data_ram/mem[66]}

configure wave -namecolwidth 180
configure wave -valuecolwidth 120
configure wave -signalnamewidth 1

puts "==== ROM mode: nested interrupt test ===="
puts "  Watch for: Timer ISR entry (~C225), GPIO preemption (~C304)"
puts "  ROM flush absorbs first NOP at 0x200, handler executes from 0x204"

run 10us

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
