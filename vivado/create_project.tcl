# ============================================================================
# Vivado 工程自动创建脚本
# 用法:
#   方式1 (GUI):  vivado -source vivado/create_project.tcl
#   方式2 (GUI):  打开 Vivado → Tools → Run Tcl Script → 选择本文件
#   方式3 (命令行): vivado -mode batch -source vivado/create_project.tcl
#
# 执行后自动打开 GUI, 可在界面中手动点 Synthesis → Implementation → Bitstream
#
# 目标 FPGA: Xilinx Kintex-7 xc7k325tffg900-2 (Genesys 2 开发板)
# 顶层模块:  soc_top_fpga
# 时钟频率:  200 MHz (LVDS 差分输入)
# ============================================================================

# ----------------------------------------------------------------------------
# 0. 路径设置
# ----------------------------------------------------------------------------
# 获取脚本所在目录
set script_dir [file dirname [file normalize [info script]]]
# 仓库根目录 (脚本在 vivado/ 下)
set repo_root [file normalize [file join $script_dir ..]]

# 工程目录 (在 vivado/ 下)
set proj_dir  [file join $script_dir RISCV_TEST]
set proj_name RISCV_TEST
set proj_part xc7k325tffg900-2

# ----------------------------------------------------------------------------
# 1. 新建工程 (如果已存在则先关闭并删除)
# ----------------------------------------------------------------------------
puts "============================================="
puts " 创建 Vivado 工程: $proj_name"
puts " 目标器件:         $proj_part"
puts " 顶层模块:          soc_top_fpga"
puts " 仓库根目录:        $repo_root"
puts "============================================="

# 关闭已打开的同名工程
if { [catch {current_project} cp] == 0 && [get_projects -quiet $proj_name] ne "" } {
    puts "关闭已有工程 $proj_name ..."
    close_project -quiet
}

# 删除旧工程目录 (可选, 确保从头开始)
if { [file exists $proj_dir] } {
    puts "删除旧工程目录..."
    file delete -force $proj_dir
}

# 创建新工程 (in-memory 转为磁盘工程)
create_project -force $proj_name $proj_dir -part $proj_part
set_property target_language Verilog [current_project]

# ----------------------------------------------------------------------------
# 2. 添加 RTL 源文件
# ----------------------------------------------------------------------------
puts ""
puts "--- 添加 RTL 源文件 ---"

# 设置库
set_property default_lib xil_defaultlib [current_project]

# --- core/ifu ---
set ifu_dir [file join $repo_root core ifu]
if { [file exists $ifu_dir] } {
    add_files -norecurse -fileset sources_1 \
        [file join $ifu_dir pc_reg.v] \
        [file join $ifu_dir ifu_top.v]
}

# --- core/id ---
set id_dir [file join $repo_root core id]
if { [file exists $id_dir] } {
    add_files -norecurse -fileset sources_1 \
        [file join $id_dir decoder.v] \
        [file join $id_dir ctrl.v] \
        [file join $id_dir imm_gen.v] \
        [file join $id_dir regfile.v] \
        [file join $id_dir id_top.v]
}

# --- core/exu ---
set exu_dir [file join $repo_root core exu]
if { [file exists $exu_dir] } {
    add_files -norecurse -fileset sources_1 \
        [file join $exu_dir alu.v] \
        [file join $exu_dir branch.v] \
        [file join $exu_dir ex_top.v]
}

# --- core/mem ---
set mem_dir [file join $repo_root core mem]
if { [file exists $mem_dir] } {
    add_files -norecurse -fileset sources_1 \
        [file join $mem_dir mem_ctrl.v] \
        [file join $mem_dir mem_top.v]
}

# --- core/wbu ---
set wbu_dir [file join $repo_root core wbu]
if { [file exists $wbu_dir] } {
    add_files -norecurse -fileset sources_1 \
        [file join $wbu_dir wb_mux.v] \
        [file join $wbu_dir wb_top.v]
}

# --- core/pipeline ---
set pipe_dir [file join $repo_root core pipeline]
if { [file exists $pipe_dir] } {
    add_files -norecurse -fileset sources_1 \
        [file join $pipe_dir if_id_reg.v] \
        [file join $pipe_dir id_ex_reg.v] \
        [file join $pipe_dir ex_mem_reg.v] \
        [file join $pipe_dir mem_wb_reg.v]
}

# --- core/hazard ---
set hazard_dir [file join $repo_root core hazard]
if { [file exists $hazard_dir] } {
    add_files -norecurse -fileset sources_1 \
        [file join $hazard_dir hazard_unit.v] \
        [file join $hazard_dir forwarding_unit.v]
}

# --- core/csr ---
set csr_dir [file join $repo_root core csr]
if { [file exists $csr_dir] } {
    add_files -norecurse -fileset sources_1 \
        [file join $csr_dir csr_regfile.v] \
        [file join $csr_dir csr_instructions.v]
}

# --- core/interrupt ---
set intr_dir [file join $repo_root core interrupt]
if { [file exists $intr_dir] } {
    add_files -norecurse -fileset sources_1 \
        [file join $intr_dir interrupt_controller.v] \
        [file join $intr_dir interrupt_pipeline.v] \
        [file join $intr_dir bank_controller.v]
}

# --- core_top ---
set core_top_file [file join $repo_root core core_top.v]
if { [file exists $core_top_file] } {
    add_files -norecurse -fileset sources_1 $core_top_file
}

# --- soc/mem ---
set soc_mem_dir [file join $repo_root soc mem]
if { [file exists $soc_mem_dir] } {
    add_files -norecurse -fileset sources_1 \
        [file join $soc_mem_dir inst_bram.v] \
        [file join $soc_mem_dir data_ram.v]
}

# --- soc/bus ---
set soc_bus_file [file join $repo_root soc bus bus_arbiter.v]
if { [file exists $soc_bus_file] } {
    add_files -norecurse -fileset sources_1 $soc_bus_file
}

# --- soc/periph ---
set periph_dir [file join $repo_root soc periph]
if { [file exists $periph_dir] } {
    add_files -norecurse -fileset sources_1 \
        [file join $periph_dir uart_tx.v] \
        [file join $periph_dir uart_rx.v] \
        [file join $periph_dir uart_ctrl.v] \
        [file join $periph_dir gpio.v] \
        [file join $periph_dir timer.v] \
        [file join $periph_dir spi_master.v] \
        [file join $periph_dir spi_flash_ctrl.v] \
        [file join $periph_dir i2c_master.v]
}

# --- soc/top ---
set soc_top_file  [file join $repo_root soc top soc_top.v]
set soc_fpga_file  [file join $repo_root soc top soc_top_fpga.v]
if { [file exists $soc_top_file] } {
    add_files -norecurse -fileset sources_1 $soc_top_file
}
if { [file exists $soc_fpga_file] } {
    add_files -norecurse -fileset sources_1 $soc_fpga_file
}

# ----------------------------------------------------------------------------
# 3. 设置顶层模块
# ----------------------------------------------------------------------------
set_property top soc_top_fpga [current_fileset]
puts ""
puts "顶层模块: [get_property top [current_fileset]]"

# ----------------------------------------------------------------------------
# 4. 添加约束文件
# ----------------------------------------------------------------------------
set xdc_file [file join $repo_root constraints.xdc]
if { [file exists $xdc_file] } {
    add_files -fileset constrs_1 $xdc_file
    puts "约束文件: $xdc_file"
} else {
    puts "警告: 未找到约束文件 $xdc_file"
}

# ----------------------------------------------------------------------------
# 5. 综合与实现策略设置
# ----------------------------------------------------------------------------
# 使用默认策略, 可在 GUI 中手动修改
set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
set_property strategy Flow_PerfOptimized_high [get_runs impl_1]

# 提高综合 effort (可选)
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY rebuilt [get_runs synth_1]

# 200 MHz 时序目标 — 实现时尽量满足
# (已在 constraints.xdc 中定义 create_clock, 这里不重复)

# ----------------------------------------------------------------------------
# 6. 保存工程信息
# ----------------------------------------------------------------------------
puts ""
puts "--- 源文件统计 ---"
puts "  Verilog 文件数: [llength [get_files -of_objects [get_filesets sources_1] -filter {FILE_TYPE == Verilog}]]"
puts "  约束文件数:     [llength [get_files -of_objects [get_filesets constrs_1]]]"

puts ""
puts "============================================="
puts " 工程创建完成!"
puts ""
puts " 接下来在 GUI 中手动操作:"
puts "   1. 点击左侧 Flow Navigator → Synthesis → Run Synthesis"
puts "   2. 综合完成后 → Run Implementation"
puts "   3. 实现完成后 → Generate Bitstream"
puts ""
puts " 或者用 Tcl 命令一键运行 (在 Vivado Tcl Console 中):"
puts "   launch_runs synth_1 -jobs 8"
puts "   wait_on_run synth_1"
puts "   launch_runs impl_1 -jobs 8"
puts "   wait_on_run impl_1"
puts "   launch_runs impl_1 -to_step write_bitstream"
puts "============================================="

# ----------------------------------------------------------------------------
# 7. 启动 GUI
# ----------------------------------------------------------------------------
# 如果从命令行用 vivado -source 运行, start_gui 会打开界面
start_gui
