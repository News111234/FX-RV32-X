# run_minimal_blt.do — 最小 blt 测试 + 关键信号转储
# 从项目根目录运行: vsim -c -do sim/run_minimal_blt.do

vlib work
vmap work work

foreach f {
    core/ifu/pc_reg.v core/ifu/ifu_top.v
    core/id/decoder.v core/id/ctrl.v core/id/imm_gen.v core/id/regfile.v core/id/id_top.v
    core/exu/alu.v core/exu/branch.v core/exu/ex_top.v
    core/mem/mem_ctrl.v core/mem/mem_top.v
    core/wbu/wb_mux.v core/wbu/wb_top.v
    core/pipeline/if_id_reg.v core/pipeline/id_ex_reg.v
    core/pipeline/ex_mem_reg.v core/pipeline/mem_wb_reg.v
    core/hazard/hazard_unit.v core/hazard/forwarding_unit.v
    core/csr/csr_regfile.v core/csr/csr_instructions.v
    core/interrupt/interrupt_controller.v
    core/interrupt/interrupt_pipeline.v
    core/interrupt/bank_controller.v
    core/core_top.v
    soc/bus/bus_arbiter.v soc/mem/inst_bram.v soc/mem/inst_rom.v soc/mem/data_ram.v
    soc/periph/uart_ctrl.v soc/periph/uart_tx.v soc/periph/uart_rx.v
    soc/periph/gpio.v soc/periph/timer.v
    soc/periph/spi_master.v soc/periph/spi_flash_ctrl.v
    soc/periph/i2c_master.v
    soc/top/soc_top.v
    tb/tb_nested_check.v
} { vlog -sv -work work +acc $f }
puts "==== Compile Done ===="

# 指令存储器选择: -gUSE_INST_ROM=1 (ROM/2周期延迟) 或 -gUSE_INST_ROM=0 (BRAM/3周期延迟)
vsim -voptargs=+acc -gUSE_INST_ROM=1 work.tb_nested_check

# 记录所有信号到波形文件
log -r /*
puts "==== Logging all signals ===="

# 运行仿真
run 10us

puts "==== Simulation Complete ===="
puts ""
puts "=== KEY SIGNALS at end of sim ==="
puts "if_pc          = [examine -hex u_soc_top/u_core/if_pc]"
puts "if_pc_current  = [examine -hex u_soc_top/u_core/if_pc_current]"
puts "if_id_instr    = [examine -hex u_soc_top/u_core/if_id_instr]"
puts "if_id_pc       = [examine -hex u_soc_top/u_core/if_id_pc]"
puts "ex_branch_taken= [examine u_soc_top/u_core/ex_branch_taken]"
puts "ex_jump_taken  = [examine u_soc_top/u_core/ex_jump_taken]"
puts "forwardA       = [examine u_soc_top/u_core/forwardA]"
puts "forwardB       = [examine u_soc_top/u_core/forwardB]"
puts "op1_selected   = [examine -hex u_soc_top/u_core/op1_selected]"
puts "op2_selected   = [examine -hex u_soc_top/u_core/op2_selected]"
puts "id_ex_pc       = [examine -hex u_soc_top/u_core/id_ex_pc]"
puts "id_ex_branch   = [examine u_soc_top/u_core/id_ex_branch]"
puts "flush_id       = [examine u_soc_top/u_core/flush_id]"
puts "pc_value       = [examine -hex u_soc_top/u_core/u_ifu_top/pc_value]"
puts "pc_delayed     = [examine -hex u_soc_top/u_core/u_ifu_top/pc_delayed]"
puts "reg_t0         = [examine -hex u_soc_top/u_core/u_id_top/u_regfile/registers\[5\]]"
puts "reg_t1         = [examine -hex u_soc_top/u_core/u_id_top/u_regfile/registers\[6\]]"
puts ""
puts "=== MEM/WB signals ==="
puts "wb_alu_result  = [examine -hex u_soc_top/u_core/wb_alu_result]"
puts "wb_reg_we      = [examine u_soc_top/u_core/wb_reg_we]"
puts "wb_rd_addr     = [examine -hex u_soc_top/u_core/wb_rd_addr]"
puts ""
puts "=== EX/MEM signals ==="
puts "ex_mem_alu_result = [examine -hex u_soc_top/u_core/ex_mem_alu_result]"
puts "ex_mem_reg_we     = [examine u_soc_top/u_core/ex_mem_reg_we]"
puts "ex_mem_rd_addr    = [examine -hex u_soc_top/u_core/ex_mem_rd_addr]"
