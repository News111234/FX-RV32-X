# intr_test.s — 验证影子寄存器上下文保存与恢复
#
# 测试流程:
#   1. 初始化 x1-x5 为已知值 (0xA1 ~ 0xA5)
#   2. 设置 mtvec 指向 ISR, mie 使能定时器中断, mstatus.MIE 开中断
#   3. 进入主循环等待中断 (通过内存标志 [0x200] 检测)
#   4. UVM Driver 在指定周期注入定时器中断脉冲
#   5. ISR 破坏性地修改 x1-x5 (改为 0xB1 ~ 0xB5)
#   6. ISR 写 [0x200]=1 通知主循环, 然后 MRET
#   7. 影子寄存器恢复 x1-x5 为中断前的值 (0xA1~0xA5)
#   8. 主循环检查 x1-x5 是否恢复为 0xA1~0xA5
#   9. 结果写入 [0xFC] (tohost)
#
# PASS: [0xFC] = 0x00 (全部恢复正确)
# FAIL: [0xFC] = 非零 (某寄存器未恢复)
#
# 注意: 所有 sw/lw 使用 x0 作基址 + 立即数偏移 (例如 0x200(x0)),
#       以绕开转发单元对地址计算的 bug。

    .section .text
    .globl _start

_start:
    # ==== 初始化寄存器为已知值 ====
    addi x1, x0, 0xA1         # x1 = 0x000000A1
    addi x2, x0, 0xA2         # x2 = 0x000000A2
    addi x3, x0, 0xA3         # x3 = 0x000000A3
    addi x4, x0, 0xA4         # x4 = 0x000000A4
    addi x5, x0, 0xA5         # x5 = 0x000000A5

    # ==== 清零中断标志 [0x200] ====
    # 使用 x0 基址避免转发依赖
    sw   x0, 0x200(x0)        # [0x200] = 0

    # ==== 设置中断向量表 (Direct模式) ====
    # isr_entry 位于地址 0x80（如汇编后有变动需手动更新）
    lui  x6, 0
    addi x6, x6, 0x80         # x6 = isr_entry
    csrw mtvec, x6            # mtvec = isr_entry, MODE=00

    # ==== 使能定时器中断 ====
    addi x7, x0, 0x80         # mie[7] = MTIE
    csrw mie, x7

    # ==== 开启全局中断 ====
    li   x8, 0x8              # mstatus[3] = MIE
    csrs mstatus, x8

    # ==== 主循环: 等待中断通过内存标志 [0x200] 通知 ====
    # 中断由 UVM Driver 在 ~2000 周期时注入
wait_intr:
    lw   x10, 0x200(x0)       # x10 = [0x200] (基址 x0, 转发无关)
    bne  x10, x0, check_result
    j    wait_intr

check_result:
    # ==== 验证 x1-x5 是否恢复为原始值 ====
    addi x10, x0, 0xA1
    bne  x1, x10, fail        # x1 != 0xA1?

    addi x10, x0, 0xA2
    bne  x2, x10, fail        # x2 != 0xA2?

    addi x10, x0, 0xA3
    bne  x3, x10, fail        # x3 != 0xA3?

    addi x10, x0, 0xA4
    bne  x4, x10, fail        # x4 != 0xA4?

    addi x10, x0, 0xA5
    bne  x5, x10, fail        # x5 != 0xA5?

    # 全部通过
pass:
    sw   x0, 0xFC(x0)         # [0xFC] = 0 → PASS (基址 x0)
    j    done

fail:
    addi x10, x0, 1
    sw   x10, 0xFC(x0)        # [0xFC] = 1 → FAIL (基址 x0)
    j    done

done:
    j    done


# ============================================
# 中断服务程序 (ISR)
# 注意: 硬件影子寄存器自动保存 x1-x31
#       本 ISR 故意破坏 x1-x5, 测试 MRET 后是否恢复
#       使用 x0 作基址 + 立即数偏移写内存标志
# ============================================
isr_entry:
    # 破坏 x1-x5 (ISR 结束 MRET 后影子寄存器应恢复)
    addi x1, x0, 0xB1
    addi x2, x0, 0xB2
    addi x3, x0, 0xB3
    addi x4, x0, 0xB4
    addi x5, x0, 0xB5

    # 写内存标志通知主循环中断已发生
    # 使用 x0 基址避免转发依赖
    addi x31, x0, 1
    sw   x31, 0x200(x0)       # [0x200] = 1 (基址 x0)

    mret                      # 返回主循环 (硬件影子寄存器恢复 x1-x31)
