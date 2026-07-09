# test9_mixedwork.S — 混合负载确定性验证
# 同时包含 ALU + 访存 + 分支 + 跳转 + CSR 读写的混合计算
# 确定性要求: 20轮周期数完全相等, 每轮计算结果一致

.section .text
.globl _start

_start:
    li   x5, 20
    li   x6, 0x140

outer_mix:
    csrr x22, 0xB00

    # ==== Block 1: ALU 密集 ====
    addi x10, x0, 256
    addi x11, x0, 55
    add  x12, x10, x11         # 311
    sub  x13, x12, x11         # 256
    # 用多次 slli+sub 模拟运算, 避免 srli
    slli x14, x13, 4           # 4096
    slli x15, x14, 1           # 8192 (不用 srli)
    add  x16, x14, x15         # 4096 + 8192 = 12288
    sub  x17, x16, x14         # 12288 - 4096 = 8192
    slli x18, x14, 1           # 8192
    bne  x17, x18, fail        # 验证 sub 正确

    # ==== Block 2: 访存 (写后读+) ====
    addi x7, x0, 0x180
    addi x19, x0, 0x500
    sw   x19, 0(x7)            # [0x180] = 0x500
    addi x20, x0, 0x400
    sw   x20, 4(x7)            # [0x184] = 0x400
    addi x21, x0, 0x300
    sw   x21, 8(x7)            # [0x188] = 0x300
    lw   x28, 4(x7)            # 0x400
    lw   x29, 0(x7)            # 0x500
    lw   x30, 8(x7)            # 0x300
    addi x0, x0, 0             # NOP: 等 x28/x29/x30 写回
    addi x0, x0, 0             # NOP
    sub  x25, x29, x30         # 0x500 - 0x300 = 0x200
    addi x0, x0, 0             # NOP: 等 x25 写回
    addi x0, x0, 0             # NOP
    add  x26, x25, x28         # 0x200 + 0x400 = 0x600
    addi x28, x0, 0x600
    bne  x26, x28, fail

    # ==== Block 3: 循环验证 ====
    addi x24, x0, 0
    addi x25, x0, 10
count_lp:
    addi x24, x24, 7
    addi x25, x25, -1
    bnez x25, count_lp
    addi x28, x0, 70           # 10 × 7 = 70
    bne  x24, x28, fail

    # ==== Block 4: 函数调用 (jal+jalr) ====
    jal  x1, sub_func
    addi x0, x0, 0             # NOP
    addi x0, x0, 0             # NOP
    addi x28, x0, 0xBEE
    addi x0, x0, 0             # NOP
    addi x0, x0, 0             # NOP
    bne  x10, x28, fail

    # ==== Block 5: CSR 确定性 ====
    csrr x26, mcause
    csrr x27, mcause
    bne  x26, x27, fail        # 两次读应相同

    csrr x20, 0xB00
    sub  x21, x20, x22         # 周期数
    sw   x21, 0(x6)
    addi x6, x6, 4
    addi x5, x5, -1
    bnez x5, outer_mix

    sw   x0, 0xFC(x0)          # PASS
    j    done

# 子函数
sub_func:
    addi x10, x0, 0xBEE
    jalr x0, 0(x1)

fail:
    addi x11, x0, 1
    sw   x11, 0xFC(x0)         # FAIL

done:
    j    done
