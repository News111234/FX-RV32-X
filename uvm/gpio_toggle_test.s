# gpio_toggle_test.s — GPIO 软件翻转速率测试
#
# 用途: 演示 FX-RV32 的 1-cycle GPIO 输出延迟和确定性
#       FPGA/仿真均可运行
#
# 原理:
#   CPU 在循环体中写入 GPIO_OUT 交替输出 0xFFFFFFFF 和 0x00000000
#   每个 store 到引脚翻转的延迟固定为 1 时钟周期
#
# 预期结果 (200MHz):
#   一个 toggle 循环 = 5 条指令 (li + li + sw + li + sw + j = 6 cycles)
#   GPIO 方波周期 = 6 cycles = 30 ns → 33.3 MHz
#   等价于 1/2 CPU 频率 (因每 6 cycles 翻转一次)
#
# 对比:
#   若无 bus wait states 和 cache miss, GPIO 翻转完全确定性
#   OpenE902: store→pin = 3 cycles, 方波仅 ~CPU/6

    .section .text
    .globl _start

_start:
    # 初始化 GPIO: 全输出
    li   x5, 0x10001000         # GPIO_BASE
    li   x6, 0xFFFFFFFF
    sw   x6, 0x04(x5)           # GPIO_OE = 全输出

    # 初始化 mcycle 计数器
    csrrwi x0, mcycle, 0         # 清零 cycle 计数器

    # 初始化 tohost 为 0
    sw   x0, 0xFC(x0)            # [0xFC] = 0

    # 主循环: 交替输出 0xFFFFFFFF 和 0x00000000
toggle_loop:
    li   x6, 0xFFFFFFFF
    sw   x6, 0x00(x5)            # GPIO_OUT = 全高
    li   x6, 0x00000000
    sw   x6, 0x00(x5)            # GPIO_OUT = 全低
    j    toggle_loop

    # 程序不会执行到这里 (无限循环)
