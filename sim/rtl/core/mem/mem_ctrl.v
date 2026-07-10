// ================================================
// Module: mem_ctrl
// Function: Memory Access Controller with Alignment Check
// ================================================
`timescale 1ns/1ps

// ============================================================================
// 模块: mem_ctrl
// 功能: 内存访问控制器，支持地址对齐检查和地址合法性检查
// 描述:
//   本模块具有内存访问操作的预检查:
//   1. 地址对齐检查: LW/SW地址需按2字节对齐，LH/SH地址需按1字节对齐
//   2. 地址合法性检查: 当前支持的有效地址范围为 0x0000_0000 ~ 0x0FFF_FFFF
//   3. 若地址未对齐或超出范围，产生异常信号并阻止内存访问
// ============================================================================
module mem_ctrl (
    // ========== 来自EX阶段的输入 ==========
    input  wire [31:0] alu_result_i,   // ALU结果 (用作内存地址)
    input  wire [31:0] wdata_i,        // 写数据
    input  wire        mem_we_i,       // 内存写使能
    input  wire        mem_re_i,       // 内存读使能
    input  wire [2:0]  mem_width_i,    // 访问宽度

    // ========== 输出到内存 ==========
    output wire [31:0] mem_addr_o,     // 内存地址
    output wire [31:0] mem_wdata_o,    // 内存写数据
    output wire        mem_we_o,       // 内存写使能 (对齐检查后)
    output wire        mem_re_o,       // 内存读使能 (对齐检查后)
    output wire [2:0]  mem_width_o,    // 访问宽度

    // ========== 异常输出 ==========
    output wire        mem_misalign_o, // 地址未对齐异常
    output wire        mem_error_o     // 地址越界异常
);

// ========== 地址对齐检查 ==========
wire misalign = (mem_width_i == 3'b010 && alu_result_i[1:0] != 2'b00) || // LW/SW
                (mem_width_i == 3'b001 && alu_result_i[0]   != 1'b0);    // LH/SH

// ========== 输出信号 ==========
assign mem_addr_o   = alu_result_i;
assign mem_wdata_o  = wdata_i;          // data_ram 内部处理写数据字节/半字写入
assign mem_we_o     = mem_we_i && !misalign;
assign mem_re_o     = mem_re_i && !misalign;
assign mem_width_o  = mem_width_i;

// ========== 异常信号 ==========
assign mem_misalign_o = misalign;
assign mem_error_o    = (mem_we_i || mem_re_i) && (alu_result_i[31:28] != 4'h0); // 判断有效地址为 0x0000_0000 ~ 0x0FFF_FFFF

endmodule
