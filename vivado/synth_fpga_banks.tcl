# ============================================================================
# FX-RV32-X FPGA 批量综合脚本 — Banks=1/2/4/8
#
# 用法:
#   vivado -mode batch -source vivado/synth_fpga_banks.tcl
#   vivado -mode batch -source vivado/synth_fpga_banks.tcl -tclargs -impl 1
#
# 选项:
#   -impl 0  仅综合 (快速, ~5分钟/配置)
#   -impl 1  综合+实现 (完整, ~30分钟/配置, 含布局布线和时序)
# ============================================================================

set run_impl 0
if { [llength $argv] > 0 } {
    foreach {k v} $argv {
        if {$k eq "-impl"} { set run_impl $v }
    }
}

# 获取脚本所在目录
set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir ..]]

set part_name xc7k325tffg900-2
set top_name  soc_top_fpga

# 配置列表
set configs [list \
    [list 1 0 "1Bank_NoNest"] \
    [list 2 0 "2Bank_1Nest"] \
    [list 4 0 "4Bank_3Nest"] \
    [list 8 0 "8Bank_7Nest"] \
]

# 输出目录
set out_dir [file join $script_dir synth_results]
file mkdir $out_dir

set summary_file [file join $out_dir fpga_summary.md]
set summary_fh [open $summary_file w]

puts $summary_fh "# FX-RV32-X FPGA 综合结果"
puts $summary_fh ""
puts $summary_fh "**器件**: Xilinx Kintex-7 xc7k325tffg900-2  "
puts $summary_fh "**时钟约束**: 200 MHz  "
puts $summary_fh "**综合策略**: Flow_PerfOptimized_high  "
puts $summary_fh "**日期**: [clock format [clock seconds] -format %Y-%m-%d]"
puts $summary_fh ""
puts $summary_fh "---"
puts $summary_fh ""
puts $summary_fh "## 资源占用"
puts $summary_fh ""
puts $summary_fh "| Banks | LUT | FF | BRAM (18K) | DSP |"
puts $summary_fh "|:-----:|----:|----:|:---------:|:---:|"

close $summary_fh

puts "=============================================="
puts " FX-RV32-X FPGA 批量综合"
puts " 配置数: [llength $configs]"
puts " 模式:   [expr {$run_impl ? "综合+实现" : "仅综合"}]"
puts " 器件:   $part_name"
puts "=============================================="

# RTL 文件列表
proc add_all_rtl {repo_root} {
    set core_dir  [file join $repo_root core]
    set soc_dir   [file join $repo_root soc]

    # core/ifu
    add_files -norecurse [file join $core_dir ifu pc_reg.v]
    add_files -norecurse [file join $core_dir ifu ifu_top.v]
    # core/id
    add_files -norecurse [file join $core_dir id decoder.v]
    add_files -norecurse [file join $core_dir id ctrl.v]
    add_files -norecurse [file join $core_dir id imm_gen.v]
    add_files -norecurse [file join $core_dir id regfile.v]
    add_files -norecurse [file join $core_dir id id_top.v]
    # core/exu
    add_files -norecurse [file join $core_dir exu alu.v]
    add_files -norecurse [file join $core_dir exu branch.v]
    add_files -norecurse [file join $core_dir exu ex_top.v]
    # core/mem
    add_files -norecurse [file join $core_dir mem mem_ctrl.v]
    add_files -norecurse [file join $core_dir mem mem_top.v]
    # core/wbu
    add_files -norecurse [file join $core_dir wbu wb_mux.v]
    add_files -norecurse [file join $core_dir wbu wb_top.v]
    # core/pipeline
    add_files -norecurse [file join $core_dir pipeline if_id_reg.v]
    add_files -norecurse [file join $core_dir pipeline id_ex_reg.v]
    add_files -norecurse [file join $core_dir pipeline ex_mem_reg.v]
    add_files -norecurse [file join $core_dir pipeline mem_wb_reg.v]
    # core/hazard
    add_files -norecurse [file join $core_dir hazard hazard_unit.v]
    add_files -norecurse [file join $core_dir hazard forwarding_unit.v]
    # core/csr
    add_files -norecurse [file join $core_dir csr csr_regfile.v]
    add_files -norecurse [file join $core_dir csr csr_instructions.v]
    # core/interrupt
    add_files -norecurse [file join $core_dir interrupt interrupt_controller.v]
    add_files -norecurse [file join $core_dir interrupt interrupt_pipeline.v]
    add_files -norecurse [file join $core_dir interrupt bank_controller.v]
    add_files -norecurse [file join $core_dir interrupt bank_controller.v]
    # core_top
    add_files -norecurse [file join $core_dir core_top.v]
    # soc/mem
    add_files -norecurse [file join $soc_dir mem inst_bram.v]
    add_files -norecurse [file join $soc_dir mem data_ram.v]
    # soc/bus
    add_files -norecurse [file join $soc_dir bus bus_arbiter.v]
    # soc/periph
    add_files -norecurse [file join $soc_dir periph uart_tx.v]
    add_files -norecurse [file join $soc_dir periph uart_rx.v]
    add_files -norecurse [file join $soc_dir periph uart_ctrl.v]
    add_files -norecurse [file join $soc_dir periph gpio.v]
    add_files -norecurse [file join $soc_dir periph timer.v]
    add_files -norecurse [file join $soc_dir periph spi_master.v]
    add_files -norecurse [file join $soc_dir periph spi_flash_ctrl.v]
    add_files -norecurse [file join $soc_dir periph i2c_master.v]
    # soc/top
    add_files -norecurse [file join $soc_dir top soc_top.v]
    add_files -norecurse [file join $soc_dir top soc_top_fpga.v]

    # 约束文件
    set xdc_file [file join $repo_root constraints.xdc]
    if {[file exists $xdc_file]} {
        add_files -fileset constrs_1 $xdc_file
    }
}

set results_data {}

foreach cfg $configs {
    lassign $cfg banks pol label

    set cfg_name "BANKS${banks}_POL${pol}"
    puts ""
    puts "----------------------------------------------"
    puts " 配置: $label (SHADOW_BANKS=$banks, OVERFLOW_POLICY=$pol)"
    puts "----------------------------------------------"

    # 创建 in-memory 工程
    create_project -in_memory -part $part_name
    set_property target_language Verilog [current_project]

    # 添加 RTL
    add_all_rtl $repo_root

    # 设置顶层和参数
    set_property top $top_name [current_fileset]
    set_property generic "SHADOW_BANKS=$banks OVERFLOW_POLICY=$pol" [current_fileset]

    # 综合
    puts "  → 综合中..."
    set synth_start [clock seconds]
    synth_design -top $top_name -part $part_name \
        -generic "SHADOW_BANKS=$banks OVERFLOW_POLICY=$pol" \
        -flatten_hierarchy rebuilt
    set synth_elapsed [expr {[clock seconds] - $synth_start}]
    puts "  ✓ 综合完成 (${synth_elapsed}s)"

    # 收集综合报告
    set util_rpt [file join $out_dir ${cfg_name}_utilization.rpt]
    set timing_rpt [file join $out_dir ${cfg_name}_timing.rpt]

    report_utilization -file $util_rpt
    report_timing_summary -file $timing_rpt

    # 解析利用率
    set luts [get_property SLICE_LUTS [get_designs]]
    set regs [get_property SLICE_REGISTERS [get_designs]]
    set bram [llength [get_cells -hierarchical -filter {PRIMITIVE_TYPE =~ BLOCKRAM*}]]
    set dsp  [llength [get_cells -hierarchical -filter {PRIMITIVE_TYPE =~ DSP*}]]

    # 解析时序 (WNS)
    set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
    set period 5.0;  # 200MHz = 5ns
    set fmax [expr {1000.0 / ($period - $wns)}]

    puts "    LUT: $luts  FF: $regs  BRAM: $bram  DSP: $dsp"
    puts "    WNS: ${wns}ns  Fmax: [format %.1f $fmax] MHz"

    # 完整实现 (可选)
    set impl_wns ""
    set impl_fmax ""
    if {$run_impl} {
        puts "  → 实现中 (opt + place + route)..."
        set impl_start [clock seconds]
        set impl_ok 1
        if {[catch {opt_design} opt_result]} {
            puts "  ✗ opt_design 失败: $opt_result"
            set impl_ok 0
        }
        if {$impl_ok && [catch {place_design} place_result]} {
            puts "  ✗ place_design 失败: $place_result"
            set impl_ok 0
        }
        if {$impl_ok && [catch {route_design} route_result]} {
            puts "  ✗ route_design 失败: $route_result"
            set impl_ok 0
        }
        set impl_elapsed [expr {[clock seconds] - $impl_start}]

        if {$impl_ok} {
            puts "  ✓ 实现完成 (${impl_elapsed}s)"
            set impl_wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1]]
            set impl_fmax [expr {1000.0 / ($period - $impl_wns)}]

            set impl_util_rpt [file join $out_dir ${cfg_name}_impl_utilization.rpt]
            set impl_timing_rpt [file join $out_dir ${cfg_name}_impl_timing.rpt]
            report_utilization -file $impl_util_rpt
            report_timing_summary -file $impl_timing_rpt
            puts "    实现 WNS: ${impl_wns}ns  Fmax: [format %.1f $impl_fmax] MHz"
        } else {
            puts "  ✗ 实现跳过 (${impl_elapsed}s), 仅保留综合数据"
        }
    }

    # 保存到结果列表
    lappend results_data [list $banks $luts $regs $bram $dsp $wns $fmax $impl_wns $impl_fmax]

    close_project
}

# ==========================================================================
# 生成汇总报告
# ==========================================================================
puts ""
puts "=============================================="
puts " 生成汇总报告"
puts "=============================================="

set summary_fh [open $summary_file w]

puts $summary_fh "# FX-RV32-X FPGA 综合结果"
puts $summary_fh ""
puts $summary_fh "**器件**: Xilinx Kintex-7 xc7k325tffg900-2  "
puts $summary_fh "**时钟约束**: 200 MHz (5ns period)  "
puts $summary_fh "**综合策略**: Flow_PerfOptimized_high — flatten_hierarchy=rebuilt  "
puts $summary_fh "**日期**: [clock format [clock seconds] -format %Y-%m-%d]"
puts $summary_fh ""
puts $summary_fh "---"
puts $summary_fh ""
puts $summary_fh "## 资源占用 (综合)"
puts $summary_fh ""
puts $summary_fh "| Banks | LUT | FF | BRAM | DSP | WNS (ns) | Fmax (MHz) |"
puts $summary_fh "|:-----:|----:|----:|:----:|:---:|:--------:|:----------:|"

foreach row $results_data {
    lassign $row banks luts regs bram dsp wns fmax impl_wns impl_fmax
    puts $summary_fh "| $banks | $luts | $regs | $bram | $dsp | $wns | [format %.1f $fmax] |"
}

puts $summary_fh ""

# 如果有实现数据, 加一列
if {$run_impl} {
    puts $summary_fh "## 资源占用 (实现后)"
    puts $summary_fh ""
    puts $summary_fh "| Banks | WNS (ns) | Fmax (MHz) |"
    puts $summary_fh "|:-----:|:--------:|:----------:|"
    foreach row $results_data {
        lassign $row banks luts regs bram dsp wns fmax impl_wns impl_fmax
        puts $summary_fh "| $banks | $impl_wns | [format %.1f $impl_fmax] |"
    }
    puts $summary_fh ""
}

puts $summary_fh "---"
puts $summary_fh ""
puts $summary_fh "## 与 ASIC (DC 55nm) 对比"
puts $summary_fh ""
puts $summary_fh "| Banks | ASIC 面积 (kGE) | ASIC 功耗 (mW) | FPGA LUT | FPGA FF |"
puts $summary_fh "|:-----:|:---------------:|:--------------:|:--------:|:-------:|"
puts $summary_fh "| 1 | 36.00 | 6.07 | [lindex $results_data 0 1] | [lindex $results_data 0 2] |"
puts $summary_fh "| 2 | 42.99 | 7.70 | [lindex $results_data 1 1] | [lindex $results_data 1 2] |"
puts $summary_fh "| 4 | 62.41 | 11.54 | [lindex $results_data 2 1] | [lindex $results_data 2 2] |"
puts $summary_fh "| 8 | 100.20 | 19.38 | [lindex $results_data 3 1] | [lindex $results_data 3 2] |"
puts $summary_fh ""
puts $summary_fh "> 注: ASIC 数据来自 Design Compiler SMIC 55nm 工艺库; FPGA 数据来自 Vivado xc7k325t."

close $summary_fh

puts ""
puts "=============================================="
puts " 批量综合完成!"
puts " 汇总: $summary_file"
puts " 详细报告: $out_dir/"
puts "=============================================="
