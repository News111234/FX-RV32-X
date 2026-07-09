// rtl/interrupt/interrupt_pipeline.v - 中断流水线控制器 (多Bank版本, 含bank_ptr管理)
`timescale 1ns/1ps

// ============================================================================
// 模块: interrupt_pipeline
// 功能: 中断流水线控制器 + 多Bank影子寄存器管理
//
// 本模块负责:
//   1. 中断检测与接受 (恒定2周期延迟)
//   2. PC选择与CSR更新 (mepc, mcause, mstatus)
//   3. 流水线冲刷控制
//   4. 多Bank影子寄存器 bank_ptr 管理 (来自bank_controller的决策输入)
//   5. shadow_save / shadow_restore 脉冲生成
// ============================================================================
module interrupt_pipeline #(
    parameter SHADOW_EN    = 1,     // 影子寄存器使能
    parameter SHADOW_BANKS = 4      // 影子Bank数量
) (
    // ========== 系统接口 ==========
    input  wire        clk_i,
    input  wire        rst_n_i,

    // ========== 来自各级流水线的PC和状态信息 ==========
    input  wire [31:0] if_pc_i,
    input  wire        id_valid_i,
    input  wire [31:0] id_pc_i,
    input  wire        ex_valid_i,
    input  wire [31:0] ex_pc_i,
    input  wire        ex_branch_taken_i,
    input  wire        ex_jump_taken_i,
    input  wire        mem_valid_i,
    input  wire [31:0] mem_pc_i,
    input  wire        mem_mem_re_i,
    input  wire        mem_mem_we_i,
    input  wire        bus_ready_i,
    input  wire        wb_valid_i,
    input  wire [4:0]  wb_rd_addr_i,
    input  wire        wb_reg_we_i,
    input  wire        id_ex_mret,

    // ========== 中断请求 ==========
    input  wire        intr_pending_i,
    input  wire [31:0] intr_cause_i,

    // ========== CSR当前值 ==========
    input  wire [31:0] mstatus_i,

    // ========== Bank Controller决策输入 (组合逻辑) ==========
    input  wire        allow_nesting_i,       // 允许嵌套分配新Bank
    input  wire        bank_full_i,           // Bank已满
    input  wire        tail_chain_detect_i,   // Tail-Chaining检测
    input  wire        degradation_reuse_i,   // 降级复用模式 (Bank满但允许嵌套)

    // ========== 对CSR的更新信号 ==========
    output reg         csr_mepc_we_o,
    output reg  [31:0] csr_mepc_data_o,
    output reg         csr_mcause_we_o,
    output reg  [31:0] csr_mcause_data_o,
    output reg         csr_mstatus_we_o,
    output reg  [31:0] csr_mstatus_data_o,

    // ========== 影子寄存器控制输出 ==========
    output reg         shadow_save_o,        // 保存x1-x31到Bank[bank_ptr-1]
    output reg         shadow_restore_o,     // 从Bank[bank_ptr-1]恢复x1-x31
    output wire [3:0]  bank_ptr_o,           // 当前Bank指针 (assign驱动)

    // ========== 对流水线的控制 ==========
    output reg         interrupt_taken_o,
    output reg         interrupt_flush_o,
    output reg  [31:0] interrupt_pc_o,

    // ========== 组合逻辑输出 ==========
    output wire        intr_take_now_o,       // PC提前跳转
    output wire        interrupt_accepted_o,  // 中断已接受 (通知bank_controller)
    output wire        interrupt_processing_o // 正在服务中断 (给bank_controller)

);

// ========== 中断条件判断 ==========
wire interrupt_condition_all = intr_pending_i;

// ========== 中断PC选择 ==========
reg [31:0] interrupt_pc;

always @(*) begin
    if (mem_valid_i && (mem_pc_i != 32'b0)) begin
        if (mem_mem_re_i && !bus_ready_i)
            interrupt_pc = mem_pc_i;
        else
            interrupt_pc = mem_pc_i + 4;
    end else if (ex_valid_i && (ex_pc_i != 32'b0)) begin
        interrupt_pc = ex_pc_i;
    end else if (id_valid_i && (id_pc_i != 32'b0)) begin
        interrupt_pc = id_pc_i;
    end else begin
        interrupt_pc = if_pc_i;
    end
end

// ========== 状态寄存器 ==========
reg         interrupt_accepted;
reg         interrupt_processed;
reg [31:0]  saved_interrupt_pc;
reg [31:0]  saved_interrupt_cause;
reg [3:0]   bank_ptr_reg;          // Bank指针 (0=主程序, 1-N=嵌套)

// ========== 组合逻辑中断接受指示 ==========
// 允许抢占: 当前无中断服务, 或 高优先级中断可抢占
wire can_accept = !interrupt_accepted && (!interrupt_processed || allow_nesting_i);
wire intr_take_now = interrupt_condition_all && can_accept;
assign intr_take_now_o        = intr_take_now;
assign interrupt_accepted_o   = interrupt_accepted;
assign interrupt_processing_o = interrupt_processed;

always @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
        interrupt_accepted    <= 1'b0;
        interrupt_processed   <= 1'b0;
        saved_interrupt_pc    <= 32'b0;
        saved_interrupt_cause <= 32'b0;
        bank_ptr_reg          <= 4'd0;

        csr_mepc_we_o         <= 1'b0;
        csr_mepc_data_o       <= 32'b0;
        csr_mcause_we_o       <= 1'b0;
        csr_mcause_data_o     <= 32'b0;
        csr_mstatus_we_o      <= 1'b0;
        csr_mstatus_data_o    <= 32'b0;
        shadow_save_o         <= 1'b0;
        shadow_restore_o      <= 1'b0;
        interrupt_taken_o     <= 1'b0;
        interrupt_flush_o     <= 1'b0;
        interrupt_pc_o        <= 32'b0;

    end else begin
        // 默认值 (脉冲信号清零)
        csr_mepc_we_o     <= 1'b0;
        csr_mcause_we_o   <= 1'b0;
        csr_mstatus_we_o  <= 1'b0;
        shadow_save_o     <= 1'b0;
        shadow_restore_o  <= 1'b0;
        interrupt_taken_o <= 1'b0;
        interrupt_flush_o <= 1'b0;

        // ========== 中断进入 (允许高优先级抢占) ==========
        if (interrupt_condition_all && can_accept) begin
            interrupt_accepted    <= 1'b1;
            saved_interrupt_pc    <= interrupt_pc;
            saved_interrupt_cause <= intr_cause_i;

            // 写入 CSR (mepc, mcause, mstatus)
            csr_mepc_we_o   <= 1'b1;
            csr_mepc_data_o <= interrupt_pc;
            csr_mcause_we_o <= 1'b1;
            csr_mcause_data_o <= intr_cause_i;
            csr_mstatus_we_o <= 1'b1;
            csr_mstatus_data_o <= {
                mstatus_i[31:13],
                2'b11,              // MPP = Machine
                mstatus_i[10:8],
                mstatus_i[3],       // MPIE = old MIE
                mstatus_i[6:4],
                1'b0,               // MIE = 0
                mstatus_i[2:0]
            };

            // 流水线控制
            interrupt_taken_o <= 1'b1;
            interrupt_flush_o <= 1'b1;
            interrupt_pc_o    <= interrupt_pc;

            // 多Bank管理: 与shadow_save在同一时钟沿触发
            if (SHADOW_EN) begin
                // 允许嵌套: 分配新Bank, 保存当前上下文
                if (allow_nesting_i) begin
                    shadow_save_o <= 1'b1;  // 保存当前上下文到Bank[bank_ptr-1]
                    // 降级复用模式: bank_ptr保持N不变 (覆盖最深嵌套层Bank[N-1])
                    if (!degradation_reuse_i) begin
                        bank_ptr_reg <= bank_ptr_reg + 4'd1;
                    end
                end
                // 不允许嵌套但当前是主程序 (首次中断)
                else if (bank_ptr_reg == 4'd0) begin
                    shadow_save_o <= 1'b1;  // 保存主程序上下文到Bank[0]
                    bank_ptr_reg <= 4'd1;
                end
                // 不允许嵌套且已在ISR中: bank_ptr不变, 不触发save
            end

        end
        // ========== 中断接受完成 ==========
        else if (interrupt_accepted) begin
            interrupt_accepted  <= 1'b0;
            interrupt_processed <= 1'b1;
        end
        // ========== MRET: 中断退出 ==========
        else if (id_ex_mret) begin
            interrupt_processed <= 1'b0;

            // 恢复mstatus
            csr_mstatus_we_o <= 1'b1;
            csr_mstatus_data_o <= {mstatus_i[31:13],
                                   2'b00,             // MPP <= 00
                                   mstatus_i[10:8],
                                   mstatus_i[7],      // MPIE <= 1
                                   mstatus_i[6:4],
                                   mstatus_i[7],      // MIE <= old MPIE
                                   mstatus_i[2:0]
                                  };

            // 多Bank管理
            if (SHADOW_EN && bank_ptr_reg > 4'd0) begin
                if (tail_chain_detect_i) begin
                    // Tail-Chaining: 跳过restore, bank_ptr不变
                end else begin
                    // 正常MRET: 先递减bank_ptr, 再触发restore从Bank[bank_ptr]
                    bank_ptr_reg     <= bank_ptr_reg - 4'd1;
                    shadow_restore_o <= 1'b1;
                end
            end
        end
    end
end

// ========== 输出 ==========
assign bank_ptr_o = bank_ptr_reg;

endmodule
