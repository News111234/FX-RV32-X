`timescale 1ns/1ps

// 模块: forwarding_unit
// 功能: 转发单元 (数据前递) 解决流水线的数据冒险
// 描述:
//   指令在ID阶段时就开始检测数据冒险,
//   若目的寄存器不是x0则产生转发控制信号(forwardA_o/forwardB_o),
//   通知EX阶段从后面阶段的结果直接获取数据，避免流水线停顿。
//
// 转发优先级:
//   1. 优先使用EX/MEM阶段的数据 (最新)
//   2. 其次使用MEM/WB阶段的数据，排除load指令 (因为load数据在MEM阶段才就绪)
//
// 转发选择编码:
//   2'b00: 不转发，使用ID/EX寄存器的原始值
//   2'b01: 转发来自EX/MEM阶段的结果 (alu_result)
//   2'b10: 转发来自MEM/WB阶段的结果 (mem_rdata或alu_result)
// ============================================================================
module forwarding_unit (
    // ========== 读ID/EX寄存器的源寄存器地址 ==========
    input  wire [4:0] id_ex_rs1_addr_i,  // ID/EX阶段指令的rs1地址
    input  wire [4:0] id_ex_rs2_addr_i,  // ID/EX阶段指令的rs2地址

    // ========== 读EX/MEM寄存器的写回信息 ==========
    input  wire [4:0] ex_mem_rd_addr_i,  // EX/MEM阶段指令的目标寄存器地址
    input  wire       ex_mem_reg_we_i,   // EX/MEM阶段寄存器写使能
    input  wire       ex_mem_mem_re_i,   // EX/MEM阶段是否为load指令 (需要排除)

    // ========== 读MEM/WB寄存器的写回信息 ==========
    input  wire [4:0] mem_wb_rd_addr_i,  // MEM/WB阶段指令的目标寄存器地址
    input  wire       mem_wb_reg_we_i,   // MEM/WB阶段寄存器写使能

    // ========== 流水线控制 ==========
    input  wire       stall_i,           // 流水线停顿标志 (停顿期间不进行转发)

    // ========== 转发选择输出 ==========
    output reg  [1:0] forwardA_o,        // 操作数1的转发选择
    output reg  [1:0] forwardB_o        // 操作数2的转发选择


);



always @(*) begin
    if (stall_i) begin
        forwardA_o = 2'b00;
        forwardB_o = 2'b00;
    end else begin
        forwardA_o = 2'b00;
        forwardB_o = 2'b00;

// 优先检测 EX/MEM 阶段，最新的数据：
        if (ex_mem_reg_we_i && (ex_mem_rd_addr_i != 5'b0) && !ex_mem_mem_re_i) begin
            if (ex_mem_rd_addr_i == id_ex_rs1_addr_i)
                forwardA_o = 2'b01;
            if (ex_mem_rd_addr_i == id_ex_rs2_addr_i)
                forwardB_o = 2'b01;
        end

        // 再检测 MEM/WB 阶段，旧数据，仅在 EX/MEM 没有匹配时：
        if (forwardA_o == 2'b00 && mem_wb_reg_we_i && (mem_wb_rd_addr_i != 5'b0)) begin
            if (mem_wb_rd_addr_i == id_ex_rs1_addr_i)
                forwardA_o = 2'b10;
        end
        if (forwardB_o == 2'b00 && mem_wb_reg_we_i && (mem_wb_rd_addr_i != 5'b0)) begin
            if (mem_wb_rd_addr_i == id_ex_rs2_addr_i)
                forwardB_o = 2'b10;
        end
    end
end

endmodule
