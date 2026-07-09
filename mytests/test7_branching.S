# test7_branching.S — 控制流确定性验证
# 决策树: 输入固定值42, 经过4级分支, 每次走完全相同的路径
# 确定性要求: 20轮周期数完全相等, x12恒为777

.section .text
.globl _start

_start:
    li   x5, 20
    li   x6, 0x140

outer_br:
    csrr x22, 0xB00

    li   x10, 42                # 固定输入

    # ==== L1: x10 >= 20 ? → R(右) ====
    addi x11, x0, 20
    bge  x10, x11, tree_R1
    j    tree_L1
tree_R1:
    # ==== L2: x10 < 60 ? → R→L(左) ====
    addi x11, x0, 60
    blt  x10, x11, tree_R1L2
    j    tree_R1R2
tree_L1:
    li   x12, 111               # 不该到这里
    j    merge
tree_R1R2:
    li   x12, 222               # 不该到这里
    j    merge
tree_R1L2:
    # ==== L3: x10 是偶数? → R→L→L(左, 是偶数) ====
    andi x11, x10, 1
    beq  x11, x0, tree_R1L2L3   # 42 是偶数 → 跳
    j    tree_R1L2R3
tree_R1L2R3:
    li   x12, 333               # 不该到这里
    j    merge
tree_R1L2L3:
    # ==== L4: x10 >= 45 ? → 不走(R), 走 L → R→L→L→L ====
    addi x11, x0, 45
    bge  x10, x11, tree_R1L2L3R4  # 42>=45? NO → 不走, 顺序往下
    j    tree_R1L2L3L4
tree_R1L2L3R4:
    li   x12, 444               # 不该到这里
    j    merge
tree_R1L2L3L4:
    li   x12, 777               # ✓ 正确路径: 42 → R→L→L→L
    j    merge

merge:
    # x12 应恒等于 777
    addi x11, x0, 777
    bne  x12, x11, fail

    csrr x20, 0xB00
    sub  x21, x20, x22
    sw   x21, 0(x6)
    addi x6, x6, 4
    addi x5, x5, -1
    bnez x5, outer_br

    li   x10, 0xFC
    sw   x0, 0(x10)             # PASS
    j    done

fail:
    li   x10, 0xFC
    addi x11, x0, 1
    sw   x11, 0(x10)            # FAIL

done:
    j    done
