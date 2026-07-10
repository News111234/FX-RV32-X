# regression_test.do — Multi-SHADOW_BANKS regression test (ROM mode)
# Usage: vsim -c -do sim/regression_test.do

cd [file dirname [info script]]

# ---- Step 1: Assemble test program ----
puts "==== Assembling nested_test.s ===="
exec python ../python/asm_to_hex.py nested_test.s nested_test.hex
puts "==== Assemble Done ===="

# ---- Step 2: Compile RTL once ----
vlib work
vmap work work

foreach f {
    ../core/ifu/pc_reg.v ../core/ifu/ifu_top.v
    ../core/id/decoder.v ../core/id/ctrl.v ../core/id/imm_gen.v ../core/id/regfile.v ../core/id/id_top.v
    ../core/exu/alu.v ../core/exu/branch.v ../core/exu/ex_top.v
    ../core/mem/mem_ctrl.v ../core/mem/mem_top.v
    ../core/wbu/wb_mux.v ../core/wbu/wb_top.v
    ../core/pipeline/if_id_reg.v ../core/pipeline/id_ex_reg.v
    ../core/pipeline/ex_mem_reg.v ../core/pipeline/mem_wb_reg.v
    ../core/hazard/hazard_unit.v ../core/hazard/forwarding_unit.v
    ../core/csr/csr_regfile.v ../core/csr/csr_instructions.v
    ../core/interrupt/interrupt_controller.v
    ../core/interrupt/interrupt_pipeline.v
    ../core/interrupt/bank_controller.v
    ../core/core_top.v
    ../soc/bus/bus_arbiter.v ../soc/mem/inst_bram.v ../soc/mem/inst_rom.v ../soc/mem/data_ram.v
    ../soc/periph/uart_ctrl.v ../soc/periph/uart_tx.v ../soc/periph/uart_rx.v
    ../soc/periph/gpio.v ../soc/periph/timer.v
    ../soc/periph/spi_master.v ../soc/periph/spi_flash_ctrl.v
    ../soc/periph/i2c_master.v
    ../soc/top/soc_top.v
    ../tb/tb_nested_check.v
} { vlog -sv -work work +acc $f }
puts "==== Compile Done ===="

# ---- Step 3: Test with different SHADOW_BANKS values ----
foreach {banks label} {4 "SHADOW_BANKS=4 (baseline)" 2 "SHADOW_BANKS=2" 1 "SHADOW_BANKS=1"} {
    puts ""
    puts "============================================"
    puts "  TEST: $label"
    puts "============================================"

    vsim -c -voptargs=+acc -gSHADOW_BANKS=$banks -gUSE_INST_ROM=1 \
        work.tb_nested_check -do {run 10us; quit -f}

    puts "  $label: DONE"
}
puts ""
puts "==== All regression tests complete ===="
