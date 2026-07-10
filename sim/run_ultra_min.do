# run_ultra_min.do — ultra_min_test 独立仿真 (inst_rom, GUI波形)
# 用法: cd sim && vsim -do run_ultra_min.do

# ===== 1. 创建 work 库 =====
if {[file exists work]} { vdel -all }
vlib work

# ===== 2. 编译 RTL =====
set RTL_ROOT ../core
set SOC_ROOT ../soc
set TB_ROOT  ../tb

# core
vlog $RTL_ROOT/ifu/pc_reg.v
vlog $RTL_ROOT/ifu/ifu_top.v
vlog $RTL_ROOT/id/decoder.v
vlog $RTL_ROOT/id/ctrl.v
vlog $RTL_ROOT/id/imm_gen.v
vlog $RTL_ROOT/id/regfile.v
vlog $RTL_ROOT/id/id_top.v
vlog $RTL_ROOT/exu/alu.v
vlog $RTL_ROOT/exu/branch.v
vlog $RTL_ROOT/exu/ex_top.v
vlog $RTL_ROOT/mem/mem_ctrl.v
vlog $RTL_ROOT/mem/mem_top.v
vlog $RTL_ROOT/wbu/wb_mux.v
vlog $RTL_ROOT/wbu/wb_top.v
vlog $RTL_ROOT/pipeline/if_id_reg.v
vlog $RTL_ROOT/pipeline/id_ex_reg.v
vlog $RTL_ROOT/pipeline/ex_mem_reg.v
vlog $RTL_ROOT/pipeline/mem_wb_reg.v
vlog $RTL_ROOT/hazard/hazard_unit.v
vlog $RTL_ROOT/hazard/forwarding_unit.v
vlog $RTL_ROOT/csr/csr_regfile.v
vlog $RTL_ROOT/csr/csr_instructions.v
vlog $RTL_ROOT/interrupt/interrupt_controller.v
vlog $RTL_ROOT/interrupt/interrupt_pipeline.v
vlog $RTL_ROOT/interrupt/bank_controller.v
vlog $RTL_ROOT/core_top.v

# soc
vlog $SOC_ROOT/mem/inst_rom.v
vlog $SOC_ROOT/mem/inst_bram.v
vlog $SOC_ROOT/mem/data_ram.v
vlog $SOC_ROOT/bus/bus_arbiter.v
vlog $SOC_ROOT/periph/uart_tx.v
vlog $SOC_ROOT/periph/uart_rx.v
vlog $SOC_ROOT/periph/uart_ctrl.v
vlog $SOC_ROOT/periph/gpio.v
vlog $SOC_ROOT/periph/timer.v
vlog $SOC_ROOT/periph/spi_master.v
vlog $SOC_ROOT/periph/spi_flash_ctrl.v
vlog $SOC_ROOT/periph/i2c_master.v
vlog $SOC_ROOT/top/soc_top.v

# testbench
vlog $TB_ROOT/tb_nested_check.v

# ===== 3. 准备 hex 文件 (复制为 nested_test.hex) =====
# tb_nested_check 硬编码读取 nested_test.hex
exec cp ultra_min_test.hex nested_test.hex

# ===== 4. 启动仿真 (GUI模式) =====
# USE_INST_ROM=1 (默认, inst_rom 组合读)
vsim -gUSE_INST_ROM=1 -gSHADOW_BANKS=4 work.tb_nested_check

# ===== 5. 添加波形 =====
add wave -divider "时钟复位"
add wave clk rst_n

add wave -divider "IF/ID 流水线"
add wave -radix hex u_soc_top/u_core/if_pc
add wave -radix hex u_soc_top/u_core/if_instr_i
add wave -radix hex u_soc_top/u_core/if_id_pc
add wave -radix hex u_soc_top/u_core/if_id_instr

add wave -divider "ID/EX"
add wave -radix hex u_soc_top/u_core/id_ex_pc
add wave -radix hex u_soc_top/u_core/id_ex_rs2_data
add wave -radix hex u_soc_top/u_core/id_ex_rs2_addr

add wave -divider "EX阶段"
add wave -radix hex u_soc_top/u_core/ex_alu_result
add wave -radix hex u_soc_top/u_core/ex_mem_wdata
add wave u_soc_top/u_core/ex_mem_we
add wave u_soc_top/u_core/ex_branch_taken
add wave u_soc_top/u_core/ex_jump_taken

add wave -divider "EX/MEM"
add wave -radix hex u_soc_top/u_core/ex_mem_alu_result
add wave -radix hex u_soc_top/u_core/ex_mem_rd_addr
add wave u_soc_top/u_core/ex_mem_reg_we
add wave u_soc_top/u_core/ex_mem_mem_re

add wave -divider "转发"
add wave -radix hex u_soc_top/u_core/forwardA
add wave -radix hex u_soc_top/u_core/forwardB
add wave -radix hex u_soc_top/u_core/op1_selected
add wave -radix hex u_soc_top/u_core/op2_selected

add wave -divider "冲刷/停顿"
add wave u_soc_top/u_core/flush_if
add wave u_soc_top/u_core/flush_id
add wave u_soc_top/u_core/stall_if
add wave u_soc_top/u_core/stall_id

add wave -divider "中断"
add wave u_soc_top/u_core/intr_pending
add wave u_soc_top/u_core/interrupt_taken_pipe
add wave u_soc_top/u_core/intr_take_now
add wave -radix hex u_soc_top/u_core/bank_ptr
add wave u_soc_top/u_core/shadow_save
add wave u_soc_top/u_core/shadow_restore

add wave -divider "总线/存储"
add wave u_soc_top/core_bus_we
add wave -radix hex u_soc_top/core_bus_addr
add wave -radix hex u_soc_top/core_bus_wdata
add wave u_soc_top/bus_ram_we
add wave -radix hex [get objects -filter {name =~ "*u_data_ram*mem*"}]

add wave -divider "结果 (mem[0x40]=0x100)"
add wave -radix hex u_soc_top/u_data_ram/mem[63]
add wave -radix hex u_soc_top/u_data_ram/mem[64]

# ===== 6. 运行 =====
run 5us
