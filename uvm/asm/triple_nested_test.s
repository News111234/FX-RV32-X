# triple_nested_test.s — 三级嵌套中断 (SW→Timer→GPIO)
# ISR代码放在.org之前确保地址正确
.section .text
.globl _start
_start:
    li sp, 0x400
    sw zero, 0x100(x0)   # mem[64]  sw marker
    sw zero, 0x104(x0)   # mem[65]  timer marker
    sw zero, 0x108(x0)   # mem[66]  gpio marker
    sw zero, 0x10C(x0)   # mem[67]  sw_preempted
    sw zero, 0x110(x0)   # mem[68]  timer_preempted
    sw zero, 0xFC(x0)    # tohost

    li t0, 0x201
    csrw mtvec, t0
    li t0, 0x888          # mie[11]+mie[7]+mie[3]
    csrw mie, t0
    csrr t0, mstatus
    ori t0, t0, 8
    csrw mstatus, t0

    # GPIO: 输入模式, 上升沿触发
    li t0, 0x10001000
    li t1, 1
    sw t1, 0xC(t0)
    sw t1, 0x10(t0)

    # Timer: LOAD=200, one-shot
    li t0, 0x10002000
    li t1, 200
    sw t1, 4(t0)
    li t1, 1
    sw t1, 0(t0)
    li t1, 1
    sw t1, 0xC(t0)

main_loop:
    lw t0, 0x108(x0)       # gpio marker
    li t1, 1
    nop
    bltu t0, t1, main_loop
    sw zero, 0xFC(x0)
spin:
    j spin

# ISR 代码 (在.org之前, 确保地址正确)
isr_sw:
    li t0, 0xCAFE0003
    sw t0, 0x100(x0)       # sw marker
    li t0, 1
    sw t0, 0x10C(x0)       # sw_preempted=1
    csrr t0, mstatus
    ori t0, t0, 8
    csrw mstatus, t0        # 重开MIE
    li t3, 40
sw_delay:
    addi t3, t3, -1
    bnez t3, sw_delay
    sw zero, 0x10C(x0)
    mret

isr_timer:
    li t0, 0xDEAD0007
    sw t0, 0x104(x0)       # timer marker
    li t0, 1
    sw t0, 0x110(x0)       # timer_preempted=1
    li t0, 0x10002000
    li t1, 4
    sw t1, 0(t0)            # clear Timer
    csrr t0, mstatus
    ori t0, t0, 8
    csrw mstatus, t0        # 重开MIE
    li t3, 20
timer_delay:
    addi t3, t3, -1
    bnez t3, timer_delay
    sw zero, 0x110(x0)
    mret

isr_gpio:
    li t0, 0xBEEF000B
    sw t0, 0x108(x0)       # gpio marker
    li t0, 0x10001000
    li t1, 1
    sw t1, 0x14(t0)        # clear GPIO
    mret

# 向量表
.org 0x200
    j spin       # 0
    j spin       # 1
    j spin       # 2
    j isr_sw     # 3  MSI (SW)
    j spin       # 4
    j spin       # 5
    j spin       # 6
    j isr_timer  # 7  MTI (Timer)
    j spin       # 8
    j spin       # 9
    j spin       # 10
    j isr_gpio   # 11 MEI (GPIO)
    j spin       # 12
    j spin       # 13
