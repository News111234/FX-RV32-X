# run_cli_tailchain.do — 尾链优化测试 (BANKS=4)
if {[file exists work]} { vdel -all }; vlib work
set R ../core; set S ../soc; set T ../tb
foreach f [list \
$R/ifu/pc_reg.v $R/ifu/ifu_top.v \
$R/id/decoder.v $R/id/ctrl.v $R/id/imm_gen.v $R/id/regfile.v $R/id/id_top.v \
$R/exu/alu.v $R/exu/branch.v $R/exu/ex_top.v \
$R/mem/mem_ctrl.v $R/mem/mem_top.v \
$R/wbu/wb_mux.v $R/wbu/wb_top.v \
$R/pipeline/if_id_reg.v $R/pipeline/id_ex_reg.v $R/pipeline/ex_mem_reg.v $R/pipeline/mem_wb_reg.v \
$R/hazard/hazard_unit.v $R/hazard/forwarding_unit.v \
$R/csr/csr_regfile.v $R/csr/csr_instructions.v \
$R/interrupt/interrupt_controller.v $R/interrupt/interrupt_pipeline.v $R/interrupt/bank_controller.v \
$R/core_top.v \
$S/mem/inst_rom.v $S/mem/inst_bram.v $S/mem/data_ram.v \
$S/bus/bus_arbiter.v \
$S/periph/uart_tx.v $S/periph/uart_rx.v $S/periph/uart_ctrl.v \
$S/periph/gpio.v $S/periph/timer.v \
$S/periph/spi_master.v $S/periph/spi_flash_ctrl.v $S/periph/i2c_master.v \
$S/top/soc_top.v \
$T/tb_nested_check.v] { vlog -quiet $f }
file copy -force tail_chain_test.hex nested_test.hex
vsim -onfinish stop -c -novopt -gUSE_INST_ROM=1 -gSHADOW_BANKS=4 work.tb_nested_check

# Timer先触发(GPIO由testbench触发)
# GPIO在~2us时触发
run 2us
force -deposit /tb_nested_check/gpio_pin0 1
run 50ns
force -deposit /tb_nested_check/gpio_pin0 0

run 10us

set tail [exam u_soc_top/u_data_ram/mem\[64\]]
set tc [exam u_soc_top/u_data_ram/mem\[65\]]
set gc [exam u_soc_top/u_data_ram/mem\[66\]]
set gc_cyc [exam u_soc_top/u_data_ram/mem\[67\]]
set tc_cyc [exam u_soc_top/u_data_ram/mem\[68\]]
puts "mem\[64\]=$tail (tail_chain flag)"
puts "mem\[65\]=$tc (timer_count)"
puts "mem\[66\]=$gc (gpio_count)"
puts "mem\[67\]=$gc_cyc (mcycle at GPIO entry)"
puts "mem\[68\]=$tc_cyc (mcycle at Timer entry after TC)"

# 验证: tail_chain flag=1, timer_count>=1, gpio_count>=1
scan $tc "%x" tc_dec
scan $gc "%x" gc_dec
puts "timer_count=$tc_dec, gpio_count=$gc_dec"
if {[string equal -nocase $tail 32'h00000001] && $tc_dec >= 1 && $gc_dec >= 1} {
    puts "=> PASS"
} else {
    puts "=> FAIL ***"
}
quit -f
