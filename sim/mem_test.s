# mem_test.s — 最简内存读写测试
.section .text
.globl _start
_start:
    li t0, 0x12345678
    sw t0, 0x100(x0)           # 写 data_ram[64] = 0x12345678
    lw t1, 0x100(x0)           # 读回
    li t2, 0x12345678
    bne t1, t2, fail           # 不匹配 → FAIL
    sw zero, 0xFC(x0)          # PASS
spin:
    j spin
fail:
    li t0, 1
    sw t0, 0xFC(x0)
    j fail
