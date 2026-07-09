# run_cli_compile.do — RTL 编译脚本
# 用法: vsim -c -do run_cli_compile.do

if {[file exists work]} { vdel -all }
vlib work

set R ../core; set S ../soc; set T ../tb
foreach f [list \
    $R/ifu/pc_reg.v $R/ifu/ifu_top.v \
    $R/id/decoder.v $R/id/ctrl.v $R/id/imm_gen.v $R/id/regfile.v $R/id/id_top.v \
    $R/exu/alu.v $R/exu/branch.v $R/exu/ex_top.v \
    $R/mem/mem_ctrl.v $R/mem/mem_top.v \
    $R/wbu/wb_mux.v $R/wbu/wb_top.v \
    $R/pipeline/if_id_reg.v $R/pipeline/id_ex_reg.v $R/pipeline/ex_mem_reg.v $R/pipeline/mem_wb_reg.v \
    $R/hazard/hazard_unit.v $R/hazard/forwarding_unit.v \
    $R/csr/csr_regfile.v $R/csr/csr_instructions.v \
    $R/interrupt/interrupt_controller.v $R/interrupt/interrupt_pipeline.v $R/interrupt/bank_controller.v \
    $R/core_top.v \
    $S/mem/inst_rom.v $S/mem/inst_bram.v $S/mem/data_ram.v \
    $S/bus/bus_arbiter.v \
    $S/periph/uart_tx.v $S/periph/uart_rx.v $S/periph/uart_ctrl.v \
    $S/periph/gpio.v $S/periph/timer.v \
    $S/periph/spi_master.v $S/periph/spi_flash_ctrl.v $S/periph/i2c_master.v \
    $S/top/soc_top.v \
    $T/tb_nested_check.v] {
    vlog -quiet $f
}
echo "=== 编译完成 ==="
quit -f
