# store_test.s — 最小 store 测试
# 验证 SW 指令是否能正确写 data_ram

    .section .text
    .globl _start

_start:
    # 写 0x1234 到地址 0x100 (基址 x0, 无转发依赖)
    addi x10, x0, 0x1234
    sw   x10, 0x100(x0)       # [0x100] = 0x1234

    # 等 2 个 NOP, 确保 x10 写回后再用
    addi x0, x0, 0
    addi x0, x0, 0

    # 从 0x100 读回验证
    lw   x11, 0x100(x0)       # x11 = [0x100]
    addi x0, x0, 0
    addi x0, x0, 0
    bne  x11, x10, fail

    # PASS
pass:
    sw   x0, 0xFC(x0)         # [0xFC] = 0
    j    done

fail:
    addi x12, x0, 1
    sw   x12, 0xFC(x0)        # [0xFC] = 1

done:
    j    done
