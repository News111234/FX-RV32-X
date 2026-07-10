# test2_fib.S – 递归斐波那契，重复20次,每个间距11个周期，估算了一下大概97周期
#这测试有问题，结束周期根本无法保存，还需要修改
.section .text
.globl _start

_start:
    li sp, 0x200 
    li   x5, 20
    li   x6, 0x140             # results

fib_loop:
    csrr x22, mcycle
    li   a0, 8
    call fib
    csrr x23, mcycle       #0x18
    sub  x24, x23, x22
    sw   x24, 0(x6)
    addi x6, x6, 4
    addi x5, x5, -1
    bnez x5, fib_loop

    li   x10, 0xFC
    sw   x0, 0(x10)
    j    .

# 递归函数 fib
fib:
    addi sp, sp, -16     #sp:x2,ra:x1   0x3c
    sw   ra, 12(sp)   #0x40
    sw   a0, 8(sp)   #0x44
    li   t0, 2      #0x48
    bge  a0, t0, recurse   #rs1:x10,rs2:x5 0x4c
    li   a0, 1    #0x50 
    addi sp, sp, 16  #0x58
    ret    #0x5c

recurse:
    addi a0, a0, -1  #0x60
    call fib    #0x64
    sw   a0, 4(sp)   #0x68
    lw   a0, 8(sp) 
    addi a0, a0, -2
    call fib
    lw   t0, 4(sp)
    add  a0, a0, t0
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret