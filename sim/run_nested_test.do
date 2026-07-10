# run_nested_test.do — 嵌套中断测试（使用修复后的 hazard_unit）
# 从项目根目录运行: vsim -c -do sim/run_nested_test.do

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

# 记录所有信号
log -r /*
puts "==== Logging all signals ===="

run 10us

puts "==== Simulation Complete ===="
puts "=== Checking results ==="
echo [examine -hex u_soc_top/u_data_ram/mem[63]]
echo [examine -hex u_soc_top/u_data_ram/mem[64]]
echo [examine -hex u_soc_top/u_data_ram/mem[65]]
echo [examine -hex u_soc_top/u_data_ram/mem[66]]
