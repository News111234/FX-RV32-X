# test6_forwarding.S — 前递确定性验证
# 依赖链: 每条指令的 rs1 来自上一条的 rd, 强制前递路径全部激活
# 重复20次, 每次记录周期数。确定性要求: 周期数完全相等, 结果一致

.section .text
.globl _start

_start:
    li   x5, 20
    li   x6, 0x140

outer_fwd:
    csrr x22, 0xB00            # 起始 mcycle

    # ==== 段1: EX/MEM 前递链 (10条) ====
    addi x10, x0, 1
    addi x10, x10, 2
    addi x10, x10, 4
    addi x10, x10, 8
    addi x10, x10, 16
    addi x10, x10, 32
    addi x10, x10, 64
    addi x10, x10, 128
    addi x10, x10, 256
    addi x10, x10, 512
    # x10 应为 1+2+4+8+16+32+64+128+256+512 = 1023 = 0x3FF
    li   x28, 1023
    bne  x10, x28, fail

    # ==== 段2: MEM/WB 前递 (有间隔, 测试不同前递源) ====
    addi x11, x0, 100
    addi x0,  x0, 0            # NOP
    addi x12, x11, 50          # MEM/WB 前递 x11: 150
    addi x0,  x0, 0            # NOP
    addi x0,  x0, 0            # NOP
    li   x28, 150
    bne  x12, x28, fail

    # ==== 段3: 混合前递 (sub/xor/sll同时依赖) ====
    addi x10, x0, 0x100        # x10 = 256
    addi x11, x0, 0x0FF        # x11 = 255
    addi x0,  x0, 0
    sub  x12, x10, x11         # 256 - 255 = 1, 前递 x10 和 x11
    addi x0,  x0, 0
    addi x0,  x0, 0
    addi x28, x0, 1
    bne  x12, x28, fail

    # ==== 段4: 移位前递 ====
    addi x10, x0, 1
    addi x0,  x0, 0
    slli x10, x10, 10          # 1 << 10 = 1024, 前递 x10
    addi x0,  x0, 0
    addi x0,  x0, 0
    li   x28, 1024
    bne  x10, x28, fail

    csrr x20, 0xB00            # 结束 mcycle
    sub  x21, x20, x22         # 周期数
    sw   x21, 0(x6)
    addi x6, x6, 4
    addi x5, x5, -1
    bnez x5, outer_fwd

    li   x10, 0xFC
    sw   x0, 0(x10)            # PASS
    j    done

fail:
    li   x10, 0xFC
    addi x11, x0, 1
    sw   x11, 0(x10)           # FAIL

done:
    j    done
