# run_gui.do — GUI波形验证 (论文截图用)
# 用法: cd sim && vsim -do run_gui.do

file copy -force ultra_min_test.hex nested_test.hex

# 加载设计 (关闭vopt优化以保留所有信号)
vsim -voptargs=+acc -gUSE_INST_ROM=1 work.tb_nested_check

set DUT /tb_nested_check/u_soc_top/u_core

# === 时钟和复位 ===
add wave -divider "时钟与复位"
add wave -label clk /tb_nested_check/clk
add wave -label rst_n /tb_nested_check/rst_n

# === IF/ID 流水线 ===
add wave -divider "IF/ID 流水线"
add wave -label PC -radix hex $DUT/if_pc
add wave -label IF_instr -radix hex $DUT/if_instr_i
add wave -label IFID_PC -radix hex $DUT/if_id_pc
add wave -label IFID_instr -radix hex $DUT/if_id_instr

# === ID/EX 流水线 ===
add wave -divider "ID/EX"
add wave -label IDEX_PC -radix hex $DUT/id_ex_pc
add wave -label IDEX_rs2 -radix hex $DUT/id_ex_rs2_data
add wave -label IDEX_rs2_addr $DUT/id_ex_rs2_addr

# === EX 阶段 ===
add wave -divider "EX 阶段"
add wave -label EX_alu -radix hex $DUT/ex_alu_result
add wave -label EX_wdata -radix hex $DUT/ex_mem_wdata
add wave -label EX_mem_we $DUT/ex_mem_we
add wave -label EX_jump $DUT/ex_jump_taken

# === 转发单元 (论文核心截图) ===
add wave -divider "转发 (Forwarding)"
add wave -label fwdA $DUT/forwardA
add wave -label fwdB $DUT/forwardB
add wave -label op2_sel -radix hex $DUT/op2_selected

# === 流水线控制 ===
add wave -divider "流水线控制"
add wave -label flush_if $DUT/flush_if
add wave -label flush_id $DUT/flush_id
add wave -label stall_if $DUT/stall_if

# === 中断系统 ===
add wave -divider "中断系统"
add wave -label intr_pending $DUT/intr_pending
add wave -label intr_taken $DUT/interrupt_taken_pipe
add wave -label bank_ptr $DUT/bank_ptr
add wave -label shadow_save $DUT/shadow_save
add wave -label shadow_restore $DUT/shadow_restore

# === 总线与存储 (sw写0x42) ===
add wave -divider "总线与存储"
add wave -label bus_we /tb_nested_check/u_soc_top/core_bus_we
add wave -label bus_addr -radix hex /tb_nested_check/u_soc_top/core_bus_addr
add wave -label bus_wdata -radix hex /tb_nested_check/u_soc_top/core_bus_wdata
add wave -label mem64 -radix hex {/tb_nested_check/u_soc_top/u_data_ram/mem[64]}

# === 波形显示配置 ===
configure wave -signalnamewidth 1
configure wave -gridperiod 50000
configure wave -timelineunits ns

# 运行到 ISR 执行完成
# C6: 133ns mem[64]=0xAAAAAAAA (主程序)
# C51: 358ns 中断进入 bank_ptr=1
# C56: 383ns sw写0x42 ← 核心验证点!
run 4200

# 缩放到中断进入前后
wave zoom range 320000 420000

echo "=========================================="
echo "  波形窗口已就绪 - 可截图用于论文"
echo "  关键观察点:"
echo "    ~133ns: 主程序 sw 0xAAAAAAAA"
echo "    ~358ns: 中断进入 bank_ptr=1"
echo "    ~383ns: ISR sw 0x42 (bus_wdata)"
echo "    flush_if: 仅1周期脉冲"
echo "=========================================="
