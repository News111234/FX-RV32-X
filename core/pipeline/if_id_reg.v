// core/pipeline/if_id_reg.v — IF/ID 流水线寄存器
`timescale 1ns/1ps

// ============================================================================
// 模块: if_id_reg
// 功能: IF/ID 流水线寄存器，连接取指阶段和译码阶段
// 描述:
//   该寄存器在时钟上升沿捕获 IF 阶段的 PC 和指令，传递给 ID 阶段。
//   支持停顿 (stall)、流水线刷新 (flush)、中断刷新 (intr_flush)。
//   刷新时输出 NOP 指令 (0x00000013, addi x0, x0, 0)，阻止无效指令继续传播。
// ============================================================================
module if_id_reg (
    // ========== 系统接口 ==========
    input  wire        clk_i,              // 时钟信号
    input  wire        rst_n_i,            // 复位信号 (低电平有效)

    // ========== 流水线控制信号 ==========
    input  wire        stall_i,            // 停顿标志 (保持当前值)
    input  wire        flush_i,            // 流水线刷新标志 (分支/跳转)
    input  wire        intr_flush_i,       // 中断刷新标志 (优先级高于普通刷新)

    // ========== IF 阶段输入 ==========
    input  wire [31:0] if_pc_i,            // IF 阶段 PC
    input  wire [31:0] if_instr_i,         // IF 阶段指令

    // ========== ID 阶段输出 ==========
    output reg  [31:0] id_pc_o,            // ID 阶段 PC
    output reg  [31:0] id_instr_o          // ID 阶段指令
);

always @(posedge clk_i) begin
    if (!rst_n_i) begin
        id_pc_o    <= 32'b0;
        id_instr_o <= 32'b0;
    end
    else if (flush_i || intr_flush_i) begin  // 合并刷新信号
        id_pc_o    <= 32'b0;
        id_instr_o <= 32'h00000013;          // NOP: addi x0, x0, 0
    end
    else if (!stall_i) begin
        id_pc_o    <= if_pc_i;
        id_instr_o <= if_instr_i;
    end
end

endmodule
