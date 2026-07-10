# bootloader.s — UART + SPI Flash 混合启动加载器 (v2: 使用 spi_flash_ctrl)
#
# Function: 上电后检测 UART 或 SPI Flash, 加载用户程序到 inst_bram 然后跳转
#
# Memory layout:
#   Bootloader:   inst_bram 0x000 - 0x1FF (2KB)
#   User program: inst_bram 0x200 - 0x1FFF (30KB)
#
# Address map:
#   UART:       0x1000_0000
#   INST_BRAM:  0x2000_0000 (bus window → write user program here)
#   SPI_FLASH:  0x3000_0000 (spi_flash_ctrl read window, 16MB)
#
#   Flash window details (spi_flash_ctrl handles SPI protocol in hardware):
#     lw 0x3000_0000 → Flash offset 0x01000000 + 0  (Magic Number)
#     lw 0x3000_0004 → Flash offset 0x01000000 + 4  (Program Size)
#     lw 0x3000_0008 → Flash offset 0x01000000 + 8  (Program data word 0)
#
# UART protocol (PC -> FPGA):
#   Byte 0-3: program size in words (big-endian)
#   Byte 4-N: program data (4 bytes per word, big-endian)
# ============================================================================

.equ UART_BASE,     0x10000000
.equ UART_STATUS,   0x10000004
.equ UART_CTRL,     0x10000008
.equ UART_RX_DATA,  0x10000010

.equ INST_BRAM,     0x20000200     # inst_bram bus window + 0x200 offset

.equ FLASH_BASE,    0x30000000     # spi_flash_ctrl read window
.equ MAGIC_NUM,     0x46585256     # "FXRV"

# ============================================================================
# _start: Bootloader entry point (address 0x000)
# ============================================================================
    .section .text
    .globl _start
_start:
    # ---------------------------------------------------------------
    # Step 1: Initialize UART — enable RX
    # ---------------------------------------------------------------
    lui  x1, 0x10000
    lw   x2, 8(x1)             # read UART_CTRL
    ori  x2, x2, 2             # bit1 = rx_enable
    sw   x2, 8(x1)             # write back

    # ---------------------------------------------------------------
    # Step 2: Poll UART RX for ~10ms
    # ---------------------------------------------------------------
    li   x3, 0                  # counter
    li   x4, 2000000            # timeout (~10ms @ 200MHz)
uart_poll:
    lw   x5, 4(x1)             # UART_STATUS
    andi x5, x5, 4             # bit2: rx_ready
    bne  x5, x0, uart_mode     # data available -> UART load
    addi x3, x3, 1
    blt  x3, x4, uart_poll
    j    flash_mode             # timeout -> SPI Flash load

# ============================================================================
# UART Loading Mode (开发调试用)
# ============================================================================
uart_mode:
    # Step U1: Receive program size (4 bytes -> x13)
    jal  ra, uart_rx_byte
    slli x13, x10, 24
    jal  ra, uart_rx_byte
    slli x14, x10, 16
    or   x13, x13, x14
    jal  ra, uart_rx_byte
    slli x14, x10, 8
    or   x13, x13, x14
    jal  ra, uart_rx_byte
    or   x13, x13, x10          # x13 = word count

    # Step U2: Loop receive words -> write to inst_bram
    li   x14, 0                  # received word counter
    lui  x15, 0x20000
    addi x15, x15, 0x200        # inst_bram target = 0x20000200
uart_load_loop:
    beq  x14, x13, done

    # Receive 4 bytes -> assemble word in x16
    jal  ra, uart_rx_byte
    slli x16, x10, 24
    jal  ra, uart_rx_byte
    slli x17, x10, 16
    or   x16, x16, x17
    jal  ra, uart_rx_byte
    slli x17, x10, 8
    or   x16, x16, x17
    jal  ra, uart_rx_byte
    or   x16, x16, x10

    sw   x16, 0(x15)            # write to inst_bram
    addi x15, x15, 4
    addi x14, x14, 1
    j    uart_load_loop

# ============================================================================
# SPI Flash Loading Mode (独立运行, spi_flash_ctrl 硬件处理 SPI 协议)
# ============================================================================
flash_mode:
    # ---------------------------------------------------------------
    # Flash 读窗口 0x3000_0000:
    #   lw 自动触发 spi_flash_ctrl 硬件状态机:
    #     CS低 → 发 0x03(READ) → 发 24-bit 地址 → 读 4 字节 → CS高
    #   每次 lw 耗时 ~1280 周期 (6.4μs @ 200MHz)
    # ---------------------------------------------------------------

    lui  x8, 0x30000            # x8 = FLASH_BASE

    # 读 Magic Number (offset 0x00)
    lw   x9, 0(x8)              # Flash word 0 → Magic Number
    li   x12, MAGIC_NUM
    bne  x9, x12, no_program    # magic mismatch -> fallback

    # 读程序大小 (offset 0x04)
    lw   x13, 4(x8)             # Flash word 1 → program size

    # 循环: 从 Flash 读 -> 写入 inst_bram
    li   x14, 0                  # word counter
    lui  x15, 0x20000
    addi x15, x15, 0x200        # inst_bram target
    addi x8, x8, 8              # x8 = 0x30000008 (program data start)
flash_load_loop:
    beq  x14, x13, done

    lw   x16, 0(x8)             # read word from Flash (hardware auto SPI)
    sw   x16, 0(x15)            # write to inst_bram
    addi x8, x8, 4              # next Flash word
    addi x15, x15, 4             # next inst_bram word
    addi x14, x14, 1
    j    flash_load_loop

no_program:
    # Flash 无有效程序 → 回到 UART 轮询模式
    lui  x1, 0x10000
    j    uart_poll

# ============================================================================
# Done: jump to user program at address 0x200
# ============================================================================
done:
    fence.i                      # instruction fence (NOP on FX-RV32)
    li   x1, 0x200              # absolute address of user program
    jalr x0, x1, 0              # jump to user program

# ============================================================================
# Subroutine: uart_rx_byte — receive one byte via UART
#   Blocks until rx_ready, returns byte in x10
#   Clobbers: x5, x6, x10
# ============================================================================
uart_rx_byte:
    lui  x5, 0x10000
uart_rx_wait:
    lw   x6, 4(x5)              # UART_STATUS
    andi x6, x6, 4              # bit2: rx_ready
    beq  x6, x0, uart_rx_wait   # wait until data available
    lw   x10, 16(x5)            # UART_RX_DATA (offset 0x10)
    ret
