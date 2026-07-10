# test4_bubble.S – 冒泡排序，重复20次
#1081个周期
.section .text
.globl _start

_start:
    # 初始化源数组 (0x100) ：9,3,5,1,7,2,8,4,6,0
    li   x7, 0x100
    li   x8, 9
    sw   x8, 0(x7)
    li   x8, 3
    sw   x8, 4(x7)
    li   x8, 5
    sw   x8, 8(x7)
    li   x8, 1
    sw   x8, 12(x7)
    li   x8, 7
    sw   x8, 16(x7)
    li   x8, 2
    sw   x8, 20(x7)
    li   x8, 8
    sw   x8, 24(x7)
    li   x8, 4
    sw   x8, 28(x7)
    li   x8, 6
    sw   x8, 32(x7)
    li   x8, 0
    sw   x8, 36(x7)

    li   x5, 20
    li   x6, 0x140

outer_b:
    csrr x22, mcycle

    # 复制源数组到工作数组 (0x128)
    li   x11, 0
    li   x7, 0x100
    li   x8, 0x128
copy_b:
    slli x12, x11, 2
    add  x13, x7, x12
    lw   x14, 0(x13)
    add  x15, x8, x12
    sw   x14, 0(x15)
    addi x11, x11, 1
    li   x19, 10
    blt  x11, x19, copy_b

    # 冒泡排序（升序）
    li   x9, 0x128
    li   x13, 9              # n-1
outer_sort:
    li   x14, 0
inner_sort:
    slli x15, x14, 2
    add  x16, x9, x15
    lw   x17, 0(x16)
    lw   x18, 4(x16)
    bge  x18, x17, no_swap   # 若 arr[j+1] >= arr[j] 则不交换
    sw   x18, 0(x16)
    sw   x17, 4(x16)
no_swap:
    addi x14, x14, 1
    li   x19, 9
    blt  x14, x19, inner_sort
    addi x13, x13, -1
    bnez x13, outer_sort

    csrr x20, mcycle
    sub  x21, x20, x22
    sw   x21, 0(x6)
    addi x6, x6, 4
    addi x5, x5, -1
    bnez x5, outer_b

    li   x10, 0xFC
    sw   x0, 0(x10)
    j    .