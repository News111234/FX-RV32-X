// rtl/ifu/inst_rom_interrupt.v - 带中断测试的程序
//大概在440多ns的时刻，触发中断信号，中断延迟一共两个周期
`timescale 1ns/1ps

module inst_rom(
    input  wire [31:0] addr_i,
    output reg  [31:0] data_o
);

reg [31:0] rom [0:511];  // 扩大ROM到512条指令
integer i;

initial begin
    // 初始化所有指令为nop
    for (i = 0; i <= 511; i = i + 1) begin
        rom[i] = 32'h00000013; // nop: addi x0, x0, 0
    end
    
       // ========== 主程序 ==========
    
    // 1. 配置 GPIO (用于观察中断)
    rom[0]  = 32'h100010B7;  // lui x1, 0x10001000
    rom[1]  = 32'h00408093;  // addi x1, x1, 0x004     -> OE地址
    rom[2]  = 32'h00100113;  // addi x2, x0, 1
    rom[3]  = 32'h0020A023;  // sw x2, 0(x1)           -> 设置GPIO bit0为输出
    
    // 2. 配置定时器 (LOAD=50, 使能+自动重装)
    rom[4]  = 32'h100020B7;  // lui x1, 0x10002000
    rom[5]  = 32'h00408093;  // addi x1, x1, 0x004     -> LOAD地址
    rom[6]  = 32'h03200113;  // addi x2, x0, 50
    rom[7]  = 32'h0020A023;  // sw x2, 0(x1)           -> LOAD = 50
    
    rom[8]  = 32'h100020B7;  // lui x1, 0x10002000
    rom[9]  = 32'h00008093;  // addi x1, x1, 0x000     -> CTRL地址
    rom[10] = 32'h00300113;  // addi x2, x0, 3         -> bit0=1使能, bit1=1自动重装
    rom[11] = 32'h0020A023;  // sw x2, 0(x1)           -> 启动定时器
    
    // 3. 使能定时器中断 (IER)
    rom[12] = 32'h100020B7;  // lui x1, 0x10002000
    rom[13] = 32'h00C08093;  // addi x1, x1, 0x00C     -> IER地址
    rom[14] = 32'h00100113;  // addi x2, x0, 1
    rom[15] = 32'h0020A023;  // sw x2, 0(x1)           -> 使能中断
    
    // 4. 设置 mtvec = 0x100 (ISR地址)
    rom[16] = 32'h10000593;  // addi x11, x0, 0x100
    rom[17] = 32'h30559073;  // csrw mtvec, x11
    
    // 5. 使能全局中断 (mstatus.MIE=1)
    rom[18] = 32'h30046073;  // csrrsi x0, mstatus, 8
    
    // 6. 使能定时器中断 (mie.MTIE=1, bit7)
    rom[19] = 32'h000010B7;  // lui x1, 0x1
    rom[20] = 32'hF8008093;  // addi x1, x1, -128      -> x1 = 0x1000 - 128 = 0xF80? 不对
    // 修正：要得到 0x80 (128) 用于设置 bit7
    rom[19] = 32'h000010B7;  // lui x1, 0x1            -> x1 = 0x1000
    rom[20] = 32'hF8008093;  // addi x1, x1, -128      -> x1 = 0x1000 - 128 = 0xF80 (不对)
    // 正确方法：直接用 addi 从 0 开始
    rom[19] = 32'h08000593;  // addi x11, x0, 128      -> x11 = 128 (0x80, bit7)
    rom[20] = 32'h30459073;  // csrrs x0, mie, x11     -> 设置 mie[7]=1
    
    // 7. 主循环 (无限循环)
    rom[21] = 32'h0000006F;  // jal x0, 0

    // ========== 中断服务程序 (0x100, 索引 64) ==========
    
// 第一步：清除定时器中断标志（必须最先执行！）
rom[64] = 32'h100020B7;  // lui x1, 0x10002
rom[65] = 32'h00008093;  // addi x1, x1, 0x000
rom[66] = 32'h00400113;  // addi x2, x0, 4
rom[67] = 32'h0020A023;  // sw x2, 0(x1)           -> 清除 irq_flag

// 第二步：翻转 GPIO
rom[68] = 32'h100010B7;  // lui x1, 0x10001
rom[69] = 32'h00008093;  // addi x1, x1, 0x000
rom[70] = 32'h0001A283;  // lw x5, 0(x1)
rom[71] = 32'h00128293;  // addi x5, x5, 1
rom[72] = 32'h0050A023;  // sw x5, 0(x1)

// 第三步：中断返回
rom[73] = 32'h30200073;  // mret
end

always @(*) begin
    if (addr_i[31:2] <= 511) begin
        data_o = rom[addr_i[31:2]];
    end else begin
        data_o = 32'h00000013; // nop
    end
end

endmodule