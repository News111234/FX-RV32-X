# run_cli_all.do — 命令行批量测试 (ROM模式, 6个测试)
# 用法: cd sim && vsim -c -do run_cli_all.do
# 包括: 编译RTL → 逐个测试 → 汇总 PASS/FAIL → 退出

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

# ============================================================
# 测试函数 (参数: hex名称 显示名称 期望值1 [期望值2])
# 使用 restart -f 复用编译结果, -onfinish stop 防止 $finish 退出
# ============================================================
set PASS_CNT 0; set FAIL_CNT 0

proc test_one {hex name exp1 {exp2 ""}} {
    global PASS_CNT FAIL_CNT
    echo ""
    echo "--- $name ---"
    file copy -force $hex nested_test.hex
    restart -f
    run 10us

    set r1 [exam u_soc_top/u_data_ram/mem[64]]
    echo "  mem[64]=$r1 (exp=$exp1)"
    set ok 1
    if {$r1 != $exp1} { set ok 0 }

    if {$exp2 ne ""} {
        set r2 [exam u_soc_top/u_data_ram/mem[65]]
        echo "  mem[65]=$r2 (exp=$exp2)"
        if {$r2 != $exp2} { set ok 0 }
    }

    if {$ok} {
        echo "  => PASS"
        incr PASS_CNT
    } else {
        echo "  => FAIL ***"
        incr FAIL_CNT
    }
}

# ============================================================
# BANKS=4 测试 (基本 + 嵌套)
# ============================================================
vsim -onfinish stop -gUSE_INST_ROM=1 -gSHADOW_BANKS=4 work.tb_nested_check

test_one single_intr_test.hex  "1.single_intr"    32'hDEAD0001
test_one ultra_min_test.hex    "2.ultra_min"      32'h00000042
test_one no_intr_test.hex      "3.no_intr"        32'h00000042
test_one nested_test.hex       "4.nested(B4)"     32'hDEAD0001 32'hBEEF0001

quit -f

# ============================================================
# BANKS=1 测试 (Bank溢出)
# ============================================================
vsim -onfinish stop -gUSE_INST_ROM=1 -gSHADOW_BANKS=1 -gOVERFLOW_POLICY=0 work.tb_nested_check

test_one overflow_minimal.hex  "5.overflow_min(B1)" 32'h00000042
test_one overflow_test.hex     "6.overflow(B1)"     32'hDEAD0001 32'hBEEF0002

# ============================================================
# 汇总
# ============================================================
echo ""
echo "=========================================="
echo "  TOTAL: [expr $PASS_CNT + $FAIL_CNT]  PASS: $PASS_CNT  FAIL: $FAIL_CNT"
echo "=========================================="
quit -f
