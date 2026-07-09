# run_gui_single_intr.do — GUI: single_intr_test (li+sw ISR, BANKS=4)
# 用法: cd sim && vsim -do run_gui_single_intr.do

file copy -force single_intr_test.hex nested_test.hex

vsim -voptargs=+acc -onfinish stop -gUSE_INST_ROM=1 -gSHADOW_BANKS=4 work.tb_nested_check

add wave -divider {时钟复位}
add wave -label clk /tb_nested_check/clk
add wave -label rst_n /tb_nested_check/rst_n

add wave -divider {取指}
add wave -label PC -radix hex /tb_nested_check/u_soc_top/u_core/if_pc
add wave -label IF_instr -radix hex /tb_nested_check/u_soc_top/u_core/if_instr_i
add wave -label IFID_instr -radix hex /tb_nested_check/u_soc_top/u_core/if_id_instr

add wave -divider {执行}
add wave -label EX_alu -radix hex /tb_nested_check/u_soc_top/u_core/ex_alu_result
add wave -label EX_wdata -radix hex /tb_nested_check/u_soc_top/u_core/ex_mem_wdata

add wave -divider {转发 (li=2指令→转发距离充足)}
add wave -label fwdA /tb_nested_check/u_soc_top/u_core/forwardA
add wave -label fwdB /tb_nested_check/u_soc_top/u_core/forwardB
add wave -label op2_sel -radix hex /tb_nested_check/u_soc_top/u_core/op2_selected

add wave -divider {中断}
add wave -label intr_taken /tb_nested_check/u_soc_top/u_core/interrupt_taken_pipe
add wave -label bank_ptr -radix unsigned /tb_nested_check/u_soc_top/u_core/bank_ptr
add wave -label shadow_save /tb_nested_check/u_soc_top/u_core/shadow_save
add wave -label shadow_restore /tb_nested_check/u_soc_top/u_core/shadow_restore

add wave -divider {存储}
add wave -label bus_we /tb_nested_check/u_soc_top/core_bus_we
add wave -label bus_wdata -radix hex /tb_nested_check/u_soc_top/core_bus_wdata
add wave -label mem64 -radix hex /tb_nested_check/u_soc_top/u_data_ram/mem\[64\]

configure wave -signalnamewidth 1
configure wave -gridperiod 200000
configure wave -timelineunits ns

run 2500ns
wave zoom range 500000 900000

echo {==========================================}
echo {  single_intr_test 波形已就绪}
echo {  ISR: li(2指令)+sw → 转发距离充足 → mem[64]=0xDEAD0001}
echo {==========================================}
