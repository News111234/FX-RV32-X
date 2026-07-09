// core/id/imm_gen.v — 立即数生成器
`timescale 1ns/1ps

// ============================================================================
// 模块: imm_gen
// 功能: 立即数生成器，从 32 位指令中提取并符号扩展立即数
// 描述:
//   本模块根据指令类型 (I/S/B/U/J/CSR)，从指令中提取对应的立即数字段，
//   并进行符号扩展，生成完整的 32 位立即数。
//
// 指令类型对应的立即数格式:
//   - I-type (ADDI, LW, JALR):    imm[11:0] 符号扩展
//   - S-type (SW, SH, SB):        imm[11:5] + imm[4:0] 符号扩展
//   - B-type (BEQ, BNE, ...):     imm[12] + imm[10:5] + imm[4:1] + 1'b0 符号扩展
//   - U-type (LUI, AUIPC):        imm[31:12] + 12'b0
//   - J-type (JAL):               imm[20] + imm[10:1] + imm[11] + imm[19:12] + 1'b0 符号扩展
//   - CSR (CSRRW, CSRRS, ...):    zimm[4:0] 零扩展
// ============================================================================
module imm_gen (
    // ========== 输入端口 ==========
    input  wire [31:0] instr_i,         // 32 位指令

    // ========== 输出端口 ==========
    output reg  [31:0] imm_o            // 32 位立即数 (符号扩展或零扩展)
);

wire [6:0] opcode = instr_i[6:0];
reg [20:0] jal_imm;
reg [19:0] combined_imm;

always @(*) begin
    case (opcode)
        // I-type 指令
        7'b0010011,  // I-type 运算指令
        7'b0000011,  // LOAD 指令
        7'b1100111:  // JALR 指令
        begin
            imm_o = {{20{instr_i[31]}}, instr_i[31:20]};
        end

        // S-type 指令
        7'b0100011:  // STORE 指令
        begin
            imm_o = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
        end

        // B-type 指令
        7'b1100011:  // BRANCH 指令
        begin
            imm_o = {{20{instr_i[31]}}, instr_i[7], instr_i[30:25],
                     instr_i[11:8], 1'b0};
        end

        // U-type 指令
        7'b0110111,  // LUI
        7'b0010111:  // AUIPC
        begin
            imm_o = {instr_i[31:12], 12'b0};
        end

        // J-type 指令
        7'b1101111:  // JAL
        begin
            combined_imm[19:0] = {
                instr_i[31],      // bit19 (imm[20])
                instr_i[19:12],   // bits18-11 (imm[19:12])
                instr_i[20],      // bit10 (imm[11])
                instr_i[30:21]    // bits9-0 (imm[10:1])
            };
            imm_o = {{11{combined_imm[19]}}, combined_imm, 1'b0};
        end

        // SYSTEM 指令 (含 CSR)
        7'b1110011:  // SYSTEM
        begin
            // CSR 指令的立即数是 zimm[4:0] (零扩展)
            // 对于 ECALL/EBREAK 等，立即数为 0
            if (instr_i[14:12] != 3'b000) begin
                // CSR 指令: zimm[4:0] 取自 rs1 字段
                imm_o = {27'b0, instr_i[19:15]};
            end else begin
                imm_o = 32'b0;
            end
        end

        default:
        begin
            imm_o = 32'b0;
        end
    endcase
end

endmodule
