// core/mem/mem_top.v — 访存阶段顶层模块 (FPGA 专用, 带总线接口)
`timescale 1ns/1ps

// ============================================================================
// 模块: mem_top
// 功能: 访存阶段顶层模块 (FPGA 专用)，连接系统总线仲裁器
// 描述:
//   本模块是流水线访存阶段的核心，功能包括:
//   1. 接收来自 EX/MEM 流水线寄存器的内存访问请求
//   2. 将请求直接转发给系统总线仲裁器 (bus_arbiter)
//   3. 接收总线返回的读取数据
//   4. 将 PC+4 和写回控制信号透传给 MEM/WB 流水线寄存器
//   本模块不包含实际的 RAM，内存访问通过总线进行。
// ============================================================================
module mem_top (
    // ========== 系统接口 ==========
    input  wire        clk_i,              // 时钟信号
    input  wire        rst_n_i,            // 复位信号 (低电平有效)

    // ========== 来自 EX/MEM 流水线寄存器的输入 ==========
    input  wire [31:0] alu_result_i,       // ALU 结果 (内存地址)
    input  wire [31:0] wdata_i,            // 写数据
    input  wire        mem_we_i,           // 内存写使能
    input  wire        mem_re_i,           // 内存读使能
    input  wire [2:0]  mem_width_i,        // 访问宽度
    input  wire [31:0] pc_plus4_i,         // PC+4 (用于 JAL 返回地址)
    input  wire        reg_we_i,           // 寄存器写使能
    input  wire [1:0]  wb_sel_i,           // 写回选择
    input  wire [4:0]  rd_addr_i,          // 目标寄存器地址

    // ========== 送入 MEM/WB 流水线寄存器 ==========
    output wire [31:0] pc_plus4_o,         // PC+4 (透传)
    output wire        reg_we_o,           // 寄存器写使能 (透传)
    output wire [1:0]  wb_sel_o,           // 写回选择 (透传)
    output wire [4:0]  rd_addr_o,          // 目标寄存器地址 (透传)

    // ========== 总线接口 (连接到 bus_arbiter) ==========
    output wire        bus_re_o,           // 总线读请求
    output wire        bus_we_o,           // 总线写请求
    output wire [31:0] bus_addr_o,         // 总线地址
    output wire [31:0] bus_wdata_o,        // 总线写数据
    output wire [2:0]  bus_width_o,        // 总线访问宽度
    input  wire [31:0] bus_rdata_i,        // 总线读数据
    input  wire        bus_ready_i,        // 总线就绪信号

    // ========== 异常输出 ==========
    output wire        mem_exception_o     // 内存异常标志
);

// 总线信号直接转发
// bus_re 既是读请求也是写请求 — 对 LOAD 和 STORE 都要拉高, 否则外围逻辑无法响应写操作
assign bus_re_o    = mem_re_i || mem_we_i;
assign bus_we_o    = mem_we_i;
assign bus_addr_o  = alu_result_i;
assign bus_wdata_o = wdata_i;
assign bus_width_o = mem_width_i;

// 控制信号透传到下一阶段
assign pc_plus4_o      = pc_plus4_i;
assign reg_we_o        = reg_we_i;
assign wb_sel_o        = wb_sel_i;
assign rd_addr_o       = rd_addr_i;
assign mem_exception_o = 1'b0;  // 暂不支持异常

endmodule
