# test1_vvadd.S – 向量加法，重复20次，记录周期差
#143周期
.section .text
.globl _start

_start:
    # 初始化 A[0..9] 于 0x100
    li   x7, 0x100
    li   x8, 1
    sw   x8, 0(x7)
    li   x8, 2
    sw   x8, 4(x7)
    li   x8, 3
    sw   x8, 8(x7)
    li   x8, 4
    sw   x8, 12(x7)
    li   x8, 5
    sw   x8, 16(x7)
    li   x8, 6
    sw   x8, 20(x7)
    li   x8, 7
    sw   x8, 24(x7)
    li   x8, 8
    sw   x8, 28(x7)
    li   x8, 9
    sw   x8, 32(x7)
    li   x8, 10
    sw   x8, 36(x7)

    # 初始化 B[0..9] 于 0x128
    li   x7, 0x128
    li   x8, 10
    sw   x8, 0(x7)
    li   x8, 9
    sw   x8, 4(x7)
    li   x8, 8
    sw   x8, 8(x7)
    li   x8, 7
    sw   x8, 12(x7)
    li   x8, 6
    sw   x8, 16(x7)
    li   x8, 5
    sw   x8, 20(x7)
    li   x8, 4
    sw   x8, 24(x7)
    li   x8, 3
    sw   x8, 28(x7)
    li   x8, 2
    sw   x8, 32(x7)
    li   x8, 1
    sw   x8, 36(x7)

    # 主循环
    li   x5, 20
    li   x6, 0x140             # results 数组

outer_v:
    # 保存起始 mcycle
    csrr x22, mcycle

    # 向量加法
    li   x11, 0
    li   x7, 0x100      # A base
    li   x8, 0x128      # B base
    li   x9, 0x118      # C base

inner_v:
    slli x12, x11, 2
    add  x13, x7, x12
    lw   x14, 0(x13)
    add  x15, x8, x12
    lw   x16, 0(x15)
    add  x17, x14, x16
    add  x18, x9, x12
    sw   x17, 0(x18)
    addi x11, x11, 1
    li   x19, 10
    blt  x11, x19, inner_v

    # 读取结束 mcycle，计算差值
    csrr x20, mcycle
    sub  x21, x20, x22
    sw   x21, 0(x6)
    addi x6, x6, 4
    addi x5, x5, -1
    bnez x5, outer_v

    # 写 tohost = 0
    li   x10, 0xFC
    sw   x0, 0(x10)
    j    .

    //每一次循环都是143个周期
    //sub那里减的有问题
    
    //该汇编程序执行的是向量加法，具体为：

//对于 i = 0 到 9：

//A[i] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10}

//B[i] = {10, 9, 8, 7, 6, 5, 4, 3, 2, 1}

//C[i] = A[i] + B[i]

//因此，C[i] = 11 对于所有 i（因为 1+10=11, 2+9=11, …, 10+1=11）。