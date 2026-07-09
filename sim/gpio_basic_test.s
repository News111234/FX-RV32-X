# sim/gpio_basic_test.s — 最简 GPIO 中断测试：验证 ISR 能进入/退出
#
# 流程: 使能 GPIO 中断 → GPIO 边沿触发 → ISR 递增计数器 → MRET → 主循环检查
#
# 内存:
#   0x100: pass_count  (ISR 执行次数)
#   0xFC:  tohost      (0=PASS, 1=FAIL)

.section .text
.globl _start

_start:
    li sp, 0x400
    sw zero, 0x100(x0)         # pass_count = 0

    # mtvec = 0x200, vectored mode (MODE=01)
    li t0, 0x201
    csrw mtvec, t0

    # mie[11] = 1 (外部中断使能)
    li t0, 0x800
    csrw mie, t0

    # mstatus[3] = 1 (全局中断使能)
    csrr t0, mstatus
    ori t0, t0, 0x8
    csrw mstatus, t0

    # GPIO 配置: 0x10001000
    li t0, 0x10001000
    li t1, 1
    sw t1, 0xC(t0)             # GPIO_IE[0] = 1 (pin0 中断使能)
    sw t1, 0x10(t0)            # GPIO_EDGE[0] = 1 (边沿触发)

main_loop:
    lw t0, 0x100(x0)           # 读 pass_count
    li t1, 2
    bge t0, t1, test_pass      # pass_count >= 2 → PASS
    wfi
    j main_loop

test_pass:
    sw zero, 0xFC(x0)          # tohost = 0
    j test_pass

test_fail:
    li t0, 1
    sw t0, 0xFC(x0)            # tohost = 1
    j test_fail

# ========== 向量表 (基址 0x200) ==========
.org 0x200
    j test_fail                 # ID=0
    j test_fail                 # ID=1
    j test_fail                 # ID=2
    j test_fail                 # ID=3 MSI
    j test_fail                 # ID=4
    j test_fail                 # ID=5
    j test_fail                 # ID=6
    j isr_gpio_external         # ID=7 MTI (用同一个 ISR 测试)
    j test_fail                 # ID=8
    j test_fail                 # ID=9
    j test_fail                 # ID=10
    j isr_gpio_external         # ID=11 MEI

# ========== ISR (通用: 递增计数 + 清中断 + MRET) ==========
isr_gpio_external:
    # 递增 pass_count
    lw t0, 0x100(x0)
    addi t0, t0, 1
    sw t0, 0x100(x0)

    # 清除 GPIO 中断标志 (写 1 到 GPIO_IF)
    li t0, 0x10001000
    li t1, 1
    sw t1, 0x14(t0)

    mret
