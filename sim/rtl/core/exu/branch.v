// ================================================
// 模块: branch
// 功能: 分支判断单元 - 处理条件分支转移
// 描述: 接收操作数输入、ALU的zero标志
// 输出: 分支是否跳转、跳转目标地址
// ================================================
`timescale 1ns/1ps

// 模块: branch
// 功能: 分支判断单元，处理所有条件分支指令(BEQ, BNE, BLT, BGE, BLTU, BGEU)
// 描述:
//   本模块根据指令的funct3字段，比较两个操作数(rs1和rs2)的值，
//   判断分支条件是否满足，若满足则计算分支目标地址(PC + 偏移量)。
//   注意: 本模块不使用ALU的zero标志，而是独立进行比较。
// ============================================================================
module branch (
    // ========== 输入端口 ==========
    input  wire [31:0] rs1_data_i,   // 源寄存器rs1的值
    input  wire [31:0] rs2_data_i,   // 源寄存器rs2的值
    input  wire [31:0] pc_i,         // 当前PC值
    input  wire [31:0] imm_i,        // 分支偏移量立即数 (已符号扩展)
    input  wire [2:0]  funct3_i,     // funct3字段 (区分不同分支指令)
    input  wire        branch_i,     // 分支指令标志 (是否为分支指令)
    input  wire        alu_zero_i,   // ALU零标志 (当前未使用，保留)

    // ========== 输出端口 ==========
    output reg         branch_taken_o,  // 分支是否跳转 (1: 跳转)
    output reg  [31:0] branch_target_o  // 分支目标地址 (PC + imm_i)
);

// ========== 内部信号 ==========
wire        beq_taken;      // BEQ: rs1 == rs2 时跳转
wire        bne_taken;      // BNE: rs1 != rs2 时跳转
wire        blt_taken;      // BLT: rs1 < rs2(有符号)时跳转
wire        bge_taken;      // BGE: rs1 >= rs2(有符号)时跳转
wire        bltu_taken;     // BLTU: rs1 < rs2(无符号)时跳转
wire        bgeu_taken;     // BGEU: rs1 >= rs2(无符号)时跳转

// ========== 1. 计算各分支条件 ==========
// BEQ: Branch if Equal
assign beq_taken = (rs1_data_i == rs2_data_i) ? 1'b1 : 1'b0;

// BNE: Branch if Not Equal
assign bne_taken = (rs1_data_i != rs2_data_i) ? 1'b1 : 1'b0;

// BLT: Branch if Less Than (有符号比较)
assign blt_taken = ($signed(rs1_data_i) < $signed(rs2_data_i)) ? 1'b1 : 1'b0;

// BGE: Branch if Greater or Equal (有符号比较)
assign bge_taken = ($signed(rs1_data_i) >= $signed(rs2_data_i)) ? 1'b1 : 1'b0;

// BLTU: Branch if Less Than Unsigned (无符号比较)
assign bltu_taken = (rs1_data_i < rs2_data_i) ? 1'b1 : 1'b0;

// BGEU: Branch if Greater or Equal Unsigned
assign bgeu_taken = (rs1_data_i >= rs2_data_i) ? 1'b1 : 1'b0;

// ========== 2. 根据funct3选择分支结果 ==========
// RISC-V的funct3编码：
// 000: BEQ, 001: BNE, 100: BLT, 101: BGE, 110: BLTU, 111: BGEU
always @(*) begin
    // 默认不跳转
    branch_taken_o = 1'b0;

    // 只有branch_i=1(是分支指令)时判断
    if (branch_i) begin
        case (funct3_i)
            3'b000: branch_taken_o = beq_taken;    // BEQ
            3'b001: branch_taken_o = bne_taken;    // BNE
            3'b100: branch_taken_o = blt_taken;    // BLT
            3'b101: branch_taken_o = bge_taken;    // BGE
            3'b110: branch_taken_o = bltu_taken;   // BLTU
            3'b111: branch_taken_o = bgeu_taken;   // BGEU
            default: branch_taken_o = 1'b0;        // 无效编码，不跳转
        endcase
    end
end

// ========== 3. 计算分支目标地址 ==========
// 分支目标地址 = PC + 符号扩展后的偏移量
// 注意：B-type偏移量已经左移1位(以2字节为单位)
always @(*) begin
    if (branch_i) begin
        // 分支目标：PC + 偏移量(由立即数提供)
        branch_target_o = pc_i + imm_i;
    end else begin
        // 不是分支指令，目标地址无意义(默认为0)
        branch_target_o = 32'b0;
    end
end


endmodule
