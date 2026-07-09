// rtl/interrupt/interrupt_controller.v
`timescale 1ns/1ps

// ============================================================================
// 模块: interrupt_controller
// 功能: 中断控制器根据CSR判断是否有中断需要响应
// 描述:
//   输入中断信号
//   读取CSR中mie(中断使能)和mip(中断挂起)寄存器的值
//   以及全局中断使能位mstatus.MIE判断是否有中断等待处理
//   中断优先级(由高到低): 外部中断(MEI) > 定时器中断(MTI) > 软件中断(MSI)
//   支持两种中断处理模式:
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
    output wire [31:0] intr_handler_addr_o // 中断处理程序入口地址
);

// ========== 中断优先级编码 ==========
// RISC-V特权规范
// 中断ID: 3=MSI, 7=MTI, 11=MEI, 12=SPI, 13=I2C
// 优先级: MEI > MTI > MSI > SPI > I2C (按ID从高到低)

wire meip = mie_i[11] && (mip_i[11] || intr_external_i);  // 外部中断使能且待处理
wire mtip = mie_i[7]  && (mip_i[7]  || intr_timer_i);   // 定时器中断使能且待处理
wire msip = mie_i[3]  && (mip_i[3]  || intr_software_i); // 软件中断使能且待处理

wire spip = mie_i[12] && intr_spi_i;  // SPI中断使能且待处理
wire i2cip = mie_i[13] && intr_i2c_i;  // I2C中断使能且待处理

// 全局中断使能 (M-mode)
wire global_ie = mstatus_i[3];        // MIE位

// 中断优先级编码
reg [31:0] intr_cause;
reg        intr_valid;

always @(*) begin
    intr_valid = 1'b0;
    intr_cause = 32'b0;

    if (global_ie) begin
        // 优先级: MEI > MTI > SPI > I2C > MSI
        if (meip) begin
            intr_valid = 1'b1;
            intr_cause = {1'b1, 31'd11};  // 机器外部中断
        end else if (mtip) begin
            intr_valid = 1'b1;
            intr_cause = {1'b1, 31'd7};   // 机器定时器中断
        end else if (spip) begin
            intr_valid = 1'b1;
            intr_cause = {1'b1, 31'd12};  // SPI中断
        end else if (i2cip) begin
            intr_valid = 1'b1;
            intr_cause = {1'b1, 31'd13};  // I2C中断
        end else if (msip) begin
            intr_valid = 1'b1;
            intr_cause = {1'b1, 31'd3};   // 机器软件中断
        end
    end
end

// 中断处理程序地址计算
// mtvec[1:0] 模式编码:
// 00: 直接模式 (所有中断跳转至同一地址)
// 01: 向量模式 (按中断ID跳转)
wire [1:0] mtvec_mode = mtvec_i[1:0];
wire [31:0] mtvec_base = {mtvec_i[31:2], 2'b0};

reg [31:0] handler_addr;

always @(*) begin
    if (intr_valid) begin
        if (mtvec_mode == 2'b01) begin
            // 向量模式: base + cause*4
            handler_addr = mtvec_base + (intr_cause[4:0] << 2);
        end else begin
            // 直接模式: base
            handler_addr = mtvec_base;
        end
    end else begin
        handler_addr = 32'b0;
    end
end

assign intr_pending_o       = intr_valid;
assign intr_cause_o         = intr_cause;
assign intr_handler_addr_o  = handler_addr;

endmodule
