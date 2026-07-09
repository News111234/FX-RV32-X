# context_integrity_test.s — 嵌套中断后寄存器完整性验证
# 验证: 两级嵌套(Timer→GPIO)返回后, x1-x31 全部恢复
.section .text
.globl _start
_start:
    li sp, 0x400
    sw zero, 0x100(x0)   # mem[64]  timer marker
    sw zero, 0x104(x0)   # mem[65]  gpio marker
    sw zero, 0x108(x0)   # mem[66]  preempted flag
    sw zero, 0xFC(x0)    # tohost

    # 预加载 x1-x31 为已知值: x1=1, x2=2, ..., x31=31
    li x1, 1
    li x2, 2
    li x3, 3
    li x4, 4
    li x5, 5
    li x6, 6
    li x7, 7
    li x8, 8
    li x9, 9
    li x10, 10
    li x11, 11
    li x12, 12
    li x13, 13
    li x14, 14
    li x15, 15
    li x16, 16
    li x17, 17
    li x18, 18
    li x19, 19
    li x20, 20
    li x21, 21
    li x22, 22
    li x23, 23
    li x24, 24
    li x25, 25
    li x26, 26
    li x27, 27
    li x28, 28
    li x29, 29
    li x30, 30
    li x31, 31

    # 配置 mtvec + 使能中断
    li t0, 0x201
    csrw mtvec, t0
    li t0, 0x880          # mie[11]=1 (GPIO), mie[7]=1 (Timer)
    csrw mie, t0
    csrr t0, mstatus
    ori t0, t0, 8
    csrw mstatus, t0

    # GPIO: 输入模式, 上升沿触发, pin0中断使能
    li t0, 0x10001000
    li t1, 1
    sw t1, 0xC(t0)        # IE=1 (中断使能)
    sw t1, 0x10(t0)        # EDGE=1 (上升沿触发)

    # Timer: LOAD=200, one-shot, 使能中断
    li t0, 0x10002000
    li t1, 200
    sw t1, 4(t0)           # LOAD
    li t1, 1
    sw t1, 0(t0)           # enable
    li t1, 1
    sw t1, 0xC(t0)         # IER=1

main_loop:
    lw t0, 0x104(x0)       # gpio_count
    li t1, 1
    nop
    bltu t0, t1, main_loop

    # ==========================================
    # 嵌套中断已返回, 验证 x1-x31 全部恢复
    # ==========================================
    li t0, 1
    bne x1, t0, fail
    li t0, 2
    bne x2, t0, fail
    li t0, 3
    bne x3, t0, fail
    li t0, 4
    bne x4, t0, fail
    li t0, 5
    bne x5, t0, fail
    li t0, 6
    bne x6, t0, fail
    li t0, 7
    bne x7, t0, fail
    li t0, 8
    bne x8, t0, fail
    li t0, 9
    bne x9, t0, fail
    li t0, 10
    bne x10, t0, fail
    li t0, 11
    bne x11, t0, fail
    li t0, 12
    bne x12, t0, fail
    li t0, 13
    bne x13, t0, fail
    li t0, 14
    bne x14, t0, fail
    li t0, 15
    bne x15, t0, fail
    li t0, 16
    bne x16, t0, fail
    li t0, 17
    bne x17, t0, fail
    li t0, 18
    bne x18, t0, fail
    li t0, 19
    bne x19, t0, fail
    li t0, 20
    bne x20, t0, fail
    li t0, 21
    bne x21, t0, fail
    li t0, 22
    bne x22, t0, fail
    li t0, 23
    bne x23, t0, fail
    li t0, 24
    bne x24, t0, fail
    li t0, 25
    bne x25, t0, fail
    li t0, 26
    bne x26, t0, fail
    li t0, 27
    bne x27, t0, fail
    li t0, 28
    bne x28, t0, fail
    li t0, 29
    bne x29, t0, fail
    li t0, 30
    bne x30, t0, fail
    li t0, 31
    bne x31, t0, fail

    # 全部通过
    sw zero, 0xFC(x0)
spin_pass:
    j spin_pass

fail:
    li t0, 1
    sw t0, 0xFC(x0)
spin_fail:
    j spin_fail

.org 0x200
    j spin          # 0
    j spin          # 1
    j spin          # 2
    j spin          # 3
    j spin          # 4
    j spin          # 5
    j spin          # 6
    j isr_timer     # 7  Timer
    j spin          # 8
    j spin          # 9
    j spin          # 10
    j isr_gpio      # 11 GPIO
    j spin          # 12
    j spin          # 13

isr_timer:
    # 篡改部分寄存器再恢复, 验证 shadow 能保护原值
    li t0, 0xDEAD0001
    sw t0, 0x100(x0)       # timer marker
    li t0, 1
    sw t0, 0x108(x0)       # preempted=1

    # 清除 Timer 中断
    li t0, 0x10002000
    li t1, 4
    sw t1, 0(t0)           # CTRL=4: clear_irq + disable

    # 重开 MIE 允许 GPIO 嵌套
    csrr t0, mstatus
    ori t0, t0, 8
    csrw mstatus, t0

    # 篡改 x1-x5 为错误值, 验证 shadow_restore 能恢复
    li x1, 0xAA
    li x2, 0xBB
    li x3, 0xCC
    li x4, 0xDD
    li x5, 0xEE

    li t3, 20
timer_delay:
    addi t3, t3, -1
    bnez t3, timer_delay
    sw zero, 0x108(x0)     # preempted=0
    mret

isr_gpio:
    li t0, 0xBEEF0001
    sw t0, 0x104(x0)       # gpio marker

    # 清除 GPIO 中断
    li t0, 0x10001000
    li t1, 1
    sw t1, 0x14(t0)        # IF=1 (clear)

    # 篡改 x6-x10
    li x6, 0x11
    li x7, 0x22
    li x8, 0x33
    li x9, 0x44
    li x10, 0x55
    mret

spin:
    j spin
