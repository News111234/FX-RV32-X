# sim/gpio_minimal.s — 极简测试: ISR 写 tohost=0 然后死循环
.section .text
.globl _start
_start:
    li sp, 0x400
    # mtvec = 0x200, vectored
    li t0, 0x201
    csrw mtvec, t0
    # mie[11] = 1
    li t0, 0x800
    csrw mie, t0
    # mstatus.MIE = 1
    csrr t0, mstatus
    ori t0, t0, 0x8
    csrw mstatus, t0
    # GPIO IE[0]=1, EDGE[0]=1
    li t0, 0x10001000
    li t1, 1
    sw t1, 0xC(t0)
    sw t1, 0x10(t0)
    # tohost = 1 (初始: 如果ISR不触发则保持1=FAIL)
    li t0, 1
    sw t0, 0xFC(x0)
loop:
    wfi
    j loop

# 向量表
.org 0x200
    j loop
    j loop
    j loop
    j loop
    j loop
    j loop
    j loop
    j loop       # ID=7
    j loop
    j loop
    j loop
    j isr        # ID=11 MEI

isr:
    # GPIO IF 写1清除
    li t0, 0x10001000
    li t1, 1
    sw t1, 0x14(t0)
    # tohost = 0 (PASS)
    sw zero, 0xFC(x0)
spin:
    j spin
