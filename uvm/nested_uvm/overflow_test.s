# overflow_test.s — Bank溢出测试 (SHADOW_BANKS=1 硬限制模式)
#
# 测试场景:
#   SHADOW_BANKS=1, OVERFLOW_POLICY=0 (硬限制)
#   1. Timer中断先触发 → ISR写0xDEAD0001到mem[64]
#   2. Timer ISR执行中, GPIO中断到来但bank满 → 被阻塞, 保持pending
#   3. Timer ISR完成(MRET) → GPIO中断自动进入
#   4. GPIO ISR写0xBEEF0002到mem[65] → MRET
#   5. Main loop检查: timer=0xDEAD0001, gpio=0xBEEF0002 → PASS
#
# 与嵌套测试的区别:
#   - SHADOW_BANKS=1: 不支持嵌套, GPIO排队等待
#   - SHADOW_BANKS=4: 支持嵌套, GPIO抢占Timer
#   - gpio marker不同: 0xBEEF0002(溢出/排队) vs 0xBEEF0001(嵌套)

.section .text
.globl _start
_start:
    li sp, 0x400
    # 初始化: 清零结果区
    sw zero, 0x100(x0)    # mem[64] = 0 (timer_count)
    sw zero, 0x104(x0)    # mem[65] = 0 (gpio_count)
    sw zero, 0x108(x0)    # mem[66] = 0 (preempted)
    sw zero, 0xFC(x0)     # mem[63] = 0 (tohost)

    # 配置中断向量表 (vectored mode, base=0x200 → mtvec=0x201)
    li t0, 0x201
    csrw mtvec, t0

    # 使能 Timer 中断 (mie[7]=1) 和 GPIO/外部中断 (mie[11]=1)
    li t0, 0x880
    csrw mie, t0

    # 全局中断使能 (mstatus.MIE=1)
    csrr t0, mstatus
    ori t0, t0, 8
    csrw mstatus, t0

    # 配置 Timer: one-shot, LOAD=50
    li t0, 0x10002000    # Timer base
    li t1, 50
    sw t1, 4(t0)         # LOAD = 50
    li t1, 1
    sw t1, 0(t0)         # CTRL: enable, one-shot
    li t1, 1
    sw t1, 0xC(t0)       # IER: enable interrupt

    # 配置 GPIO: 输入模式, 上升沿触发, pin0中断使能
    li t0, 0x10001000    # t0 = 0x10001000 (GPIO base)
    sw zero, 4(t0)       # OE: all input
    li t1, 1
    sw t1, 0xC(t0)       # IE: pin0 interrupt enable
    sw t1, 0x10(t0)      # EDGE: rising edge

    # 等待中断 (死循环, 由ISR处理)
main_loop:
    lw t0, 0x104(x0)     # 读 gpio_count
    bnez t0, check_result # gpio_count != 0 → ISR已执行
    j main_loop

check_result:
    # 延迟等写完成
    li t3, 10
wait_done:
    addi t3, t3, -1
    bnez t3, wait_done

    # 验证 timer_count == 0xDEAD0001
    lw t0, 0x100(x0)
    li t1, 0xDEAD0001
    bne t0, t1, fail

    # 验证 gpio_count == 0xBEEF0002 (溢出/排队标记)
    lw t0, 0x104(x0)
    li t1, 0xBEEF0002
    bne t0, t1, fail

pass:
    sw zero, 0xFC(x0)
    j pass

fail:
    li t0, 1
    sw t0, 0xFC(x0)
    j fail


# ============================================================
# 向量表 (Vectored mode, 4字节/entry)
# ============================================================
.org 0x200
vec_table:
    j spin              # 0x200: cause 0  (unused)
    j spin              # 0x204: cause 1
    j spin              # 0x208: cause 2
    j spin              # 0x20C: cause 3 (MSI)
    j spin              # 0x210: cause 4
    j spin              # 0x214: cause 5
    j spin              # 0x218: cause 6
    j isr_timer         # 0x21C: cause 7 (MTI) — Timer
    j spin              # 0x220: cause 8
    j spin              # 0x224: cause 9
    j spin              # 0x228: cause 10
    j isr_gpio          # 0x22C: cause 11 (MEI) — GPIO

spin:
    j spin              # 未使用的中断源陷入死循环

# ============================================================
# Timer ISR (bank_ptr: 0→1, shadow_save)
# ============================================================
.org 0x240
isr_timer:
    # 写 Timer 标记
    li t0, 0xDEAD0001
    sw t0, 0x100(x0)    # mem[64] = 0xDEAD0001

    # 置 preempted 标志 (表示Timer ISR正在执行)
    li t0, 1
    sw t0, 0x108(x0)    # mem[66] = 1

    # 清除 Timer 中断标志
    li t0, 0x10002000
    li t1, 4
    sw t1, 0(t0)        # Timer CTRL: clear_irq=1

    # 重开 MIE (允许GPIO中断pending, 但由于bank_full被阻塞)
    csrr t0, mstatus
    ori t0, t0, 8
    csrw mstatus, t0

    # 延迟循环 (等待GPIO中断尝试进入——但bank_full会阻塞它)
    li t3, 300
timer_delay:
    addi t3, t3, -1
    bnez t3, timer_delay

    # 清除 preempted 标志
    sw zero, 0x108(x0)

    # 返回 (GPIO中断此时应被触发——在MRET后作为新中断进入)
    mret


# ============================================================
# GPIO ISR (bank_ptr: 0→1, 非嵌套——Timer已完成)
# ============================================================
.org 0x280
isr_gpio:
    # 写 GPIO 标记 (0xBEEF0002=溢出/排队模式)
    li t0, 0xBEEF0002
    sw t0, 0x104(x0)    # mem[65] = 0xBEEF0002

    # 清除 GPIO 中断标志
    lui t0, 0x10001      # t0 = 0x10001000 (GPIO base)
    li t1, 1
    sw t1, 0x14(t0)     # IF: write-1-clear pin0

    mret
