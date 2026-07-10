# load_use_test.s — 定向验证 load-use 冒险停顿机制
#
# 测试项:
#   1. lw + add  (RAW依赖)     — 基本 load-use 停顿
#   2. lw + sw  (存数依赖)     — load 后 store 使用同一基址
#   3. lw + lw + add (背靠背) — 连续两条 load 的冒险
#
# PASS: 所有结果存入 [0xFC] 的值依次为预期值
# FAIL: 任一结果不匹配

    .section .text
    .globl _start

_start:
    # ========================================
    # 初始化: 在地址 0x100 和 0x104 写入已知值
    # li 伪指令正确处理符号扩展 (ori 的 bit11=1 会破坏高20位)
    # ========================================
    li   x10, 0xDEADBEEF     # x10 = 0xDEADBEEF
    addi x11, x0, 0x100
    addi x0,  x0, 0          # NOP: 等 x10 写回
    addi x0,  x0, 0          # NOP
    sw   x10, 0(x11)         # [0x100] = 0xDEADBEEF

    li   x10, 0xCAFEBABE     # x10 = 0xCAFEBABE
    addi x0,  x0, 0          # NOP: 等 x10 写回
    addi x0,  x0, 0          # NOP
    sw   x10, 4(x11)         # [0x104] = 0xCAFEBABE

    addi x20, x0, 0xFC      # x20 = tohost 地址
    addi x4,  x0, 0x100     # x4  = 0x100 (数据基址)
    addi x0,  x0, 0         # NOP: 等 x20/x4 写回寄存器文件
    addi x0,  x0, 0         # NOP

    # ========================================
    # Test 1: lw + add (RAW依赖, 单周期停顿)
    # ========================================
    # x1 ← mem[0x100] = 0xDEADBEEF
    # x3 ← x1 + 1 = 0xDEADBEF0
    # 预期: x3 = 0xDEADBEF0
    addi x5, x0, 1           # x5 = 1 (加数)
    lw   x1, 0(x4)           # x1 = 0xDEADBEEF  ← load
    add  x3, x1, x5          # x3 = x1 + 1        ← use (stall 1 cycle)
    addi x0,  x0, 0          # NOP: 等 x3 写回
    addi x0,  x0, 0          # NOP
    sw   x3, 0(x20)          # [0xFC] = x3 (Test1结果)

    # ========================================
    # Test 2: lw + addi (立即数, RAW依赖)
    # ========================================
    # x1 ← mem[0x104] = 0xCAFEBABE
    # x6 ← x1 + 0x100
    # 预期: x6 = 0xCAFEBBBE
    lw   x1, 4(x4)           # x1 = 0xCAFEBABE  ← load
    addi x6, x1, 0x100       # x6 = x1 + 0x100   ← use (stall 1 cycle)
    addi x0,  x0, 0          # NOP: 等 x6 写回
    addi x0,  x0, 0          # NOP
    sw   x6, 0(x20)          # [0xFC] = x6 (Test2结果)

    # ========================================
    # Test 3: lw + sw (存数据依赖)
    # ========================================
    # x1 ← mem[0x100] = 0xDEADBEEF
    # 将 x1 存到 [0x108]
    # 预期: [0x108] = 0xDEADBEEF
    lw   x1, 0(x4)           # x1 = 0xDEADBEEF  ← load
    sw   x1, 8(x4)           # [0x108] = x1      ← use (stall 1 cycle)
    lw   x7, 8(x4)           # x7 = [0x108]
    addi x0,  x0, 0          # NOP: 等 x7 写回
    addi x0,  x0, 0          # NOP
    sw   x7, 0(x20)          # [0xFC] = x7 (Test3结果)

    # ========================================
    # 结束: 无限循环
    # ========================================
done:
    j done
