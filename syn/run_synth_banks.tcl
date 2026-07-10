#!/usr/bin/env dc_shell
# =============================================================================
# run_synth_banks.tcl — FX-RV32-X 多Bank影子寄存器 DC综合脚本
# =============================================================================
# 用途: 对不同的 SHADOW_BANKS 配置 (1/2/4/8) 运行 Design Compiler 综合
#       顶层为 soc_top, 与第一篇论文方法一致, core_top 数据从层次化报告提取
# 使用: dc_shell -f run_synth_banks.tcl
#
# 与第一篇论文脚本的差异:
#   1. rtl_root 指向 FX-RV32_Custom (含多Bank RTL)
#   2. 新增 bank_controller.v, uart_rx.v, spi_flash_ctrl.v, inst_bram.v
#   3. 通过 elaborate -parameters 传递 SHADOW_BANKS, 无需手动编辑 Verilog
#   4. 报告输出到 doc/NewWork/syn/banks_X/
#
# 数据提取: 在 area_hier.rpt / power_hier.rpt 中查找 core_top 行
#
# 参考: doc/NewWork/syn_guide.md
# =============================================================================

# =============================================================================
# 0. 用户配置 — 修改此处即可
# =============================================================================
set SHADOW_BANKS 8                ;# 影子Bank数量: 1 / 2 / 4 / 8
set USE_INST_ROM 1                ;# 0=inst_bram, 1=inst_rom (与第一篇论文一致)
set CLK_PERIOD   5.0              ;# 时钟周期 (ns), 200MHz=5ns
set CLK_NAME     clk              ;# 时钟端口名
set TOP_MODULE   soc_top          ;# 顶层模块 (第一篇论文方法)
set PROJECT_ROOT /home/yifengxin/FX-RV32_Custom
set REPORT_DIR   ${PROJECT_ROOT}/doc/NewWork/syn/banks_${SHADOW_BANKS}

# =============================================================================
# 1. 库设置
# =============================================================================
set lib_path /home/yifengxin/smic55_rvt_lib/synopsys/1.2v
set search_path [list . $lib_path]
set target_library scc55nll_hd_rvt_tt_v1p2_25c_basic.db
set link_library [list * $target_library]
set symbol_library {}

# =============================================================================
# 2. 创建输出目录
# =============================================================================
if {![file exists $REPORT_DIR]} {
    file mkdir $REPORT_DIR
}

set rtl_root $PROJECT_ROOT

# =============================================================================
# 3. 分析 RTL 文件 (soc_top + core_top + 全部子模块)
# =============================================================================
analyze -format verilog -lib WORK [list \
    ${rtl_root}/soc/top/soc_top.v \
    ${rtl_root}/core/core_top.v \
    ${rtl_root}/soc/mem/inst_rom.v \
    ${rtl_root}/soc/mem/inst_bram.v \
    ${rtl_root}/soc/mem/data_ram.v \
    ${rtl_root}/soc/bus/bus_arbiter.v \
    ${rtl_root}/soc/periph/gpio.v \
    ${rtl_root}/soc/periph/timer.v \
    ${rtl_root}/soc/periph/uart_ctrl.v \
    ${rtl_root}/soc/periph/uart_tx.v \
    ${rtl_root}/soc/periph/uart_rx.v \
    ${rtl_root}/soc/periph/spi_master.v \
    ${rtl_root}/soc/periph/spi_flash_ctrl.v \
    ${rtl_root}/soc/periph/i2c_master.v \
    ${rtl_root}/core/ifu/ifu_top.v \
    ${rtl_root}/core/ifu/pc_reg.v \
    ${rtl_root}/core/id/ctrl.v \
    ${rtl_root}/core/id/decoder.v \
    ${rtl_root}/core/id/id_top.v \
    ${rtl_root}/core/id/imm_gen.v \
    ${rtl_root}/core/id/regfile.v \
    ${rtl_root}/core/exu/alu.v \
    ${rtl_root}/core/exu/branch.v \
    ${rtl_root}/core/exu/ex_top.v \
    ${rtl_root}/core/mem/mem_top.v \
    ${rtl_root}/core/mem/mem_ctrl.v \
    ${rtl_root}/core/wbu/wb_mux.v \
    ${rtl_root}/core/wbu/wb_top.v \
    ${rtl_root}/core/hazard/forwarding_unit.v \
    ${rtl_root}/core/hazard/hazard_unit.v \
    ${rtl_root}/core/pipeline/if_id_reg.v \
    ${rtl_root}/core/pipeline/id_ex_reg.v \
    ${rtl_root}/core/pipeline/ex_mem_reg.v \
    ${rtl_root}/core/pipeline/mem_wb_reg.v \
    ${rtl_root}/core/csr/csr_regfile.v \
    ${rtl_root}/core/csr/csr_instructions.v \
    ${rtl_root}/core/interrupt/interrupt_controller.v \
    ${rtl_root}/core/interrupt/interrupt_pipeline.v \
    ${rtl_root}/core/interrupt/bank_controller.v
]

# =============================================================================
# 4. 综设 (Elaborate)
# =============================================================================
# 通过 -parameters 传递, 参数传播链:
#   soc_top → core_top → interrupt_pipeline / regfile / bank_controller
elaborate ${TOP_MODULE} -parameters "SHADOW_BANKS=${SHADOW_BANKS}, USE_INST_ROM=${USE_INST_ROM}"
current_design ${TOP_MODULE}
link
check_design

# =============================================================================
# 5. 时序约束
# =============================================================================
create_clock -name ${CLK_NAME} -period ${CLK_PERIOD} [get_ports clk_i]
set_input_delay  -clock ${CLK_NAME} -max 2 [remove_from_collection [all_inputs] [get_ports clk_i]]
set_output_delay -clock ${CLK_NAME} -max 2 [all_outputs]

# 面积优化
set compile_optimize_netlist_area true

# =============================================================================
# 6. 功耗分析 (必须在 compile 前使能)
# =============================================================================
set power_enable_analysis TRUE

# =============================================================================
# 7. 综合 (Compile)
# =============================================================================
compile

# =============================================================================
# 8. 保存输出 (网表/SDF/SDC/DDC)
# =============================================================================
write -f ddc     -hierarchy -output ${REPORT_DIR}/soc_top_banks${SHADOW_BANKS}.ddc
write -f verilog -hierarchy -output ${REPORT_DIR}/soc_top_banks${SHADOW_BANKS}_netlist.v
write_sdf -version 2.1 ${REPORT_DIR}/soc_top_banks${SHADOW_BANKS}.sdf
write_sdc ${REPORT_DIR}/soc_top_banks${SHADOW_BANKS}.sdc

# =============================================================================
# 9. 报告 (面积/功耗/时序)
# =============================================================================
# 扁平报告
redirect -file ${REPORT_DIR}/area.rpt        {report_area}
redirect -file ${REPORT_DIR}/power.rpt       {report_power}
redirect -file ${REPORT_DIR}/timing.rpt      {report_timing}

# 层次化报告 — 从中提取 core_top 数据
redirect -file ${REPORT_DIR}/area_hier.rpt   {report_area   -hierarchy}
redirect -file ${REPORT_DIR}/power_hier.rpt  {report_power  -hierarchy}
redirect -file ${REPORT_DIR}/power_cell.rpt  {report_power  -cell -hierarchy}

# =============================================================================
# 10. 打印汇总
# =============================================================================
puts "\n=============================================="
puts " 综合完成: SHADOW_BANKS = ${SHADOW_BANKS}"
puts " 报告目录: ${REPORT_DIR}"
puts " 请在 area_hier.rpt 中查找 core_top 行获取面积"
puts " 请在 power_hier.rpt 中查找 core_top 行获取功耗"
puts "==============================================\n"

exit
