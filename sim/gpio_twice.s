# gpio_twice.s — 两次 GPIO 中断计数
.section .text
.globl _start
_start:
    li sp, 0x400; sw zero, 0x100(x0)
    li t0, 0x201; csrw mtvec, t0
    li t0, 0x800; csrw mie, t0
    csrr t0, mstatus; ori t0, t0, 8; csrw mstatus, t0
    li t0, 0x10001000; li t1, 1; sw t1, 0xC(t0); sw t1, 0x10(t0)
main:
    lw t0, 0x100(x0)
    li t1, 2
    blt t0, t1, main               # count < 2 → 继续等
    sw zero, 0xFC(x0)              # count >= 2 → PASS
    j .

.org 0x200
    j .; j .; j .; j .; j .; j .; j .
    j isr; j .; j .; j .; j isr

isr:
    lw t0, 0x100(x0)
    addi t0, t0, 1
    sw t0, 0x100(x0)
    li t0, 0x10001000; li t1, 1; sw t1, 0x14(t0)
    mret
