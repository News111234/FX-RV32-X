// rtl/ifu/inst_rom.v - 测试GPIO输出延迟-结论：延迟只有一个周期
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
    
// rom[   0] = 32'h100010b7;  // lui x1, 0x10001000
// rom[   1] = 32'h00008093;  // addi x1, x1, 0
// rom[   2] = 32'h00100113;  // li x2, 1
// rom[   3] = 32'h0020a223;  // sw x2, 4(x1)
// rom[   4] = 32'h0020a023;  // sw x2, 0(x1)
// rom[   5] = 32'h0000a023;  // sw x0, 0(x1)
// rom[   6] = 32'h0020a023;  // sw x2, 0(x1)
// rom[   7] = 32'h0000a023;  // sw x0, 0(x1)
// rom[   8] = 32'h0020a023;  // sw x2, 0(x1)
// rom[   9] = 32'h0000a023;  // sw x0, 0(x1)
// rom[  10] = 32'h0020a023;  // sw x2, 0(x1)
// rom[  11] = 32'h0000a023;  // sw x0, 0(x1)
// rom[  12] = 32'h0020a023;  // sw x2, 0(x1)
// rom[  13] = 32'h0000a023;  // sw x0, 0(x1)

rom[   0] = 32'h100010b7;  // lui    x1, 0x10001000
rom[   1] = 32'h00100193;  // li     x3, 1
rom[   2] = 32'h0030a223;  // sw     x3, 4(x1)
rom[   3] = 32'hfff00113;  // addi   x2, x0, -1
rom[   4] = 32'h0020a023;  // sw     x2, 0(x1)
rom[   5] = 32'h0000a023;  // sw     x0, 0(x1)
rom[   6] = 32'h0020a023;  // sw     x2, 0(x1)
rom[   7] = 32'h0000a023;  // sw     x0, 0(x1)
rom[   8] = 32'h0020a023;  // sw     x2, 0(x1)
rom[   9] = 32'h0000a023;  // sw     x0, 0(x1)
rom[   10] = 32'h0020a023;  // sw     x2, 0(x1)
rom[   11] = 32'h0000a023;  // sw     x0, 0(x1)
rom[   12] = 32'h0020a023;  // sw     x2, 0(x1)
rom[   13] = 32'h0000a023;  // sw     x0, 0(x1)
rom[   14] = 32'h0020a023;  // sw     x2, 0(x1)
rom[   15] = 32'h0000a023;  // sw     x0, 0(x1)
rom[   16] = 32'h0020a023;  // sw     x2, 0(x1)
rom[   17] = 32'h0000a023;  // sw     x0, 0(x1)
rom[   18] = 32'h0020a023;  // sw     x2, 0(x1)
rom[   19] = 32'h0000a023;  // sw     x0, 0(x1)

end

always @(*) begin
    if (addr_i[31:2] <= 511) begin
        data_o = rom[addr_i[31:2]];
    end else begin
        data_o = 32'h00000013; // nop
    end
end

endmodule

// add wave -position end  sim:/tb_soc_top/u_soc_top/u_gpio/gpio_oe
// add wave -position end  sim:/tb_soc_top/u_soc_top/u_gpio/gpio_out
// add wave -position 1  sim:/tb_soc_top/u_soc_top/u_core/u_ifu_top/instr
// add wave -position 2  sim:/tb_soc_top/u_soc_top/u_core/u_ifu_top/pc
// add wave -position end  sim:/tb_soc_top/u_soc_top/u_core/u_id_top/u_regfile/registers