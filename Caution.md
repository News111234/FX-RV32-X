  fig1 — 架构框图
  - 五级流水线标注 IF/ID/EX/MEM/WB 是否完整
  - 影子寄存器是否画在寄存器堆内
  - 中断控制器→中断流水线→PC 的路径是否正确
  - 总线仲裁器→外设的连接

  fig2–fig7 — 流水线各级微架构
  - fig2(IF): next_pc 优先级是否标注（intr_take_now > interrupt_taken > branch > jump > stall > pc+4）
  - fig3(ID): 译码器→立即数生成→寄存器堆读→控制单元 的路径
  - fig4(EX): 前递通路（EX/MEM→EX、MEM/WB→EX）
  - fig5(MEM): 总线仲裁器→data_ram/periph 路由
  - fig6(WB): 四选一写回 mux（ALU/MEM/PC+4/CSR）
  - fig7: 哈佛架构（指令 ROM 和数据 RAM 分离）

  fig8 — 中断系统框图
  - 中断源：SW(3)、Timer(7)、External(11, 合并 SPI+I2C)
  - mtvec MODE 位：Direct vs Vectored 两种模式
  - 中断流水线→PC 重定向路径

  fig9 — 2 周期中断响应时序
  - T1: interrupt_pending → intr_take_now → PC 跳转 + CSR 写
  - T2: shadow_save 脉冲 → ISR 首条指令进入 IF
  - IF/ID 不冲刷（NOP 不应出现）

  fig10 — 寄存器堆内部结构
  - 32 GPR + 31 影子寄存器
  - shadow_save/shadow_restore 信号路径
  - 写优先级：shadow_restore > WB > shadow_save

  fig11 — 中断全流程时序
  - 中断进入 2 周期 + 影子保存 1 周期
  - MRET 返回 3 周期 + 影子恢复 1 周期
  - mstatus.MIE 在中断进入时清零、MRET 时恢复

  fig12 — GPIO 写时序
  - store 指令→下一时钟沿引脚更新，1 周期延迟

  fig13 — 面积对比柱状图
  - 核对数字：PicoRV32 base 18.6、FX baseline 24.9、Sophon 28.6、PicoRV32 full 29.5、FX+shadow 32.4
  - 单位 kGE，55nm

  fig14 — 综合结果对比
  - 核对数字：FX baseline 27,879 µm² (24.9 kGE)、FX+shadow 36,252 µm² (32.4 kGE)
  - Sophon 六个配置的面积/时序是否与论文 IV.B.2 一致
  - OpenE902 83,924 µm² (74.9 kGE)

  fig15a–h — 八个测试的周期数直方图
  - 每个子图 40 次运行，柱子是否全部等长（零方差）
  - 纵轴周期数：143/97/1081/312/33/16/41/8 是否匹配

  fig16 — 中断延迟对比
  - 核对延迟数字：FX 2、Sophon 3、PicoRV32 3*、OpenE902 9、Fast Intr 13、CV32E40P 24/33
  - Sophon 非向量模式的 7 和 39 是否标注
  - PicoRV32 的 3 是否需要加注（非标准机制）