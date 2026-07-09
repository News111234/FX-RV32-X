// core/interrupt/bank_controller.v — 多Bank影子寄存器硬件管理器 (组合逻辑决策)
`timescale 1ns/1ps

// ============================================================================
// 模块: bank_controller
// 功能: 多Bank影子寄存器的组合逻辑决策单元
//
// 本模块是纯组合逻辑，提供嵌套/抢占/Tail-Chaining的判断信号。
// 所有时序关键信号(bank_ptr, shadow_save, shadow_restore)由interrupt_pipeline管理。
//
// 决策输出:
//   allow_nesting_o:     允许分配新Bank (优先级抢占 && 未满)
//   bank_full_o:         Bank已满
//   tail_chain_detect_o: 检测到Tail-Chaining条件 (MRET+pending)
// ============================================================================
module bank_controller #(
    parameter SHADOW_BANKS      = 4,
    parameter TAIL_CHAIN_EN     = 0,    // Tail-chaining: 默认关闭 (需进一步验证)
    parameter OVERFLOW_POLICY   = 0     // Bank溢出策略: 0=硬限制, 1=降级复用
) (
    // ========== 系统接口 ==========
    input  wire        clk_i,
    input  wire        rst_n_i,

    // ========== Bank状态输入 ==========
    input  wire [3:0]  bank_ptr_i,             // 当前Bank指针 (来自interrupt_pipeline)

    // ========== 中断状态输入 ==========
    input  wire        mret_in_ex_i,           // MRET指令在EX阶段
    input  wire        intr_pending_i,         // 有中断pending (用于tail-chain)
    input  wire        interrupt_processing_i,  // 当前正在服务中断 (interrupt_processed)

    // ========== 优先级输入 ==========
    input  wire [3:0]  current_priority_i,     // 当前服务中断优先级 (0=无中断)
    input  wire [3:0]  new_priority_i,         // 新中断优先级

    // ========== 决策输出 (纯组合逻辑) ==========
    output wire        allow_nesting_o,        // 允许嵌套: 抢占 && (未满 || 降级复用)
    output wire        bank_full_o,            // Bank已满
    output wire        tail_chain_detect_o,    // Tail-Chaining检测
    output wire        degradation_reuse_o     // 降级复用模式 (Bank满但允许嵌套)

);

// ============================================================================
// 组合逻辑: 优先级抢占判定
// ============================================================================
// 当前无中断服务 或 新中断优先级更高 → 允许响应
wire preemption_allowed = (current_priority_i == 4'd0) ||
                          (new_priority_i > current_priority_i);

// ============================================================================
// 组合逻辑: Bank溢出检测
// ============================================================================
// bank_ptr == SHADOW_BANKS → 所有Bank已用尽
wire bank_full = (bank_ptr_i == SHADOW_BANKS[3:0]);

// ============================================================================
// 组合逻辑: Tail-Chaining检测
// ============================================================================
// MRET在EX阶段 && 有中断pending → 跳过restore, 保持Bank
wire tail_chain_detect = TAIL_CHAIN_EN && mret_in_ex_i && intr_pending_i;

// ============================================================================
// 组合逻辑: 综合决策
// ============================================================================
// 降级复用: Bank满时, 若OVERFLOW_POLICY=1且新中断优先级更高, 允许覆盖最深嵌套层
wire degradation_reuse = (OVERFLOW_POLICY == 1) && bank_full && preemption_allowed;

// 可以分配新Bank: 优先级允许 且 (未满 或 降级复用) 且 非Tail-Chain
assign allow_nesting_o     = preemption_allowed && (!bank_full || degradation_reuse) && !tail_chain_detect;
assign bank_full_o         = bank_full;
assign tail_chain_detect_o = tail_chain_detect;
assign degradation_reuse_o = degradation_reuse;

endmodule
