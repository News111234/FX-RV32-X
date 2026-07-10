// rtl/id/id_top.v (多Bank影子寄存器版本)
`timescale 1ns/1ps
// ============================================================================
// 模块: id_top
// 功能: 译码阶段顶层模块，集成寄存器堆、立即数生成、解码和控制单元
// 描述:
//   1. 接收IF/ID寄存器的指令和PC
//   2. 调用decoder和ctrl进行指令译码，生成所有控制信号
//   3. 调用imm_gen生成立即数
//   4. 访问寄存器堆，读取rs1和rs2的值
//   5. 接收来自WB阶段的写回数据(前递)，用于解决RAW冒险
//   6. 将所有译码结果和控制信号输出到ID/EX寄存器
//   7. 转发多Bank影子寄存器控制信号到regfile

// ============================================================================
module id_top #(
    parameter SHADOW_EN    = 1,     // 影子寄存器使能: 1=开启, 0=关闭
    parameter SHADOW_BANKS = 4      // 影子Bank数量 (默认4)
) (
    // ========== 系统接口 ==========
    input  wire        clk,           // 时钟信号
    input  wire        rst_n,         // 复位信号 (低电平有效)

    // ========== 来自IF/ID寄存器的输入 ==========
    input  wire [31:0] instr,         // 指令
    input  wire [31:0] pc,            // 当前PC值

    // ========== 来自WB阶段的写回数据 (前递) ==========
    input  wire        wb_we_i,       // WB阶段寄存器写使能
    input  wire [4:0]  wb_rd_addr_i,  // WB阶段目标寄存器地址
    input  wire [31:0] wb_rd_data_i,  // WB阶段写回数据

    // ========== 多Bank影子寄存器控制 ==========
    input  wire [3:0]  bank_ptr_i,        // 当前Bank指针
    input  wire        shadow_save_i,     // 保存x1-x31到影子寄存器
    input  wire        shadow_restore_i,  // 从影子寄存器恢复x1-x31

    // ========== 输出到ID/EX寄存器 ==========
    output wire [31:0] rs1_data_o,    // rs1寄存器值
    output wire [31:0] rs2_data_o,    // rs2寄存器值
    output wire [31:0] imm_o,         // 立即数
    output wire [4:0]  rs1_addr_o,    // rs1地址
    output wire [4:0]  rs2_addr_o,    // rs2地址
    output wire [4:0]  rd_addr_o,     // 目标寄存器地址
    output wire [3:0]  alu_op_o,      // ALU操作码
    output wire        alu_src_o,     // ALU源操作数2选择
    output wire        mem_we_o,      // 内存写使能
    output wire        mem_re_o,      // 内存读使能
    output wire [1:0]  wb_sel_o,      // 写回选择
    output wire        reg_we_o,      // 寄存器写使能
    output wire        branch_o,      // 分支指令标志
    output wire        jump_o,        // 跳转指令标志
    output wire [2:0]  funct3_o,      // funct3字段
    output wire [2:0]  mem_width_o,   // 内存访问宽度
    output wire [6:0]  opcode_o,      // 操作码

    // ========== CSR相关输出 ==========
    output wire        csr_inst_o,    // CSR指令标志
    output wire [11:0] csr_addr_o,    // CSR地址
    output wire [2:0]  csr_op_o,      // CSR操作类型
    output wire [4:0]  csr_zimm_o,    // CSR立即数

    // ========== MRET输出 ==========
    output wire        mret_o         // MRET

);


wire [4:0]  rs1_addr;
wire [4:0]  rs2_addr;
wire [4:0]  rd_addr;
wire [31:0] imm;
wire [6:0]  opcode;
wire [2:0]  funct3;
wire [6:0]  funct7;
wire        branch;
wire        jump;

// CSR相关内部信号
wire        csr_inst;
wire [11:0] csr_addr;
wire [2:0]  csr_op;
wire [4:0]  csr_zimm;

// 内部信号
wire mret;
decoder u_decoder (
    .instr_i   (instr),
    .opcode_o  (opcode),
    .rd_addr_o (rd_addr),
    .funct3_o  (funct3),
    .rs1_addr_o(rs1_addr),
    .rs2_addr_o(rs2_addr),
    .funct7_o  (funct7),
    .alu_op_o  (alu_op_o),
    .alu_src_o (alu_src_o),
    .mem_we_o  (mem_we_o),
    .mem_re_o  (mem_re_o),
    .wb_sel_o  (wb_sel_o),
    .reg_we_o  (reg_we_o),

    // CSR输出
    .csr_inst_o(csr_inst),
    .csr_addr_o(csr_addr),
    .csr_op_o  (csr_op),
    .csr_zimm_o(csr_zimm),
    .mret_o    (mret)
);

imm_gen u_imm_gen (
    .instr_i (instr),
    .imm_o   (imm)
);

regfile #(
    .SHADOW_EN   (SHADOW_EN),
    .SHADOW_BANKS(SHADOW_BANKS)
) u_regfile (
    .clk              (clk),
    .rst_n            (rst_n),
    .raddr1_i         (rs1_addr),
    .raddr2_i         (rs2_addr),
    .rdata1_o         (rs1_data_o),
    .rdata2_o         (rs2_data_o),
    .we_i             (wb_we_i),
    .waddr_i          (wb_rd_addr_i),
    .wdata_i          (wb_rd_data_i),

    // 多Bank影子寄存器控制
    .bank_ptr_i       (bank_ptr_i),
    .shadow_save_i    (shadow_save_i),
    .shadow_restore_i (shadow_restore_i)
);

ctrl u_ctrl (
    .opcode_i     (opcode),
    .funct3_i     (funct3),
    .funct7_i     (funct7),
    .instr_i      (instr),
    .branch_o     (branch),
    .jump_o       (jump)
);

// 输出赋值
assign imm_o       = imm;
assign rs1_addr_o  = rs1_addr;
assign rs2_addr_o  = rs2_addr;
assign rd_addr_o   = rd_addr;
assign branch_o    = branch;

assign jump_o = jump;  // 注意：jump_o 现在来自 ctrl，包含了 MRET

assign funct3_o    = funct3;
assign opcode_o    = opcode;
assign mem_width_o = (opcode == 7'b0000011 || opcode == 7'b0100011) ? funct3 : 3'b010;

// CSR输出赋值
assign csr_inst_o  = csr_inst;
assign csr_addr_o  = csr_addr;
assign csr_op_o    = csr_op;
assign csr_zimm_o  = csr_zimm;

// MRET
assign mret_o = mret;
endmodule
