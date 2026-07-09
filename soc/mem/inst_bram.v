// soc/mem/inst_bram.v — 真双端口指令 Block RAM
//
// 功能: 替换 inst_rom.v, 同时支持 CPU 取指和总线写入
//   Port A: CPU 取指 (只读, 同步读) — 直接映射到 if_pc
//   Port B: 总线接口 (读写, 同步读) — bootloader 通过此端口写程序
//
// 内存布局 (32KB = 8192 × 32-bit):
//   0x000 - 0x1FF (512 words = 2KB): Bootloader (固化在 initial 块, 写保护)
//   0x200 - 0x1FFF (7680 words = 30KB): 用户程序区 (bootloader 加载目标)
//
// 总线地址映射:
//   总线地址 0x2000_0000 → inst_bram 内部地址 0x000
//   总线地址 0x2000_0200 → inst_bram 内部地址 0x200
// ============================================================================
`timescale 1ns/1ps

module inst_bram #(
    parameter INST_DEPTH = 8192             // 8192 × 32-bit = 32KB
) (
    // ===== Port A: CPU 取指 =====
    input  wire        clk_i,
    input  wire [31:0] if_addr_i,           // CPU 的 if_pc
    output reg  [31:0] if_instr_o,          // 送到 CPU 的指令

    // ===== Port B: 总线接口 =====
    input  wire        bus_we_i,            // 写使能
    input  wire        bus_re_i,            // 读使能
    input  wire [31:0] bus_addr_i,          // 总线地址 (0x2000_0000 起始)
    input  wire [31:0] bus_wdata_i,         // 写数据
    output reg  [31:0] bus_rdata_o,         // 读数据
    output wire        bus_ready_o
);

    (* ram_style = "block" *) reg [31:0] mem [0:INST_DEPTH-1];

    integer i;

    // ========================================================================
    // Bootloader 固化在低 2KB (0x000 - 0x1FF)
    //
    // 汇编: python/bootloader.s → python/riscv_asm7.py → 机器码
    // 使用 python/rom_output/gen_rom.py 生成 rom[i] = 32'hXXXX; 格式
    // ========================================================================
    initial begin
        // 默认全部填充 NOP
        for (i = 0; i < INST_DEPTH; i = i + 1) begin
            mem[i] = 32'h00000013;          // addi x0, x0, 0 = NOP
        end

        // ============================================================
        // Bootloader (68 instructions, 272 bytes)
        // 汇编: python/bootloader.s → riscv_asm7.py (start addr 0)
        // v2: Flash 读取使用 spi_flash_ctrl 硬件控制器 (lw 0x3000_XXXX)
        // ============================================================

        // --- init UART RX enable ---
        mem[ 0] = 32'h000100b7;  // lui  x1, 0x10000
        mem[ 1] = 32'h0080a103;  // lw   x2, 8(x1)
        mem[ 2] = 32'h00216113;  // ori  x2, x2, 2
        mem[ 3] = 32'h0020a423;  // sw   x2, 8(x1)

        // --- poll UART RX ~10ms timeout ---
        mem[ 4] = 32'h00000193;  // li   x3, 0
        mem[ 5] = 32'h001e8237;  // lui  x4, 0x1e8
        mem[ 6] = 32'h48020213;  // addi x4, x4, 0x480
        mem[ 7] = 32'h0040a283;  // lw   x5, 4(x1)       ; uart_poll:
        mem[ 8] = 32'h0042f293;  // andi x5, x5, 4
        mem[ 9] = 32'h00029663;  // bne  x5, x0, uart_mode
        mem[10] = 32'h00118193;  // addi x3, x3, 1
        mem[11] = 32'hfe41c6e3;  // blt  x3, x4, uart_poll
        mem[12] = 32'h0700006f;  // j    flash_mode

        // --- UART mode: recv size (4 bytes -> x13) ---
        mem[13] = 32'h0c0000ef;  // jal  ra, uart_rx_byte  ; uart_mode:
        mem[14] = 32'h01851693;  // slli x13, x10, 24
        mem[15] = 32'h0b8000ef;  // jal  ra, uart_rx_byte
        mem[16] = 32'h01051713;  // slli x14, x10, 16
        mem[17] = 32'h00e6e6b3;  // or   x13, x13, x14
        mem[18] = 32'h0ac000ef;  // jal  ra, uart_rx_byte
        mem[19] = 32'h00851713;  // slli x14, x10, 8
        mem[20] = 32'h00e6e6b3;  // or   x13, x13, x14
        mem[21] = 32'h0a0000ef;  // jal  ra, uart_rx_byte
        mem[22] = 32'h00a6e6b3;  // or   x13, x13, x10

        // --- UART mode: loop recv words -> sw to inst_bram ---
        mem[23] = 32'h00000713;  // li   x14, 0
        mem[24] = 32'h000207b7;  // lui  x15, 0x20000
        mem[25] = 32'h20078793;  // addi x15, x15, 0x200
        mem[26] = 32'h08d70063;  // beq  x14, x13, done    ; uart_load_loop:
        mem[27] = 32'h088000ef;  // jal  ra, uart_rx_byte
        mem[28] = 32'h01851813;  // slli x16, x10, 24
        mem[29] = 32'h080000ef;  // jal  ra, uart_rx_byte
        mem[30] = 32'h01051893;  // slli x17, x10, 16
        mem[31] = 32'h01186833;  // or   x16, x16, x17
        mem[32] = 32'h074000ef;  // jal  ra, uart_rx_byte
        mem[33] = 32'h00851893;  // slli x17, x10, 8
        mem[34] = 32'h01186833;  // or   x16, x16, x17
        mem[35] = 32'h068000ef;  // jal  ra, uart_rx_byte
        mem[36] = 32'h00a86833;  // or   x16, x16, x10
        mem[37] = 32'h0107a023;  // sw   x16, 0(x15)
        mem[38] = 32'h00478793;  // addi x15, x15, 4
        mem[39] = 32'h00170713;  // addi x14, x14, 1
        mem[40] = 32'hfc5ff06f;  // j    uart_load_loop

        // --- Flash mode: lw from 0x3000_0000 (spi_flash_ctrl handles SPI) ---
        mem[41] = 32'h00030437;  // lui  x8, 0x30000       ; flash_mode:
        mem[42] = 32'h00042483;  // lw   x9, 0(x8)         ; read Magic
        mem[43] = 32'h46585637;  // lui  x12, 0x46585
        mem[44] = 32'h25660613;  // addi x12, x12, 0x256
        mem[45] = 32'h02c49663;  // bne  x9, x12, no_program
        mem[46] = 32'h00442683;  // lw   x13, 4(x8)        ; read size
        mem[47] = 32'h00000713;  // li   x14, 0
        mem[48] = 32'h000207b7;  // lui  x15, 0x20000
        mem[49] = 32'h20078793;  // addi x15, x15, 0x200
        mem[50] = 32'h00840413;  // addi x8, x8, 8          ; x8 = &prog[0]
        mem[51] = 32'h00d70e63;  // beq  x14, x13, done    ; flash_load_loop:
        mem[52] = 32'h00042803;  // lw   x16, 0(x8)        ; read word
        mem[53] = 32'h0107a023;  // sw   x16, 0(x15)       ; write inst_bram
        mem[54] = 32'h00440413;  // addi x8, x8, 4
        mem[55] = 32'h00478793;  // addi x15, x15, 4
        mem[56] = 32'h00170713;  // addi x14, x14, 1
        mem[57] = 32'hfe1ff06f;  // j    flash_load_loop

        // --- no_program: fallback to UART ---
        mem[58] = 32'h000100b7;  // lui  x1, 0x10000       ; no_program:
        mem[59] = 32'hf2dff06f;  // j    uart_poll

        // --- done: jump to user program at 0x200 ---
        mem[60] = 32'h20000093;  // li   x1, 0x200         ; done:
        mem[61] = 32'h00008067;  // jalr x0, x1, 0

        // ============================================================
        // Subroutine: uart_rx_byte (x10 = received byte)
        // ============================================================
        mem[62] = 32'h000102b7;  // lui  x5, 0x10000       ; uart_rx_byte:
        mem[63] = 32'h0042a303;  // lw   x6, 4(x5)         ; uart_rx_wait:
        mem[64] = 32'h00437313;  // andi x6, x6, 4
        mem[65] = 32'hfe030ae3;  // beq  x6, x0, uart_rx_wait
        mem[66] = 32'h0102a503;  // lw   x10, 16(x5)
        mem[67] = 32'h00008067;  // ret
    end

    // ========================================================================
    // Port A: CPU 取指 (同步读)
    // ========================================================================
    always @(posedge clk_i) begin
        if (if_addr_i[31:2] < INST_DEPTH)
            if_instr_o <= mem[if_addr_i[31:2]];
        else
            if_instr_o <= 32'h00000013;     // 超范围返回 NOP
    end

    // ========================================================================
    // Port B: 总线读写 (同步读)
    //
    // 写保护: 总线地址 < 0x200 的写操作被忽略 (保护 bootloader 区域)
    // bus_addr_i 是 inst_bram 内部地址 (已在 bus_arbiter 中减去基址)
    // ========================================================================
    always @(posedge clk_i) begin
        // 写保护: 字地址 0-511 (低 2KB) 为 bootloader 区域, 禁止总线写入
        // bus_addr_i 是内部地址 (已在 bus_arbiter 中减去 INST_BRAM_BASE)
        if (bus_we_i && (bus_addr_i[31:2] < INST_DEPTH) && (bus_addr_i[31:2] >= 12'd512))
            mem[bus_addr_i[31:2]] <= bus_wdata_i;
    end

    always @(posedge clk_i) begin
        if (bus_re_i && (bus_addr_i[31:2] < INST_DEPTH))
            bus_rdata_o <= mem[bus_addr_i[31:2]];
        else
            bus_rdata_o <= 32'h0;
    end

    assign bus_ready_o = 1'b1;

endmodule
