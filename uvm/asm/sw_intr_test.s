# sw_intr_test.s — 软件中断最小测试
# 避免.org, 手动用jump链到ISR
.section .text
.globl _start
_start:
    li sp, 0x400
    sw zero, 0x100(x0)
    sw zero, 0xFC(x0)

    li t0, 0x201
    csrw mtvec, t0
    li t0, 0x8            # mie[3]=1
    csrw mie, t0
    csrr t0, mstatus
    ori t0, t0, 8
    csrw mstatus, t0

main_loop:
    lw t0, 0x100(x0)
    li t1, 1
    nop
    bltu t0, t1, main_loop
    sw zero, 0xFC(x0)
    j spin

# ISR代码放在前面, 确保地址正确
isr_sw:
    li t0, 0xCAFE0003
    sw t0, 0x100(x0)
    mret

spin:
    j spin

# 向量表 (0x200)
.org 0x200
    j spin       # 0
    j spin       # 1
    j spin       # 2
    j isr_sw     # 3 MSI
    j spin       # 4
    j spin       # 5
    j spin       # 6
    j spin       # 7
    j spin       # 8
    j spin       # 9
    j spin       # 10
    j spin       # 11
