# run_gui_nested.do — GUI波形: 嵌套中断 (SHADOW_BANKS=4)
# 用法: cd sim && vsim -do run_gui_nested.do
# 关键验证: Timer ISR→GPIO抢占 (bank_ptr: 0→1→2)

vsim -voptargs=+acc -onfinish stop -gUSE_INST_ROM=1 -gSHADOW_BANKS=4 work.tb_nested_check

# === 时钟复位 ===
add wave -divider {时钟与复位}
add wave -label clk /tb_nested_check/clk
add wave -label rst_n /tb_nested_check/rst_n

# === 取指 ===
add wave -divider {取指 (IF/ID)}
add wave -label PC -radix hex /tb_nested_check/u_soc_top/u_core/if_pc
add wave -label IF_instr -radix hex /tb_nested_check/u_soc_top/u_core/if_instr_i

# === 执行 ===
add wave -divider {执行 (EX)}
add wave -label EX_alu -radix hex /tb_nested_check/u_soc_top/u_core/ex_alu_result
add wave -label EX_jump /tb_nested_check/u_soc_top/u_core/ex_jump_taken

# === 中断 (核心: bank_ptr=2展示嵌套) ===
add wave -divider {中断嵌套 (bank_ptr: 0→1→2)}
add wave -label intr_pending /tb_nested_check/u_soc_top/u_core/intr_pending
add wave -label intr_taken /tb_nested_check/u_soc_top/u_core/interrupt_taken_pipe
add wave -label bank_ptr -radix unsigned /tb_nested_check/u_soc_top/u_core/bank_ptr
add wave -label shadow_save /tb_nested_check/u_soc_top/u_core/shadow_save
add wave -label shadow_restore /tb_nested_check/u_soc_top/u_core/shadow_restore

# === 转发 ===
add wave -divider {转发}
add wave -label fwdA /tb_nested_check/u_soc_top/u_core/forwardA
add wave -label fwdB /tb_nested_check/u_soc_top/u_core/forwardB

# === 存储 ===
add wave -divider {存储结果}
add wave -label bus_we /tb_nested_check/u_soc_top/core_bus_we
add wave -label bus_wdata -radix hex /tb_nested_check/u_soc_top/core_bus_wdata
add wave -label mem64 -radix hex /tb_nested_check/u_soc_top/u_data_ram/mem\[64\]
add wave -label mem65 -radix hex /tb_nested_check/u_soc_top/u_data_ram/mem\[65\]
add wave -label mem66 -radix hex /tb_nested_check/u_soc_top/u_data_ram/mem\[66\]

# === 配置 ===
configure wave -signalnamewidth 1
configure wave -gridperiod 500000
configure wave -timelineunits ns

# 运行至嵌套完成 (C225 Timer进入, C304 GPIO抢占)
run 3000ns

wave zoom range 1200000 1700000

echo {==========================================}
echo {  嵌套中断波形已就绪 (SHADOW_BANKS=4)}
echo {  bank_ptr: 0→1(Timer)→2(GPIO嵌套!)→1(MRET)→0(MRET)}
echo {  mem[64]=0xDEAD0001  mem[65]=0xBEEF0001}
echo {==========================================}
