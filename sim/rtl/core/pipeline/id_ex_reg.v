// core/pipeline/id_ex_reg.v (修改版)
`timescale 1ns/1ps

// ============================================================================
// 模块: id_ex_reg
// 功能: ID/EX 流水线寄存器，连接译码阶段和执行阶段
// 描述:
//   该寄存器将ID阶段产生的所有控制信号和数据，传递给EX阶段。
//   包括: PC值、寄存器数据、寄存器地址、ALU控制、内存控制、
//   写回控制、分支/跳转控制、CSR控制等。
//   支持停顿(stall)、流水线刷新(flush)、中断刷新(intr_flush)。
// ============================================================================
module id_ex_reg (
    // ========== 系统接口 ==========
    input  wire        clk_i,          // 时钟信号
    input  wire        rst_n_i,        // 复位信号 (低电平有效)

    // ========== 流水线控制信号 ==========
    input  wire        stall_i,        // 停顿标志
    input  wire        flush_i,        // 流水线刷新标志
    input  wire        intr_flush_i,   // 中断刷新标志

    // ========== ID阶段输入 ==========
    input  wire [31:0] id_pc_i,        // PC
    input  wire [31:0] id_rs1_data_i,  // rs1数据
    input  wire [31:0] id_rs2_data_i,  // rs2数据
    input  wire [31:0] id_imm_i,       // 立即数
    input  wire [4:0]  id_rs1_addr_i,  // rs1地址
    input  wire [4:0]  id_rs2_addr_i,  // rs2地址
    input  wire [4:0]  id_rd_addr_i,   // 目标寄存器地址

    input  wire [3:0]  id_alu_op_i,    // ALU操作码
    input  wire        id_alu_src_i,   // ALU源选择
    input  wire        id_mem_we_i,    // 内存写使能
    input  wire        id_mem_re_i,    // 内存读使能
    input  wire [2:0]  id_mem_width_i, // 内存宽度控制
    input  wire [1:0]  id_wb_sel_i,    // 写回选择
    input  wire        id_reg_we_i,    // 寄存器写使能
    input  wire        id_branch_i,    // 分支标志
    input  wire        id_jump_i,      // 跳转标志
    input  wire [2:0]  id_funct3_i,    // funct3字段
    input  wire [6:0]  id_opcode_i,    // 操作码

    // ========== CSR接口输入 ==========
    input  wire        id_csr_inst_i,  // CSR指令标志
    input  wire [11:0] id_csr_addr_i,  // CSR地址
    input  wire [2:0]  id_csr_op_i,    // CSR操作类型
    input  wire [4:0]  id_csr_zimm_i,  // CSR立即数
    input  wire        id_mret_i,      // MRET指令标志
    // ========== EX阶段输出 ==========
    output reg  [31:0] ex_pc_o,
    output reg  [31:0] ex_rs1_data_o,
    output reg  [31:0] ex_rs2_data_o,
    output reg  [31:0] ex_imm_o,
    output reg  [4:0]  ex_rs1_addr_o,
    output reg  [4:0]  ex_rs2_addr_o,
    output reg  [4:0]  ex_rd_addr_o,

    output reg  [3:0]  ex_alu_op_o,
    output reg         ex_alu_src_o,
    output reg         ex_mem_we_o,
    output reg         ex_mem_re_o,
    output reg  [2:0]  ex_mem_width_o,
    output reg  [1:0]  ex_wb_sel_o,
    output reg         ex_reg_we_o,
    output reg         ex_branch_o,
    output reg         ex_jump_o,
    output reg  [2:0]  ex_funct3_o,
    output reg  [6:0]  ex_opcode_o,

    // ========== CSR接口输出 ==========
    output reg         ex_csr_inst_o,
    output reg  [11:0] ex_csr_addr_o,
    output reg  [2:0]  ex_csr_op_o,
    output reg  [4:0]  ex_csr_zimm_o,
    output reg         ex_mret_o
);

always @(posedge clk_i ) begin
    if (!rst_n_i) begin
        ex_pc_o         <= 32'b0;
        ex_rs1_data_o   <= 32'b0;
        ex_rs2_data_o   <= 32'b0;
        ex_imm_o        <= 32'b0;
        ex_rs1_addr_o   <= 5'b0;
        ex_rs2_addr_o   <= 5'b0;
        ex_rd_addr_o    <= 5'b0;

        ex_alu_op_o     <= 4'b0000;
        ex_alu_src_o    <= 1'b0;
        ex_mem_we_o     <= 1'b0;
        ex_mem_re_o     <= 1'b0;
        ex_mem_width_o  <= 3'b010;
        ex_wb_sel_o     <= 2'b00;
        ex_reg_we_o     <= 1'b0;
        ex_branch_o     <= 1'b0;
        ex_jump_o       <= 1'b0;
        ex_funct3_o     <= 3'b000;
        ex_opcode_o     <= 7'b0;

        ex_csr_inst_o   <= 1'b0;
        ex_csr_addr_o   <= 12'b0;
        ex_csr_op_o     <= 3'b0;
        ex_csr_zimm_o   <= 5'b0;
        ex_mret_o       <= 1'b0;
    end
    else if (flush_i || intr_flush_i) begin
        ex_pc_o         <= 32'b0;
        ex_rs1_data_o   <= 32'b0;
        ex_rs2_data_o   <= 32'b0;
        ex_imm_o        <= 32'b0;
        ex_rs1_addr_o   <= 5'b0;
        ex_rs2_addr_o   <= 5'b0;
        ex_rd_addr_o    <= 5'b0;

        ex_alu_op_o     <= 4'b0000;
        ex_alu_src_o    <= 1'b1;
        ex_mem_we_o     <= 1'b0;
        ex_mem_re_o     <= 1'b0;
        ex_mem_width_o  <= 3'b010;
        ex_wb_sel_o     <= 2'b00;
        ex_reg_we_o     <= 1'b0;
        ex_branch_o     <= 1'b0;
        ex_jump_o       <= 1'b0;
        ex_funct3_o     <= 3'b000;
        ex_opcode_o     <= 7'b0010011;  // NOP的操作码

        ex_csr_inst_o   <= 1'b0;
        ex_csr_addr_o   <= 12'b0;
        ex_csr_op_o     <= 3'b0;
        ex_csr_zimm_o   <= 5'b0;
        ex_mret_o       <= 1'b0;
    end
    else if (!stall_i) begin
        ex_pc_o         <= id_pc_i;
        ex_rs1_data_o   <= id_rs1_data_i;
        ex_rs2_data_o   <= id_rs2_data_i;
        ex_imm_o        <= id_imm_i;
        ex_rs1_addr_o   <= id_rs1_addr_i;
        ex_rs2_addr_o   <= id_rs2_addr_i;
        ex_rd_addr_o    <= id_rd_addr_i;

        ex_alu_op_o     <= id_alu_op_i;
        ex_alu_src_o    <= id_alu_src_i;
        ex_mem_we_o     <= id_mem_we_i;
        ex_mem_re_o     <= id_mem_re_i;
        ex_mem_width_o  <= id_mem_width_i;
        ex_wb_sel_o     <= id_wb_sel_i;
        ex_reg_we_o     <= id_reg_we_i;
        ex_branch_o     <= id_branch_i;
        ex_jump_o       <= id_jump_i;
        ex_funct3_o     <= id_funct3_i;
        ex_opcode_o     <= id_opcode_i;

        ex_csr_inst_o   <= id_csr_inst_i;
        ex_csr_addr_o   <= id_csr_addr_i;
        ex_csr_op_o     <= id_csr_op_i;
        ex_csr_zimm_o   <= id_csr_zimm_i;
        ex_mret_o       <= id_mret_i;
    end
end

endmodule
