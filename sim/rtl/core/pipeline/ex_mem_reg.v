// core/pipeline/ex_mem_reg.v — EX/MEM 流水线寄存器
`timescale 1ns/1ps

// ============================================================================
// 模块: ex_mem_reg
// 功能: EX/MEM 流水线寄存器，连接执行阶段和访存阶段
// 描述:
//   该寄存器捕获 EX 阶段产生的 ALU 结果、内存访问信息、写回控制等，
//   传递给 MEM 阶段。
//   同时传递 CSR 运算结果，支持 CSR 指令的写回。
// ============================================================================
module ex_mem_reg (
    // ========== 系统接口 ==========
    input  wire        clk_i,              // 时钟信号
    input  wire        rst_n_i,            // 复位信号 (低电平有效)

    // ========== 流水线控制信号 ==========
    input  wire        stall_i,            // 停顿标志
    input  wire        flush_i,            // 流水线刷新标志
    input  wire        intr_flush_i,       // 中断刷新标志

    // ========== EX 阶段输入 ==========
    input  wire [31:0] ex_alu_result_i,    // ALU 结果
    input  wire [31:0] ex_mem_addr_i,      // 内存地址
    input  wire [31:0] ex_mem_wdata_i,     // 内存写数据
    input  wire [31:0] ex_pc_plus4_i,      // PC+4
    input  wire [4:0]  ex_rd_addr_i,       // 目标寄存器地址

    input  wire        ex_mem_we_i,        // 内存写使能
    input  wire        ex_mem_re_i,        // 内存读使能
    input  wire [2:0]  ex_mem_width_i,     // 内存访问宽度
    input  wire [1:0]  ex_wb_sel_i,        // 写回选择
    input  wire        ex_reg_we_i,        // 寄存器写使能

    // ========== CSR 结果输入 ==========
    input  wire [31:0] ex_csr_result_i,    // EX 阶段 CSR 结果

    // ========== MEM 阶段输出 ==========
    output reg  [31:0] mem_alu_result_o,
    output reg  [31:0] mem_mem_addr_o,
    output reg  [31:0] mem_mem_wdata_o,
    output reg  [31:0] mem_pc_plus4_o,
    output reg  [4:0]  mem_rd_addr_o,

    output reg         mem_mem_we_o,
    output reg         mem_mem_re_o,
    output reg  [2:0]  mem_mem_width_o,
    output reg  [1:0]  mem_wb_sel_o,
    output reg         mem_reg_we_o,

    // ========== CSR 结果输出 ==========
    output reg  [31:0] mem_csr_result_o
);

always @(posedge clk_i) begin
    if (!rst_n_i) begin
        mem_alu_result_o <= 32'b0;
        mem_mem_addr_o   <= 32'b0;
        mem_mem_wdata_o  <= 32'b0;
        mem_pc_plus4_o   <= 32'b0;
        mem_rd_addr_o    <= 5'b0;

        mem_mem_we_o     <= 1'b0;
        mem_mem_re_o     <= 1'b0;
        mem_mem_width_o  <= 3'b0;
        mem_wb_sel_o     <= 2'b0;
        mem_reg_we_o     <= 1'b0;

        mem_csr_result_o <= 32'b0;
    end
    else if (flush_i || intr_flush_i) begin
        mem_alu_result_o <= 32'b0;
        mem_mem_addr_o   <= 32'b0;
        mem_mem_wdata_o  <= 32'b0;
        mem_pc_plus4_o   <= 32'b0;
        mem_rd_addr_o    <= 5'b0;

        mem_mem_we_o     <= 1'b0;
        mem_mem_re_o     <= 1'b0;
        mem_mem_width_o  <= 3'b0;
        mem_wb_sel_o     <= 2'b0;
        mem_reg_we_o     <= 1'b0;

        mem_csr_result_o <= 32'b0;
    end
    else if (!stall_i) begin
        mem_alu_result_o <= ex_alu_result_i;
        mem_mem_addr_o   <= ex_mem_addr_i;
        mem_mem_wdata_o  <= ex_mem_wdata_i;
        mem_pc_plus4_o   <= ex_pc_plus4_i;
        mem_rd_addr_o    <= ex_rd_addr_i;

        mem_mem_we_o     <= ex_mem_we_i;
        mem_mem_re_o     <= ex_mem_re_i;
        mem_mem_width_o  <= ex_mem_width_i;
        mem_wb_sel_o     <= ex_wb_sel_i;
        mem_reg_we_o     <= ex_reg_we_i;

        mem_csr_result_o <= ex_csr_result_i;
    end
end

endmodule
