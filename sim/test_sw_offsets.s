.section .text
.globl _start
_start:
    sw zero, 0x100(x0)
    sw zero, 0x104(x0)
    sw zero, 0x108(x0)
    sw zero, 0x10C(x0)
