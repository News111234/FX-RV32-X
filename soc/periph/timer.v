// soc/periph/timer.v — 可编程定时器 (含中断逻辑)
`timescale 1ns/1ps

// ============================================================================
// 模块: timer
// 功能: 定时器，提供递减计数和中断功能
// 描述:
//   本模块实现一个 32 位递减定时器:
//   - 写 LOAD 寄存器设置计数器初值
//   - 使能后每个时钟周期计数器减 1
//   - 计数器减到 0 时产生中断
//   - 支持单次模式和自动重载模式
//
//   寄存器地址映射:
//     0x00: TIMER_CTRL  - 控制寄存器 (bit0: enable, bit1: auto_reload, bit2: clr_irq)
//     0x04: TIMER_LOAD  - 重载寄存器 (写入初值)
//     0x08: TIMER_COUNT - 当前计数值 (只读)
//     0x0C: TIMER_IER   - 中断使能寄存器 (bit0: irq_enable)
// ============================================================================
module timer (
    // ========== 系统接口 ==========
    input  wire        clk_i,              // 时钟信号
    input  wire        rst_n_i,            // 复位信号 (低电平有效)

    // ========== 总线接口 ==========
    input  wire        we_i,               // 写使能
    input  wire        re_i,               // 读使能
    input  wire [31:0] addr_i,             // 寄存器地址
    input  wire [31:0] wdata_i,            // 写数据
    output reg  [31:0] rdata_o,            // 读数据

    // ========== 中断输出 ==========
    output wire        interrupt_o         // 定时器中断信号 (组合逻辑, 无延迟)

);

// 寄存器地址偏移
localparam TIMER_CTRL  = 8'h00;
localparam TIMER_LOAD  = 8'h04;
localparam TIMER_COUNT = 8'h08;
localparam TIMER_IER   = 8'h0C;

reg        enable;
reg        auto_reload;
reg        irq_flag;
reg        irq_enable;
reg [31:0] load_value;
reg [31:0] counter;
reg        just_loaded;  // 标记是否刚加载，避免加载时误触发中断

// 寄存器写 + 计数器管理 (写操作和计数器递减分离，互不阻塞)
always @(posedge clk_i) begin
    if (!rst_n_i) begin
        enable      <= 1'b0;
        auto_reload <= 1'b0;
        irq_flag    <= 1'b0;
        irq_enable  <= 1'b0;
        load_value  <= 32'b0;
        counter     <= 32'b0;
        just_loaded <= 1'b0;
    end else begin
        // ---- 寄存器写 ----
        if (we_i) begin
            case (addr_i[7:0])
                TIMER_CTRL: begin
                    enable      <= wdata_i[0];
                    auto_reload <= wdata_i[1];
                    if (wdata_i[2]) irq_flag <= 1'b0;   // 写 1 清除中断标志
                end
                TIMER_LOAD: begin
                    load_value <= wdata_i;
                    if (!enable) begin
                        counter     <= wdata_i;
                        just_loaded <= 1'b1;
                    end
                end
                TIMER_IER: irq_enable <= wdata_i[0];
                default: ;
            endcase
        end

        // ---- 计数器递减 (每周期执行, 不受 we_i 影响) ----
        if (enable && !just_loaded) begin
            if (counter > 1) begin
                counter <= counter - 1;
            end else if (counter == 1) begin
                counter  <= 32'b0;
                irq_flag <= 1'b1;
            end else if (counter == 0) begin
                if (auto_reload) begin
                    counter <= load_value;
                    if (load_value == 0)
                        enable <= 1'b0;
                end else begin
                    enable <= 1'b0;
                end
            end
        end else begin
            just_loaded <= 1'b0;
        end
    end
end

// 读数据
always @(*) begin
    case (addr_i[7:0])
        TIMER_CTRL:  rdata_o = {29'b0, irq_flag, auto_reload, enable};
        TIMER_LOAD:  rdata_o = load_value;
        TIMER_COUNT: rdata_o = counter;
        TIMER_IER:   rdata_o = {31'b0, irq_enable};
        default:     rdata_o = 32'b0;
    endcase
end

// 中断输出 (组合逻辑: 清除 irq_flag 后同一周期中断即撤销)
assign interrupt_o = irq_flag && irq_enable;

endmodule
