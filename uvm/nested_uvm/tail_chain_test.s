# tail_chain_test.s — 尾链优化测试
# 场景: GPIO ISR执行MRET时Timer已pending, 跳过shadow_restore
# 测试方法: GPIO ISR末尾使能Timer(短LOAD), 然后MRET
# GPIO ISR内重新使能Timer(LOAD=10), MRET时Timer已pending
.section .text
.globl _start
_start:
    li sp, 0x400
    sw zero, 0x100(x0)   # mem[64]  tail_chain flag (1=hit)
    sw zero, 0x104(x0)   # mem[65]  timer_count (ISR执行次数)
    sw zero, 0x108(x0)   # mem[66]  gpio_count
    sw zero, 0x10C(x0)   # mem[67]  cycle: mcycle at GPIO entry
    sw zero, 0x110(x0)   # mem[68]  cycle: mcycle at Timer entry after TC
    sw zero, 0xFC(x0)    # tohost

    li t0, 0x201
    csrw mtvec, t0
    li t0, 0x880
    csrw mie, t0
    csrr t0, mstatus
    ori t0, t0, 8
    csrw mstatus, t0

    # GPIO: 输入模式, 上升沿触发
    li t0, 0x10001000
    li t1, 1
    sw t1, 0xC(t0)
    sw t1, 0x10(t0)

    # Timer: LOAD=80, one-shot, 先让Timer触发第一级ISR
    li t0, 0x10002000
    li t1, 80
    sw t1, 4(t0)
    li t1, 1
    sw t1, 0(t0)
    li t1, 1
    sw t1, 0xC(t0)

    # 等待 Timer + GPIO 都执行过
main_loop:
    lw t0, 0x108(x0)       # gpio_count
    li t1, 1
    bltu t0, t1, main_loop

    sw zero, 0xFC(x0)
spin:
    j spin

.org 0x200
    j spin
    j spin
    j spin
    j spin
    j spin
    j spin
    j spin
    j isr_timer     # 7
    j spin
    j spin
    j spin
    j isr_gpio      # 11
    j spin

isr_timer:
    # 递增 timer_count
    lw t0, 0x104(x0)
    addi t0, t0, 1
    sw t0, 0x104(x0)

    # 清除 Timer
    li t0, 0x10002000
    li t1, 4
    sw t1, 0(t0)

    # 记录 mcycle
    csrr t2, mcycle
    sw t2, 0x110(x0)

    mret

isr_gpio:
    # 递增 gpio_count
    lw t0, 0x108(x0)
    addi t0, t0, 1
    sw t0, 0x108(x0)

    # 记录 mcycle
    csrr t2, mcycle
    sw t2, 0x10C(x0)

    # 清除 GPIO
    li t0, 0x10001000
    li t1, 1
    sw t1, 0x14(t0)

    # ==== 尾链关键: MRET前使能Timer(LOAD=1, 极短) ====
    # MRET执行时Timer大概率已pending → tail_chain_detect=1
    li t0, 0x10002000
    li t1, 1
    sw t1, 4(t0)           # LOAD=1 → 下一周期即触发
    li t1, 1
    sw t1, 0(t0)           # 使能
    li t1, 1
    sw t1, 0xC(t0)         # IER

    # 写 tail_chain flag = 1 (GPIO ISR 已完成, 下面测试尾链)
    li t0, 1
    sw t0, 0x100(x0)

    mret     # ← 此时 Timer 已 pending, 尾链触发

spin:
    j spin
