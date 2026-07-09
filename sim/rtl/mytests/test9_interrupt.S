# test9_interrupt.S — 中断确定性验证 (SoC版)
# 测量 ISR 进入→退出 的精确周期数
# 验证影子寄存器保存/恢复的确定性
# 定时器自动重载, 20次中断, 确定性要求: 所有20次的ISR周期数完全相等

.section .text
.globl _start

_start:
    # ==== 初始化寄存器快照 (ISR会破坏以下寄存器, MRET后应恢复) ====
    addi x1,  x0, 0xA1      # ISR 破坏
    addi x5,  x0, 0xA5      # ISR 破坏
    addi x28, x0, 0xA8      # ISR 破坏 (check marker)

    # ==== 清零标志位 [0x200] ====
    sw   x0, 0x200(x0)

    # ==== 配置定时器 (Timer @ 0x10002000000) ====
    lui  x7, 0x10002000          # x7 = 0x10002000000

    # LOAD = 0xC8 (200 cycles)
    addi x8, x0, 0xC8
    sw   x8, 4(x7)            # TIMER_LOAD = 200

    # IER = 1 (使能定时器中断)
    addi x8, x0, 1
    sw   x8, 0xC(x7)          # TIMER_IER = 1

    # CTRL = 3 (enable + auto_reload)
    addi x8, x0, 3
    sw   x8, 0(x7)            # TIMER_CTRL = 3

    # ==== 设置中断向量 (ISR @ 0xF8, 指令索引62) ====
    lui  x6, 0
    addi x6, x6, 0xF8
    csrw mtvec, x6

    # ==== 使能定时器中断 + 全局中断 ====
    addi x7, x0, 0x80         # MTIE (bit7)
    csrw mie, x7
    li   x8, 0x8              # MIE (bit3)
    csrs mstatus, x8

    # ==== 迭代计数: 20轮 (使用未被ISR破坏的寄存器) ====
    li   x9, 20               # 循环计数器
    li   x6, 0x300            # 结果存储起始地址 (避开 flag 0x200-0x20C)

intr_loop:
    # 等待中断
wait_intr:
    lw   x10, 0x200(x0)
    beq  x10, x0, wait_intr

    # 读回 ISR 测量数据并保存到数组
    lw   x21, 0x204(x0)       # ISR 内部周期数 (delta)
    sw   x21, 0(x6)           # [x6+0] = ISR_duration
    lw   x22, 0x208(x0)       # ISR 入口 mcycle
    sw   x22, 4(x6)           # [x6+4] = entry_mcycle
    lw   x23, 0x20C(x0)       # 定时器 COUNT (距触发经过的周期)
    sw   x23, 8(x6)           # [x6+8] = timer_count
    addi x6, x6, 12           # 每轮 3 words

    # 验证 x1 恢复 (ISR写0xB1, MRET后应为0xA1)
    addi x11, x0, 0xA1
    bne  x1, x11, fail

    # 验证 x5 恢复 (ISR写0xB5, MRET后应为0xA5)
    addi x11, x0, 0xA5
    bne  x5, x11, fail

    # 验证 x28 恢复 (ISR写0xB8, MRET后应为0xA8)
    addi x11, x0, 0xA8
    bne  x28, x11, fail

    # 清除标志, 准备下一轮
    sw   x0, 0x200(x0)

    addi x9, x9, -1
    bnez x9, intr_loop

    # ==== 20轮全部完成 ====
    li   x10, 0xFC
    sw   x0, 0(x10)           # PASS
    j    done

fail:
    li   x10, 0xFC
    addi x11, x0, 1
    sw   x11, 0(x10)          # FAIL

done:
    j    done


# ============================================
# 中断服务程序 (ISR) @ 0xF8
# ============================================
    # NOP 填充, 使 ISR 对齐到 0xB0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0
    addi x0, x0, 0

isr_entry:
    # ---- 中断延迟测量: 读定时器 COUNT (触发时 counter=0, 重载到200后递减) ----
    lui  x31, 0x10002000     # x31 = 定时器基址
    lw   x27, 8(x31)         # x27 = timer COUNT (距离中断触发经过的周期)
    csrr x29, mcycle         # x29 = ISR 入口 mcycle

    # 保存测量数据: [0x208]=entry_mcycle, [0x20C]=timer_count
    sw   x29, 0x208(x0)
    sw   x27, 0x20C(x0)

    # ---- 破坏 x1, x5, x28 (MRET 后影子寄存器应恢复) ----
    addi x1, x0, 0xB1
    addi x5, x0, 0xB5
    addi x28, x0, 0xB8

    # 清除定时器中断标志 (x31 仍为定时器基址)
    addi x30, x0, 7          # CTRL=7 (enable+auto_reload+clr_irq)
    sw   x30, 0(x31)

    # 通知主循环: [0x200] = 1
    addi x30, x0, 1
    sw   x30, 0x200(x0)

    # 记录结束 mcycle, 计算 ISR 内部周期数
    csrr x30, mcycle
    sub  x29, x30, x29        # x29 = ISR 内部周期数
    sw   x29, 0x204(x0)

    mret
