# run_gui_no_intr.do — GUI: no_intr_test (BANKS=4, 无中断)
# 用法: cd sim && vsim -do run_gui_no_intr.do

file copy -force no_intr_test.hex nested_test.hex
vsim -voptargs=+acc -gUSE_INST_ROM=1 -gSHADOW_BANKS=4 work.tb_nested_check

set DUT /tb_nested_check/u_soc_top/u_core

add wave -divider "时钟与复位"
add wave -label clk /tb_nested_check/clk
add wave -label rst_n /tb_nested_check/rst_n

add wave -divider "IF/ID"
add wave -label PC -radix hex $DUT/if_pc
add wave -label IF_instr -radix hex $DUT/if_instr_i
add wave -label IFID_instr -radix hex $DUT/if_id_instr

add wave -divider "总线与存储"
add wave -label bus_we /tb_nested_check/u_soc_top/core_bus_we
add wave -label bus_wdata -radix hex /tb_nested_check/u_soc_top/core_bus_wdata
add wave -label mem64 -radix hex {/tb_nested_check/u_soc_top/u_data_ram/mem[64]}
add wave -label mem65 -radix hex {/tb_nested_check/u_soc_top/u_data_ram/mem[65]}

configure wave -signalnamewidth 1
configure wave -gridperiod 50000
configure wave -timelineunits ns

run 500ns
echo "=========================================="
echo "  no_intr_test 波形已就绪"
echo "  无中断触发, mem[64]直接写入0x42"
echo "=========================================="
