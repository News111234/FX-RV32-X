# nested_uvm/run_nested.tcl — 论文10项测试 UVM 一键运行脚本
# 用法: vsim -c -do run_nested.tcl                        (控制台, test_single_intr)
#       vsim -c -do "set TEST test_nested; do run_nested.tcl"  (指定测试)
#       vsim -do "set TEST test_triple; set GUI 1; do run_nested.tcl" (GUI+波形)

if {![info exists TEST]}   { set TEST   test_single_intr }
if {![info exists GUI]}    { set GUI    0 }
if {![info exists BANKS]}  { set BANKS  4 }
if {![info exists POL]}    { set POL    0 }

# UVM库路径
set UVM_SRC ""
if {[info exists env(UVM_HOME)]} {
    set UVM_SRC $env(UVM_HOME)/src
} else {
    foreach p [list "$env(MODEL_TECH)/../uvm-1.2/src" "C:/modeltech/uvm-1.2/src"] {
        if {[file exists $p/uvm_pkg.sv]} { set UVM_SRC $p; break }
    }
}

puts "=========================================="
puts "  FX-RV32-X Nested Interrupt UVM Tests"
puts "=========================================="
puts "  TEST: $TEST  BANKS: $BANKS  POL: $POL"
puts "=========================================="

# 编译
if {[file exists work]} { vdel -all }
vlib work

# UVM库
if {$UVM_SRC != ""} {
    vlog -work work +incdir+$UVM_SRC +define+UVM_NO_DPI $UVM_SRC/uvm_pkg.sv
}

# RTL文件列表 (从rtl_filelist.f读取, 加上soc_top)
set RTL_ROOT ../core
set SOC_ROOT ../soc
set TB_ROOT  ../tb

# 编译RTL
foreach f [concat \
    [glob -nocomplain $RTL_ROOT/ifu/*.v] \
    [glob -nocomplain $RTL_ROOT/id/*.v] \
    [glob -nocomplain $RTL_ROOT/exu/*.v] \
    [glob -nocomplain $RTL_ROOT/mem/*.v] \
    [glob -nocomplain $RTL_ROOT/wbu/*.v] \
    [glob -nocomplain $RTL_ROOT/pipeline/*.v] \
    [glob -nocomplain $RTL_ROOT/hazard/*.v] \
    [glob -nocomplain $RTL_ROOT/csr/*.v] \
    [glob -nocomplain $RTL_ROOT/interrupt/*.v] \
    $RTL_ROOT/core_top.v \
    [glob -nocomplain $SOC_ROOT/mem/*.v] \
    [glob -nocomplain $SOC_ROOT/bus/*.v] \
    [glob -nocomplain $SOC_ROOT/periph/*.v] \
    $SOC_ROOT/top/soc_top.v] {
    vlog -work work +acc $f
}

# 编译UVM环境
vlog -work work +acc +define+UVM_NO_DPI +incdir+$UVM_SRC cpu_if.sv
vlog -work work +acc +define+UVM_NO_DPI +incdir+$UVM_SRC nested_pkg.sv
vlog -work work +acc +define+UVM_NO_DPI +incdir+$UVM_SRC tb_top.sv

# 仿真
if {$GUI} {
    vsim -voptargs=+acc work.tb_top \
        +UVM_TESTNAME=$TEST -gSHADOW_BANKS=$BANKS -gOVERFLOW_POLICY=$POL
    add wave -group "Interrupt" \
        tb_top/u_soc_top/u_core/interrupt_taken_pipe \
        tb_top/u_soc_top/u_core/bank_ptr \
        tb_top/u_soc_top/u_core/shadow_save \
        tb_top/u_soc_top/u_core/shadow_restore
    add wave -group "Data RAM" \
        -radix hex \
        tb_top/u_soc_top/u_data_ram/mem[64] \
        tb_top/u_soc_top/u_data_ram/mem[65] \
        tb_top/u_soc_top/u_data_ram/mem[66]
    add wave -group "GPIO" tb_top/vif/gpio_pin0
} else {
    vsim -c -voptargs=+acc work.tb_top \
        +UVM_TESTNAME=$TEST -gSHADOW_BANKS=$BANKS -gOVERFLOW_POLICY=$POL \
        -do "run -all; quit -f"
}
