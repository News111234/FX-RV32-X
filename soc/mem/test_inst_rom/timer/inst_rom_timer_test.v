// rtl/ifu/inst_rom_interrupt.v - 带中断测试的程序
`timescale 1ns/1ps

module inst_rom_hello (
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
    
    // ========== 定时器手动模式测试 ==========
    // 设置 LOAD = 50
    rom[0] = 32'h100020B7;  // lui x1, 0x10002        -> x1 = 0x10002000
    rom[1] = 32'h00408093;  // addi x1, x1, 0x004     -> x1 = TIMER_LOAD (0x04)
    rom[2] = 32'h03200113;  // addi x2, x0, 50        -> x2 = 50 (0x032)
    rom[3] = 32'h0020A023;  // sw x2, 0(x1)           -> 写 LOAD = 50

    // 设置 CTRL (enable=1, auto_reload=1)
    rom[4] = 32'h100020B7;  // lui x1, 0x10002
    rom[5] = 32'h00008093;  // addi x1, x1, 0x000     -> x1 = TIMER_CTRL (0x00)
    rom[6] = 32'h00300113;  // addi x2, x0, 3         -> x2 = 3 (bit0=1使能, bit1=1自动重装)
    rom[7] = 32'h0020A023;  // sw x2, 0(x1)           -> 写 CTRL

    // 循环读取 COUNT 寄存器
    rom[8]  = 32'h100020B7;  // lui x1, 0x10002
    rom[9]  = 32'h00808093;  // addi x1, x1, 0x008     -> x1 = TIMER_COUNT (0x08)
    rom[10] = 32'h0002A283;  // lw x5, 0(x1)           -> 读 COUNT 到 x5
rom[11] = 32'hFE9FFE6F;  // jal x0, -12            -> 跳回 rom[8] 循环
end

always @(*) begin
    if (addr_i[31:2] <= 511) begin
        data_o = rom[addr_i[31:2]];
    end else begin
        data_o = 32'h00000013; // nop
    end
end

endmodule