# overflow_minimal.s — 最小溢出验证 (SHADOW_BANKS=1)
# 仅测试Timer ISR能否在SHADOW_BANKS=1下正常工作

.section .text
.globl _start
_start:
    li sp, 0x400
    sw zero, 0x100(x0)    # mem[64] = 0
    sw zero, 0xFC(x0)     # mem[63] = 0

    # 中断配置: vectored mode, base=0x200 (mtvec = 0x201)
    li t0, 0x201
    csrw mtvec, t0
    li t0, 0x080          # MIE[7]=1 (Timer only)
    csrw mie, t0
    csrr t0, mstatus
    ori t0, t0, 8
    csrw mstatus, t0

    # Timer: one-shot, LOAD=40
    li t0, 0x10002000
    li t1, 40
    sw t1, 4(t0)
    li t1, 1
    sw t1, 0(t0)
    li t1, 1
    sw t1, 0xC(t0)

    # 等待 Timer ISR
    li t3, 200
wait_lp:
    addi t3, t3, -1
    bnez t3, wait_lp

    # 验证
    lw t0, 0x100(x0)
    li t1, 0x42
    beq t0, t1, pass
fail:
    li t0, 1
    sw t0, 0xFC(x0)
    j fail
pass:
    sw zero, 0xFC(x0)
    j pass

# 向量表
.org 0x200
vec_table:
    j spin              # 0x200: cause 0
    j spin              # 0x204: cause 1
    j spin              # 0x208: cause 2
    j spin              # 0x20C: cause 3
    j spin              # 0x210: cause 4
    j spin              # 0x214: cause 5
    j spin              # 0x218: cause 6
    j isr_timer         # 0x21C: cause 7 (Timer)

spin:
    j spin

.org 0x240
isr_timer:
    addi t0, x0, 0x42
    sw t0, 0x100(x0)     # mem[64] = 0x42
    # 清除 Timer
    li t0, 0x10002000
    li t1, 4
    sw t1, 0(t0)
    mret
