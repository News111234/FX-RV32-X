# load_use_test.s — 构造 load-use 冒险，验证停顿机制
#
# 测试场景:
#   lw x1, 0(x2)   # 从内存加载数据到 x1
#   add x3, x1, x4 # 立即使用 x1（load-use 冒险）
#
# 如果停顿正确: x3 = mem[0] + x4 (x1 是 load 的新值)
# 如果停顿失败: x3 = x1_old + x4 (x1 是 load 前的旧值)
#
# 测试流程:
#   1. 初始化: x2 = 0x100 (数据地址), x4 = 0x200
#   2. 写已知值 0xDEADBEEF 到地址 0x100
#   3. lw x1, 0(x2)  从 0x100 读取 0xDEADBEEF
#   4. add x3, x1, x4 (load-use 冒险点: x1=x3=?)
#   5. 将 x3 存入 0xFC (tohost), Verilator 检测结果

    .section .text
    .globl _start

_start:
    # ==== 初始化寄存器 ====
    addi x2, x0, 0          # x2 = 0
    addi x4, x0, 0x200      # x4 = 0x200 (用作加数，便于检查结果)
    addi x5, x0, 0          # x5 = 0

    # ==== 写已知值 0xDEADBEEF 到地址 0x100 ====
    lui  x6, 0xDEADB        # x6 = 0xDEADB000
    ori  x6, x6, 0xEEF      # x6 = 0xDEADBEEF
    addi x7, x0, 0x100      # x7 = 0x100 (存放地址)
    sw   x6, 0(x7)          # [0x100] = 0xDEADBEEF

    # ==== 构造 load-use 冒险 ====
    # x2 指向 0x100
    addi x2, x0, 0x100      # x2 = 0x100

    # 这里开始是关键序列 —— 连续的 lw + add (load-use)
    lw   x1, 0(x2)          # x1 = mem[0x100] = 0xDEADBEEF
    add  x3, x1, x4         # x3 = x1 + x4 = 0xDEADBEEF + 0x200 = 0xDEADB0EF
                             # 如果停顿失败，x1是旧值(未知)，结果也是错的

    # ==== 将结果写入 tohost (0xFC) ====
    addi x8, x0, 0xFC       # x8 = 0xFC (tohost 地址)
    sw   x3, 0(x8)          # [0xFC] = x3

    # ==== 无限循环 (等待仿真结束) ====
loop:
    j loop
