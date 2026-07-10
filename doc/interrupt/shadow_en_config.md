# SHADOW_EN 参数配置说明

## 概述

`SHADOW_EN` 是一个 Verilog 参数（parameter），用于控制 FX-RV32 CPU 核心的影子寄存器功能开关。当 `SHADOW_EN=1` 时，中断进入/退出时硬件自动保存/恢复 x1-x31 通用寄存器；当 `SHADOW_EN=0` 时，关闭此硬件机制，中断上下文保存由软件负责。

## 参数定义位置

参数独立定义在两个子模块中，互不影响：

| 文件 | 行号 | 作用 |
|------|------|------|
| `core/id/id_top.v` | `parameter SHADOW_EN = 1` | 透传给 regfile，控制影子寄存器阵列的保存/恢复操作 |
| `core/interrupt/interrupt_pipeline.v` | `parameter SHADOW_EN = 1` | 控制是否发出 shadow_save / shadow_restore 脉冲 |

`core/id/regfile.v` 也有同名参数，由 `id_top` 实例化时传入，无需单独修改。

## 使用方式

### 方式一：修改子模块默认值（推荐）

直接在对应文件中修改 parameter 默认值即可：

```verilog
// core/id/id_top.v 第 32 行
module id_top #(
    parameter SHADOW_EN = 0   // 改为 0 关闭
) (
    ...
);

// core/interrupt/interrupt_pipeline.v 第 23 行
module interrupt_pipeline #(
    parameter SHADOW_EN = 0   // 改为 0 关闭
) (
    ...
);
```

**注意**：两个模块的参数是独立的，关闭时需要同时修改两处。可只改一处实现部分关闭，但通常建议两处保持一致。

### 方式二：在实例化时覆盖

在 `core/core_top.v` 中对子模块实例化时覆盖参数：

```verilog
// core/core_top.v
id_top #(
    .SHADOW_EN(0)
) u_id_top (
    ...
);

interrupt_pipeline #(
    .SHADOW_EN(0)
) u_interrupt_pipeline (
    ...
);
```

### 为什么不在 core_top 集中控制

`core_top` 不持有 `SHADOW_EN` 参数，也不向子模块透传。原因：

```
core_top  --- 实例化 ---> id_top #(.SHADOW_EN(...))  --- 实例化 ---> regfile
         |
         +-- 实例化 ---> interrupt_pipeline #(.SHADOW_EN(...))
```

若 `core_top` 显式传参（如 `.SHADOW_EN(SHADOW_EN)`），则子模块自身的默认值被覆盖。此时在 `id_top.v` 里改默认值无效——因为 `core_top` 传来的值优先级更高。去掉显式传参后，每个模块真正使用自己的默认值，修改任意层级均可生效。

## 两种模式对比

| | SHADOW_EN = 1（开启） | SHADOW_EN = 0（关闭） |
|---|---|---|
| 中断延迟 | 固定，硬件单周期保存 | 取决于软件 ISR 的 push/pop 指令数 |
| 资源消耗 | 额外 31×32bit ≈ 992bit 寄存器 | 无额外寄存器开销 |
| ISR 编写 | 无需手动保存/恢复寄存器 | 需手动 push/pop 用到的寄存器 |
| 中断嵌套 | 不支持（单组影子寄存器） | 软件可控 |
| 适用场景 | 低延迟嵌入式实时系统 | 面积敏感、需嵌套中断的系统 |

## 关闭后的中断处理

当 `SHADOW_EN=0` 时，中断服务程序需要手动保存和恢复上下文：

```asm
# 中断向量表
vector_base:
    j timer_handler

# 定时器中断处理程序（手动保存/恢复）
timer_handler:
    # 手动保存将被修改的寄存器
    addi sp, sp, -16
    sw   ra, 12(sp)
    sw   t0, 8(sp)
    sw   t1, 4(sp)
    sw   t2, 0(sp)

    # 中断处理逻辑
    li   t0, 0x10002000
    lw   t1, 0(t0)
    addi t1, t1, 1
    sw   t1, 0(t0)

    # 手动恢复寄存器
    lw   t2, 0(sp)
    lw   t1, 4(sp)
    lw   t0, 8(sp)
    lw   ra, 12(sp)
    addi sp, sp, 16

    mret
```

## 实现细节

- 当 `SHADOW_EN=0` 时，`interrupt_pipeline` 的 `shadow_save_o` 和 `shadow_restore_o` 永远为 0，不产生保存/恢复脉冲。
- `regfile` 中的 `SHADOW_EN &&` 条件确保影子寄存器阵列永远不会被写入或读取，综合工具会将其优化掉。
- 除影子寄存器外的所有中断机制（mepc/mcause/mstatus 更新、流水线冲刷、PC 重定向）不受影响。
