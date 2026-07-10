# minimal_isr_test.s — Minimal test: does ISR store work?
.section .text
.globl _start
_start:
    li sp, 0x400
    # Initialize memory markers
    li t0, 0xAAAAAAAA
    sw t0, 0x100(x0)    # mem[64] = 0xAAAAAAAA (detect if store works)
    sw zero, 0xFC(x0)   # tohost = 0

    # Setup vectored mode, base=0x200
    li t0, 0x201
    csrw mtvec, t0
    li t0, 0x080         # MTI only
    csrw mie, t0
    csrr t0, mstatus
    ori t0, t0, 8
    csrw mstatus, t0

    # Timer: LOAD=50, one-shot
    li t0, 0x10002000
    li t1, 50
    sw t1, 4(t0)
    li t1, 1
    sw t1, 0(t0)
    li t1, 1
    sw t1, 0xC(t0)

    # Wait for timer interrupt and check result
    nop
    nop
    nop
    nop
    nop

check:
    lw t0, 0x100(x0)
    # If ISR ran, result should be 0xDEADBEEF
    li t1, 0xDEADBEEF
    nop
    beq t0, t1, pass
    j check

pass:
    sw zero, 0xFC(x0)
    j pass

.org 0x200
    j spin
    j spin
    j spin
    j spin
    j spin
    j spin
    j spin
    j isr_timer

.org 0x220
isr_timer:
    li t0, 0xDEADBEEF
    nop
    nop
    nop
    sw t0, 0x100(x0)
    # Clear timer
    li t0, 0x10002000
    li t1, 4
    sw t1, 0(t0)
    mret

.org 0x280
spin:
    j spin
