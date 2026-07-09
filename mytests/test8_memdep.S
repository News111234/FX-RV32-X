# test8_memdep.S — 访存确定性验证
# 写入已知模式 → 乱序读回比对 → 覆盖写入验证
# 确定性要求: 20轮中每轮 load 结果必须与 store 值完全一致

.section .text
.globl _start

_start:
    li   x5, 20
    li   x6, 0x140
    li   x7, 0x100              # 基址, 全程不变

outer_mem:
    csrr x22, 0xB00

    # ==== Phase 1: 写入 6 个已知值 ====
    addi x8, x0, 0x111
    sw   x8, 0(x7)              # [0x100] = 0x111
    addi x8, x0, 0x222
    sw   x8, 4(x7)              # [0x104] = 0x222
    addi x8, x0, 0x333
    sw   x8, 8(x7)              # [0x108] = 0x333
    addi x8, x0, 0x444
    sw   x8, 12(x7)             # [0x10C] = 0x444
    addi x8, x0, 0x555
    sw   x8, 16(x7)             # [0x110] = 0x555
    addi x8, x0, 0x666
    sw   x8, 20(x7)             # [0x114] = 0x666

    # ==== Phase 2: 乱序读回, 逐一比对 ====
    lw   x9, 20(x7)             # [0x114]
    addi x10, x0, 0x666
    bne  x9, x10, fail

    lw   x9, 0(x7)              # [0x100]
    addi x10, x0, 0x111
    bne  x9, x10, fail

    lw   x9, 12(x7)             # [0x10C]
    addi x10, x0, 0x444
    bne  x9, x10, fail

    lw   x9, 4(x7)              # [0x104]
    addi x10, x0, 0x222
    bne  x9, x10, fail

    lw   x9, 16(x7)             # [0x110]
    addi x10, x0, 0x555
    bne  x9, x10, fail

    lw   x9, 8(x7)              # [0x108]
    addi x10, x0, 0x333
    bne  x9, x10, fail

    # ==== Phase 3: 覆盖写入 + 读回验证 ====
    addi x8, x0, 0x999
    sw   x8, 0(x7)              # 覆盖 [0x100]
    addi x8, x0, 0x888
    sw   x8, 20(x7)             # 覆盖 [0x114]

    lw   x9, 0(x7)              # 读回 [0x100]
    addi x10, x0, 0x999
    bne  x9, x10, fail

    lw   x9, 20(x7)             # 读回 [0x114]
    addi x10, x0, 0x888
    bne  x9, x10, fail

    # ==== Phase 4: 背靠背 sw→lw ====
    addi x8, x0, 0x777
    sw   x8, 32(x7)             # [0x120] = 0x777
    lw   x9, 32(x7)
    addi x10, x0, 0x777
    bne  x9, x10, fail

    csrr x20, 0xB00
    sub  x21, x20, x22
    sw   x21, 0(x6)
    addi x6, x6, 4
    addi x5, x5, -1
    bnez x5, outer_mem

    sw   x0, 0xFC(x0)           # PASS: tohost = 0
    j    done

fail:
    addi x11, x0, 1
    sw   x11, 0xFC(x0)          # FAIL: tohost = 1

done:
    j    done
