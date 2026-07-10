// rtl/ifu/inst_rom_interrupt.v - 带中断测试的程序
`timescale 1ns/1ps

module inst_rom (
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
    
    $display("=== Loading Interrupt Test Program ===");
    
 // 原乘法测试指令 (rom[0]~rom[4])
rom[0] = 32'h00a00513;  // li x10, 10
rom[1] = 32'h01400593;  // li x11, 20
rom[2] = 32'h02b50633;  // mul x12, x10, x11
rom[3] = 32'h02a5d6b3;  // div x13, x11, x10
rom[4] = 32'h02a5f733;  // rem x14, x11, x10

// GPIO 测试（修正版）
rom[5] = 32'h100010B7;  // lui x1, 0x10001      -> x1 = 0x10001000
rom[6] = 32'h00408093;  // addi x1, x1, 0x004   -> x1 = 0x10001004
rom[7] = 32'h00100113;  // addi x2, x0, 1
rom[8] = 32'h0020A023;  // sw x2, 0(x1)         -> 写 OE 寄存器

rom[9] = 32'h100010B7;  // lui x1, 0x10001      -> x1 = 0x10001000
rom[10]= 32'h00008093;  // addi x1, x1, 0       -> x1 = 0x10001000
rom[11]= 32'h0020A023;  // sw x2, 0(x1)         -> 写 OUT 寄存器
rom[12]= 32'h0000006F;  // jal x0, 0            -> 无限循环
    
    $display("Interrupt Test Program loaded successfully!");
    $display("- UART base: 0x10000000");
    $display("- MTVEC set to: 0x20000100");
    $display("- MIE bit 7 (MTIE) enabled");
    $display("- Global interrupt (MIE) enabled");
    $display("- Main loop: prints \"Hello World!\"");
    $display("- Interrupt handler: prints '*' when timer interrupt occurs");
end

always @(*) begin
    if (addr_i[31:2] <= 511) begin
        data_o = rom[addr_i[31:2]];
    end else begin
        data_o = 32'h00000013; // nop
    end
end

endmodule