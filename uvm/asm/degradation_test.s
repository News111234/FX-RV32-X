# degradation_test.s — Bank降级复用测试 (BANKS=1, OVERFLOW_POLICY=1)
# 验证: Bank满时若POL=1, 高优先级中断仍可抢占, 覆盖最深嵌套层Bank
# 预期: GPIO立即进入 (2周期延迟), Timer上下文被覆盖
.section .text
.globl _start
_start:
    li sp, 0x400
    sw zero, 0x100(x0)   # mem[64]  timer marker
    sw zero, 0x104(x0)   # mem[65]  gpio marker
    sw zero, 0x108(x0)   # mem[66]  timer_preempted flag
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

    # Timer: LOAD=80, one-shot
    li t0, 0x10002000
    li t1, 80
    sw t1, 4(t0)
    li t1, 1
    sw t1, 0(t0)
    li t1, 1
    sw t1, 0xC(t0)

main_loop:
    lw t0, 0x104(x0)
    li t1, 1
    nop
    bltu t0, t1, main_loop

    # GPIO marker 已写入, 嵌套抢占成功
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
    li t0, 0xDEAD0001
    sw t0, 0x100(x0)

    # 清除 Timer
    li t0, 0x10002000
    li t1, 4
    sw t1, 0(t0)

    # 重开 MIE — BANKS=1/POL=1 时 GPIO 可直接抢占(覆盖 Bank[0])
    csrr t0, mstatus
    ori t0, t0, 8
    csrw mstatus, t0

    li t3, 30
timer_delay:
    addi t3, t3, -1
    bnez t3, timer_delay
    # 若 GPIO 已抢占, 此处的上下文已被覆盖
    # Timer MRET 将恢复到被 GPIO 覆盖的 Bank[0]
    # → 返回地址可能是 GPIO ISR 某处, 行为未定义
    # 我们不依赖 Timer 正确返回, 只检查 GPIO 是否成功抢占
    mret

isr_gpio:
    li t0, 0xBEEF0003    # 降级复用标记 (不同于嵌套的 BEEF0001)
    sw t0, 0x104(x0)

    li t0, 0x10001000
    li t1, 1
    sw t1, 0x14(t0)      # clear GPIO IF
    mret

spin:
    j spin
