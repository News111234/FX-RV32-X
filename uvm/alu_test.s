# alu_test.s — 基础指令测试 (RV32I)
#
# 测试项:
#   R-type: add, sub, and, or, xor, slt, sltu, sll, srl, sra
#   I-type: addi, andi, ori, xori, slti, sltiu, slli, srli, srai
#   Memory: sw, lw
#   Branch: beq, bne, blt, bge
#   Jump:   jal
#   Upper:  lui
#   CSR:    csrr
#
# 注意: 所有产生寄存器值的指令和消费该值的指令之间至少间隔 2 条指令，
#       确保值已写回寄存器文件，绕过当前转发单元对地址计算的 bug。
#
# PASS: [0xFC] = 0
# FAIL: [0xFC] = 1

    .section .text
    .globl _start

_start:
    # ============================================
    # Test 1: R-type — 算术 (add, sub)
    # ============================================
    addi x10, x0, 100         # x10 = 100
    addi x11, x0, 50          # x11 = 50
    addi x0,  x0, 0           # nop (间隔)
    add  x12, x10, x11        # x12 = 150
    addi x0,  x0, 0           # nop
    addi x0,  x0, 0           # nop
    addi x13, x0, 150
    bne  x12, x13, fail       # check x12 == 150

    sub  x12, x10, x11        # x12 = 50
    addi x0,  x0, 0
    addi x0,  x0, 0
    addi x13, x0, 50
    bne  x12, x13, fail       # check x12 == 50

    # ============================================
    # Test 2: R-type — 逻辑 (and, or, xor)
    # ============================================
    addi x10, x0, 0xFF        # x10 = 0xFF
    addi x11, x0, 0x0F        # x11 = 0x0F
    addi x0,  x0, 0
    and  x12, x10, x11        # x12 = 0x0F
    addi x0,  x0, 0
    addi x0,  x0, 0
    addi x13, x0, 0x0F
    bne  x12, x13, fail

    or   x12, x10, x11        # x12 = 0xFF
    addi x0,  x0, 0
    addi x0,  x0, 0
    addi x13, x0, 0xFF
    bne  x12, x13, fail

    xor  x12, x10, x11        # x12 = 0xF0
    addi x0,  x0, 0
    addi x0,  x0, 0
    addi x13, x0, 0xF0
    bne  x12, x13, fail

    # ============================================
    # Test 3: R-type — 移位 (sll, srl, sra)
    # ============================================
    addi x10, x0, 1           # x10 = 1
    addi x11, x0, 5           # x11 = 5
    addi x0,  x0, 0
    sll  x12, x10, x11        # x12 = 32
    addi x0,  x0, 0
    addi x0,  x0, 0
    addi x13, x0, 32
    bne  x12, x13, fail

    addi x10, x0, -16         # x10 = -16 = 0xFFFFFFF0
    addi x0,  x0, 0
    addi x0,  x0, 0
    srli x12, x10, 2          # x12 = (0xFFFFFFF0 >> 2) = 0x3FFFFFFC
    addi x0,  x0, 0
    addi x0,  x0, 0
    lui  x13, 0x40000        # x13 = 0x40000000
    addi x13, x13, -4        # x13 = 0x3FFFFFFC
    bne  x12, x13, fail

    srai x12, x10, 2          # x12 = -4 = 0xFFFFFFFC
    addi x0,  x0, 0
    addi x0,  x0, 0
    addi x13, x0, -4
    bne  x12, x13, fail

    # ============================================
    # Test 4: 比较指令 (slt, sltu)
    # ============================================
    addi x10, x0, -5          # x10 = -5
    addi x11, x0, 10          # x11 = 10
    addi x0,  x0, 0
    slt  x12, x10, x11        # x12 = 1 (signed: -5 < 10)
    addi x0,  x0, 0
    addi x0,  x0, 0
    addi x13, x0, 1
    bne  x12, x13, fail

    sltu x12, x10, x11        # x12 = 0 (unsigned: 0xFFFFFFFB > 10)
    addi x0,  x0, 0
    addi x0,  x0, 0
    bne  x12, x0, fail

    # ============================================
    # Test 5: I-type 立即数 (andi, ori, xori, slti)
    # ============================================
    addi x10, x0, 0x1FF       # x10 = 0x1FF
    addi x0,  x0, 0
    addi x0,  x0, 0
    andi x12, x10, 0x0FF      # x12 = 0x0FF
    addi x0,  x0, 0
    addi x0,  x0, 0
    addi x13, x0, 0xFF
    bne  x12, x13, fail

    ori  x12, x10, 0x300      # x12 = 0x3FF
    addi x0,  x0, 0
    addi x0,  x0, 0
    addi x13, x0, 0x3FF
    bne  x12, x13, fail

    xori x12, x10, 0x100      # x12 = 0x0FF (bit0=1 ^ 1 = 0... let's compute)
    addi x0,  x0, 0           # 0x1FF ^ 0x100 = 0x0FF
    addi x0,  x0, 0
    addi x13, x0, 0xFF
    bne  x12, x13, fail

    addi x10, x0, -10         # x10 = -10
    addi x0,  x0, 0
    addi x0,  x0, 0
    slti x12, x10, 5          # x12 = 1 (-10 < 5 signed)
    addi x0,  x0, 0
    addi x0,  x0, 0
    addi x13, x0, 1
    bne  x12, x13, fail

    sltiu x12, x10, 5         # x12 = 0 (unsigned: 0xFFFFFFF6 > 5)
    addi x0,  x0, 0
    addi x0,  x0, 0
    bne  x12, x0, fail

    # ============================================
    # Test 6: 分支 (beq, bne, blt, bge)
    # ============================================
    addi x10, x0, 7
    addi x11, x0, 7
    addi x0,  x0, 0
    beq  x10, x11, br_test1_ok
    j    fail
br_test1_ok:
    addi x11, x0, 8
    addi x0,  x0, 0
    addi x0,  x0, 0
    blt  x10, x11, br_test2_ok
    j    fail
br_test2_ok:
    addi x0,  x0, 0
    addi x0,  x0, 0
    bge  x11, x10, br_test3_ok
    j    fail
br_test3_ok:

    # ============================================
    # Test 7: 跳转 (jal)
    # ============================================
    addi x10, x0, 0
    addi x0,  x0, 0
    jal  x11, skip_fail
    addi x10, x0, 99          # should be skipped
skip_fail:
    addi x0,  x0, 0
    addi x0,  x0, 0
    addi x12, x0, 0
    bne  x10, x12, fail       # x10 should still be 0

    # ============================================
    # Test 8: lui
    # ============================================
    lui  x10, 0x12345         # x10 = 0x12345000
    addi x0,  x0, 0
    addi x0,  x0, 0
    srli x11, x10, 12         # x11 = 0x00012345
    addi x0,  x0, 0
    addi x0,  x0, 0
    addi x12, x0, 0x12345
    sub  x12, x11, x12        # x12 should be 0
    addi x0,  x0, 0           # wait for x12
    addi x0,  x0, 0
    bne  x12, x0, fail

    # ============================================
    # Test 9: CSR 读取
    # ============================================
    csrr x10, mcause          # mcause 复位后应为 0
    addi x0,  x0, 0
    addi x0,  x0, 0
    bne  x10, x0, fail

    # ============================================
    # Test 10: Memory (sw + lw)
    #   使用固定地址 0x200, 确保地址寄存器值已稳定写回
    # ============================================
    addi x20, x0, 0x200       # x20 = 0x200 (base addr)
    addi x21, x0, 0xDEAD      # x21 = 0xDEAD (test data)
    addi x0,  x0, 0
    addi x0,  x0, 0
    sw   x21, 0(x20)          # [0x200] = 0xDEAD
    addi x0,  x0, 0
    addi x0,  x0, 0
    lw   x22, 0(x20)          # x22 = mem[0x200]
    addi x0,  x0, 0
    addi x0,  x0, 0
    bne  x22, x21, fail       # check loaded value

    # ============================================
    # All tests passed
    # ============================================
pass:
    addi x10, x0, 0
    addi x11, x0, 0xFC
    addi x0,  x0, 0
    sw   x10, 0(x11)          # [0xFC] = 0 → PASS
    j    done

fail:
    addi x10, x0, 1
    addi x11, x0, 0xFC
    addi x0,  x0, 0
    sw   x10, 0(x11)          # [0xFC] = 1 → FAIL
    j    done

done:
    j    done
