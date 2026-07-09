# nested_test.s — Timer ISR 被 GPIO 抢占 (单次 timer)
.section .text
.globl _start
_start:
    li sp, 0x400
    sw zero, 0x100(x0)
    sw zero, 0x104(x0)
    sw zero, 0x108(x0)

    li t0, 0x201
    csrw mtvec, t0
    li t0, 0x880
    csrw mie, t0
    csrr t0, mstatus
    ori t0, t0, 8
    csrw mstatus, t0

    li t0, 0x10001000
    li t1, 1
    sw t1, 0xC(t0)
    sw t1, 0x10(t0)

    # Timer: LOAD=200, enable (约 1μs 后触发, 在 GPIO 之前)
    li t0, 0x10002000
    li t1, 200
    sw t1, 4(t0)
    li t1, 1
    sw t1, 0(t0)
    li t1, 1
    sw t1, 0xC(t0)

main_loop:
    lw t0, 0x104(x0)
    li t1, 1
    nop                        # 确保 t1 写回后再被 blt 读取
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
    j isr_timer
    j spin
    j spin
    j spin
    j isr_gpio

isr_timer:
    li t0, 0xDEAD0001
    sw t0, 0x100(x0)
    li t0, 1
    sw t0, 0x108(x0)
    # 先清除 Timer 中断, 再重开 MIE 以支持 GPIO 嵌套
    li t0, 0x10002000
    li t1, 4
    sw t1, 0(t0)            # CTRL=4: clear_irq + disable
    csrr t0, mstatus
    ori t0, t0, 8
    csrw mstatus, t0        # 重开 MIE (Timer 中断已清除, 仅 GPIO 可抢占)
    li t3, 20               # 延迟循环 (给 GPIO 留时间抢占)
timer_delay:
    addi t3, t3, -1
    bnez t3, timer_delay
    sw zero, 0x108(x0)
    mret

isr_gpio:
    li t0, 0xBEEF0001
    sw t0, 0x104(x0)
    li t0, 0x10001000
    li t1, 1
    sw t1, 0x14(t0)
    mret
