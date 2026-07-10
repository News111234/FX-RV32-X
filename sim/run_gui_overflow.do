# run_gui_overflow.do — GUI波形: Bank溢出测试 (SHADOW_BANKS=1)
# 用法: cd sim && vsim -do run_gui_overflow.do

file copy -force overflow_test.hex nested_test.hex

vsim -voptargs=+acc -onfinish stop -gUSE_INST_ROM=1 -gSHADOW_BANKS=1 work.tb_nested_check

# === 时钟复位 ===
add wave -divider "时钟与复位"
add wave -label clk /tb_nested_check/clk
add wave -label rst_n /tb_nested_check/rst_n

# === 取指 ===
add wave -divider "取指 (IF/ID)"
add wave -label PC -radix hex /tb_nested_check/u_soc_top/u_core/if_pc
add wave -label IF_instr -radix hex /tb_nested_check/u_soc_top/u_core/if_instr_i
add wave -label IFID_instr -radix hex /tb_nested_check/u_soc_top/u_core/if_id_instr

# === 执行 ===
add wave -divider "执行 (EX)"
add wave -label EX_alu -radix hex /tb_nested_check/u_soc_top/u_core/ex_alu_result
add wave -label EX_wdata -radix hex /tb_nested_check/u_soc_top/u_core/ex_mem_wdata

# === 中断 (核心: bank_ptr展示溢出阻塞) ===
add wave -divider "中断系统"
add wave -label intr_pending /tb_nested_check/u_soc_top/u_core/intr_pending
add wave -label intr_taken /tb_nested_check/u_soc_top/u_core/interrupt_taken_pipe
add wave -label bank_ptr -radix unsigned /tb_nested_check/u_soc_top/u_core/bank_ptr
add wave -label shadow_save /tb_nested_check/u_soc_top/u_core/shadow_save
add wave -label shadow_restore /tb_nested_check/u_soc_top/u_core/shadow_restore

# === 转发 ===
add wave -divider "转发"
add wave -label fwdA /tb_nested_check/u_soc_top/u_core/forwardA
add wave -label fwdB /tb_nested_check/u_soc_top/u_core/forwardB

# === 总线存储 ===
add wave -divider {存储 (mem[64]=Timer, mem[65]=GPIO)}
add wave -label bus_we /tb_nested_check/u_soc_top/core_bus_we
add wave -label bus_addr -radix hex /tb_nested_check/u_soc_top/core_bus_addr
add wave -label bus_wdata -radix hex /tb_nested_check/u_soc_top/core_bus_wdata
add wave -label mem64 -radix hex /tb_nested_check/u_soc_top/u_data_ram/mem\[64\]
add wave -label mem65 -radix hex /tb_nested_check/u_soc_top/u_data_ram/mem\[65\]
add wave -label mem66 -radix hex /tb_nested_check/u_soc_top/u_data_ram/mem\[66\]

# === 配置 ===
configure wave -signalnamewidth 1
configure wave -gridperiod 1000000
configure wave -timelineunits ns

# 运行至 GPIO ISR 完成 (C72~C1302, ~6630ns覆盖全部关键事件)
run 6600ns

# 缩放到关键区间: Timer ISR进入→GPIO ISR MRET
wave zoom range 400000 6640000

echo "=========================================="
echo "  溢出测试波形已就绪 (SHADOW_BANKS=1)"
echo "  bank_ptr: 0→1(Timer)→1(GPIO阻塞)→0(MRET)→1(GPIO串行)"
echo {  mem[64]=0xDEAD0001  mem[65]=0xBEEF0002}
echo "=========================================="
