#!/bin/bash
# run_all_tests.sh — 一键命令行测试 (inst_rom 模式, 6个测试)
# 用法: cd sim && bash run_all_tests.sh
#
# CLI 一键测试:  bash run_all_tests.sh
# GUI 波形:      vsim -do run_gui_single_intr.do

cd "$(dirname "$0")"
VSIM="vsim"

# ============================================================
# 1. 编译 RTL
# ============================================================
echo "=== 编译 RTL ==="
$VSIM -c -do run_cli_compile.do 2>&1 | tail -1
echo ""

# ============================================================
# 2. 测试函数
# ============================================================
PASS=0; FAIL=0

run_test() {
    local hex=$1 name=$2 banks=$3 exp1=$4 exp2=$5
    cp "$hex" nested_test.hex
    printf "%-22s  " "$name"
    # TCL: string equal 安全比较 (避免 ' 字符解析问题)
    if [ -z "$exp2" ]; then
        local check="set r \[exam u_soc_top/u_data_ram/mem\\[64\\]\]; if {\[string equal \$r $exp1\]} { echo CLI_PASS } else { echo CLI_FAIL }"
    else
        local check="set r1 \[exam u_soc_top/u_data_ram/mem\\[64\\]\]; set r2 \[exam u_soc_top/u_data_ram/mem\\[65\\]\]; if {\[string equal \$r1 $exp1\] && \[string equal \$r2 $exp2\]} { echo CLI_PASS } else { echo CLI_FAIL }"
    fi
    local result=$($VSIM -onfinish stop -c -gUSE_INST_ROM=1 -gSHADOW_BANKS=$banks work.tb_nested_check \
        -do "run 10us; $check; quit -f" 2>&1 | grep "CLI_")
    if echo "$result" | grep -q "CLI_PASS"; then
        echo "PASS"
        PASS=$((PASS+1))
    else
        echo "FAIL ***"
        FAIL=$((FAIL+1))
    fi
}

# ============================================================
# 3. 运行测试
# ============================================================

echo "=== BANKS=4 测试 ==="
run_test single_intr_test.hex  "1.single_intr"      4 "32'hDEAD0001"
run_test ultra_min_test.hex    "2.ultra_min"        4 "32'h00000042"
run_test no_intr_test.hex      "3.no_intr"          4 "32'h00000042"
run_test nested_test.hex       "4.nested"           4 "32'hDEAD0001" "32'hBEEF0001"

echo ""
echo "=== BANKS=1 测试 ==="
run_test overflow_minimal.hex  "5.overflow_min"     1 "32'h00000042"
run_test overflow_test.hex     "6.overflow"          1 "32'hDEAD0001" "32'hBEEF0002"

echo ""
echo "==============================================="
echo "  TOTAL: $((PASS+FAIL))  PASS: $PASS  FAIL: $FAIL"
echo "==============================================="
