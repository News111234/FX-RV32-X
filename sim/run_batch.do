# run_batch.do — 命令行批量测试
# 用法: cd sim && vsim -c -do run_batch.do

if {[file exists work]} { vdel -all }
vlib work

set R ../core; set S ../soc; set T ../tb
echo "=== 编译 RTL ==="
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

# 加载设计
vsim -c -gUSE_INST_ROM=1 work.tb_nested_check

proc run_one_test {hex_file test_name expected64} {
    echo ""
    echo "=== $test_name ==="
    file copy -force $hex_file nested_test.hex
    restart -f
    run 10us
    set result [exam u_soc_top/u_data_ram/mem[64]]
    set tohost [exam u_soc_top/u_data_ram/mem[63]]
    echo "  mem[63](tohost)=$tohost  mem[64](timer)=$result"
    if {$result == $expected64} {
        echo "  => PASS"
    } else {
        echo "  => FAIL (expected $expected64)"
    }
}

run_one_test ultra_min_test.hex    "ultra_min_test"    00000042
run_one_test single_intr_test.hex  "single_intr_test"  DEAD0001
run_one_test no_intr_test.hex      "no_intr_test"      00000042

echo ""
echo "=== 全部测试完成 ==="
quit -f
