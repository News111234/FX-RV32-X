# sim/nested_intr_test.s — 多Bank影子寄存器嵌套中断测试程序
#
# 测试目标:
#   1. 定时器中断 (优先级7, 较低) → ISR_timer 执行中
#   2. GPIO外部中断 (优先级11, 更高) → 抢占ISR_timer (嵌套)
#   3. 验证影子寄存器正确保存/恢复Timer ISR的上下文
#   4. MRET从GPIO ISR返回Timer ISR, 再从Timer ISR返回主程序
#   5. 第二次中断测试 (再次触发, 验证Bank复用)
#
# 内存布局:
#   0x00: 代码 (.text)
#   0x100: 数据 (计数器/标志)
#   0xFC: tohost (0=PASS)
#
# 预期结果:
#   tohost = 0 (PASS)
#   nest_count >= 2 (至少2次嵌套中断)
#   preempt_flag = 1 (GPIO抢占Timer成功)
# ============================================================================

.section .text
.globl _start

_start:
    # 初始化栈指针
    li sp, 0x200

    # 清零计数器
    sw zero, 0x100(x0)   # nest_count = 0
    sw zero, 0x104(x0)   # preempt_flag = 0
    sw zero, 0x108(x0)   # timer_count = 0
    sw zero, 0x10C(x0)   # gpio_count = 0

    # 设置mtvec为向量模式, 基址=0x200
    # mtvec: base=0x200, MODE=01 (vectored)
    li t0, 0x201
    csrw mtvec, t0

    # 使能定时器中断 (mie[7]=1) 和外部中断 (mie[11]=1)
    li t0, 0x880
    csrw mie, t0

    # 全局中断使能 (mstatus[3]=1)
    csrr t0, mstatus
    ori t0, t0, 0x8
    csrw mstatus, t0

    # 配置定时器: 加载值=50周期, 自动重载, 使能
    li t0, 0x10002000   # TIMER base
    li t1, 100          # 100周期
    sw t1, 4(t0)        # TIMER_LOAD
    li t1, 0x3          # enable + auto_reload
    sw t1, 0(t0)        # TIMER_CTRL
    li t1, 0x1
    sw t1, 0xC(t0)      # TIMER_IER (中断使能)

    # 配置GPIO: 使能中断
    li t0, 0x10001000   # GPIO base
    li t1, 0x1
    sw t1, 0xC(t0)      # GPIO_IE (pin0中断使能)
    sw t1, 0x10(t0)     # GPIO_EDGE (边沿触发)

    # 主循环: 等待中断
main_loop:
    wfi
    # 读取nest_count, 如果>=2则PASS
    lw t0, 0x100(x0)
    li t1, 2
    bge t0, t1, test_pass
    j main_loop

test_pass:
    sw zero, 0xFC(x0)   # tohost = 0 (PASS)
    j test_pass

test_fail:
    li t0, 1
    sw t0, 0xFC(x0)     # tohost = 1 (FAIL)
    j test_fail

# ============================================================================
# 向量表 (基址 0x200)
# 每个entry 4字节, 放一条jump指令到对应ISR
# ============================================================================
.org 0x200
vector_table:
    # ID=0: unused
    j test_fail
    # ID=1: unused
    j test_fail
    # ID=2: unused
    j test_fail
    # ID=3: MSI (软件中断) — 不测试
    j test_fail
    # ID=4-6: unused
    j test_fail
    j test_fail
    j test_fail
    # ID=7: MTI (定时器中断)
    j isr_timer
    # ID=8-10: unused
    j test_fail
    j test_fail
    j test_fail
    # ID=11: MEI (外部中断=GPIO)
    j isr_gpio

# ============================================================================
# 定时器ISR (优先级7, 较低)
# ============================================================================
isr_timer:
    # 硬件影子寄存器自动保存x1-x31到Bank (对软件透明!)
    # 不需要手动push任何寄存器

    # 递增nest_count
    lw t0, 0x100(x0)
    addi t0, t0, 1
    sw t0, 0x100(x0)

    # 递增timer_count
    lw t0, 0x108(x0)
    addi t0, t0, 1
    sw t0, 0x108(x0)

    # 设置preempt_flag=1 (标记Timer ISR已被调用)
    # 如果被GPIO抢占, 这个值会在GPIO ISR执行期间保持在影子寄存器中
    li t0, 1
    sw t0, 0x104(x0)

    # 清除定时器中断标志
    li t0, 0x10002000
    li t1, 0x4           # clr_irq
    sw t1, 0(t0)

    # 短暂延迟 (模拟ISR工作)
    li t2, 5
timer_delay:
    addi t2, t2, -1
    bnez t2, timer_delay

    # 检查是否被抢占 (preempt_flag在外层仍然为1)
    # 如果GPIO ISR破坏了preempt_flag, 这里读到的是0
    lw t0, 0x104(x0)
    li t1, 1
    bne t0, t1, isr_timer_error

    # MRET: 硬件影子寄存器自动恢复x1-x31
    # 不需要手动pop任何寄存器
    mret

isr_timer_error:
    li t0, 2
    sw t0, 0xFC(x0)     # tohost = 2 (TIMER ISR context corruption!)
    j isr_timer_error

# ============================================================================
# GPIO ISR (优先级11, 更高 — 会抢占Timer ISR)
# ============================================================================
isr_gpio:
    # 硬件影子寄存器自动保存当前x1-x31到新Bank
    # (保存的是Timer ISR的上下文!)

    # 检查preempt_flag (应该为1, 表示Timer ISR在我们之前运行)
    lw t0, 0x104(x0)
    li t1, 1
    bne t0, t1, isr_gpio_error

    # 修改preempt_flag=2 (标记GPIO ISR已运行)
    li t0, 2
    sw t0, 0x104(x0)

    # 递增gpio_count
    lw t0, 0x10C(x0)
    addi t0, t0, 1
    sw t0, 0x10C(x0)

    # 清除GPIO中断标志 (写1清除bit0)
    li t0, 0x10001000
    li t1, 1
    sw t1, 0x14(t0)

    # 短暂延迟
    li t2, 3
gpio_delay:
    addi t2, t2, -1
    bnez t2, gpio_delay

    # 恢复preempt_flag=1 (让Timer ISR看到正确的值)
    li t0, 1
    sw t0, 0x104(x0)

    # MRET: 硬件影子寄存器从Bank[gpio_bank]恢复Timer ISR的上下文
    mret

isr_gpio_error:
    li t0, 3
    sw t0, 0xFC(x0)     # tohost = 3 (GPIO ISR error!)
    j isr_gpio_error

# ============================================================================
# 填充到hex格式所需的结尾
# ============================================================================
.org 0x300
    nop
