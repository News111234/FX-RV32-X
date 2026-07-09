// core/pipeline/mem_wb_reg.v (最新修改版)
`timescale 1ns/1ps

// ============================================================================
// 模块: mem_wb_reg
// 功能: MEM/WB 流水线寄存器，连接访存阶段和写回阶段
// 描述:
//   该寄存器将MEM阶段的ALU结果、内存读取数据、写回控制等，
//   传递给WB阶段。
//   通过mem_mem_re_i输入，供转发单元判断load指令状态。
// ============================================================================
module mem_wb_reg (
    // ========== 系统接口 ==========
    input  wire        clk_i,          // 时钟信号
    input  wire        rst_n_i,        // 复位信号 (低电平有效)

    // ========== 流水线控制信号 ==========
    input  wire        stall_i,        // 停顿标志
    input  wire        flush_i,        // 流水线刷新标志
    input  wire        intr_flush_i,   // 中断刷新标志

    // ========== MEM阶段输入 ==========
    input  wire [31:0] mem_alu_result_i, // ALU结果
    input  wire [31:0] mem_mem_rdata_i,  // 内存读取数据
    input  wire [31:0] mem_pc_plus4_i,   // PC+4
    input  wire [4:0]  mem_rd_addr_i,    // 目标寄存器地址

    input  wire [1:0]  mem_wb_sel_i,     // 写回选择
    input  wire        mem_reg_we_i,     // 寄存器写使能

    // ========== CSR相关接口 ==========
    input  wire [31:0] mem_csr_result_i, // MEM阶段CSR结果

    // ========== Load标志传递 (用于转发) ==========
    input  wire        mem_mem_re_i,     // 是否为load指令

    // ========== WB阶段输出 ==========
    output reg  [31:0] wb_alu_result_o,
    output reg  [31:0] wb_mem_rdata_o,
    output reg  [31:0] wb_pc_plus4_o,
    output reg  [4:0]  wb_rd_addr_o,

    output reg  [1:0]  wb_wb_sel_o,
    output reg         wb_reg_we_o,

    // ========== CSR结果输出 ==========
    output reg  [31:0] wb_csr_result_o,

    // ========== Load标志输出 (用于转发) ==========
    output reg         wb_mem_re_o
);

always @(posedge clk_i ) begin
    if (!rst_n_i) begin
        wb_alu_result_o <= 32'b0;
        wb_mem_rdata_o  <= 32'b0;
        wb_pc_plus4_o   <= 32'b0;
        wb_rd_addr_o    <= 5'b0;
        wb_wb_sel_o     <= 2'b0;
        wb_reg_we_o     <= 1'b0;
        wb_csr_result_o <= 32'b0;
        wb_mem_re_o     <= 1'b0;              // 清零
    end
    else if (flush_i || intr_flush_i) begin
        wb_alu_result_o <= 32'b0;
        wb_mem_rdata_o  <= 32'b0;
        wb_pc_plus4_o   <= 32'b0;
        wb_rd_addr_o    <= 5'b0;
        wb_wb_sel_o     <= 2'b0;
        wb_reg_we_o     <= 1'b0;
        wb_csr_result_o <= 32'b0;
        wb_mem_re_o     <= 1'b0;              // 清零
    end
    else if (!stall_i) begin
        wb_alu_result_o <= mem_alu_result_i;
        wb_mem_rdata_o  <= mem_mem_rdata_i;
        wb_pc_plus4_o   <= mem_pc_plus4_i;
        wb_rd_addr_o    <= mem_rd_addr_i;
        wb_wb_sel_o     <= mem_wb_sel_i;
        wb_reg_we_o     <= mem_reg_we_i;
        wb_csr_result_o <= mem_csr_result_i;
        wb_mem_re_o     <= mem_mem_re_i;     // 正常传递 load 标志
    end
end

endmodule