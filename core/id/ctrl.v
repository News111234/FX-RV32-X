// core/id/ctrl.v — 分支与跳转控制单元
`timescale 1ns/1ps

// ============================================================================
// 模块: ctrl
// 功能: 根据指令类型生成分支和跳转控制信号
// 描述:
//   本模块从指令操作码出发，识别分支指令 (beq/bne/blt/bge/bltu/bgeu)
//   和跳转指令 (JAL/JALR)，生成 branch_o / jump_o 控制信号。
//   其他控制信号 (mem_we, mem_re, reg_we, alu_src 等) 由 decoder 模块生成。
// ============================================================================
module ctrl (
    // ========== 输入端口 ==========
    input  wire [6:0]  opcode_i,        // 指令操作码 (7 位)
    input  wire [2:0]  funct3_i,        // 功能码 3 位
    input  wire [6:0]  funct7_i,        // 功能码 7 位
    input  wire [31:0] instr_i,         // 完整指令 (用于识别 MRET)

    // ========== 输出端口: 分支和跳转控制 ==========
    output wire        branch_o,        // 分支指令标志
    output wire        jump_o           // 跳转指令标志 (JAL / JALR / MRET)
);

// ========== 指令类型识别 ==========
wire is_branch = (opcode_i == 7'b1100011);
wire is_jal    = (opcode_i == 7'b1101111);
wire is_jalr   = (opcode_i == 7'b1100111);
wire is_system = (opcode_i == 7'b1110011);

// MRET: opcode=SYSTEM, funct3=0, funct12=0x302
wire is_mret = is_system && (funct3_i == 3'b000) && (instr_i[31:20] == 12'h302);

// ========== 生成控制信号 ==========
assign branch_o = is_branch;
assign jump_o   = is_jal || is_jalr || is_mret;

endmodule
