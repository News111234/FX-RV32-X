# minimal_blt_test.s — 最简 blt 测试
.section .text
.globl _start
_start:
    addi t0, x0, 0       # t0 = 0
    addi t1, x0, 1       # t1 = 1
    nop                   # 消除数据冒险
loop:
    blt t0, t1, loop      # 0 < 1, 应该一直跳转 (死循环在loop)
    addi t2, x0, 0x123    # 不应该执行到这儿
    sw t2, 0xFC(x0)       # 不应该执行
spin:
    j spin
