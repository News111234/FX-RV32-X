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
    
   // GPIO 输入测试程序
rom[0] = 32'h100010B7;  // lui x1, 0x10001
rom[1] = 32'h00808093;  // addi x1, x1, 0x008
rom[2] = 32'h00008183;  // lw x3, 0(x1)
rom[3] =32'hffdff06f;  // 真.jal x0, -4 
end

always @(*) begin
    if (addr_i[31:2] <= 511) begin
        data_o = rom[addr_i[31:2]];
    end else begin
        data_o = 32'h00000013; // nop
    end
end

endmodule