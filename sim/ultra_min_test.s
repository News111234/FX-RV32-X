# ultra_min_test.s — Single addi+sw to check store data path
.section .text
.globl _start
_start:
    li sp, 0x400
    li t0, 0xAAAAAAAA
    sw t0, 0x100(x0)    # mem[64] = 0xAAAAAAAA
    sw zero, 0xFC(x0)

    # Setup Timer interrupt
    li t0, 0x201
    csrw mtvec, t0
    li t0, 0x080
    csrw mie, t0
    csrr t0, mstatus
    ori t0, t0, 8
    csrw mstatus, t0

    # Timer: LOAD=30, one-shot
    li t0, 0x10002000
    li t1, 30
    sw t1, 4(t0)
    li t1, 1
    sw t1, 0(t0)
    li t1, 1
    sw t1, 0xC(t0)

    # Wait loop
    li t3, 200
wait_lp:
    addi t3, t3, -1
    bnez t3, wait_lp

    # Check result
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
    addi t0, x0, 0x42    # single instruction: t0 = 0x42
    sw t0, 0x100(x0)     # store 0x42 to mem[64]
    li t0, 0x10002000
    li t1, 4
    sw t1, 0(t0)
    mret

.org 0x280
spin:
    j spin
