# gpio_once.s — 单次 GPIO 中断: ISR 写 count=1, 主循环读count>=1就PASS
.section .text
.globl _start
_start:
    li sp, 0x400
    sw zero, 0x100(x0)              # count = 0
    li t0, 0x201; csrw mtvec, t0    # vectored mode, base=0x200
    li t0, 0x800; csrw mie, t0      # mie[11]=1
    csrr t0, mstatus; ori t0, t0, 8; csrw mstatus, t0  # MIE=1
    li t0, 0x10001000
    li t1, 1; sw t1, 0xC(t0); sw t1, 0x10(t0)           # GPIO IE+EDGE
main:
    lw t0, 0x100(x0)               # 读 count
    bnez t0, pass                  # count != 0 → PASS
    wfi
    j main
pass:
    sw zero, 0xFC(x0)              # tohost = 0
    j pass
fail:
    li t0, 1; sw t0, 0xFC(x0)      # tohost = 1
    j fail

.org 0x200
    j fail; j fail; j fail; j fail; j fail; j fail; j fail
    j isr   # ID=7
    j fail; j fail; j fail
    j isr   # ID=11

isr:
    li t0, 1; sw t0, 0x100(x0)     # count = 1
    li t0, 0x10001000; li t1, 1; sw t1, 0x14(t0)  # clear GPIO IF
    mret
