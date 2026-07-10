// core/csr/csr_instructions.v — CSR 指令执行单元
`timescale 1ns/1ps

// ============================================================================
// 模块: csr_instructions
// 功能: CSR 指令处理单元
// 描述:
//   本模块接收 CSR 指令信息，生成对 CSR 寄存器文件的写使能和写数据，
//   并输出 CSR 指令的读回值。支持全部 6 种 CSR 操作:
//     CSRRW  — 原子读/写 CSR
//     CSRRS  — 原子读并置位 CSR
//     CSRRC  — 原子读并清零 CSR
//     CSRRWI — 原子读/写 CSR (立即数)
//     CSRRSI — 原子读并置位 CSR (立即数)
//     CSRRCI — 原子读并清零 CSR (立即数)
// ============================================================================
module csr_instructions (
    // ========== 系统接口 ==========
    input  wire        clk_i,              // 时钟信号
    input  wire        rst_n_i,            // 复位信号 (低电平有效)

    // ========== 来自 ID 阶段的 CSR 指令信息 ==========
    input  wire        csr_inst_valid_i,   // CSR 指令有效标志
    input  wire [2:0]  csr_op_i,           // CSR 操作类型
    input  wire [11:0] csr_addr_i,         // CSR 地址
    input  wire [4:0]  rs1_addr_i,         // rs1 寄存器地址
    input  wire [31:0] rs1_data_i,         // rs1 寄存器的值
    input  wire [31:0] imm_i,              // 立即数

    // ========== 来自 CSR 寄存器文件的读取数据 ==========
    input  wire [31:0] csr_rdata_i,        // 当前读取的 CSR 值

    // ========== 对 CSR 寄存器文件的写操作 ==========
    output reg         csr_we_o,           // CSR 写使能
    output reg  [11:0] csr_waddr_o,        // CSR 写地址
    output reg  [31:0] csr_wdata_o,        // CSR 写数据

    // ========== 送到 EX 阶段的结果 ==========
    output reg  [31:0] csr_result_o        // CSR 指令的结果 (读回的旧值)

);

// ========== CSR 操作类型定义 ==========
// RISC-V 特权规范中的 CSR 指令类型
localparam CSR_OP_NONE = 3'b000;  // 非 CSR 指令 (ECALL / EBREAK)
localparam CSR_OP_RW   = 3'b001;  // CSRRW  - 原子读/写 CSR
localparam CSR_OP_RS   = 3'b010;  // CSRRS  - 原子读并置位 CSR
localparam CSR_OP_RC   = 3'b011;  // CSRRC  - 原子读并清零 CSR
localparam CSR_OP_RWI  = 3'b101;  // CSRRWI - 原子读/写 CSR (立即数)
localparam CSR_OP_RSI  = 3'b110;  // CSRRSI - 原子读并置位 CSR (立即数)
localparam CSR_OP_RCI  = 3'b111;  // CSRRCI - 原子读并清零 CSR (立即数)

// ========== 立即数提取 ==========
// 对于 CSR 立即数版本指令，zimm[4:0] 取自 rs1 字段或 imm 的低 5 位
wire [4:0] zimm = rs1_addr_i;  // 取自 rs1 字段，用于 CSRRWI/CSRRSI/CSRRCI

// 判断是否为立即数版本的 CSR 指令
wire is_imm_csr = csr_op_i[2];  // 操作码高位为 1 表示立即数版本

// ========== CSR 写数据计算 ==========
reg [31:0] csr_write_val;
reg        do_csr_write;

always @(*) begin
    csr_write_val = 32'b0;
    do_csr_write  = 1'b0;

    if (csr_inst_valid_i) begin
        case (csr_op_i)
            // CSRRW: csr = x[rs1]
            CSR_OP_RW: begin
                do_csr_write  = (rs1_addr_i != 5'b0);  // rs1=x0 时不写
                csr_write_val = rs1_data_i;
            end

            // CSRRS: csr = csr | x[rs1]
            CSR_OP_RS: begin
                do_csr_write  = (rs1_addr_i != 5'b0);
                csr_write_val = csr_rdata_i | rs1_data_i;
            end

            // CSRRC: csr = csr & ~x[rs1]
            CSR_OP_RC: begin
                do_csr_write  = (rs1_addr_i != 5'b0);
                csr_write_val = csr_rdata_i & (~rs1_data_i);
            end

            // CSRRWI: csr = zimm
            CSR_OP_RWI: begin
                do_csr_write  = (zimm != 5'b0);  // zimm=0 时不写
                csr_write_val = {27'b0, zimm};
            end

            // CSRRSI: csr = csr | zimm
            CSR_OP_RSI: begin
                do_csr_write  = (zimm != 5'b0);
                csr_write_val = csr_rdata_i | {27'b0, zimm};
            end

            // CSRRCI: csr = csr & ~zimm
            CSR_OP_RCI: begin
                do_csr_write  = (zimm != 5'b0);
                csr_write_val = csr_rdata_i & (~{27'b0, zimm});
            end

            default: begin
                do_csr_write  = 1'b0;
                csr_write_val = 32'b0;
            end
        endcase
    end
end

// ========== CSR 写操作输出 ==========
always @(*) begin
    csr_we_o    = do_csr_write;
    csr_waddr_o = csr_addr_i;
    csr_wdata_o = csr_write_val;
end

// ========== CSR 指令结果 ==========
// CSR 指令的结果始终是 CSR 的旧值 (读回值)
always @(*) begin
    csr_result_o = csr_rdata_i;
end

endmodule
