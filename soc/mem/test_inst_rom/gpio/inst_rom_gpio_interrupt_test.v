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
    //GPIO中断测试
   // ========== 主程序 (0x00 ~ 0x38) ==========
    rom[0]  = 32'h100010b7;  // lui x1, 0x10001000
    rom[1]  = 32'h00c08093;  // addi x1, x1, 0x00c
    rom[2]  = 32'h00100113;  // li x2, 1
    rom[3]  = 32'h0020a023;  // sw x2, 0(x1)

    rom[4]  = 32'h100010b7;  // lui x1, 0x10001000
    rom[5]  = 32'h01008093;  // addi x1, x1, 0x010
    rom[6]  = 32'h00100113;  // li x2, 1
    rom[7]  = 32'h0020a023;  // sw x2, 0(x1)

    rom[8]  = 32'h10000593;  // li x11, 0x100
    rom[9]  = 32'h30559073;  // csrw mtvec, x11

    rom[10] = 32'h30046073;  // csrrsi x0, mstatus, 8

    rom[11] = 32'h000010b7;  // lui x1, 0x1000
    rom[12] = 32'h80008093;  // addi x1, x1, -2048
    rom[13] = 32'h3040a073;  // csrrs x0, mie, x1

    rom[14] = 32'h0000006f;  // jal x0, loop

    // ========== 中断服务程序 (0x100, 索引 64) ==========
    rom[64] = 32'h100010b7;  // lui x1, 0x10001000
    rom[65] = 32'h01408093;  // addi x1, x1, 0x014
    rom[66] = 32'h00100113;  // li x2, 1
    rom[67] = 32'h0020a023;  // sw x2, 0(x1)

    rom[68] = 32'h100010b7;  // lui x1, 0x10001000
    rom[69] = 32'h00008093;  // addi x1, x1, 0x000
    rom[70] = 32'h0000a183;  // lw x3, 0(x1)
    rom[71] = 32'h0011c193;  // xori x3, x3, 1
    rom[72] = 32'h0030a023;  // sw x3, 0(x1)

    rom[73] = 32'h00000013;  // nop
rom[74] = 32'h00000013;  // nop
rom[75] = 32'h30200073;  // mret
end

always @(*) begin
    if (addr_i[31:2] <= 511) begin
        data_o = rom[addr_i[31:2]];
    end else begin
        data_o = 32'h00000013; // nop
    end
end

endmodule