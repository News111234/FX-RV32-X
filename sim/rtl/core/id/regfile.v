// rtl/id/regfile.v (增强版 - 多Bank影子寄存器)
`timescale 1ns/1ps

// ============================================================================
// 模块: regfile
// 功能: 通用寄存器堆，包含32个32位寄存器 (x0-x31) + N组影子寄存器
// 特性:
//   1. 两个读端口，一个写端口
//   2. x0寄存器硬连线为0，写入无效
//   3. 写数据内部转发(读地址等于写地址且写使能有效时，直接返回写入数据)
//   4. 多Bank影子寄存器: 中断时自动保存x1-x31到指定Bank, MRET时从指定Bank恢复
//   5. Bank选择由bank_ptr控制 (0=主程序, 1-N=嵌套层级)
// ============================================================================
module regfile #(
    parameter SHADOW_EN    = 1,     // 影子寄存器使能: 1=开启, 0=关闭
    parameter SHADOW_BANKS = 4      // 影子Bank数量 (默认4, 支持3级嵌套)
) (
    // ========== 系统接口 ==========
    input  wire        clk,           // 时钟信号
    input  wire        rst_n,         // 复位信号 (低电平有效)

    // ========== 读端口1 ==========
    input  wire [4:0]  raddr1_i,      // 读地址1
    output reg  [31:0] rdata1_o,      // 读数据1

    // ========== 读端口2 ==========
    input  wire [4:0]  raddr2_i,      // 读地址2
    output reg  [31:0] rdata2_o,      // 读数据2

    // ========== 写端口 ==========
    input  wire        we_i,          // 写使能
    input  wire [4:0]  waddr_i,       // 写地址
    input  wire [31:0] wdata_i,       // 写数据

    // ========== 多Bank影子寄存器控制 ==========
    input  wire [3:0]  bank_ptr_i,        // 当前Bank指针 (0=主程序, 1-N=嵌套层级)
    input  wire        shadow_save_i,     // 保存x1-x31到影子寄存器Bank[bank_ptr]
    input  wire        shadow_restore_i   // 从影子寄存器Bank[bank_ptr-1]恢复x1-x31

);

reg [31:0] registers [0:31];
// 多Bank影子寄存器: shadow[Bank][reg_index]
reg [31:0] shadow_registers [0:SHADOW_BANKS-1][1:31];
integer i, b;

// 读逻辑 - 组合电路
always @(*) begin
    // 读端口1
    if (raddr1_i == 5'b0) begin
        rdata1_o = 32'b0;  // x0始终为0
    end else if (we_i && (raddr1_i == waddr_i)) begin
        rdata1_o = wdata_i;  // 转发:直接返回当前写入的数据值
    end else begin
        rdata1_o = registers[raddr1_i];
    end

    // 读端口2
    if (raddr2_i == 5'b0) begin
        rdata2_o = 32'b0;
    end else if (we_i && (raddr2_i == waddr_i)) begin
        rdata2_o = wdata_i;  // 转发:直接返回当前写入的数据值
    end else begin
        rdata2_o = registers[raddr2_i];
    end
end

// 写逻辑 (含多Bank影子寄存器操作)
always @(posedge clk) begin
    if (!rst_n) begin
        for (i = 0; i < 32; i = i + 1) begin
            registers[i] <= 32'b0;
        end
        for (b = 0; b < SHADOW_BANKS; b = b + 1) begin
            for (i = 1; i < 32; i = i + 1) begin
                shadow_registers[b][i] <= 32'b0;
            end
        end
    end else begin
        // 影子恢复 (最高优先级): 从Bank[bank_ptr]恢复x1-x31
        // bank_ptr在interrupt_pipeline中已先递减, 此处的bank_ptr指向被恢复的上下文
        if (SHADOW_EN && shadow_restore_i) begin
            for (i = 1; i < 32; i = i + 1) begin
                registers[i] <= shadow_registers[bank_ptr_i][i];
            end
        end else begin
            // 正常写操作 (优先级高于影子保存,确保WB写入先完成)
            if (we_i && waddr_i != 5'b0) begin
                registers[waddr_i] <= wdata_i;
            end

            // 影子保存 (最低优先级): 将当前x1-x31保存到指定Bank
            // shadow_save时, bank_ptr已指向新Bank, 保存到Bank[bank_ptr-1]（当前上下文）
            if (SHADOW_EN && shadow_save_i && bank_ptr_i > 4'd0) begin
                for (i = 1; i < 32; i = i + 1) begin
                    shadow_registers[bank_ptr_i - 1][i] <= registers[i];
                end
            end
        end
    end
end


endmodule

//寄存器文件专用名称：ABI约定说明
// zero	x0	硬连线为0
// ra	x1	返回地址
// sp	x2	栈指针
// gp	x3	全局指针
// tp	x4	线程指针
// t0	x5	临时寄存器（无需被调用者保存）
// t1	x6	临时寄存器
// t2	x7	临时寄存器
// s0/fp	x8	保存寄存器/帧指针
// s1	x9	保存寄存器
// a0-a7	x10-x17	参数/返回值寄存器
// t3-t6	x28-x31	更多临时寄存器
//
// 多Bank影子寄存器说明:
//   N组影子寄存器(shadow_registers[0:N-1][1:31])对应x1-x31
//   - shadow_save_i:   中断进入时将x1-x31保存到Bank[bank_ptr-1]
//   - shadow_restore_i: MRET时将Bank[bank_ptr-1]恢复到x1-x31
//   - bank_ptr_i:       当前Bank指针 (0=主程序无中断, 1-N=嵌套层级)
//   - 优先级: shadow_restore > 正常写 > shadow_save
