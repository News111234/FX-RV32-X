# alt_isr_test.s — ISR at alternative location, use direct mode (not vectored)
.section .text
.globl _start
_start:
    li sp, 0x400
    li t0, 0xAAAAAAAA
    sw t0, 0x100(x0)
    sw zero, 0xFC(x0)

    # Direct mode: mtvec base = isr_timer address
    la t0, isr_timer
    csrw mtvec, t0
    li t0, 0x080
    csrw mie, t0
    csrr t0, mstatus
    ori t0, t0, 8
    csrw mstatus, t0

    # Timer setup
    li t0, 0x10002000
    li t1, 30
    sw t1, 4(t0)
    li t1, 1
    sw t1, 0(t0)
    li t1, 1
    sw t1, 0xC(t0)

    # Wait
    li t3, 200
wait_lp:
    addi t3, t3, -1
    bnez t3, wait_lp

    # Check
    lw t0, 0x100(x0)
    li t1, 0x42
    beq t0, t1, pass
fail:
    li t0, 1
    sw t0, 0xFC(x0)
    j fail
pass:
    sw zero, 0xFC(x0)
    j pass

# ISR at a completely different location (not near vector table)
.org 0x400
isr_timer:
    addi t0, x0, 0x42
    sw t0, 0x100(x0)
    li t0, 0x10002000
    li t1, 4
    sw t1, 0(t0)
    mret
