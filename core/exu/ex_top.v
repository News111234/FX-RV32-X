// core/exu/ex_top.v — 执行阶段顶层模块
`timescale 1ns/1ps

// ============================================================================
// 模块: ex_top
// 功能: 执行阶段顶层模块，集成ALU、分支单元、跳转逻辑和转发数据选择
// 描述:
//   本模块是流水线执行阶段的核心，功能包括:
//   1. 接收来自ID/EX流水线寄存器的指令信息和操作数
//   2. 根据转发控制信号(forwardA_i / forwardB_i)选择正确的操作数
//   3. 调用ALU执行算术/逻辑运算
//   4. 调用分支单元判断分支是否跳转
//   5. 处理JAL / JALR / MRET跳转，计算跳转目标地址
//   6. 根据wb_sel_i选择最终结果(ALU结果 / 内存数据 / PC+4 / CSR结果)
//   7. 生成内存访问所需的地址、写数据和宽度控制信号
//
//   转发数据选择:
//     forwardA/forwardB = 00: 使用ID/EX寄存器中的原始操作数
//     forwardA/forwardB = 01: 使用EX/MEM阶段的转发数据
//     forwardA/forwardB = 10: 使用MEM/WB阶段的转发数据
//
//   跳转类型:
//     JAL:   jump_target = pc + imm
//     JALR:  jump_target = (rs1 + imm) & 0xFFFFFFFE
//     MRET:  jump_target = csr_mepc
// ============================================================================
module ex_top (
    // ========== 系统接口 ==========
    input  wire        clk_i,              // 时钟信号
    input  wire        rst_n_i,            // 复位信号 (低电平有效)

    // ========== 来自ID/EX流水线寄存器的数据 ==========
    input  wire [31:0] rs1_data_i,         // rs1 原始数据
    input  wire [31:0] rs2_data_i,         // rs2 原始数据
    input  wire [31:0] imm_i,              // 立即数
    input  wire [31:0] pc_i,               // 当前指令PC

    // ========== 控制信号 ==========
    input  wire [1:0]  wb_sel_i,           // 写回选择: 00=ALU, 01=MEM, 10=PC+4, 11=CSR
    input  wire        reg_we_i,           // 寄存器写使能
    input  wire [4:0]  rd_addr_i,          // 目标寄存器地址
    input  wire [3:0]  alu_op_i,           // ALU操作码
    input  wire        alu_src_i,          // ALU操作数2选择: 0=rs2, 1=imm
    input  wire        branch_i,           // 分支指令标志
    input  wire        jump_i,             // 跳转指令标志 (JAL / JALR)
    input  wire [2:0]  funct3_i,           // funct3字段 (分支条件判断用)
    input  wire        mem_we_i,           // 内存写使能
    input  wire        mem_re_i,           // 内存读使能
    input  wire [2:0]  mem_width_i,        // 内存访问宽度
    input  wire [6:0]  opcode_i,           // 指令opcode (用于区分JAL / JALR)

    // ========== 转发数据输入 ==========
    input  wire [31:0] ex_forward_data_i,  // 来自EX/MEM阶段的转发数据
    input  wire [31:0] mem_forward_data_i, // 来自MEM/WB阶段的转发数据
    input  wire [1:0]  forwardA_i,         // 操作数1转发选择: 00=原始, 01=EX/MEM, 10=MEM/WB
    input  wire [1:0]  forwardB_i,         // 操作数2转发选择: 00=原始, 01=EX/MEM, 10=MEM/WB

    // ========== CSR与中断相关 ==========
    input  wire [31:0] csr_result_i,       // CSR指令执行结果
    input  wire [31:0] csr_mepc_i,         // mepc寄存器值 (MRET返回地址)
    input  wire        mret_i,             // MRET指令标志

    // ========== 送入EX/MEM流水线寄存器的输出 ==========
    output wire [31:0] alu_result_o,       // ALU运算结果
    output wire [31:0] mem_addr_o,         // 内存访问地址 (= alu_result)
    output wire [31:0] mem_wdata_o,        // 内存写数据
    output wire        mem_we_o,           // 内存写使能
    output wire        mem_re_o,           // 内存读使能
    output wire [2:0]  mem_width_o,        // 内存访问宽度

    // ========== 分支/跳转输出 ==========
    output wire        branch_taken_o,     // 分支是否跳转
    output wire [31:0] branch_target_o,    // 分支目标地址
    output wire        jump_taken_o,       // 跳转是否发生 (JAL / JALR / MRET)
    output wire [31:0] jump_target_o,      // 跳转目标地址

    // ========== 流水线控制透传 ==========
    output wire [31:0] pc_plus4_o,         // PC+4 (JAL返回地址)
    output wire [1:0]  wb_sel_o,           // 写回选择 (透传)
    output wire        reg_we_o,           // 寄存器写使能 (透传)
    output wire [4:0]  rd_addr_o,          // 目标寄存器地址 (透传)

    // ========== 调试输出 ==========
    output wire [31:0] op1_selected_o,     // 调试: 经转发选择后的操作数1
    output wire [31:0] op2_selected_o,     // 调试: 经转发选择后的操作数2
    output wire [31:0] ex_csr_result_o     // 调试: CSR结果
);

// ============================================================================
// 1. 转发数据选择 — 根据 forwardA / forwardB 选择正确的操作数
//    00: 使用ID/EX寄存器中的原始值 (无数据依赖)
//    01: 使用EX/MEM阶段的转发数据 (上一条指令的ALU结果)
//    10: 使用MEM/WB阶段的转发数据 (上上条指令的结果)
// ============================================================================
wire [31:0] op1_selected;
wire [31:0] op2_selected;

assign op1_selected = (forwardA_i == 2'b01) ? ex_forward_data_i :
                      (forwardA_i == 2'b10) ? mem_forward_data_i :
                      rs1_data_i;

assign op2_selected = (forwardB_i == 2'b01) ? ex_forward_data_i :
                      (forwardB_i == 2'b10) ? mem_forward_data_i :
                      rs2_data_i;

assign op1_selected_o = op1_selected;
assign op2_selected_o = op2_selected;

// ============================================================================
// 2. ALU 操作数准备
//    LUI:   op1=0, op2=imm (结果 = imm)
//    AUIPC: op1=pc, op2=imm (结果 = pc + imm)
//    其他:  op1=转发后rs1, op2=转发后rs2或imm
// ============================================================================
// LUI/AUIPC 检测 (在EX阶段根据opcode判断)
wire is_lui_ex   = (opcode_i == 7'b0110111);
wire is_auipc_ex = (opcode_i == 7'b0010111);

wire [31:0] alu_op1 = is_lui_ex   ? 32'b0 :
                       is_auipc_ex ? pc_i :
                       op1_selected;
wire [31:0] alu_op2 = alu_src_i ? imm_i : op2_selected;

// ============================================================================
// 3. ALU 实例化 — 执行算术/逻辑/移位/比较运算
// ============================================================================
wire [31:0] alu_result;
wire        alu_zero;

alu u_alu (
    .op1_i     (alu_op1),
    .op2_i     (alu_op2),
    .alu_op_i  (alu_op_i),
    .funct3_i  (funct3_i),
    .result_o  (alu_result),
    .zero_o    (alu_zero)
);

// ============================================================================
// 4. 分支单元 — 判断条件分支是否跳转, 计算分支目标地址
// ============================================================================
branch u_branch (
    .rs1_data_i      (op1_selected),
    .rs2_data_i      (op2_selected),
    .pc_i            (pc_i),
    .imm_i           (imm_i),
    .funct3_i        (funct3_i),
    .branch_i        (branch_i),
    .alu_zero_i      (alu_zero),
    .branch_taken_o  (branch_taken_o),
    .branch_target_o (branch_target_o)
);

// ============================================================================
// 5. 跳转逻辑 — JAL / JALR / MRET
//    JAL:  目标 = PC + 立即数
//    JALR: 目标 = (rs1 + 立即数) & 0xFFFFFFFE (最低位清零, 对齐到半字)
//    MRET: 目标 = mepc (从中断/异常返回)
// ============================================================================
wire jump_taken = jump_i || mret_i;   // MRET也产生跳转

wire [31:0] jal_target  = pc_i + imm_i;
wire [31:0] jalr_target = (op1_selected + imm_i) & 32'hfffffffe;

wire [31:0] jump_target = mret_i ? csr_mepc_i :
                          (opcode_i == 7'b1101111) ? jal_target :   // JAL
                          (opcode_i == 7'b1100111) ? jalr_target :  // JALR
                          32'b0;

assign jump_taken_o  = jump_taken;
assign jump_target_o = jump_target;

// ============================================================================
// 6. 输出到 EX/MEM 流水线寄存器
// ============================================================================
assign alu_result_o = alu_result;
assign mem_addr_o   = alu_result;         // 访存地址即ALU结果
assign mem_wdata_o  = (mem_width_i == 3'b000) ? {24'b0, op2_selected[7:0]}  :   // SB
                      (mem_width_i == 3'b001) ? {16'b0, op2_selected[15:0]} :   // SH
                      op2_selected;                                             // SW

assign mem_we_o    = mem_we_i;
assign mem_re_o    = mem_re_i;
assign pc_plus4_o  = pc_i + 32'h4;
assign mem_width_o = mem_width_i;

// 控制信号透传 (WB阶段使用)
assign wb_sel_o  = wb_sel_i;
assign reg_we_o  = reg_we_i;
assign rd_addr_o = rd_addr_i;

// CSR 结果透传
assign ex_csr_result_o = csr_result_i;

endmodule
