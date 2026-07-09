// core/hazard/hazard_unit.v — 冒险检测单元 (含中断刷新控制)
`timescale 1ns/1ps

// ============================================================================
// 模块: hazard_unit
// 功能: 冒险检测单元，处理流水线的 load-use 冒险和控制冒险
// 描述:
//   本模块检测流水线中两种主要冒险:
//   1. Load-Use 冒险 (Load-Use Hazard):
//      当前指令 (ID 阶段) 的源寄存器等于上一条 load 指令 (EX 阶段) 的目标寄存器，
//      且 load 指令尚未进入 MEM 阶段。此时需要停顿流水线 (IF/ID) 一个周期，
//      让 load 数据从 MEM 阶段转发到 EX 阶段。
//
//   2. 控制冒险 (Control Hazard):
//      当分支或跳转指令在 EX 阶段判定为跳转时，需要刷新 (flush) IF/ID 阶段，
//      丢弃已取到的错误指令。
//   此外，本模块还负责中断触发的流水线刷新，中断刷新覆盖所有流水线阶段。
// ============================================================================
module hazard_unit #(
    parameter SYNC_INST_MEM = 1   // 1=BRAM(sync read)需2周期flush, 0=ROM(combinational)仅需1周期
) (
    // ========== 系统接口 ==========
    input  wire        clk_i,              // 时钟信号
    input  wire        rst_n_i,            // 复位信号 (低电平有效)

    // ========== ID 阶段当前指令的源寄存器 ==========
    input  wire [4:0] id_rs1_addr_i,       // ID 阶段指令的 rs1 地址
    input  wire [4:0] id_rs2_addr_i,       // ID 阶段指令的 rs2 地址

    // ========== ID/EX 流水线寄存器中的指令信息 ==========
    input  wire [4:0] id_ex_rd_addr_i,     // ID/EX 阶段指令的目标寄存器地址
    input  wire       id_ex_reg_we_i,      // ID/EX 阶段寄存器写使能
    input  wire       id_ex_mem_re_i,      // ID/EX 阶段是否为 load 指令

    // ========== EX/MEM 流水线寄存器中的指令信息 ==========
    input  wire [4:0] ex_mem_rd_addr_i,    // EX/MEM 阶段指令的目标寄存器地址
    input  wire       ex_mem_reg_we_i,     // EX/MEM 阶段寄存器写使能
    input  wire       ex_mem_mem_re_i,     // EX/MEM 阶段是否为 load 指令

    // ========== 控制冒险信号 ==========
    input  wire       branch_taken_i,      // 分支跳转标志 (来自 EX 阶段)
    input  wire       jump_taken_i,        // 跳转标志 (来自 EX 阶段)

    // ========== 中断信号 ==========
    input  wire       interrupt_taken_i,   // 中断已被接受标志
    input  wire       interrupt_flush_i,   // 中断刷新标志

    // ========== 流水线控制输出 ==========
    output wire       stall_if_o,          // 停顿 IF 阶段 (IF/ID 寄存器)
    output wire       stall_id_o,          // 停顿 ID 阶段 (ID/EX 寄存器)
    output wire       flush_if_o,          // 刷新 IF 阶段 (控制冒险)
    output wire       flush_id_o,          // 刷新 ID 阶段 (控制冒险)

    // ========== 中断刷新输出 (刷新 ID/EX/MEM/WB 阶段) ==========
    // 注意: IF 阶段不需要刷新——intr_take_now 已把 PC 重定向到 handler 地址，
    //       指令 ROM 输出的第一条 ISR 指令正常通过 IF/ID 寄存器进入 ID 阶段
    output wire       intr_flush_id_o,     // 中断刷新 ID 阶段 (中断刷新IF/ID, 清除旧指令残留)
    output wire       intr_flush_ex_o,     // 中断刷新 EX 阶段
    output wire       intr_flush_mem_o,    // 中断刷新 MEM 阶段
    output wire       intr_flush_wb_o      // 中断刷新 WB 阶段

);

// ========== Load-Use 冒险检测 ==========
// 关键条件: 只有 load 在 EX 阶段时才需要 stall
// 如果 load 已经进入 MEM 阶段，应通过转发解决
wire load_in_ex  = id_ex_mem_re_i;                      // load 在 EX 阶段
wire load_in_mem = ex_mem_mem_re_i;                     // load 在 MEM 阶段

// 冒险条件:
// 1. 上一条指令是 load 且还在 EX 阶段，还没进 MEM
// 2. 要写回寄存器且不是 x0
// 3. 当前指令的源寄存器与之匹配
wire load_use_hazard = load_in_ex &&                    // load 在 EX 阶段
                       !load_in_mem &&                  // load 还没进入 MEM 阶段 (关键条件)
                       id_ex_reg_we_i &&
                       (id_ex_rd_addr_i != 5'b0) &&
                       ((id_ex_rd_addr_i == id_rs1_addr_i) ||
                        (id_ex_rd_addr_i == id_rs2_addr_i));


// 控制冒险检测
wire control_hazard = branch_taken_i || jump_taken_i;

// ==========================================================================
// BRAM同步读(SYNC_INST_MEM=1): 有1周期延迟, 需2周期flush:
//   第1条(EX级当拍): flush杀掉 -- control_hazard本身覆盖
//   第2条(BRAM延迟残留): control_hazard_r扩展1周期flush
//   ★ 扩展冲刷期间需stall PC, 防止PC递增跳过跳转目标地址
// ROM组合读(SYNC_INST_MEM=0): 无延迟, 仅需1周期flush, 无需扩展
// ==========================================================================
reg control_hazard_r;
always @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i)
        control_hazard_r <= 1'b0;
    else
        control_hazard_r <= control_hazard;
end

// 控制冒险: ROM仅1周期, BRAM扩展为2周期
wire control_hazard_r_active = control_hazard_r && !interrupt_taken_i;
wire control_hazard_extended = control_hazard || (SYNC_INST_MEM && control_hazard_r_active);

// ========== 控制信号输出 ==========
// ROM: 仅1周期flush, 无需stall PC
// BRAM: 2周期flush; control_hazard_r期间stall PC防止跳过跳转目标
assign stall_if_o = load_use_hazard || (SYNC_INST_MEM && control_hazard_r_active);
assign stall_id_o = load_use_hazard || (SYNC_INST_MEM && control_hazard_r_active);
assign flush_if_o = control_hazard_extended && !interrupt_taken_i;
assign flush_id_o = control_hazard_extended && !interrupt_taken_i;

// 中断刷新信号
// 不需要 intr_flush_if: intr_take_now(组合逻辑)已将PC重定向到handler,
// interrupt_taken 在ISR执行期间覆盖所有低优先级next_pc选项保证PC正常递增
//
// intr_flush_id=0 (不刷新IF/ID): 让第一条ISR指令直接通过IF/ID
//   - PC已由 intr_take_now 重定向到 handler 地址
//   - 指令存储器 (ROM或BRAM) 输出第一条 ISR 指令
//   - ROM (组合读): 同周期输出, FLUSH=0 让它通过
//   - BRAM (同步读): 1周期后输出, 此时 FLUSH 已释放,也让它通过
//   - 旧程序的残留指令进入 ID 阶段, 由下一级 intr_flush_ex 在 ID/EX 处杀死
//
// intr_flush_ex/mem/wb=interrupt_flush: 清除旧程序在 ID/EX、EX/MEM、MEM/WB 的残留
assign intr_flush_id_o  = 1'b0;               // ★ ROM/BRAM 通用: IF/ID 不冲刷
assign intr_flush_ex_o  = interrupt_flush_i;
assign intr_flush_mem_o = interrupt_flush_i;
assign intr_flush_wb_o  = interrupt_flush_i;

endmodule
