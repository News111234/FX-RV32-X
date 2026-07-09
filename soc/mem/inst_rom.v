// soc/mem/inst_rom.v — 指令 ROM (组合读, 零延迟)
//
// 程序加载: 由 testbench 在 time=0 通过层次化后门写入加载到 rom[] 数组。
// 不设 initial NOP 填充——避免与 testbench 后门写入的执行顺序冲突。
// 仿真中 ROM 输出在 testbench 写入后立即生效, CPU 复位释放前数据已就绪。
`timescale 1ns/1ps
(* DONT_TOUCH = "true" *)
module inst_rom #(
    parameter INST_DEPTH = 4096           // 4096 × 32-bit words = 16KB
) (
    input  wire [31:0] addr_i,           // PC 地址 (字节地址)
    output wire [31:0] data_o             // 组合逻辑输出 (零延迟)
);

reg [31:0] rom [0:INST_DEPTH-1];

// 组合读 — 零延迟, 地址变化立即反映到输出
assign data_o = (addr_i[31:2] < INST_DEPTH) ? rom[addr_i[31:2]] : 32'h00000013;

endmodule
