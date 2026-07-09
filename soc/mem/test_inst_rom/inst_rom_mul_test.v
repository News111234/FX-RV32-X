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
    
 rom[0] = 32'h00a00513;  // li x10, 10
rom[1] = 32'h01400593;  // li x11, 20
rom[2] = 32'h02b50633;  // mul x12, x10, x11  结果应该是 200
rom[3] = 32'h02a5d6b3;  // div x13, x11, x10  结果应该是 2
rom[4] = 32'h02a5f733;  // rem x14, x11, x10  结果应该是 0
end

always @(*) begin
    if (addr_i[31:2] <= 511) begin
        data_o = rom[addr_i[31:2]];
    end else begin
        data_o = 32'h00000013; // nop
    end
end

endmodule