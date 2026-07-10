# ===== lfsr_test_cycles.S =====
# 输入：无
# 输出：a0 = 最终 state，a1 = 消耗的周期数（从函数入口到返回）
# 依赖：硬件实现 mcycle CSR（编译时无需特殊选项）
#2053个周期
.text
.globl lfsr_test_cycles
lfsr_test_cycles:
    csrr  a1, mcycle            # 读取起始周期 (M-mode)
    li    a0, 0x12345678       # 初始状态 seed
    li    a2, 0xEDB88320       # 反射多项式
    li    a3, 256              # 迭代次数
1:
    andi  a4, a0, 1            # lsb = state & 1
    srli  a0, a0, 1            # state >>= 1
    beqz  a4, 2f               # 若 lsb==0 跳过异或
    xor   a0, a0, a2           # state ^= poly
2:
    addi  a3, a3, -1           # iter--
    bnez  a3, 1b               # 循环

    csrr  a4, mcycle            # 读取结束周期
    sub   a1, a4, a1           # cycles = end - start
    # a0 中保留最终 state
    ret