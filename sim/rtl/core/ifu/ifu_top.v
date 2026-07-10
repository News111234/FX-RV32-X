// rtl/core/ifu/ifu_top.v
`timescale 1ns/1ps
// ============================================================================
// 模块: if_top
// 功能: 取指模块顶层
// 描述:
//根据中断，停滞，分支和跳转信号生成下一周期的PC值，并将外部指令输入送入IF/ID寄存器
//如果都没有上述情况，则PC加4，取下一条指令
//
// 参数:
//   SYNC_INST_MEM = 1 (默认): 同步指令存储器 (inst_bram), 读延迟1周期
//                              pc_delayed 补偿延迟, 保证PC与指令对齐
//   SYNC_INST_MEM = 0       : 组合指令存储器 (inst_rom), 读零延迟
//                              pc = pc_value, 无延迟补偿
// ============================================================================
module ifu_top #(
    parameter SYNC_INST_MEM = 1  // 1=BRAM(sync read), 0=ROM(combinational read)
) (
    // ========== 时钟和复位 ==========
    input  wire        clk,
    input  wire        rst_n,
    

    // ========== 停滞标志，跳转标志和分支标志，跳转地址和分支地址 ==========
    input  wire        stall_i,
    input  wire        branch_taken_i,
    input  wire        jump_taken_i,
    input  wire [31:0] branch_target_i,
    input  wire [31:0] jump_target_i,

    // ========== 中断接口 ==========
    input  wire        interrupt_taken_i,
    input  wire        intr_take_now_i,     // 组合逻辑: 本周期即将接受中断(提前跳转PC)
    input  wire [31:0] intr_target_i,

    // ========== 外部指令输入 ==========
    input  wire [31:0] instr_i,          // 外部指令ROM的指令

    // ========== 送入IF/ID流水线寄存器==========
    output wire [31:0] instr,            //  instr_i 送入IF/ID寄存器的指令
    output wire [31:0] pc,               // 与BRAM输出同步的指令PC (延迟1周期)
    output wire [31:0] pc_plus4,
    output wire [31:0] pc_current        // 当前取指PC (送到BRAM地址)
    
    );

wire [31:0] pc_value;
wire [31:0] next_pc;

pc_reg u_pc_reg(
    .clk     (clk),
    .rst_n   (rst_n),
    .stall   (stall_i),
    .interrupt_taken_i(interrupt_taken_i),
    .intr_take_now_i(intr_take_now_i),
    .next_pc (next_pc),
    .pc      (pc_value)
);

// ============================================================================
// BRAM同步读延迟补偿 (仅 SYNC_INST_MEM=1 时使用)
// BRAM同步读有1周期延迟: instr_i 对应的是上一周期的PC
// 这里用pc_delayed将PC延迟1周期, 保证与指令同步
// ROM组合读 (SYNC_INST_MEM=0): 无延迟, 不需要此寄存器
// ============================================================================
generate
    if (SYNC_INST_MEM) begin : gen_pc_delayed
        reg [31:0] pc_delayed;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n)
                pc_delayed <= 32'b0;
            else if (!stall_i || interrupt_taken_i || intr_take_now_i)
                pc_delayed <= pc_value;
        end
        assign pc       = pc_delayed;
        assign pc_plus4 = pc_delayed + 32'h4;
    end else begin : gen_pc_direct
        assign pc       = pc_value;
        assign pc_plus4 = pc_value + 32'h4;
    end
endgenerate

assign instr = instr_i;

// 更新pc值，优先级可手动配置
// intr_take_now_i: 组合逻辑, 在中断pending的第一个周期(T1-T2)就为1, next_pc=handler, PC在T2↑跳转
// interrupt_taken_i: 寄存器, T2-T3期间为1, 挡住旧EX指令的分支/跳转信号, next_pc=pc+4正常递增
assign next_pc = (!rst_n)               ? 32'h0 :
                 (intr_take_now_i)       ? intr_target_i :    // T1-T2: handler
                 (interrupt_taken_i)     ? pc_value + 32'h4 :   // T2-T3: 挡分支, 正常递增
                 (branch_taken_i)       ? branch_target_i :
                 (jump_taken_i)         ? jump_target_i :
                 (stall_i)              ? pc_value :          // T2-T3: hold pc (block old branch/jump)
                 pc_value + 32'h4;

// pc: 送入IF/ID寄存器的指令PC (BRAM模式:延迟1周期; ROM模式:直接)
// pc_current: 当前取指PC, 用于指令存储器地址输入
assign pc_current = pc_value;



endmodule