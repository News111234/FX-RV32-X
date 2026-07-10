# single_intr_test.s — Single interrupt test (Timer only, no nesting)
.section .text
.globl _start
_start:
    li sp, 0x400
    sw zero, 0x100(x0)    # result = 0
    sw zero, 0xFC(x0)     # tohost = 0 (will be overwritten on PASS)

    # Setup vectored interrupt mode, base=0x200
    li t0, 0x201
    csrw mtvec, t0
    # Enable Timer interrupt only
    li t0, 0x080
    csrw mie, t0
    csrr t0, mstatus
    ori t0, t0, 8
    csrw mstatus, t0

    # Timer: LOAD=100, enable
    li t0, 0x10002000
    li t1, 100
    sw t1, 4(t0)
    li t1, 1
    sw t1, 0(t0)
    li t1, 1
    sw t1, 0xC(t0)

main_loop:
    lw t0, 0x100(x0)
    li t1, 1
    nop
    bltu t0, t1, main_loop
    # result >= 1 → PASS
    sw zero, 0xFC(x0)
spin:
    j spin

.org 0x200
    j spin
    j spin
    j spin
    j spin
    j spin
    j spin
    j spin
    j isr_timer

isr_timer:
    # Write marker 0xDEAD0001 to result
    li t0, 0xDEAD0001
    sw t0, 0x100(x0)
    # Clear Timer interrupt
    li t0, 0x10002000
    li t1, 4
    sw t1, 0(t0)
    mret
