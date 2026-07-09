// rtl/interrupt/interrupt_controller.v — 中断控制器 (含优先级抢占)
`timescale 1ns/1ps

// ============================================================================
// 模块: interrupt_controller
// 功能: 中断控制器，含优先级编码、向量地址计算、抢占判定
//
// 中断优先级(由高到低): MEI(ID=11) > MTI(ID=7) > SPI(ID=12) > I2C(ID=13) > MSI(ID=3)
// 支持两种中断处理模式:
//   - 直接模式 (mtvec.MODE=00): 所有中断跳转至同一地址
//   - 向量模式 (mtvec.MODE=01): 按中断ID跳转至 base + cause*4
// ============================================================================
module interrupt_controller (
    // ========== 系统接口 ==========
    input  wire        clk_i,             // 时钟信号
    input  wire        rst_n_i,           // 复位信号 (低电平有效)

    // ========== 外部中断源 ==========
    input  wire        intr_software_i,   // 软件中断 (来自CLINT)
    input  wire        intr_timer_i,      // 定时器中断 (来自CLINT)
    input  wire        intr_external_i,   // 外部中断 (来自PLIC/GPIO)
    input  wire        intr_spi_i,        // SPI中断
    input  wire        intr_i2c_i,        // I2C中断

    // ========== CSR接口 ==========
    input  wire [31:0] mie_i,             // 中断使能寄存器
    input  wire [31:0] mip_i,             // 中断待处理寄存器
    input  wire [31:0] mstatus_i,         // 机器状态寄存器
    input  wire [31:0] mtvec_i,           // 中断向量基址寄存器

    // ========== 中断控制器输出 ==========
    output wire        intr_pending_o,     // 有中断等待 (需要响应)
    output wire [31:0] intr_cause_o,       // 中断原因 (最高位=1表示中断)
    output wire [31:0] intr_handler_addr_o,// 中断处理程序入口地址

    // ========== 优先级输出 (给bank_controller) ==========
    output wire [3:0]  current_priority_o, // 当前服务中断优先级
    output wire [3:0]  new_priority_o      // 新中断优先级

);

// ========== 中断优先级编码 ==========
// 中断ID: 3=MSI, 7=MTI, 11=MEI, 12=SPI, 13=I2C
// 优先级编码: 11(外部) > 7(定时器) > 12(SPI) > 13(I2C) > 3(软件)

// 定义优先级值 (用于抢占比较)
localparam PRIO_MEI  = 4'd11;
localparam PRIO_MTI  = 4'd7;
localparam PRIO_SPI  = 4'd5;
localparam PRIO_I2C  = 4'd4;
localparam PRIO_MSI  = 4'd3;
localparam PRIO_NONE = 4'd0;

wire meip = mie_i[11] && (mip_i[11] || intr_external_i);
wire mtip = mie_i[7]  && (mip_i[7]  || intr_timer_i);
wire msip = mie_i[3]  && (mip_i[3]  || intr_software_i);
wire spip = mie_i[12] && intr_spi_i;
wire i2cip = mie_i[13] && intr_i2c_i;

// 全局中断使能 (M-mode)
wire global_ie = mstatus_i[3];

// 中断优先级编码 (含优先级值)
reg [31:0] intr_cause;
reg        intr_valid;
reg [3:0]  new_prio;         // 新中断的优先级值

always @(*) begin
    intr_valid = 1'b0;
    intr_cause = 32'b0;
    new_prio   = PRIO_NONE;

    if (global_ie) begin
        // 优先级: MEI > MTI > SPI > I2C > MSI
        if (meip) begin
            intr_valid = 1'b1;
            intr_cause = {1'b1, 31'd11};
            new_prio   = PRIO_MEI;
        end else if (mtip) begin
            intr_valid = 1'b1;
            intr_cause = {1'b1, 31'd7};
            new_prio   = PRIO_MTI;
        end else if (spip) begin
            intr_valid = 1'b1;
            intr_cause = {1'b1, 31'd12};
            new_prio   = PRIO_SPI;
        end else if (i2cip) begin
            intr_valid = 1'b1;
            intr_cause = {1'b1, 31'd13};
            new_prio   = PRIO_I2C;
        end else if (msip) begin
            intr_valid = 1'b1;
            intr_cause = {1'b1, 31'd3};
            new_prio   = PRIO_MSI;
        end
    end
end

// ========== 中断处理程序地址计算 ==========
wire [1:0] mtvec_mode = mtvec_i[1:0];
wire [31:0] mtvec_base = {mtvec_i[31:2], 2'b0};

reg [31:0] handler_addr;

always @(*) begin
    if (intr_valid) begin
        if (mtvec_mode == 2'b01)
            handler_addr = mtvec_base + (intr_cause[4:0] << 2);  // 向量模式
        else
            handler_addr = mtvec_base;                             // 直接模式
    end else begin
        handler_addr = 32'b0;
    end
end

// ========== 当前服务优先级跟踪 ==========
// current_priority: 0=无中断活跃, 非0=对应中断ID的优先级值
reg [3:0] current_priority;

always @(posedge clk_i or negedge rst_n_i) begin
    if (!rst_n_i) begin
        current_priority <= PRIO_NONE;
    end else begin
        // 简单跟踪: intr_pending上升沿时更新
        // 实际抢占逻辑在bank_controller中, 这里只提供优先级值
        if (intr_pending_o && current_priority == PRIO_NONE) begin
            current_priority <= new_prio;  // 首次中断
        end else if (!intr_pending_o) begin
            current_priority <= PRIO_NONE; // 无中断pending
        end
    end
end

assign intr_pending_o       = intr_valid;
assign intr_cause_o         = intr_cause;
assign intr_handler_addr_o  = handler_addr;

assign new_priority_o       = new_prio;
assign current_priority_o   = current_priority;

endmodule
