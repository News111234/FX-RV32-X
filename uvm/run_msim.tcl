# run_msim.tcl — Modelsim/Questa UVM 自动化仿真脚本
# 用法: vsim -do run_msim.tcl
#       vsim -c -do "set HEX_FILE xxx.hex; do run_msim.tcl"  (控制台模式)
#       vsim -do "set GUI_MODE 1; do run_msim.tcl"            (GUI波形模式)

# ===== 默认配置 =====
if {![info exists TEST_NAME]}  { set TEST_NAME  cpu_test_alu }
if {![info exists HEX_FILE]}   { set HEX_FILE   hex/alu_test.hex }
if {![info exists GUI_MODE]}   { set GUI_MODE   0 }
if {![info exists DUMP_VCD]}   { set DUMP_VCD   0 }
if {![info exists COV_ENABLE]} { set COV_ENABLE 1 }
if {![info exists WAVE_DEPTH]} { set WAVE_DEPTH all }
if {![info exists WAVE_ENABLE]}  { set WAVE_ENABLE 1 }
if {![info exists SHADOW_BANKS]}   { set SHADOW_BANKS 4 }
if {![info exists OVERFLOW_POLICY]} { set OVERFLOW_POLICY 0 }

puts "========================================"
puts "  FX-RV32 Multi-Bank UVM Verification"
puts "========================================"
puts "  TEST_NAME     : $TEST_NAME"
puts "  HEX_FILE      : $HEX_FILE"
puts "  GUI_MODE      : $GUI_MODE"
puts "  SHADOW_BANKS  : $SHADOW_BANKS"
puts "  OVERFLOW_POLICY: $OVERFLOW_POLICY"
puts "  COV_ENABLE    : $COV_ENABLE"
puts "========================================"

# ===== UVM 库路径自动检测 =====
set UVM_SRC ""
if {[info exists env(UVM_HOME)]} {
    set UVM_SRC $env(UVM_HOME)/src
} else {
    # 尝试常见 Modelsim 安装路径
    foreach path [list \
        "$env(MODEL_TECH)/../uvm-1.2/src" \
        "C:/modeltech/uvm-1.2/src" \
        "C:/questasim/uvm-1.2/src" \
        "/usr/local/uvm-1.2/src"] {
        if {[file exists $path/uvm_pkg.sv]} {
            set UVM_SRC $path
            break
        }
    }
}

if {$UVM_SRC == ""} {
    puts "WARNING: UVM 1.2 not found automatically."
    puts "  Set UVM_HOME environment variable, or"
    puts "  pre-compile UVM library with: vlib uvm; vlog +incdir+<uvm_path>/src <uvm_path>/src/uvm_pkg.sv"
}

# ===== 创建工作库 =====
if {[file exists work]} { vdel -all }
vlib work

# ===== 编译 UVM 库 (如未预编译) =====
if {$UVM_SRC != ""} {
    set uvm_lib_compiled 0
    # 检查 work 库中是否已有 uvm_pkg
    catch { vlog -work work +incdir+$UVM_SRC +define+UVM_NO_DPI $UVM_SRC/uvm_pkg.sv }
}

# ===== 编译 RTL =====
puts "Compiling RTL..."
set rtl_files [split [string trim [read [open rtl_filelist.f r]]] "\n"]
foreach f $rtl_files {
    if {[string length [string trim $f]] > 0 && [string index [string trim $f] 0] != "/"} {
        set fname [string trim $f]
        if {[file exists $fname]} {
            vlog -work work +acc -sv $fname
        } else {
            puts "WARNING: File not found: $fname"
        }
    }
}

# ===== 编译 UVM 环境 (含覆盖率) =====
puts "Compiling UVM environment..."
if {$COV_ENABLE} {
    vlog -work work +acc +cover=sbceft +define+UVM_NO_DPI +incdir+$UVM_SRC -suppress 7053 -sv cpu_if.sv
    vlog -work work +acc +cover=sbceft +define+UVM_NO_DPI +incdir+$UVM_SRC -suppress 7053 -sv riscv_uvm_pkg.sv
    vlog -work work +acc +cover=sbceft +define+UVM_NO_DPI +incdir+$UVM_SRC -suppress 7053 -sv uvm_tb_top.sv
} else {
    vlog -work work +acc +define+UVM_NO_DPI +incdir+$UVM_SRC -suppress 7053 -sv cpu_if.sv
    vlog -work work +acc +define+UVM_NO_DPI +incdir+$UVM_SRC -suppress 7053 -sv riscv_uvm_pkg.sv
    vlog -work work +acc +define+UVM_NO_DPI +incdir+$UVM_SRC -suppress 7053 -sv uvm_tb_top.sv
}

# ===== 启动仿真 =====
puts "Starting simulation..."
if {$GUI_MODE} {
    if {$COV_ENABLE} {
        vsim -voptargs=+acc -coverage work.uvm_tb_top \
            +UVM_TESTNAME=$TEST_NAME +TEST_NAME=$TEST_NAME +HEX_FILE=$HEX_FILE \
            +SHADOW_BANKS=$SHADOW_BANKS +OVERFLOW_POLICY=$OVERFLOW_POLICY
    } else {
        vsim -voptargs=+acc work.uvm_tb_top \
            +UVM_TESTNAME=$TEST_NAME +TEST_NAME=$TEST_NAME +HEX_FILE=$HEX_FILE \
            +SHADOW_BANKS=$SHADOW_BANKS +OVERFLOW_POLICY=$OVERFLOW_POLICY
    }
} else {
    if {$COV_ENABLE} {
        vsim -c -voptargs=+acc -coverage work.uvm_tb_top \
            +UVM_TESTNAME=$TEST_NAME +TEST_NAME=$TEST_NAME +HEX_FILE=$HEX_FILE \
            +SHADOW_BANKS=$SHADOW_BANKS +OVERFLOW_POLICY=$OVERFLOW_POLICY \
            -do "run -all; coverage save cov_data.ucdb; coverage report -file coverage_report.txt -byfile -detail; quit -f"
    } else {
        vsim -c -voptargs=+acc work.uvm_tb_top \
            +UVM_TESTNAME=$TEST_NAME +TEST_NAME=$TEST_NAME +HEX_FILE=$HEX_FILE \
            +SHADOW_BANKS=$SHADOW_BANKS +OVERFLOW_POLICY=$OVERFLOW_POLICY \
            -do "run -all; quit -f"
    }
}

# ===== 覆盖率报告 (GUI 模式下仿真结束后手动查看) =====
if {$GUI_MODE && $COV_ENABLE} {
    puts ""
    puts "========================================"
    puts "  Coverage collection enabled."
    puts "  In GUI: Tools -> Coverage -> Report"
    puts "  Or run in transcript:"
    puts "    coverage save cov_data.ucdb"
    puts "    coverage report -file cov_report.txt"
    puts "========================================"
}

# ===== GUI 波形窗口 (仅在 GUI 模式下) =====
if {$GUI_MODE && $WAVE_ENABLE} {
    # 添加波形分组
    add wave -group "Clock & Reset"  uvm_tb_top/clk uvm_tb_top/rst_n

    add wave -group "IF Stage" \
        uvm_tb_top/u_dut/if_pc \
        uvm_tb_top/vif/if_instr

    add wave -group "ID Stage" \
        uvm_tb_top/u_dut/if_id_pc \
        uvm_tb_top/u_dut/if_id_instr

    add wave -group "EX Stage" \
        uvm_tb_top/u_dut/ex_alu_result \
        uvm_tb_top/u_dut/ex_branch_taken \
        uvm_tb_top/u_dut/ex_jump_taken

    add wave -group "WB Stage" \
        uvm_tb_top/u_dut/wb_reg_we_out \
        uvm_tb_top/u_dut/wb_rd_addr_out \
        uvm_tb_top/u_dut/wb_data

    add wave -group "Pipeline Ctrl (Hazard)" \
        uvm_tb_top/u_dut/stall_if \
        uvm_tb_top/u_dut/stall_id \
        uvm_tb_top/u_dut/flush_if \
        uvm_tb_top/u_dut/flush_id \
        uvm_tb_top/u_dut/forwardA \
        uvm_tb_top/u_dut/forwardB

    add wave -group "Bus" \
        uvm_tb_top/vif/bus_re \
        uvm_tb_top/vif/bus_we \
        uvm_tb_top/vif/bus_addr \
        uvm_tb_top/vif/bus_rdata \
        uvm_tb_top/vif/bus_ready

    # ===== 中断 & 多Bank 信号 (新增) =====
    add wave -group "Interrupt" \
        uvm_tb_top/u_dut/intr_take_now \
        uvm_tb_top/u_dut/interrupt_taken_pipe \
        uvm_tb_top/u_dut/bank_ptr \
        uvm_tb_top/u_dut/shadow_save \
        uvm_tb_top/u_dut/shadow_restore \
        uvm_tb_top/u_dut/id_ex_mret

    add wave -group "CSR" \
        uvm_tb_top/u_dut/u_csr_regfile/mstatus_o \
        uvm_tb_top/u_dut/u_csr_regfile/mepc_o \
        uvm_tb_top/u_dut/u_csr_regfile/mcause_o \
        uvm_tb_top/u_dut/u_csr_regfile/mie_o \
        uvm_tb_top/u_dut/u_csr_regfile/mip_o

    add wave -group "GPIO" \
        uvm_tb_top/vif/gpio_pin0 \
        uvm_tb_top/u_dut/gpio_out \
        uvm_tb_top/u_dut/gpio_oe

    add wave -group "Data RAM Markers" \
        -radix hex \
        uvm_tb_top/u_dut/u_data_ram/mem[64] \
        uvm_tb_top/u_dut/u_data_ram/mem[65] \
        uvm_tb_top/u_dut/u_data_ram/mem[66]

    # 显示完整信号值
    configure wave -signalnamewidth 1
}
