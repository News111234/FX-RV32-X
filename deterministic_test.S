.section .text
.globl _start

_start:
    # 写开始标志到 0x3EC（可选，用于观察开始执行）
    li   a5, 0x3EC
    li   a4, 0x12345678
    sw   a4, 0(a5)

    # 初始化累加和与循环计数器
    li   t0, 0          # sum = 0
    li   t1, 0          # i   = 0
    li   t2, 9          # 最大 i = 9

loop:
    add  t0, t0, t1     # sum = sum + i
    addi t1, t1, 1      # i = i + 1
    ble  t1, t2, loop   # if i <= 9 继续循环

    # 写入结果到 0x3F0
    li   a5, 0x3F0
    sw   t0, 0(a5)      # 0x3F0 应变为 45 (0x2D)

    # 无限循环，停止执行
hang:
    j    hang