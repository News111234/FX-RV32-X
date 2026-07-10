# test3_matmul.S – 2x2 矩阵乘法，重复20次
#23周期，这个减法依然有问题，后续必须要修正，缺少csr指令相关的前递处理和test1一样
.section .text
.globl _start

_start:
    # 初始化 A 矩阵 (2,3;4,5)
    li   x7, 0x100
    li   x8, 2
    sw   x8, 0(x7)
    li   x8, 3
    sw   x8, 4(x7)
    li   x8, 4
    sw   x8, 8(x7)
    li   x8, 5
    sw   x8, 12(x7)

    # 初始化 B 矩阵 (6,7;8,9)
    li   x7, 0x110
    li   x8, 6
    sw   x8, 0(x7)
    li   x8, 7
    sw   x8, 4(x7)
    li   x8, 8
    sw   x8, 8(x7)
    li   x8, 9
    sw   x8, 12(x7)

    li   x5, 20
    li   x6, 0x140

mat_loop:
    csrr x26, mcycle         # 用 x26 保存起始

    # 加载矩阵 A
    li   x7, 0x100
    lw   x8, 0(x7)
    lw   x9, 4(x7)
    lw   x10, 8(x7)
    lw   x11, 12(x7)

    # 加载矩阵 B
    li   x12, 0x110
    lw   x13, 0(x12)
    lw   x14, 4(x12)
    lw   x15, 8(x12)
    lw   x16, 12(x12)

    # 乘法
    mul  x17, x8, x13
    mul  x18, x9, x15
    add  x17, x17, x18        # C00

    mul  x19, x8, x14
    mul  x20, x9, x16
    add  x19, x19, x20        # C01

    mul  x21, x10, x13
    mul  x22, x11, x15
    add  x21, x21, x22        # C10

    mul  x23, x10, x14
    mul  x24, x11, x16
    add  x23, x23, x24        # C11

    csrr x25, mcycle      #需要前递
    sub  x27, x25, x26    #需要前递
    sw   x27, 0(x6)
    addi x6, x6, 4
    addi x5, x5, -1
    bnez x5, mat_loop

    li   x10, 0xFC
    sw   x0, 0(x10)
    j    .