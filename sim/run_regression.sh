#!/bin/bash
# Regression test script for SHADOW_BANKS=4,2,1
cd "$(dirname "$0")"
echo "==== Assembling nested_test.s ===="
python ../python/asm_to_hex.py nested_test.s nested_test.hex
echo "==== Assemble Done ===="

# Compile once
vlib work 2>/dev/null
vmap work work 2>/dev/null
for f in \
    ../core/ifu/pc_reg.v ../core/ifu/ifu_top.v \
    ../core/id/decoder.v ../core/id/ctrl.v ../core/id/imm_gen.v ../core/id/regfile.v ../core/id/id_top.v \
    ../core/exu/alu.v ../core/exu/branch.v ../core/exu/ex_top.v \
    ../core/mem/mem_ctrl.v ../core/mem/mem_top.v \
    ../core/wbu/wb_mux.v ../core/wbu/wb_top.v \
    ../core/pipeline/if_id_reg.v ../core/pipeline/id_ex_reg.v \
    ../core/pipeline/ex_mem_reg.v ../core/pipeline/mem_wb_reg.v \
    ../core/hazard/hazard_unit.v ../core/hazard/forwarding_unit.v \
    ../core/csr/csr_regfile.v ../core/csr/csr_instructions.v \
    ../core/interrupt/interrupt_controller.v \
    ../core/interrupt/interrupt_pipeline.v \
    ../core/interrupt/bank_controller.v \
    ../core/core_top.v \
    ../soc/bus/bus_arbiter.v ../soc/mem/inst_bram.v ../soc/mem/inst_rom.v ../soc/mem/data_ram.v \
    ../soc/periph/uart_ctrl.v ../soc/periph/uart_tx.v ../soc/periph/uart_rx.v \
    ../soc/periph/gpio.v ../soc/periph/timer.v \
    ../soc/periph/spi_master.v ../soc/periph/spi_flash_ctrl.v \
    ../soc/periph/i2c_master.v \
    ../soc/top/soc_top.v \
    ../tb/tb_nested_check.v; do
    vlog -sv -work work +acc "$f" 2>&1 | grep -i "error\|warning" || true
done
echo "==== Compile Done ===="

# Run tests
for banks in 4 2 1; do
    echo ""
    echo "============================================"
    echo "  TEST: SHADOW_BANKS=$banks"
    echo "============================================"
    vsim -c -voptargs=+acc -gSHADOW_BANKS=$banks -gUSE_INST_ROM=1 \
        work.tb_nested_check -do "run 10us; quit -f" 2>&1 | grep -E "tohost|timer_count|gpio_count|preempted|PASS|FAIL|INTR TAKEN|MRET|Error"
    echo "  SHADOW_BANKS=$banks: DONE"
done
echo ""
echo "==== All regression tests complete ===="
