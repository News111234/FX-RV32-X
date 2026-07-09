// core/id/decoder.v — 指令解码器 (支持 RV32I)
`timescale 1ns/1ps

// ============================================================================
// 模块: decoder
// 功能: 指令解码器，提取指令字段并生成 ALU 操作码和次级控制信号
// 描述:
//   本模块从 32 位指令中提取 opcode、rd、funct3、rs1、rs2、funct7 等字段。
//   根据指令类型 (R-type, I-type 等) 和 funct 字段，生成 ALU 操作码 (alu_op_o)。
//   支持 RV32I 扩展 (算术/逻辑) 指令。
//   同时提取 CSR 指令相关字段 (csr_addr, csr_op, csr_zimm) 和 MRET 标志。
// ============================================================================
module decoder (
    // ========== 输入端口 ==========
    input  wire [31:0] instr_i,         // 32 位指令

    // ========== 指令字段输出 ==========
    output wire [6:0]  opcode_o,        // 操作码
    output wire [4:0]  rd_addr_o,       // 目标寄存器地址
    output wire [2:0]  funct3_o,        // funct3 字段
    output wire [4:0]  rs1_addr_o,      // 源寄存器 1 地址
    output wire [4:0]  rs2_addr_o,      // 源寄存器 2 地址
    output wire [6:0]  funct7_o,        // funct7 字段

    // ========== ALU 和控制信号输出 ==========
    output wire [3:0]  alu_op_o,        // ALU 操作码 (4 位)
    output wire        alu_src_o,       // ALU 源操作数 2 选择
    output wire        mem_we_o,        // 内存写使能
    output wire        mem_re_o,        // 内存读使能
    output wire [1:0]  wb_sel_o,        // 写回选择信号 (00: ALU, 01: 内存, 10: PC+4, 11: CSR)
    output wire        reg_we_o,        // 寄存器写使能

    // ========== MRET ==========
    output wire        mret_o,          // MRET 指令标志

    // ========== CSR ==========
    output wire        csr_inst_o,      // CSR 指令标志
    output wire [11:0] csr_addr_o,      // CSR 地址 (12 位)
    output wire [2:0]  csr_op_o,        // CSR 操作类型 (funct3)
    output wire [4:0]  csr_zimm_o       // CSR 立即数 (取自 rs1 字段)
);

// ========== 第一部分: 提取指令字段 ==========
assign opcode_o   = instr_i[6:0];
assign rd_addr_o  = instr_i[11:7];
assign funct3_o   = instr_i[14:12];
assign rs1_addr_o = instr_i[19:15];
assign rs2_addr_o = instr_i[24:20];
assign funct7_o   = instr_i[31:25];

// ========== MRET 指令识别 ==========
// MRET: opcode=SYSTEM(1110011), funct3=0, funct12=0x302
wire is_mret = (opcode_o == 7'b1110011) &&
               (funct3_o == 3'b000) &&
               (instr_i[31:20] == 12'h302);

assign mret_o = is_mret;

// ========== CSR 指令识别 ==========
wire is_csr = (opcode_o == 7'b1110011);
wire is_csr_inst = is_csr && (funct3_o != 3'b000) && !is_mret;

assign csr_addr_o = instr_i[31:20];
assign csr_op_o   = funct3_o;
assign csr_zimm_o = rs1_addr_o;

// ========== 指令类型识别 ==========
wire is_r_type = (opcode_o == 7'b0110011);
wire is_i_type = (opcode_o == 7'b0010011);
wire is_load   = (opcode_o == 7'b0000011);
wire is_store  = (opcode_o == 7'b0100011);
wire is_branch = (opcode_o == 7'b1100011);
wire is_jal    = (opcode_o == 7'b1101111);
wire is_jalr   = (opcode_o == 7'b1100111);
wire is_lui    = (opcode_o == 7'b0110111);
wire is_auipc  = (opcode_o == 7'b0010111);
wire is_system = (opcode_o == 7'b1110011);

// ========== ALU 操作码生成 (支持 RV32I) ==========
reg [3:0] alu_op;
always @(*) begin
    case (opcode_o)
        7'b0110011: begin // R-type (含 I 扩展运算指令)
            case (funct3_o)
                3'b000: alu_op = (funct7_o[5] ? 4'b0001 : 4'b0000); // SUB / ADD
                3'b001: alu_op = 4'b0010; // SLL
                3'b010: alu_op = 4'b0011; // SLT
                3'b011: alu_op = 4'b0100; // SLTU
                3'b100: alu_op = 4'b0101; // XOR
                3'b101: alu_op = (funct7_o[5] ? 4'b0111 : 4'b0110); // SRA / SRL
                3'b110: alu_op = 4'b0110; // OR
                3'b111: alu_op = 4'b0111; // AND
                default: alu_op = 4'b0000;
            endcase
        end

        7'b0010011: begin // I-type 运算指令
            case (funct3_o)
                3'b000: alu_op = 4'b0000; // ADDI
                3'b010: alu_op = 4'b0011; // SLTI
                3'b011: alu_op = 4'b0100; // SLTIU
                3'b100: alu_op = 4'b0101; // XORI
                3'b110: alu_op = 4'b0110; // ORI
                3'b111: alu_op = 4'b0111; // ANDI
                3'b001: alu_op = 4'b0010; // SLLI
                3'b101: alu_op = (funct7_o[5] ? 4'b0111 : 4'b0110); // SRAI / SRLI
                default: alu_op = 4'b0000;
            endcase
        end

        7'b1100011: alu_op = 4'b0001; // BRANCH (需要比较)
        default:     alu_op = 4'b0000;
    endcase
end

assign alu_op_o = alu_op;

// ========== 控制信号生成 ==========
assign alu_src_o = is_i_type || is_load || is_store || is_lui || is_auipc;
//alu_src_=0则说明操作数来源于RS2寄存器，=1则来自于立即数
assign mem_we_o  = is_store;
assign mem_re_o  = is_load;

// wb_sel 是一个 2 位控制信号，在 WB 阶段从 4 种可能的数据来源中选择写入 rd 的值:
//   00: ALU 运算结果
//   01: 内存读取数据
//   10: PC+4 (JAL, JALR 指令保存返回地址)
//   11: CSR 指令写回值
reg [1:0] wb_sel;
always @(*) begin
    case (opcode_o)
        7'b0000011: wb_sel = 2'b01; // LOAD
        7'b1101111: wb_sel = 2'b10; // JAL
        7'b1100111: wb_sel = 2'b10; // JALR
        7'b1110011: begin            // SYSTEM
            if (is_csr_inst)
                wb_sel = 2'b11;      // CSR 写回
            else
                wb_sel = 2'b00;      // 其他 SYSTEM 指令不写回
        end
        default:    wb_sel = 2'b00;  // 默认: ALU 结果
    endcase
end

assign wb_sel_o = wb_sel;

assign reg_we_o = is_r_type || is_i_type || is_load ||
                  is_jal || is_jalr || is_lui || is_auipc ||
                  is_csr_inst;

assign csr_inst_o = is_csr_inst;

endmodule
