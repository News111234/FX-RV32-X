# run_gui_overflow_banks4.do — GUI: overflow_test BANKS=4 (嵌套对比)
# 用法: cd sim && vsim -do run_gui_overflow_banks4.do

file copy -force overflow_test.hex nested_test.hex

vsim -voptargs=+acc -onfinish stop -gUSE_INST_ROM=1 -gSHADOW_BANKS=4 work.tb_nested_check

add wave -divider {时钟复位}
add wave -label clk /tb_nested_check/clk
add wave -label rst_n /tb_nested_check/rst_n

add wave -divider {取指}
add wave -label PC -radix hex /tb_nested_check/u_soc_top/u_core/if_pc
add wave -label IFID_instr -radix hex /tb_nested_check/u_soc_top/u_core/if_id_instr

add wave -divider {执行}
add wave -label EX_alu -radix hex /tb_nested_check/u_soc_top/u_core/ex_alu_result
add wave -label EX_wdata -radix hex /tb_nested_check/u_soc_top/u_core/ex_mem_wdata

add wave -divider {中断 (BANKS=4: 支持嵌套)}
add wave -label intr_pending /tb_nested_check/u_soc_top/u_core/intr_pending
add wave -label intr_taken /tb_nested_check/u_soc_top/u_core/interrupt_taken_pipe
add wave -label bank_ptr -radix unsigned /tb_nested_check/u_soc_top/u_core/bank_ptr
add wave -label shadow_save /tb_nested_check/u_soc_top/u_core/shadow_save
add wave -label shadow_restore /tb_nested_check/u_soc_top/u_core/shadow_restore

add wave -divider {转发}
add wave -label fwdA /tb_nested_check/u_soc_top/u_core/forwardA
add wave -label fwdB /tb_nested_check/u_soc_top/u_core/forwardB

add wave -divider {存储}
add wave -label bus_we /tb_nested_check/u_soc_top/core_bus_we
add wave -label bus_wdata -radix hex /tb_nested_check/u_soc_top/core_bus_wdata
add wave -label mem64 -radix hex /tb_nested_check/u_soc_top/u_data_ram/mem\[64\]
add wave -label mem65 -radix hex /tb_nested_check/u_soc_top/u_data_ram/mem\[65\]
add wave -label mem66 -radix hex /tb_nested_check/u_soc_top/u_data_ram/mem\[66\]

configure wave -signalnamewidth 1
configure wave -gridperiod 1000000
configure wave -timelineunits ns

run 7000ns
wave zoom range 400000 6700000

echo {==========================================}
echo {  overflow_test BANKS=4 波形已就绪}
echo {  与BANKS=1对比: bank_ptr可达2 (嵌套!)}
echo {  mem[64]=0xDEAD0001  mem[65]=0xBEEF0002}
echo {==========================================}
