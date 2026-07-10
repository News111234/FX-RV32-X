// core/exu/alu.v — 算术逻辑单元 (支持 RV32I 扩展)
`timescale 1ns/1ps

// ============================================================================
// 模块: alu
// 功能: 算术逻辑单元 (ALU)，支持 RISC-V I 扩展全部运算
// 描述:
//   本模块执行算术和逻辑运算。通过 4 位操作码 (alu_op_i) 选择运算类型。
//   支持加法、减法、移位、比较和逻辑运算。
//
// 操作码定义 (alu_op_i):
//   4'b0000: ADD / ADDI      - 加法
//   4'b0001: SUB             - 减法
//   4'b0010: SLL / SLLI      - 逻辑左移
//   4'b0011: SLT / SLTI      - 有符号小于置位
//   4'b0100: SLTU / SLTIU    - 无符号小于置位
//   4'b0101: XOR / XORI      - 异或
//   4'b0110: OR / ORI / SRL / SRLI - 或 / 逻辑右移
//   4'b0111: AND / ANDI / SRA / SRAI - 与 / 算术右移
// ============================================================================
module alu (
    // ========== 输入端口 ==========
    input  wire [31:0] op1_i,     // 操作数 1 (源操作数 1)
    input  wire [31:0] op2_i,     // 操作数 2 (源操作数 2 或立即数)
    input  wire [3:0]  alu_op_i,  // ALU 操作码 (4 位, 区分不同运算类型)
    input  wire [2:0]  funct3_i,  // funct3 字段 (用于区分 OR/SRL, AND/SRA)

    // ========== 输出端口 ==========
    output reg  [31:0] result_o,  // 运算结果
    output wire        zero_o     // 零标志位 (result_o == 32'b0)
);

// ========== 内部信号 ==========
wire [31:0] add_result;    // 加法结果
wire [31:0] sub_result;    // 减法结果
wire [31:0] sll_result;    // 逻辑左移结果
wire [31:0] srl_result;    // 逻辑右移结果
wire [31:0] sra_result;    // 算术右移结果
wire        slt_result;    // 有符号小于比较结果
wire        sltu_result;   // 无符号小于比较结果
wire [31:0] xor_result;    // 异或结果
wire [31:0] or_result;     // 或结果
wire [31:0] and_result;    // 与结果

// ========== 1. 加法和减法运算 ==========
assign add_result = op1_i + op2_i;
assign sub_result = op1_i - op2_i;

// ========== 2. 移位运算 ==========
assign sll_result = op1_i << op2_i[4:0];
assign srl_result = op1_i >> op2_i[4:0];
assign sra_result = $signed(op1_i) >>> op2_i[4:0];

// ========== 3. 比较运算 ==========
assign slt_result  = ($signed(op1_i) < $signed(op2_i)) ? 1'b1 : 1'b0;
assign sltu_result = (op1_i < op2_i) ? 1'b1 : 1'b0;

// ========== 4. 逻辑运算 ==========
assign xor_result = op1_i ^ op2_i;
assign or_result  = op1_i | op2_i;
assign and_result = op1_i & op2_i;

// ========== 5. 根据 alu_op 和 funct3 选择输出 ==========
always @(*) begin
    case (alu_op_i)
        // ========== I 扩展指令 ==========
        4'b0000: result_o = add_result;           // ADD / ADDI
        4'b0001: result_o = sub_result;           // SUB
        4'b0010: result_o = sll_result;           // SLL / SLLI
        4'b0011: result_o = {31'b0, slt_result};  // SLT / SLTI
        4'b0100: result_o = {31'b0, sltu_result}; // SLTU / SLTIU
        4'b0101: result_o = xor_result;           // XOR / XORI
        4'b0110: result_o = (funct3_i == 3'b101) ? srl_result : or_result;  // SRL/SRLI : OR/ORI
        4'b0111: result_o = (funct3_i == 3'b101) ? sra_result : and_result; // SRA/SRAI : AND/ANDI

        default: result_o = add_result;
    endcase
end

// ========== 6. 输出零标志位 ==========
assign zero_o = (result_o == 32'b0) ? 1'b1 : 1'b0;

endmodule
