# no_intr_test.s — Test store WITHOUT any interrupts
.section .text
.globl _start
_start:
    # Test 1: addi+sw back-to-back
    addi t0, x0, 0x42
    sw t0, 0x100(x0)

    # Test 2: li+sw (with NOP)
    li t1, 0xDEADBEEF
    nop
    sw t1, 0x104(x0)

    # Read back and verify
    lw t0, 0x100(x0)
    li t1, 0x42
    bne t0, t1, fail

    lw t0, 0x104(x0)
    li t1, 0xDEADBEEF
    bne t0, t1, fail

pass:
    sw zero, 0xFC(x0)
    j pass

fail:
    li t0, 1
    sw t0, 0xFC(x0)
    j fail
