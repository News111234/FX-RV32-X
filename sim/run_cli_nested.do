# run_cli_nested.do - CLI: nested_test (BANKS=4)
if {[file exists work]} { vdel -all }; vlib work
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
$T/tb_nested_check.v] { vlog -quiet $f }
# 重新汇编确保 hex 正确（防止被其他测试覆盖）
catch {exec python ../python/asm_to_hex.py nested_test.s nested_test.hex}
vsim -onfinish stop -c -gUSE_INST_ROM=1 -gSHADOW_BANKS=4 work.tb_nested_check
run 8us
set r1 [exam u_soc_top/u_data_ram/mem\[64\]]
set r2 [exam u_soc_top/u_data_ram/mem\[65\]]
puts "mem\[64\] = $r1 (expected 32'hDEAD0001)"
puts "mem\[65\] = $r2 (expected 32'hBEEF0001)"
if {[string equal -nocase $r1 32'hDEAD0001] && [string equal -nocase $r2 32'hBEEF0001]} { puts "=> PASS" } else { puts "=> FAIL ***" }
quit -f
