// core/wbu/wb_mux.v — 写回数据选择器
`timescale 1ns/1ps

// ============================================================================
// 模块: wb_mux
// 功能: 写回数据选择器，根据指令类型选择写回寄存器的数据来源
// 描述:
//   本模块根据 wb_sel_i 选择信号，从四个数据来源中选择一个写回寄存器堆:
//   - 2'b00: ALU 运算结果  (R-type, I-type 运算指令)
//   - 2'b01: 内存读取数据  (load 指令: LW, LH, LB 等)
//   - 2'b10: PC + 4       (跳转指令: JAL, JALR 的返回地址)
//   - 2'b11: CSR 读取值    (CSR 指令: CSRRW, CSRRS 等)
// ============================================================================
module wb_mux (
    // ========== 数据输入端口 ==========
    input  wire [31:0] alu_result_i,    // ALU 运算结果
    input  wire [31:0] mem_rdata_i,     // 内存读取数据
    input  wire [31:0] pc_plus4_i,      // PC+4 值 (返回地址)
    input  wire [31:0] csr_data_i,      // CSR 读取值

    // ========== 控制信号输入 ==========
    input  wire [1:0]  wb_sel_i,        // 写回选择信号

    // ========== 输出端口 ==========
    output reg  [31:0] wb_data_o        // 写回寄存器的数据
);

// ========== 写回选择信号编码说明 ==========
// wb_sel_i 的 2 位编码含义:
//   2'b00: ALU 运算结果  -> R-type 指令, I-type 运算指令
//   2'b01: 内存读取数据  -> 访存指令 (LW, LH, LB 等)
//   2'b10: PC + 4        -> 跳转指令 (JAL, JALR) 的返回地址
//   2'b11: CSR 读取值    -> CSR 指令 (CSRRW, CSRRS 等)

// ========== 写回数据选择逻辑 ==========
always @(*) begin
    case (wb_sel_i)
        2'b00: wb_data_o = alu_result_i;  // ALU 结果
        2'b01: wb_data_o = mem_rdata_i;   // 内存读取数据
        2'b10: wb_data_o = pc_plus4_i;    // PC+4 (返回地址)
        2'b11: wb_data_o = csr_data_i;    // CSR 读取值
        default: wb_data_o = 32'b0;       // 安全默认值
    endcase
end

endmodule
