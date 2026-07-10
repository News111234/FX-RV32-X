# run_tb_soc.tcl — SoC 级仿真 (tb_soc_top)
catch { vdel -all }
vlib work

set rtl_files [list \
    core/ifu/pc_reg.v core/ifu/ifu_top.v core/id/decoder.v core/id/ctrl.v \
    core/id/imm_gen.v core/id/regfile.v core/id/id_top.v \
    core/exu/alu.v core/exu/branch.v core/exu/ex_top.v \
    core/mem/mem_ctrl.v core/mem/mem_top.v \
    core/wbu/wb_mux.v core/wbu/wb_top.v \
    core/pipeline/if_id_reg.v core/pipeline/id_ex_reg.v \
    core/pipeline/ex_mem_reg.v core/pipeline/mem_wb_reg.v \
    core/hazard/hazard_unit.v core/hazard/forwarding_unit.v \
    core/csr/csr_regfile.v core/csr/csr_instructions.v \
    core/interrupt/interrupt_controller.v core/interrupt/interrupt_pipeline.v \
    core/core_top.v \
    soc/bus/bus_arbiter.v soc/mem/inst_rom.v soc/mem/data_ram.v \
    soc/periph/uart_ctrl.v soc/periph/uart_tx.v \
    soc/periph/gpio.v soc/periph/timer.v \
    soc/periph/spi_master.v soc/periph/i2c_master.v \
    soc/top/soc_top.v tb/tb_soc_top.v]

foreach f $rtl_files {
    if {[file exists $f]} { vlog -work work +acc -sv $f }
}

puts "Starting simulation..."
vsim -c -voptargs=+acc work.tb_soc_top -do "run 50us; quit -f"
