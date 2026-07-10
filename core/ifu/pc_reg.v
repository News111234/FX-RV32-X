// core/ifu/pc_reg.v — PC 寄存器
`timescale 1ns/1ps

// ============================================================================
// 模块: pc_reg
// 功能: PC 寄存器，存储当前取指地址
// 描述:
//   本模块是一个简单的寄存器，在时钟上升沿更新 PC 值。
//   更新条件:
//   1. 复位时清零
//   2. 非停顿状态 (stall=0) 或中断等待时，更新为 next_pc
//   中断时强制更新 PC，即使流水线停顿也要跳转到中断处理程序入口
// ============================================================================
module pc_reg(
    // ========== 系统接口 ==========
    input  wire        clk,               // 时钟信号
    input  wire        rst_n,             // 复位信号 (低电平有效)

    // ========== 控制信号 ==========
    input  wire        stall,             // 停顿标志
    input  wire        interrupt_taken_i, // 中断等待标志 (中断时强制更新)
    input  wire        intr_take_now_i,   // 组合逻辑中断接受 (中断时强制更新)

    // ========== PC 输入 / 输出 ==========
    input  wire [31:0] next_pc,           // 下一 PC 值
    output reg  [31:0] pc                 // 当前 PC 值
);

always @(posedge clk) begin
    if (!rst_n) begin
        pc <= 32'h0000_0000;
    end
    else if (!stall || interrupt_taken_i || intr_take_now_i) begin  // 中断时强制更新 PC
        pc <= next_pc;
    end
end

endmodule
