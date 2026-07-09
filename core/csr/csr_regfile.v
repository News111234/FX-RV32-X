// core/csr/csr_regfile.v — CSR 寄存器文件 (支持多端口写)
`timescale 1ns/1ps

// ============================================================================
// 模块: csr_regfile
// 功能: 控制和状态寄存器 (CSR) 文件，实现 RISC-V 机器模式 (M-mode) 的核心 CSR
// 描述:
//   本模块实现 RISC-V 特权架构定义的关键 CSR，包括 mstatus, mtvec, mepc, mcause 等。
//   提供了两个独立写端口，允许中断响应逻辑和普通 CSR 指令同时写入，
//   并解决写冲突。同时接收外部中断输入并自动更新 mip (中断挂起) 寄存器。
//
// 主要 CSR:
//   - mstatus: 机器状态寄存器 (含全局中断使能等)
//   - mtvec:   机器中断向量基址寄存器
//   - mepc:    机器异常程序计数器 (保存中断/异常的返回地址)
//   - mcause:  机器异常/中断原因寄存器
//   - mie:     机器中断使能寄存器
//   - mip:     机器中断挂起寄存器
// 计数器: mcycle / minstret 64 位计数器 (精确性待完善)
// ============================================================================
module csr_regfile (
    // ========== 系统接口 ==========
    input  wire        clk_i,              // 时钟信号
    input  wire        rst_n_i,            // 复位信号 (低电平有效)

    // ========== CSR 读端口 ==========
    input  wire [11:0] csr_addr_i,         // 要读取的 CSR 地址
    output reg  [31:0] csr_rdata_o,        // 读取到的 CSR 值

    // ========== 普通 CSR 指令写端口 ==========
    input  wire        csr_inst_we_i,      // CSR 指令写使能
    input  wire [11:0] csr_inst_waddr_i,   // CSR 指令写地址
    input  wire [31:0] csr_inst_wdata_i,   // CSR 指令写数据

    // ========== 中断响应写端口 (新增) ==========
    input  wire        csr_mepc_we_i,      // 写 mepc 使能 (中断响应时)
    input  wire [31:0] csr_mepc_data_i,    // 写入 mepc 的值 (当前 PC)
    input  wire        csr_mcause_we_i,    // 写 mcause 使能 (中断响应时)
    input  wire [31:0] csr_mcause_data_i,  // 写入 mcause 的值 (中断原因)
    input  wire        csr_mstatus_we_i,   // 写 mstatus 使能 (中断响应时)
    input  wire [31:0] csr_mstatus_data_i, // 写入 mstatus 的值 (保存并关闭 MIE)

    // ========== 中断接口 ==========
    input  wire        intr_software_i,    // 软件中断输入
    input  wire        intr_timer_i,       // 定时器中断输入
    input  wire        intr_external_i,    // 外部中断输入

    // ========== CSR 值输出 (供其他模块使用) ==========
    output reg  [31:0] mtvec_o,            // 中断向量基址
    output reg  [31:0] mepc_o,             // 机器异常 PC
    output reg  [31:0] mcause_o,           // 机器异常/中断原因
    output reg  [31:0] mie_o,              // 机器中断使能
    output reg  [31:0] mstatus_o,          // 机器状态
    output reg  [31:0] mip_o              // 机器中断挂起

);

// ========== CSR 地址定义 ==========
localparam CSR_MSTATUS   = 12'h300;
localparam CSR_MISA      = 12'h301;
localparam CSR_MIE       = 12'h304;
localparam CSR_MTVEC     = 12'h305;
localparam CSR_MSCRATCH  = 12'h340;
localparam CSR_MEPC      = 12'h341;
localparam CSR_MCAUSE    = 12'h342;
localparam CSR_MTVAL     = 12'h343;
localparam CSR_MIP       = 12'h344;
// 硬件计数器
localparam CSR_MCYCLE    = 12'hB00;   // mcycle (低 32 位)
localparam CSR_MCYCLEH   = 12'hB80;   // mcycle (高 32 位)
localparam CSR_MINSTRET  = 12'hB02;   // minstret 低 32 位
localparam CSR_MINSTRETH = 12'hB82;   // minstret 高 32 位

// ========== CSR 寄存器定义 ==========
reg [31:0] mstatus;
reg [31:0] misa;
reg [31:0] mie;
reg [31:0] mtvec;
reg [31:0] mscratch;
reg [31:0] mepc;
reg [31:0] mcause;
reg [31:0] mtval;
reg [31:0] mip;
// 扩展 64 位计数器
reg [63:0] mcycle;
reg [63:0] minstret;

// 只读寄存器
wire [31:0] mvendorid = 32'h0;
wire [31:0] marchid   = 32'h1;  // 可自定义
wire [31:0] mimpid    = 32'h0;
wire [31:0] mhartid   = 32'h0;

// ========== 中断挂起位更新 ==========
wire [31:0] mip_next;
assign mip_next[31:12] = 20'b0;
assign mip_next[11]    = intr_external_i;   // MEIP
assign mip_next[10:8]  = 3'b0;
assign mip_next[7]     = intr_timer_i;      // MTIP
assign mip_next[6:4]   = 3'b0;
assign mip_next[3]     = intr_software_i;   // MSIP
assign mip_next[2:0]   = 3'b0;

// ========== 多端口写逻辑 ==========
always @(posedge clk_i) begin
    if (!rst_n_i) begin
        mstatus   <= 32'h00001800;
        misa      <= 32'h40000101;  // MXL=1 (RV32), Ext'I'=1
        mie       <= 32'b0;
        mtvec     <= 32'b0;
        mscratch  <= 32'b0;
        mepc      <= 32'b0;
        mcause    <= 32'b0;
        mtval     <= 32'b0;
        mip       <= 32'b0;
        mcycle    <= 64'b0;
        minstret  <= 64'b0;
    end else begin
        // 更新 mip: 使用组合逻辑计算的值
        mip <= mip_next;

        // ---- 硬件计数器 ----
        mcycle   <= mcycle + 1'b1;
        minstret <= minstret + 1'b1;  // 简化处理
        // minstret 应该根据指令实际退休情况计数，此处简化：只要 CPU 不 stall 就计数
        // 实际应用需要流水线控制信号，此处简化为每周期都计数 (CPI=1 假设)
        // 将来可以加入实际的退休信号到该端口

        // ========== 多路写端口 (同时写入) ==========

        // 1. 中断响应写 mepc
        if (csr_mepc_we_i)
            mepc <= csr_mepc_data_i;

        // 2. 中断响应写 mcause
        if (csr_mcause_we_i)
            mcause <= csr_mcause_data_i;

        // 3. 中断响应写 mstatus
        if (csr_mstatus_we_i)
            mstatus <= csr_mstatus_data_i;

        // 4. 普通 CSR 指令写 (中断响应写具有更高优先级, 不覆盖)
        if (csr_inst_we_i) begin
            case (csr_inst_waddr_i)
                CSR_MSTATUS:  if (!csr_mstatus_we_i) mstatus   <= csr_inst_wdata_i;
                CSR_MIE:      mie       <= csr_inst_wdata_i;
                CSR_MTVEC:    mtvec     <= csr_inst_wdata_i;
                CSR_MSCRATCH: mscratch  <= csr_inst_wdata_i;
                CSR_MEPC:     if (!csr_mepc_we_i)    mepc      <= csr_inst_wdata_i;
                CSR_MCAUSE:   if (!csr_mcause_we_i)  mcause    <= csr_inst_wdata_i;
                CSR_MTVAL:    mtval     <= csr_inst_wdata_i;
                // 注意: mcycle/minstret 通常只读，不写。某些实现允许写，用于测试
                default: ;
            endcase
        end
    end
end

// ========== CSR 读数据 ==========
always @(*) begin
    case (csr_addr_i)
        CSR_MSTATUS:   csr_rdata_o = mstatus;
        CSR_MISA:      csr_rdata_o = misa;
        CSR_MIE:       csr_rdata_o = mie;
        CSR_MTVEC:     csr_rdata_o = mtvec;
        CSR_MSCRATCH:  csr_rdata_o = mscratch;
        CSR_MEPC:      csr_rdata_o = mepc;
        CSR_MCAUSE:    csr_rdata_o = mcause;
        CSR_MTVAL:     csr_rdata_o = mtval;
        CSR_MIP:       csr_rdata_o = mip;
        CSR_MCYCLE:    csr_rdata_o = mcycle[31:0];
        CSR_MCYCLEH:   csr_rdata_o = mcycle[63:32];
        CSR_MINSTRET:  csr_rdata_o = minstret[31:0];
        CSR_MINSTRETH: csr_rdata_o = minstret[63:32];
        // 其他只读寄存器
        12'hF11: csr_rdata_o = mvendorid;  // mvendorid
        12'hF12: csr_rdata_o = marchid;    // marchid
        12'hF13: csr_rdata_o = mimpid;     // mimpid
        12'hF14: csr_rdata_o = mhartid;    // mhartid
        default:   csr_rdata_o = 32'b0;
    endcase
end

// ========== CSR 输出 ==========
always @(*) begin
    mtvec_o   = mtvec;
    mepc_o    = mepc;
    mcause_o  = mcause;
    mie_o     = mie;
    mstatus_o = mstatus;
    mip_o     = mip;
end

endmodule
