// rtl/core/core_top.v - RISC-V CPU核心 (多Bank影子寄存器版本)
`timescale 1ns/1ps

module core_top #(
    parameter SYNC_INST_MEM   = 1,   // 1=BRAM(sync read), 0=ROM(combinational read)
    parameter SHADOW_BANKS    = 4,   // 影子Bank数量 (默认4, 支持3级嵌套)
    parameter OVERFLOW_POLICY = 0    // Bank溢出策略: 0=硬限制, 1=降级复用
) (
    // ========== 系统接口 ==========
    input  wire        clk_i,
    input  wire        rst_n_i,

    // ========== 指令取指接口 ==========
    output wire [31:0] if_pc_o,          // 取指地址（输出到指令 ROM）
    input  wire [31:0] if_instr_i,       // 指令数据（从指令 ROM 输入）

    // ========== 总线访存接口 ==========
    output wire        bus_re_o,
    output wire        bus_we_o,
    output wire [31:0] bus_addr_o,
    output wire [31:0] bus_wdata_o,
    output wire [2:0]  bus_width_o,
    input  wire [31:0] bus_rdata_i,
    input  wire        bus_ready_i,

    // ========== 中断接口 ==========
    input  wire        intr_timer_i,
    input  wire        intr_software_i,
    input  wire        intr_external_i,
    input  wire        intr_spi_i,
    input  wire        intr_i2c_i


);

// ==========================================================================
// 参数定义
// ==========================================================================
// 多Bank影子寄存器配置 (可通过顶层parameter覆盖)
// SHADOW_EN=1 且 SHADOW_BANKS>=1 时启用多Bank功能

// ==========================================================================
// 内部信号定义——各级流水线信号、控制信号、转发信号等
// ==========================================================================

// IFU
wire [31:0] if_pc;
wire [31:0] if_pc_current;     // 当前取指PC (用于BRAM地址, 无延迟)
wire [31:0] pc_plus4;
wire [31:0] if_id_pc;
wire [31:0] if_id_instr;

// ID
wire [31:0] id_rs1_data;
wire [31:0] id_rs2_data;
wire [31:0] id_imm;
wire [4:0]  id_rs1_addr;
wire [4:0]  id_rs2_addr;
wire [4:0]  id_rd_addr;
wire [3:0]  id_alu_op;
wire        id_alu_src;
wire        id_mem_we;
wire        id_mem_re;
wire [1:0]  id_wb_sel;
wire        id_reg_we;
wire        id_branch;
wire        id_jump;
wire [2:0]  id_funct3;
wire [2:0]  id_mem_width;
wire [6:0]  id_opcode;
wire        id_csr_inst;
wire [11:0] id_csr_addr;
wire [2:0]  id_csr_op;
wire [4:0]  id_csr_zimm;
wire        id_mret;

// ID/EX
wire [31:0] id_ex_pc;
wire [31:0] id_ex_rs1_data;
wire [31:0] id_ex_rs2_data;
wire [31:0] id_ex_imm;
wire [4:0]  id_ex_rs1_addr;
wire [4:0]  id_ex_rs2_addr;
wire [4:0]  id_ex_rd_addr;
wire [3:0]  id_ex_alu_op;
wire        id_ex_alu_src;
wire        id_ex_mem_we;
wire        id_ex_mem_re;
wire [1:0]  id_ex_wb_sel;
wire        id_ex_reg_we;
wire        id_ex_branch;
wire        id_ex_jump;
wire [2:0]  id_ex_funct3;
wire [2:0]  id_ex_mem_width;
wire [6:0]  id_ex_opcode;
wire        id_ex_mret;
wire        id_ex_csr_inst;
wire [11:0] id_ex_csr_addr;
wire [2:0]  id_ex_csr_op;
wire [4:0]  id_ex_csr_zimm;

// EX
wire [31:0] ex_alu_result;
wire [31:0] ex_mem_addr;
wire [31:0] ex_mem_wdata;
wire        ex_mem_we;
wire        ex_mem_re;
wire [2:0]  ex_mem_width;
wire        ex_branch_taken;
wire        ex_jump_taken;
wire [31:0] ex_branch_target;
wire [31:0] ex_jump_target;
wire [31:0] ex_pc_plus4;
wire [1:0]  ex_wb_sel;
wire        ex_reg_we;
wire [4:0]  ex_rd_addr;
wire [31:0] op1_selected;
wire [31:0] op2_selected;
wire [31:0] ex_csr_result;
wire [31:0] forward_mem_data;

// EX/MEM
wire [31:0] ex_mem_alu_result;
wire [31:0] ex_mem_mem_addr;
wire [31:0] ex_mem_mem_wdata;
wire        ex_mem_mem_we;
wire        ex_mem_mem_re;
wire [2:0]  ex_mem_mem_width;
wire [31:0] ex_mem_pc_plus4;
wire [4:0]  ex_mem_rd_addr;
wire [1:0]  ex_mem_wb_sel;
wire        ex_mem_reg_we;
wire [31:0] ex_mem_csr_result;
wire [4:0]  ex_mem_rd_addr_for_hazard;
wire        ex_mem_reg_we_for_hazard;
wire        ex_mem_mem_re_for_hazard;

wire [31:0] ex_forward_muxed;

// MEM
wire [31:0] mem_alu_result;
wire [31:0] mem_mem_rdata;
wire [31:0] mem_pc_plus4;
wire [4:0]  mem_rd_addr;
wire [1:0]  mem_wb_sel;
wire        mem_reg_we;
wire [31:0] mem_csr_result;

// MEM/WB
wire [31:0] wb_alu_result;
wire [31:0] wb_mem_rdata;
wire [31:0] wb_pc_plus4;
wire [4:0]  wb_rd_addr;
wire [1:0]  wb_wb_sel;
wire        wb_reg_we;
wire [31:0] wb_csr_result;
wire        mem_wb_mem_re;
wire [31:0] wb_data;
wire        wb_reg_we_out;
wire [4:0]  wb_rd_addr_out;

// 总线接口 (core 内部)
wire        mem_bus_re;
wire        mem_bus_we;
wire [31:0] mem_bus_addr;
wire [31:0] mem_bus_wdata;
wire [2:0]  mem_bus_width;
wire [31:0] mem_bus_rdata;
wire        mem_bus_ready;

// 冒险与转发
wire [1:0]  forwardA;
wire [1:0]  forwardB;
wire        stall_if;
wire        stall_id;
wire        flush_if;
wire        flush_id;
wire        stall_ex;
wire        stall_mem;
wire        stall_wb;
wire        flush_ex;
wire        flush_mem;
wire        flush_wb;

// 中断相关 (内部)
wire [31:0] csr_rdata;
wire [31:0] mtvec;
wire [31:0] mepc;
wire [31:0] mcause;
wire [31:0] mie;
wire [31:0] mstatus;
wire [31:0] mip;
wire        csr_inst_valid;
wire [2:0]  csr_op;
wire [11:0] csr_addr;
wire [4:0]  csr_rs1_addr;
wire [31:0] csr_rs1_data;
wire [31:0] csr_imm;
wire [31:0] csr_inst_result;
wire        csr_inst_we;
wire [11:0] csr_inst_waddr;
wire [31:0] csr_inst_wdata;
wire [31:0] csr_result;
wire        intr_pending;
wire [31:0] intr_cause;
wire [31:0] intr_handler_addr;
wire        pipe_csr_mepc_we;
wire [31:0] pipe_csr_mepc_data;
wire        pipe_csr_mcause_we;
wire [31:0] pipe_csr_mcause_data;
wire        pipe_csr_mstatus_we;
wire [31:0] pipe_csr_mstatus_data;
wire        interrupt_taken_pipe;
wire        interrupt_flush_pipe;
wire [31:0] interrupt_pc_pipe;
wire        intr_take_now;
wire        intr_flush_id;
wire        intr_flush_ex;
wire        intr_flush_mem;
wire        intr_flush_wb;

// 多Bank影子寄存器控制
wire [3:0]  bank_ptr;               // 当前Bank指针 (从interrupt_pipeline输出)
wire        shadow_save;            // 影子保存脉冲 (从interrupt_pipeline输出)
wire        shadow_restore;         // 影子恢复脉冲 (从interrupt_pipeline输出)

// Bank Controller 组合逻辑决策信号
wire        allow_nesting;          // 允许嵌套分配新Bank
wire        bank_full;              // Bank已满
wire        tail_chain_detect;      // Tail-Chaining检测
wire        degradation_reuse;      // 降级复用模式 (Bank满但允许嵌套)

// 中断流水线到bank_controller
wire        interrupt_accepted_pipe;
wire        interrupt_processing_pipe;  // 正在服务中断标志

// 中断优先级 (从interrupt_controller输出)
wire [3:0]  current_priority;
wire [3:0]  new_priority;

// ==========================================================================
// 实例化各子模块
// ==========================================================================

// ---------- IFU ----------
ifu_top #(
    .SYNC_INST_MEM(SYNC_INST_MEM)
) u_ifu_top (
    .clk              (clk_i),
    .rst_n            (rst_n_i),
    .stall_i          (stall_if),
    .branch_taken_i   (ex_branch_taken),
    .jump_taken_i     (ex_jump_taken),
    .branch_target_i  (ex_branch_target),
    .jump_target_i    (ex_jump_target),
    .interrupt_taken_i(interrupt_taken_pipe),
    .intr_take_now_i   (intr_take_now),
    .intr_target_i     (intr_handler_addr),
    .instr_i          (if_instr_i),
    .pc               (if_pc),
    .pc_current       (if_pc_current),
    .pc_plus4         (pc_plus4)
);
assign if_pc_o = if_pc_current;

// ---------- IF/ID ----------
if_id_reg u_if_id_reg (
    .clk_i           (clk_i),
    .rst_n_i         (rst_n_i),
    .stall_i         (stall_id),
    .flush_i         (flush_id),
    .intr_flush_i    (intr_flush_id),
    .if_pc_i         (if_pc),
    .if_instr_i      (if_instr_i),
    .id_pc_o         (if_id_pc),
    .id_instr_o      (if_id_instr)
);

// ---------- ID (多Bank版本) ----------
id_top #(
    .SHADOW_BANKS(SHADOW_BANKS)
) u_id_top (
    .clk           (clk_i),
    .rst_n         (rst_n_i),
    .instr         (if_id_instr),
    .pc            (if_id_pc),
    .wb_we_i       (wb_reg_we_out),
    .wb_rd_addr_i  (wb_rd_addr_out),
    .wb_rd_data_i  (wb_data),
    .bank_ptr_i       (bank_ptr),
    .shadow_save_i    (shadow_save),
    .shadow_restore_i (shadow_restore),
    .rs1_data_o    (id_rs1_data),
    .rs2_data_o    (id_rs2_data),
    .imm_o         (id_imm),
    .rs1_addr_o    (id_rs1_addr),
    .rs2_addr_o    (id_rs2_addr),
    .rd_addr_o     (id_rd_addr),
    .alu_op_o      (id_alu_op),
    .alu_src_o     (id_alu_src),
    .mem_we_o      (id_mem_we),
    .mem_re_o      (id_mem_re),
    .wb_sel_o      (id_wb_sel),
    .reg_we_o      (id_reg_we),
    .branch_o      (id_branch),
    .jump_o        (id_jump),
    .funct3_o      (id_funct3),
    .opcode_o      (id_opcode),
    .mem_width_o   (id_mem_width),
    .mret_o        (id_mret),
    .csr_inst_o    (id_csr_inst),
    .csr_addr_o    (id_csr_addr),
    .csr_op_o      (id_csr_op),
    .csr_zimm_o    (id_csr_zimm)
);

// ---------- ID/EX ----------
id_ex_reg u_id_ex_reg (
    .clk_i           (clk_i),
    .rst_n_i         (rst_n_i),
    .stall_i         (stall_id),
    .flush_i         (flush_id),
    .intr_flush_i    (intr_flush_ex),
    .id_pc_i         (if_id_pc),
    .id_rs1_data_i   (id_rs1_data),
    .id_rs2_data_i   (id_rs2_data),
    .id_imm_i        (id_imm),
    .id_rs1_addr_i   (id_rs1_addr),
    .id_rs2_addr_i   (id_rs2_addr),
    .id_rd_addr_i    (id_rd_addr),
    .id_alu_op_i     (id_alu_op),
    .id_alu_src_i    (id_alu_src),
    .id_mem_we_i     (id_mem_we),
    .id_mem_re_i     (id_mem_re),
    .id_mem_width_i  (id_mem_width),
    .id_wb_sel_i     (id_wb_sel),
    .id_reg_we_i     (id_reg_we),
    .id_branch_i     (id_branch),
    .id_jump_i       (id_jump),
    .id_funct3_i     (id_funct3),
    .id_opcode_i     (id_opcode),
    .id_csr_inst_i   (id_csr_inst),
    .id_csr_addr_i   (id_csr_addr),
    .id_csr_op_i     (id_csr_op),
    .id_csr_zimm_i   (id_csr_zimm),
    .ex_pc_o         (id_ex_pc),
    .ex_rs1_data_o   (id_ex_rs1_data),
    .ex_rs2_data_o   (id_ex_rs2_data),
    .ex_imm_o        (id_ex_imm),
    .ex_rs1_addr_o   (id_ex_rs1_addr),
    .ex_rs2_addr_o   (id_ex_rs2_addr),
    .ex_rd_addr_o    (id_ex_rd_addr),
    .ex_alu_op_o     (id_ex_alu_op),
    .ex_alu_src_o    (id_ex_alu_src),
    .ex_mem_we_o     (id_ex_mem_we),
    .ex_mem_re_o     (id_ex_mem_re),
    .ex_mem_width_o  (id_ex_mem_width),
    .ex_wb_sel_o     (id_ex_wb_sel),
    .ex_reg_we_o     (id_ex_reg_we),
    .ex_branch_o     (id_ex_branch),
    .ex_jump_o       (id_ex_jump),
    .ex_funct3_o     (id_ex_funct3),
    .ex_opcode_o     (id_ex_opcode),
    .id_mret_i       (id_mret),
    .ex_mret_o       (id_ex_mret),
    .ex_csr_inst_o   (id_ex_csr_inst),
    .ex_csr_addr_o   (id_ex_csr_addr),
    .ex_csr_op_o     (id_ex_csr_op),
    .ex_csr_zimm_o   (id_ex_csr_zimm)
);

// ---------- Hazard ----------
hazard_unit #(
    .SYNC_INST_MEM(SYNC_INST_MEM)
) u_hazard_unit (
    .clk_i            (clk_i),
    .rst_n_i          (rst_n_i),
    .id_rs1_addr_i    (id_rs1_addr),
    .id_rs2_addr_i    (id_rs2_addr),
    .id_ex_rd_addr_i  (id_ex_rd_addr),
    .id_ex_reg_we_i   (id_ex_reg_we),
    .id_ex_mem_re_i   (id_ex_mem_re),
    .ex_mem_rd_addr_i (ex_mem_rd_addr_for_hazard),
    .ex_mem_reg_we_i  (ex_mem_reg_we_for_hazard),
    .ex_mem_mem_re_i  (ex_mem_mem_re_for_hazard),
    .branch_taken_i   (ex_branch_taken),
    .jump_taken_i     (ex_jump_taken),
    .interrupt_taken_i(interrupt_taken_pipe),
    .interrupt_flush_i(interrupt_flush_pipe),
    .stall_if_o       (stall_if),
    .stall_id_o       (stall_id),
    .flush_if_o       (flush_if),
    .flush_id_o       (flush_id),
    .intr_flush_id_o  (intr_flush_id),
    .intr_flush_ex_o  (intr_flush_ex),
    .intr_flush_mem_o (intr_flush_mem),
    .intr_flush_wb_o  (intr_flush_wb)
);

forwarding_unit u_forwarding_unit (
    .id_ex_rs1_addr_i   (id_ex_rs1_addr),
    .id_ex_rs2_addr_i   (id_ex_rs2_addr),
    .ex_mem_rd_addr_i   (ex_mem_rd_addr),
    .ex_mem_reg_we_i    (ex_mem_reg_we),
    .ex_mem_mem_re_i    (ex_mem_mem_re),
    .mem_wb_rd_addr_i   (wb_rd_addr),
    .mem_wb_reg_we_i    (wb_reg_we),
    .stall_i            (stall_id),
    .forwardA_o         (forwardA),
    .forwardB_o         (forwardB)
);

// ---------- EX ----------
ex_top u_ex_top (
    .clk_i              (clk_i),
    .rst_n_i            (rst_n_i),
    .rs1_data_i         (id_ex_rs1_data),
    .rs2_data_i         (id_ex_rs2_data),
    .imm_i              (id_ex_imm),
    .pc_i               (id_ex_pc),
    .wb_sel_i           (id_ex_wb_sel),
    .reg_we_i           (id_ex_reg_we),
    .rd_addr_i          (id_ex_rd_addr),
    .alu_op_i           (id_ex_alu_op),
    .alu_src_i          (id_ex_alu_src),
    .branch_i           (id_ex_branch),
    .jump_i             (id_ex_jump),
    .funct3_i           (id_ex_funct3),
    .mem_we_i           (id_ex_mem_we),
    .mem_re_i           (id_ex_mem_re),
    .mem_width_i        (id_ex_mem_width),
    .ex_forward_data_i  (ex_forward_muxed),
    .mem_forward_data_i (forward_mem_data),
    .forwardA_i         (forwardA),
    .forwardB_i         (forwardB),
    .opcode_i           (id_ex_opcode),
    .csr_result_i       (csr_result),
    .alu_result_o       (ex_alu_result),
    .mem_addr_o         (ex_mem_addr),
    .mem_wdata_o        (ex_mem_wdata),
    .mem_we_o           (ex_mem_we),
    .mem_re_o           (ex_mem_re),
    .branch_taken_o     (ex_branch_taken),
    .branch_target_o    (ex_branch_target),
    .jump_taken_o       (ex_jump_taken),
    .jump_target_o      (ex_jump_target),
    .pc_plus4_o         (ex_pc_plus4),
    .wb_sel_o           (ex_wb_sel),
    .reg_we_o           (ex_reg_we),
    .rd_addr_o          (ex_rd_addr),
    .mem_width_o        (ex_mem_width),
    .op1_selected_o     (op1_selected),
    .op2_selected_o     (op2_selected),
    .ex_csr_result_o    (ex_csr_result),
    .csr_mepc_i         (mepc),
    .mret_i             (id_ex_mret)
);

// ---------- EX/MEM ----------
ex_mem_reg u_ex_mem_reg (
    .clk_i              (clk_i),
    .rst_n_i            (rst_n_i),
    .stall_i            (stall_mem),
    .flush_i            (flush_mem),
    .intr_flush_i       (intr_flush_mem),
    .ex_alu_result_i    (ex_alu_result),
    .ex_mem_addr_i      (ex_mem_addr),
    .ex_mem_wdata_i     (ex_mem_wdata),
    .ex_pc_plus4_i      (ex_pc_plus4),
    .ex_rd_addr_i       (ex_rd_addr),
    .ex_mem_we_i        (ex_mem_we),
    .ex_mem_re_i        (ex_mem_re),
    .ex_mem_width_i     (ex_mem_width),
    .ex_wb_sel_i        (ex_wb_sel),
    .ex_reg_we_i        (ex_reg_we),
    .ex_csr_result_i    (ex_csr_result),
    .mem_alu_result_o   (ex_mem_alu_result),
    .mem_mem_addr_o     (ex_mem_mem_addr),
    .mem_mem_wdata_o    (ex_mem_mem_wdata),
    .mem_pc_plus4_o     (ex_mem_pc_plus4),
    .mem_rd_addr_o      (ex_mem_rd_addr),
    .mem_mem_we_o       (ex_mem_mem_we),
    .mem_mem_re_o       (ex_mem_mem_re),
    .mem_mem_width_o    (ex_mem_mem_width),
    .mem_wb_sel_o       (ex_mem_wb_sel),
    .mem_reg_we_o       (ex_mem_reg_we),
    .mem_csr_result_o   (ex_mem_csr_result)
);

// ---------- MEM ----------
mem_top u_mem_top (
    .clk_i             (clk_i),
    .rst_n_i           (rst_n_i),
    .alu_result_i      (ex_mem_alu_result),
    .wdata_i           (ex_mem_mem_wdata),
    .mem_we_i          (ex_mem_mem_we),
    .mem_re_i          (ex_mem_mem_re),
    .mem_width_i       (ex_mem_mem_width),
    .pc_plus4_i        (ex_mem_pc_plus4),
    .reg_we_i          (ex_mem_reg_we),
    .wb_sel_i          (ex_mem_wb_sel),
    .rd_addr_i         (ex_mem_rd_addr),
    .pc_plus4_o        (mem_pc_plus4),
    .reg_we_o          (mem_reg_we),
    .wb_sel_o          (mem_wb_sel),
    .rd_addr_o         (mem_rd_addr),
    .bus_re_o          (mem_bus_re),
    .bus_we_o          (mem_bus_we),
    .bus_addr_o        (mem_bus_addr),
    .bus_wdata_o       (mem_bus_wdata),
    .bus_width_o       (mem_bus_width),
    .bus_rdata_i       (mem_bus_rdata),
    .bus_ready_i       (mem_bus_ready)
);

// 总线控制: 中断时若load未完成则掐断总线请求
assign bus_re_o    = mem_bus_re && !(interrupt_taken_pipe && !bus_ready_i);
assign bus_we_o    = mem_bus_we;
assign bus_addr_o  = mem_bus_addr;
assign bus_wdata_o = mem_bus_wdata;
assign bus_width_o = mem_bus_width;
assign mem_bus_rdata = bus_rdata_i;
assign mem_bus_ready = bus_ready_i;

// ---------- MEM/WB ----------
mem_wb_reg u_mem_wb_reg (
    .clk_i            (clk_i),
    .rst_n_i          (rst_n_i),
    .stall_i          (stall_wb),
    .flush_i          (flush_wb),
    .intr_flush_i     (intr_flush_wb),
    .mem_alu_result_i (ex_mem_alu_result),
    .mem_mem_rdata_i  (mem_bus_rdata),
    .mem_pc_plus4_i   (mem_pc_plus4),
    .mem_rd_addr_i    (mem_rd_addr),
    .mem_wb_sel_i     (mem_wb_sel),
    .mem_reg_we_i     (mem_reg_we),
    .mem_csr_result_i (ex_mem_csr_result),
    .mem_mem_re_i     (ex_mem_mem_re),
    .wb_mem_re_o      (mem_wb_mem_re),
    .wb_alu_result_o  (wb_alu_result),
    .wb_mem_rdata_o   (wb_mem_rdata),
    .wb_pc_plus4_o    (wb_pc_plus4),
    .wb_rd_addr_o     (wb_rd_addr),
    .wb_wb_sel_o      (wb_wb_sel),
    .wb_reg_we_o      (wb_reg_we),
    .wb_csr_result_o  (wb_csr_result)
);

// ---------- WB ----------
wb_top u_wb_top (
    .clk_i          (clk_i),
    .rst_n_i        (rst_n_i),
    .alu_result_i   (wb_alu_result),
    .mem_rdata_i    (wb_mem_rdata),
    .pc_plus4_i     (wb_pc_plus4),
    .csr_result_i   (wb_csr_result),
    .wb_sel_i       (wb_wb_sel),
    .reg_we_i       (wb_reg_we),
    .rd_addr_i      (wb_rd_addr),
    .wb_data_o      (wb_data),
    .reg_we_o       (wb_reg_we_out),
    .rd_addr_o      (wb_rd_addr_out)
);

// ========== CSR 和中断 ==========

csr_regfile u_csr_regfile (
    .clk_i              (clk_i),
    .rst_n_i            (rst_n_i),
    .csr_addr_i         (id_ex_csr_addr),
    .csr_rdata_o        (csr_rdata),
    .csr_inst_we_i      (csr_inst_we),
    .csr_inst_waddr_i   (csr_inst_waddr),
    .csr_inst_wdata_i   (csr_inst_wdata),
    .csr_mepc_we_i      (pipe_csr_mepc_we),
    .csr_mepc_data_i    (pipe_csr_mepc_data),
    .csr_mcause_we_i    (pipe_csr_mcause_we),
    .csr_mcause_data_i  (pipe_csr_mcause_data),
    .csr_mstatus_we_i   (pipe_csr_mstatus_we),
    .csr_mstatus_data_i (pipe_csr_mstatus_data),
    .intr_software_i    (intr_software_i),
    .intr_timer_i       (intr_timer_i),
    .intr_external_i    (intr_external_i),
    .mtvec_o            (mtvec),
    .mepc_o             (mepc),
    .mcause_o           (mcause),
    .mie_o              (mie),
    .mstatus_o          (mstatus),
    .mip_o              (mip)
);

assign csr_inst_valid = id_ex_csr_inst;
assign csr_op         = id_ex_csr_op;
assign csr_addr       = id_ex_csr_addr;
assign csr_rs1_addr   = id_ex_rs1_addr;
assign csr_rs1_data   = op1_selected;
assign csr_imm        = id_ex_imm;

csr_instructions u_csr_instructions (
    .clk_i              (clk_i),
    .rst_n_i            (rst_n_i),
    .csr_inst_valid_i   (csr_inst_valid),
    .csr_op_i           (csr_op),
    .csr_addr_i         (csr_addr),
    .rs1_addr_i         (csr_rs1_addr),
    .rs1_data_i         (csr_rs1_data),
    .imm_i              (csr_imm),
    .csr_rdata_i        (csr_rdata),
    .csr_we_o           (csr_inst_we),
    .csr_waddr_o        (csr_inst_waddr),
    .csr_wdata_o        (csr_inst_wdata),
    .csr_result_o       (csr_inst_result)
);

interrupt_controller u_interrupt_controller (
    .clk_i              (clk_i),
    .rst_n_i            (rst_n_i),
    .intr_software_i    (intr_software_i),
    .intr_timer_i       (intr_timer_i),
    .intr_external_i    (intr_external_i),
    .mie_i              (mie),
    .mip_i              (mip),
    .mstatus_i          (mstatus),
    .mtvec_i            (mtvec),
    .intr_pending_o     (intr_pending),
    .intr_cause_o       (intr_cause),
    .intr_handler_addr_o(intr_handler_addr),
    .intr_spi_i         (intr_spi_i),
    .intr_i2c_i         (intr_i2c_i),
    .current_priority_o (current_priority),
    .new_priority_o     (new_priority)
);

// ========== 多Bank影子寄存器控制器 (纯组合逻辑决策) ==========
bank_controller #(
    .SHADOW_BANKS(SHADOW_BANKS),
    .OVERFLOW_POLICY(OVERFLOW_POLICY)
) u_bank_controller (
    .clk_i               (clk_i),
    .rst_n_i             (rst_n_i),
    .bank_ptr_i          (bank_ptr),
    .mret_in_ex_i        (id_ex_mret),
    .intr_pending_i      (intr_pending),
    .interrupt_processing_i(interrupt_processing_pipe),
    .current_priority_i  (current_priority),
    .new_priority_i      (new_priority),
    .allow_nesting_o     (allow_nesting),
    .bank_full_o         (bank_full),
    .tail_chain_detect_o (tail_chain_detect),
    .degradation_reuse_o (degradation_reuse)
);

// ========== 中断流水线 (多Bank版本, 含bank_ptr管理) ==========
interrupt_pipeline #(
    .SHADOW_BANKS(SHADOW_BANKS)
) u_interrupt_pipeline (
    .clk_i              (clk_i),
    .rst_n_i            (rst_n_i),
    .if_pc_i            (if_pc),
    .id_valid_i         (|if_id_instr),
    .id_pc_i            (if_id_pc),
    .ex_valid_i         (|id_ex_opcode),
    .ex_pc_i            (id_ex_pc),
    .ex_branch_taken_i  (ex_branch_taken),
    .ex_jump_taken_i    (ex_jump_taken),
    .mem_valid_i        (ex_mem_mem_we || ex_mem_mem_re),
    .mem_pc_i           (ex_mem_pc_plus4 - 4),
    .mem_mem_re_i       (ex_mem_mem_re),
    .mem_mem_we_i       (ex_mem_mem_we),
    .bus_ready_i        (bus_ready_i),
    .wb_valid_i         (wb_reg_we_out),
    .wb_rd_addr_i       (wb_rd_addr_out),
    .wb_reg_we_i        (wb_reg_we_out),
    .id_ex_mret         (id_ex_mret),
    .intr_pending_i     (intr_pending),
    .intr_cause_i       (intr_cause),
    .mstatus_i          (mstatus),
    .allow_nesting_i    (allow_nesting),
    .bank_full_i        (bank_full),
    .tail_chain_detect_i(tail_chain_detect),
    .degradation_reuse_i(degradation_reuse),
    .csr_mepc_we_o      (pipe_csr_mepc_we),
    .csr_mepc_data_o    (pipe_csr_mepc_data),
    .csr_mcause_we_o    (pipe_csr_mcause_we),
    .csr_mcause_data_o  (pipe_csr_mcause_data),
    .csr_mstatus_we_o   (pipe_csr_mstatus_we),
    .csr_mstatus_data_o (pipe_csr_mstatus_data),
    .shadow_save_o      (shadow_save),
    .shadow_restore_o   (shadow_restore),
    .bank_ptr_o         (bank_ptr),
    .interrupt_taken_o  (interrupt_taken_pipe),
    .interrupt_flush_o  (interrupt_flush_pipe),
    .interrupt_pc_o     (interrupt_pc_pipe),
    .intr_take_now_o    (intr_take_now),
    .interrupt_accepted_o(interrupt_accepted_pipe),
    .interrupt_processing_o(interrupt_processing_pipe)
);

assign csr_result = csr_inst_result;

// ==========================================================================
// 其他连接
// ==========================================================================
assign ex_mem_rd_addr_for_hazard = ex_mem_rd_addr;
assign ex_mem_reg_we_for_hazard = ex_mem_reg_we;
assign ex_mem_mem_re_for_hazard = ex_mem_mem_re;

assign forward_mem_data = (wb_wb_sel == 2'b11) ? wb_csr_result :
                          (mem_wb_mem_re      ? wb_mem_rdata : wb_alu_result);
assign ex_forward_muxed = (ex_mem_wb_sel == 2'b11) ? ex_mem_csr_result : ex_mem_alu_result;

assign stall_ex  = 1'b0;
assign stall_mem = 1'b0;
assign stall_wb  = 1'b0;
assign flush_ex  = ex_branch_taken || ex_jump_taken;
assign flush_mem = 1'b0;
assign flush_wb  = 1'b0;


endmodule
