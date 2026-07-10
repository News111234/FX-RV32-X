// soc/mem/data_ram.v — 数据存储器 (单端口, 同步读写)
// 支持: SB/SH/SW, LB/LH/LW, LBU/LHU
//
// 功能概述:
//   单端口同步写、异步读数据存储器，实现 RV32I 架构要求的 load/store 访问。
//   支持字节 (SB)、半字 (SH)、字 (SW) 写入，以及有符号/无符号的字节 (LB/LBU)
//   和半字 (LH/LHU) 读取，字读取 (LW)。
//
// 关键特性:
//   - 容量: DATA_DEPTH × 32 位字, 默认 1024 字 = 4KB, 地址范围 0x0000_0000 ~ 0x0000_0FFC
//   - 写操作: 时钟同步, 支持部分字节/半字写入, 不改变同一字内其他字节
//   - 读操作: 组合逻辑输出, 根据 width_i 进行符号扩展或零扩展
//   - 就绪信号 ready_o 恒为 1, 表示读写操作在单周期内完成
//   - 复位只清除控制逻辑, 不改变内存数据 (内存数据由 initial 预置, 综合时忽略)
//
// 地址映射:
//   实际访问地址 = addr_i[31:0], 字地址 = addr_i[31:2]
//   当 (addr_i[31:2] < DATA_DEPTH) 时访问有效, 否则返回 0
//
// width_i 编码:
//   3'b000: SB / LB  / LBU
//   3'b001: SH / LH  / LHU
//   3'b010: SW / LW
//   3'b100: LBU (无符号字节加载)
//   3'b101: LHU (无符号半字加载)
//   其余值: 返回 0, 写忽略
//
// 使用注意:
//   - 地址对齐由上层模块 mem_ctrl 检查, 本模块不做判断
//   - 初始数据可修改 initial 块中的预置数据, 仅用于仿真
//   - FPGA 综合时 initial 块会被忽略, 内存初始值由实现工具决定 (通常为 0)
// ============================================================================
`timescale 1ns/1ps

module data_ram (
    // ========== 系统接口 ==========
    input  wire        clk_i,              // 时钟信号
    input  wire        rst_n_i,            // 复位信号 (低电平有效)

    // ========== 控制信号 ==========
    input  wire        we_i,               // 写使能
    input  wire        re_i,               // 读使能
    input  wire [2:0]  width_i,            // 访问宽度
    input  wire [31:0] addr_i,             // 访问地址
    input  wire [31:0] wdata_i,            // 写数据

    // ========== 输出端口 ==========
    output reg  [31:0] rdata_o,            // 读数据 (符号扩展或零扩展)
    output wire        ready_o             // 就绪信号 (始终为 1)
);

parameter DATA_DEPTH = 1024;               // 1024 × 32-bit words = 4KB
parameter ADDR_WIDTH = 8;

reg [31:0] mem [0:DATA_DEPTH-1];
integer i;

// ========== 初始化 RAM ==========
initial begin
    for (i = 0; i < DATA_DEPTH; i = i + 1) begin
        mem[i] = 32'h0;
    end
    // 可选预置测试数据
    mem[0] = 32'h12345678;
    mem[1] = 32'h87654321;
end

// ========== 写操作 (时序) ==========
always @(posedge clk_i) begin
    if (!rst_n_i) begin
        // 复位时不做操作 (initial 已完成初始化, FPGA 综合时 initial 被忽略)
    end else if (we_i && (addr_i[31:2] < DATA_DEPTH)) begin
        case (width_i)
            3'b000: begin // SB — 字节写
                case (addr_i[1:0])
                    2'b00: mem[addr_i[31:2]][7:0]   <= wdata_i[7:0];
                    2'b01: mem[addr_i[31:2]][15:8]  <= wdata_i[7:0];
                    2'b10: mem[addr_i[31:2]][23:16] <= wdata_i[7:0];
                    2'b11: mem[addr_i[31:2]][31:24] <= wdata_i[7:0];
                endcase
            end

            3'b001: begin // SH — 半字写
                case (addr_i[1])
                    1'b0: mem[addr_i[31:2]][15:0]  <= wdata_i[15:0];
                    1'b1: mem[addr_i[31:2]][31:16] <= wdata_i[15:0];
                endcase
            end

            3'b010: begin // SW — 字写
                mem[addr_i[31:2]] <= wdata_i;
            end

            default: ;      // 无效宽度，忽略
        endcase
    end
end

// ========== 读操作 (组合逻辑) ==========
always @(*) begin
    if (re_i && (addr_i[31:2] < DATA_DEPTH)) begin
        case (width_i)
            // 有符号加载
            3'b000: begin // LB — 有符号字节加载
                case (addr_i[1:0])
                    2'b00: rdata_o = {{24{mem[addr_i[31:2]][7]}},  mem[addr_i[31:2]][7:0]};
                    2'b01: rdata_o = {{24{mem[addr_i[31:2]][15]}}, mem[addr_i[31:2]][15:8]};
                    2'b10: rdata_o = {{24{mem[addr_i[31:2]][23]}}, mem[addr_i[31:2]][23:16]};
                    2'b11: rdata_o = {{24{mem[addr_i[31:2]][31]}}, mem[addr_i[31:2]][31:24]};
                endcase
            end

            3'b001: begin // LH — 有符号半字加载
                case (addr_i[1])
                    1'b0: rdata_o = {{16{mem[addr_i[31:2]][15]}}, mem[addr_i[31:2]][15:0]};
                    1'b1: rdata_o = {{16{mem[addr_i[31:2]][31]}}, mem[addr_i[31:2]][31:16]};
                endcase
            end

            3'b010: begin // LW — 字加载
                rdata_o = mem[addr_i[31:2]];
            end

            // 无符号加载
            3'b100: begin // LBU — 无符号字节加载
                case (addr_i[1:0])
                    2'b00: rdata_o = {24'b0, mem[addr_i[31:2]][7:0]};
                    2'b01: rdata_o = {24'b0, mem[addr_i[31:2]][15:8]};
                    2'b10: rdata_o = {24'b0, mem[addr_i[31:2]][23:16]};
                    2'b11: rdata_o = {24'b0, mem[addr_i[31:2]][31:24]};
                endcase
            end

            3'b101: begin // LHU — 无符号半字加载
                case (addr_i[1])
                    1'b0: rdata_o = {16'b0, mem[addr_i[31:2]][15:0]};
                    1'b1: rdata_o = {16'b0, mem[addr_i[31:2]][31:16]};
                endcase
            end

            default: rdata_o = 32'b0;
        endcase
    end else begin
        rdata_o = 32'b0;
    end
end

assign ready_o = 1'b1;

endmodule
