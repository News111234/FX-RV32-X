# ============================================================================
# Modelsim 仿真脚本 — FX-RV32 多Bank嵌套中断验证
#
# 用法:
#   cd sim
#   vsim -c -do run_nested.do          # 命令行模式
#   vsim -do run_nested.do             # GUI模式 (带波形)
#
# 前置条件:
#   1. python/riscv_asm7.py 已准备好 (汇编器)
#   2. 顶层 testbench: tb/tb_nested_intr.v
# ============================================================================

# 切换到脚本所在目录
cd [file dirname [info script]]

# ============================================================================
# Step 1: 汇编测试程序
# ============================================================================
puts "============================================"
puts " Step 1: Assembling nested_intr_test.s"
puts "============================================"

# 使用 riscv_asm7.py 汇编, 输出 Verilog ROM 格式
# 然后用 Python 转换为 plain hex
exec python ../python/riscv_asm7.py nested_intr_test.s > nested_intr_test_rom.txt
exec python -c "
lines = open('nested_intr_test_rom.txt','r').readlines()
words = []
for line in lines:
    line = line.strip()
    if line.startswith('rom['):
        # 提取 32'hXXXX
        idx = line.find('32\'h')
        if idx >= 0:
            hex_str = line[idx+4:idx+12]
            words.append(hex_str)
with open('nested_intr_test.hex','w') as f:
    for w in words:
        f.write(w + '\n')
print(f'Generated {len(words)} hex words')
"

puts "  Done."

# ============================================================================
# Step 2: 编译RTL文件
# ============================================================================
puts "============================================"
puts " Step 2: Compiling RTL files"
puts "============================================"

# 创建work库
vlib work
vmap work work

# 编译core模块 (按依赖顺序)
vlog -sv -work work +acc ../core/ifu/pc_reg.v
vlog -sv -work work +acc ../core/ifu/ifu_top.v
vlog -sv -work work +acc ../core/id/decoder.v
vlog -sv -work work +acc ../core/id/ctrl.v
vlog -sv -work work +acc ../core/id/imm_gen.v
vlog -sv -work work +acc ../core/id/regfile.v
vlog -sv -work work +acc ../core/id/id_top.v
vlog -sv -work work +acc ../core/exu/alu.v
vlog -sv -work work +acc ../core/exu/branch.v
vlog -sv -work work +acc ../core/exu/ex_top.v
vlog -sv -work work +acc ../core/mem/mem_ctrl.v
vlog -sv -work work +acc ../core/mem/mem_top.v
vlog -sv -work work +acc ../core/wbu/wb_mux.v
vlog -sv -work work +acc ../core/wbu/wb_top.v
vlog -sv -work work +acc ../core/pipeline/if_id_reg.v
vlog -sv -work work +acc ../core/pipeline/id_ex_reg.v
vlog -sv -work work +acc ../core/pipeline/ex_mem_reg.v
vlog -sv -work work +acc ../core/pipeline/mem_wb_reg.v
vlog -sv -work work +acc ../core/hazard/hazard_unit.v
vlog -sv -work work +acc ../core/hazard/forwarding_unit.v
vlog -sv -work work +acc ../core/csr/csr_regfile.v
vlog -sv -work work +acc ../core/csr/csr_instructions.v
vlog -sv -work work +acc ../core/interrupt/interrupt_controller.v
vlog -sv -work work +acc ../core/interrupt/interrupt_pipeline.v
vlog -sv -work work +acc ../core/interrupt/bank_controller.v
vlog -sv -work work +acc ../core/core_top.v

# 编译testbench
vlog -sv -work work +acc ../tb/tb_nested_intr.v

puts "  Done."

# ============================================================================
# Step 3: 启动仿真
# ============================================================================
puts "============================================"
puts " Step 3: Starting Simulation"
puts "============================================"

# 检查是否需要GUI
if {[info exists env(GUI_MODE)]} {
    set gui_mode $env(GUI_MODE)
} else {
    set gui_mode 0
}

# 仿真参数
vsim -voptargs=+acc work.tb_nested_intr

# 添加波形
if {$gui_mode} {
    # 关键信号
    add wave -divider "Clock & Reset"
    add wave tb_nested_intr/clk
    add wave tb_nested_intr/rst_n

    add wave -divider "Pipeline PC"
    add wave -radix hex tb_nested_intr/u_core_top/if_pc
    add wave -radix hex tb_nested_intr/u_core_top/if_instr_i

    add wave -divider "Bank Controller"
    add wave -radix unsigned tb_nested_intr/u_core_top/bank_ptr
    add wave tb_nested_intr/u_core_top/bank_save_en
    add wave tb_nested_intr/u_core_top/bank_restore_en
    add wave tb_nested_intr/u_core_top/bank_overflow
    add wave tb_nested_intr/u_core_top/tail_chain_active

    add wave -divider "Interrupt Signals"
    add wave tb_nested_intr/u_core_top/intr_pending
    add wave tb_nested_intr/u_core_top/intr_take_now
    add wave tb_nested_intr/u_core_top/interrupt_taken_pipe
    add wave tb_nested_intr/u_core_top/interrupt_flush_pipe
    add wave -radix hex tb_nested_intr/u_core_top/intr_cause
    add wave -radix hex tb_nested_intr/u_core_top/intr_handler_addr

    add wave -divider "Shadow Register Control"
    add wave tb_nested_intr/u_core_top/shadow_save
    add wave tb_nested_intr/u_core_top/shadow_restore

    add wave -divider "CSR"
    add wave -radix hex tb_nested_intr/u_core_top/mepc
    add wave -radix hex tb_nested_intr/u_core_top/mcause
    add wave -radix hex tb_nested_intr/u_core_top/mstatus
    add wave -radix hex tb_nested_intr/u_core_top/mtvec

    add wave -divider "Registers (x1-x5)"
    add wave -radix hex tb_nested_intr/u_core_top/u_id_top/u_regfile/registers[1]
    add wave -radix hex tb_nested_intr/u_core_top/u_id_top/u_regfile/registers[2]
    add wave -radix hex tb_nested_intr/u_core_top/u_id_top/u_regfile/registers[3]
    add wave -radix hex tb_nested_intr/u_core_top/u_id_top/u_regfile/registers[5]
end

# 运行仿真
run -all

puts "============================================"
puts " Simulation Complete"
puts "============================================"
