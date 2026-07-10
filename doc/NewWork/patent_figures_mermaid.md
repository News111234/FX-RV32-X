# 专利 Mermaid 图代码

> 使用方法：复制代码块到 [Mermaid Live Editor](https://mermaid.live) 即可实时预览并导出 SVG/PNG。

---

## 图 0：无条件中断接受机制 — 与基础方案的条件判断对比

```mermaid
flowchart LR
    EXT["外部中断源<br/>Timer / GPIO / SPI / I2C"]

    subgraph CPU["RISC-V 处理器核心"]
        direction LR
        IF["IF<br/>取指"] --> ID["ID<br/>译码"] --> EX["EX<br/>执行"] --> MEM["MEM<br/>访存"] --> WB["WB<br/>写回"]

        INTRCTRL["中断控制器<br/>优先级仲裁<br/>向量地址计算"]
        INTRPIPE["中断流水线控制器<br/>无条件接受 + CSR更新<br/>+ Bank指针管理"]
        BANKCTRL["Bank 控制器<br/>优先级抢占判断<br/>Bank 满检测<br/>Tail-Chain 检测"]
        REGFILE["寄存器堆<br/>x0-x31 通用寄存器<br/>Bank[0..N-1] 影子寄存器"]
    end

    EXT --> INTRCTRL
    INTRCTRL -->|"intr_pending / intr_cause"| INTRPIPE
    INTRCTRL -->|"new_priority"| BANKCTRL
    INTRPIPE -->|"interrupt_accepted"| BANKCTRL
    BANKCTRL -->|"allow_nesting / bank_full / tail_chain"| INTRPIPE
    INTRCTRL -->|"intr_handler_addr"| IF
    INTRPIPE -.->|"bank_ptr / shadow_save / shadow_restore"| REGFILE
    ID -.-> REGFILE
    WB -.-> REGFILE

    style BANKCTRL fill:#fff3cd,stroke:#f0ad4e,stroke-width:3px
    style REGFILE fill:#d1ecf1,stroke:#0c5460,stroke-width:3px
    style INTRPIPE fill:#d4edda,stroke:#155724,stroke-width:2px
    style INTRCTRL fill:#d4edda,stroke:#155724,stroke-width:2px
```

> **图 0 说明**：上图展示基础方案（专利一）的"有条件"中断接受机制——需满足 EX 无分支/跳转且 MEM 无 load 才接受，延迟可变（2~4+N 周期）；下图展示在先设计（FX-RV32）中已实现的"无条件"中断接受机制——通过组合逻辑 `intr_take_now` 立即重定向 PC，无论流水线状态如何均在同周期内接受中断，延迟恒定为 2 个时钟周期。本发明（专利二）沿用该无条件接受机制，并在此基础上引入多 Bank 影子寄存器以支持中断嵌套。

---

## 图 1：多级影子寄存器在 RISC-V 核心中的整体架构

```mermaid
flowchart LR
    EXT["外部中断源<br/>Timer / GPIO / SPI / I2C"]

    subgraph CPU["RISC-V 处理器核心"]
        direction LR
        IF["IF<br/>取指"] --> ID["ID<br/>译码"] --> EX["EX<br/>执行"] --> MEM["MEM<br/>访存"] --> WB["WB<br/>写回"]

        INTRCTRL["中断控制器<br/>优先级仲裁<br/>向量地址计算"]
        INTRPIPE["中断流水线控制器<br/>无条件接受 + CSR更新<br/>+ Bank指针管理"]
        BANKCTRL["Bank 控制器<br/>优先级抢占判断<br/>Bank 满检测<br/>Tail-Chain 检测"]
        REGFILE["寄存器堆<br/>x0-x31 通用寄存器<br/>Bank[0..N-1] 影子寄存器"]
    end

    EXT --> INTRCTRL
    INTRCTRL -->|"intr_pending / intr_cause"| INTRPIPE
    INTRCTRL -->|"new_priority"| BANKCTRL
    INTRPIPE -->|"interrupt_accepted"| BANKCTRL
    BANKCTRL -->|"allow_nesting / bank_full<br/>tail_chain / degradation_reuse"| INTRPIPE
    INTRCTRL -->|"intr_handler_addr"| IF
    INTRPIPE -.->|"bank_ptr / shadow_save / shadow_restore"| REGFILE
    ID -.-> REGFILE
    WB -.-> REGFILE

    style BANKCTRL fill:#fff3cd,stroke:#f0ad4e,stroke-width:3px
    style REGFILE fill:#d1ecf1,stroke:#0c5460,stroke-width:3px
    style INTRPIPE fill:#d4edda,stroke:#155724,stroke-width:2px
    style INTRCTRL fill:#d4edda,stroke:#155724,stroke-width:2px
```

---

## 图 2：本发明方法总流程图

```mermaid
flowchart TD
    START(["系统上电复位<br/>bank_ptr = 0"])
    MONITOR["中断控制器持续监测<br/>外部中断源"]
    DETECT{"检测到<br/>有效中断?"}
    ACCEPT["无条件接受中断<br/>PC → 向量地址<br/>流水线冲刷"]
    BANKCHECK{"Bank控制器判断<br/>优先级抢占<br/>&& (未满 || 降级复用) ?"}
    ALLOC["分配新 Bank<br/>shadow_save → Bank[bank_ptr-1]<br/>bank_ptr++"]
    CSR["更新 CSR<br/>mepc, mcause, mstatus"]
    ISR_EXEC["ISR 第一条指令进入 EX<br/>(总延迟 2 周期)"]
    MRET_CHECK{"MRET<br/>在 EX 阶段?"}
    TAIL_CHECK{"Tail-Chain 条件?<br/>MRET &&<br/>intr_pending"}
    TAIL_PATH["Tail-Chaining 路径<br/>跳过 shadow_restore<br/>bank_ptr 不变<br/>直接跳转新 ISR"]
    NORMAL_MRET["正常 MRET<br/>shadow_restore ← Bank[bank_ptr-1]<br/>bank_ptr--<br/>返回被中断程序"]
    OVERFLOW{"溢出策略<br/>OVERFLOW_POLICY?"}
    HARD_LIMIT["硬限制: 阻塞新中断<br/>置 bank_overflow 异常标志"]
    DEGRADE["降级复用: 覆盖当前 Bank<br/>仍触发 shadow_save"]
    WAIT["保持 pending<br/>等待当前 ISR<br/>执行 MRET"]

    START --> MONITOR
    MONITOR --> DETECT
    DETECT -->|N| MONITOR
    DETECT -->|Y| ACCEPT
    ACCEPT --> BANKCHECK
    BANKCHECK -->|"Y (允许嵌套)"| ALLOC
    BANKCHECK -->|"N (低优先级)"| WAIT
    BANKCHECK -->|"N (Bank满)"| OVERFLOW
    OVERFLOW -->|"硬限制"| HARD_LIMIT
    OVERFLOW -->|"降级复用"| DEGRADE
    ALLOC --> CSR --> ISR_EXEC
    ISR_EXEC --> MRET_CHECK
    MRET_CHECK -->|N| ISR_EXEC
    MRET_CHECK -->|Y| TAIL_CHECK
    TAIL_CHECK -->|Y| TAIL_PATH
    TAIL_CHECK -->|N| NORMAL_MRET
    TAIL_PATH --> ACCEPT
    WAIT --> MRET_CHECK
    NORMAL_MRET --> MONITOR

    style BANKCHECK fill:#fff3cd,stroke:#f0ad4e,stroke-width:2px
    style TAIL_CHECK fill:#d1ecf1,stroke:#0c5460,stroke-width:2px
    style ALLOC fill:#d4edda,stroke:#155724,stroke-width:2px
    style TAIL_PATH fill:#d4edda,stroke:#155724,stroke-width:2px
```

---

## 图 3：两级中断嵌套流程结构图

```mermaid
flowchart LR
    subgraph P1["<b>1. 中断进入</b><br/>bank_ptr 0 to 1"]
        direction TB
        S1[" "]
        T1["T1: IRQ请求<br/>intr_pending=1<br/>intr_take_now=1"]
        T2["T2↑: 接受（同一时钟沿并行）<br/>PC→handler<br/>interrupt_taken=1<br/>shadow_save=1<br/>ID/EX+EX/MEM+MEM/WB→NOP<br/>(IF/ID不冲刷, ISR首指令通过)<br/>CSR写入: mepc/mcause/mstatus<br/>bank_ptr 0→1"]
        S1 --> T1 --> T2
    end

    subgraph P2["<b>2. Timer ISR</b><br/>bank_ptr = 1"]
        direction TB
        S2[" "]
        T5["T3: 首指令进EX<br/>延迟 = 2周期"]
        T6["Timer ISR<br/>清除Timer中断源<br/>置位MIE（重开全局中断）"]
        S2 --> T5 --> T6
    end

    subgraph P3["<b>3. GPIO 抢占</b><br/>bank_ptr 1 to 2"]
        direction TB
        S3[" "]
        G1["T6: 抢占请求<br/>prio 11 > 7<br/>allow_nesting=1"]
        G2["T7↑: 接受（同一时钟沿并行）<br/>PC→GPIO handler<br/>interrupt_taken=1<br/>shadow_save=1<br/>ID/EX+EX/MEM+MEM/WB→NOP<br/>(IF/ID不冲刷)<br/>mcause=0x8000000B<br/>bank_ptr 1→2"]
        G4["T8↑: 上下文保存<br/>regfile采样shadow_save<br/>x1-x31→Bank[1]<br/>单周期并行锁存"]
        S3 --> G1 --> G2 --> G4
    end

    subgraph P4["<b>4. GPIO ISR</b><br/>bank_ptr = 2"]
        direction TB
        S4[" "]
        G5["T8: 首指令进EX<br/>延迟 = 2周期（T6→T8）"]
        G6["GPIO ISR<br/>gpio_count++<br/>MRET"]
        G7["T11: MRET<br/>shadow_restore=1<br/>bank_ptr 2 to 1"]
        S4 --> G5 --> G6 --> G7
    end

    subgraph P5["<b>5. 返回</b><br/>bank_ptr 2 to 1 to 0"]
        direction TB
        S5[" "]
        T7["T12: 上下文恢复<br/>Bank[1]→x1-x31<br/>(Timer ISR上下文)"]
        T8["T14: MRET<br/>shadow_restore=1<br/>bank_ptr 1→0<br/>Bank[0]→x1-x31<br/>(主程序上下文)"]
        M1["主程序继续<br/>bank_ptr=0<br/>MIE=1"]
        S5 --> T7 --> T8 --> M1
    end

    M0["<b>主程序</b><br/>bank_ptr=0<br/>MIE=1"] --> P1
    P1 --> P2 --> P3 --> P4 --> P5

    style S1 fill:none,stroke:none,color:transparent
    style S2 fill:none,stroke:none,color:transparent
    style S3 fill:none,stroke:none,color:transparent
    style S4 fill:none,stroke:none,color:transparent
    style S5 fill:none,stroke:none,color:transparent
    style T2 fill:#d4edda,stroke:#155724
    style T5 fill:#d4edda,stroke:#155724
    style G2 fill:#fff3cd,stroke:#f0ad4e
    style G4 fill:#fff3cd,stroke:#f0ad4e
    style G5 fill:#fff3cd,stroke:#f0ad4e
    style T7 fill:#d1ecf1,stroke:#0c5460
    style G7 fill:#d1ecf1,stroke:#0c5460
    style T8 fill:#d1ecf1,stroke:#0c5460
```

> **图 3 说明**：本图以五个阶段（P1-P5）从左至右展示两级中断嵌套的完整流程。P1（中断进入）：T1 组合逻辑产生 intr_pending 与 intr_take_now，next_pc 被驱动为 handler；T2↑ 时钟沿 PC 跳转至 handler，同时并行置位 interrupt_taken、shadow_save、流水线冲刷（ID/EX+EX/MEM+MEM/WB→NOP，IF/ID 不冲刷）及 CSR 更新（mepc/mcause/mstatus）等全部寄存器，bank_ptr 由 0 升至 1。P2（Timer ISR）：T3 首指令进入 EX 阶段，中断延迟为 2 个时钟周期（T1→T3）；ISR 执行期间，软件清除 Timer 中断源并通过 CSR 指令序列置位 MIE 以重开全局中断使能，为 GPIO 嵌套做准备。P3（GPIO 抢占）：T6 GPIO 中断到达（优先级 11>7），intr_pending 与 intr_take_now 再次置 1；T7↑ 时钟沿 PC 跳转至 GPIO handler，同时并行置位 interrupt_taken、shadow_save、流水线冲刷及 mcause 等全部寄存器，bank_ptr 由 1 升至 2；T8↑ 由 regfile 采样 shadow_save，将 x1-x31 并行锁存至 Bank[1]。P4（GPIO ISR）：T8 首指令进入 EX 阶段，嵌套延迟同为 2 个时钟周期（T6→T8）；G7 执行 MRET 触发 shadow_restore，bank_ptr 由 2 降为 1。P5（返回）：T12 从 Bank[1] 恢复 Timer ISR 上下文，T14 执行 MRET 从 Bank[0] 恢复主程序上下文，bank_ptr 归零。图中绿色为中断接受节点，黄色为嵌套抢占及上下文保存，蓝色为 MRET 及上下文恢复。

---

## 图 4：Tail-Chaining 优化 vs 正常路径对比

```mermaid
flowchart LR
    subgraph NORMAL["正常路径 (无 Tail-Chain)"]
        direction TB
        N1["ISR_1 执行 MRET"]
        N2["shadow_restore<br/>← Bank[1]<br/>bank_ptr: 1→0<br/>(1 周期)"]
        N3["中断检测<br/>+ 向量跳转<br/>(2 周期延迟)"]
        N4["shadow_save<br/>→ Bank[0]<br/>bank_ptr: 0→1<br/>(并行,不增加延迟)"]
        N5["ISR_2 第一条指令"]
        N1 --> N2 --> N3 --> N4 --> N5
        N6["总延迟: 1+2 = 3 周期"]
    end

    NORMAL ~~~ TAIL

    subgraph TAIL["Tail-Chaining 路径"]
        direction TB
        T1["ISR_1 执行 MRET<br/>同时检测到 pending"]
        T2["tail_chain_detect = 1<br/>跳过 shadow_restore!<br/>bank_ptr 保持 = 1"]
        T3["中断检测<br/>+ 向量跳转<br/>(2 周期延迟)"]
        T4["bank_ptr > 0? → 是<br/>不触发额外 save<br/>(Bank[1] 已有上下文)"]
        T5["ISR_2 第一条指令"]
        T1 --> T2 --> T3 --> T4 --> T5
        T6["总延迟: 2 周期<br/>节省 1 周期 restore"]
    end

    style N2 fill:#f8d7da,stroke:#721c24
    style T2 fill:#d4edda,stroke:#155724
    style T4 fill:#d4edda,stroke:#155724
```

---

## 图 5：Tail-Chaining 硬件判断逻辑

```mermaid
flowchart TD
    MRET_IN_EX["MRET 在 EX 阶段<br/>(id_ex_mret = 1)"]

    CHECK{"Bank 控制器<br/>组合逻辑判断<br/><br/>TAIL_CHAIN_EN<br/>&& intr_pending_i ?"}

    TAIL_TRUE["tail_chain_detect = 1"]

    TAIL_FALSE["tail_chain_detect = 0"]

    SKIP_RESTORE["中断流水线:<br/>跳过 shadow_restore 触发<br/>bank_ptr 保持不变"]

    NORMAL_PATH["中断流水线:<br/>触发 shadow_restore<br/>bank_ptr--"]

    NEW_IRQ["新中断接受流程<br/>(2 周期延迟)"]

    BANK_CHECK{"bank_ptr > 0 ?"}

    SKIP_SAVE["不触发额外 save<br/>(Bank[bank_ptr-1] 已保存<br/>上一个 ISR 的上下文)"]

    DO_SAVE["触发 shadow_save<br/>→ Bank[bank_ptr-1]"]

    ISR_START["ISR 第一条指令执行"]

    MRET_IN_EX --> CHECK
    CHECK -->|Y| TAIL_TRUE
    CHECK -->|N| TAIL_FALSE
    TAIL_TRUE --> SKIP_RESTORE
    TAIL_FALSE --> NORMAL_PATH
    SKIP_RESTORE --> NEW_IRQ
    NORMAL_PATH --> NEW_IRQ
    NEW_IRQ --> BANK_CHECK
    BANK_CHECK -->|"Y: tail-chain场景"| SKIP_SAVE
    BANK_CHECK -->|"N: 主程序首次中断"| DO_SAVE
    SKIP_SAVE --> ISR_START
    DO_SAVE --> ISR_START

    style CHECK fill:#fff3cd,stroke:#f0ad4e,stroke-width:3px
    style TAIL_TRUE fill:#d4edda,stroke:#155724,stroke-width:2px
    style SKIP_RESTORE fill:#d4edda,stroke:#155724,stroke-width:2px
    style SKIP_SAVE fill:#d4edda,stroke:#155724,stroke-width:2px
```

---

## 图 6：Bank 溢出处理决策流程

```mermaid
flowchart TD
    OVERFLOW_CHECK{"Bank控制器检测<br/>bank_ptr == N &&<br/>新中断优先级更高?"}
    
    POLICY{"OVERFLOW_POLICY?"}
    
    HARD["硬限制策略<br/>bank_full = 1"]
    DEGRADE["降级复用策略<br/>bank_ptr 保持 = N<br/>不递增"]
    
    BLOCK["阻塞新中断<br/>新中断保持 pending<br/>mneststatus overflow标志=1"]
    DEGRADE_SAVE["shadow_save<br/>→ Bank[N-1]<br/>(覆盖最深嵌套层上下文)"]
    
    WAIT_MRET["等待当前最深层 ISR<br/>执行 MRET<br/>bank_ptr: N → N-1"]
    DEGRADE_ACCEPT["新中断接受<br/>延迟 = 2 周期"]
    
    NORMAL_RESP["Bank 释放后<br/>新中断正常响应<br/>bank_ptr 再次递增至 N"]
    
    OVERFLOW_CHECK -->|"Y (Bank满且有更高优先级)"| POLICY
    OVERFLOW_CHECK -->|"N"| NORMAL_FLOW["正常中断处理流程"]
    
    POLICY -->|"0: 硬限制"| HARD
    POLICY -->|"1: 降级复用"| DEGRADE
    
    HARD --> BLOCK
    BLOCK --> WAIT_MRET
    WAIT_MRET --> NORMAL_RESP
    
    DEGRADE --> DEGRADE_SAVE
    DEGRADE_SAVE --> DEGRADE_ACCEPT
    
    style OVERFLOW_CHECK fill:#fff3cd,stroke:#f0ad4e,stroke-width:3px
    style POLICY fill:#fff3cd,stroke:#f0ad4e,stroke-width:3px
    style HARD fill:#f8d7da,stroke:#721c24,stroke-width:2px
    style DEGRADE fill:#f8d7da,stroke:#721c24,stroke-width:2px
    style BLOCK fill:#f8d7da,stroke:#721c24
    style DEGRADE_SAVE fill:#d4edda,stroke:#155724
```

> **图 6 说明**：Bank 溢出处理的硬件决策流程。当 bank_ptr 达到上限 N 且有更高优先级中断到达时，根据 `OVERFLOW_POLICY` 参数选择策略。左支（硬限制）：阻塞新中断并置溢出标志，等待当前 ISR 的 MRET 释放 Bank 后正常响应。右支（降级复用）：bank_ptr 不递增，shadow_save 覆盖 Bank[N-1]（最深嵌套层上下文），新中断以恒定 2 周期延迟立即响应。

---

## 图 7：系统架构模块图

```mermaid
graph TB
    subgraph SYSTEM["多级影子寄存器嵌套中断系统"]

        INTRCTRL["<b>中断控制器</b><br/>────────────<br/>• 优先级仲裁<br/>• 向量地址计算<br/>• 输出 current_priority<br/>• 输出 new_priority"]

        INTRPIPE["<b>中断流水线控制器</b><br/>────────────<br/>• 无条件接受中断<br/>• mepc/mcause 更新<br/>• mstatus 管理<br/>• 流水线冲刷生成<br/>• Bank 指针寄存器"]

        BANKCTRL["<b>Bank 控制器</b><br/>────────────<br/>纯组合逻辑决策单元<br/>• 优先级抢占判断<br/>• Bank 满检测<br/>• Tail-Chain 检测<br/>• 降级复用判断"]

        SHADOW["<b>多Bank影子寄存器阵列</b><br/>────────────<br/>┌──────┬──────┬──────┐<br/>│Bank0 │Bank1 │BankN │<br/>│x1-31 │x1-31 │x1-31 │<br/>└──────┴──────┴──────┘<br/>写入优先级:<br/>restore > WB > save"]

        TAILCHAIN["<b>Tail-Chaining<br/>优化模块</b><br/>────────────<br/>• restore 跳过逻辑<br/>• bank_ptr 保持逻辑"]

        OVERFLOW["<b>Bank 溢出处理<br/>模块</b><br/>────────────<br/>• 硬限制策略<br/>• 降级复用策略"]

        CSRIF["<b>CSR 寄存器接口</b><br/>────────────<br/>mneststatus: bank_ptr, overflow<br/>mprio: current_priority"]

    end

    EXT["外部中断源<br/>Timer / GPIO / SPI / I2C"]

    EXT --> INTRCTRL
    INTRCTRL -->|"intr_pending, intr_cause<br/>new_priority"| INTRPIPE
    INTRCTRL -->|"current_priority<br/>new_priority"| BANKCTRL

    INTRPIPE -->|"interrupt_accepted<br/>mret_in_ex"| BANKCTRL
    BANKCTRL -->|"tail_chain_detect"| TAILCHAIN
    BANKCTRL -->|"allow_nesting<br/>bank_full<br/>degradation_reuse"| INTRPIPE

    TAILCHAIN -->|"skip_restore"| INTRPIPE

    INTRPIPE -->|"bank_ptr<br/>shadow_save<br/>shadow_restore"| SHADOW
    BANKCTRL -->|"bank_full"| OVERFLOW

    INTRPIPE --> CSRIF
    SHADOW --> CSRIF

    style BANKCTRL fill:#fff3cd,stroke:#f0ad4e,stroke-width:3px
    style SHADOW fill:#d1ecf1,stroke:#0c5460,stroke-width:3px
    style INTRPIPE fill:#d4edda,stroke:#155724,stroke-width:2px
    style TAILCHAIN fill:#e8daef,stroke:#6f42c1,stroke-width:2px
```

---

## 使用方法

1. 打开 [https://mermaid.live](https://mermaid.live)
2. 复制上面任意一段代码到左侧编辑器
3. 右侧实时显示效果
4. 点击右上角 **Export** → 选择 **SVG** 或 **PNG** 导出
5. 插入到 Word 专利文档对应位置

- **图 2**（流程图）最复杂，导出时建议选 SVG（矢量无损）
- **图 3**（时序图）用 Mermaid 的 sequenceDiagram 画出来会自适应调整，效果不如 Wavedrom 精确。如需更精确的时序波形，建议用 [Wavedrom](https://wavedrom.com/editor.html)
- **图 7**（系统架构模块图）建议重点美化——专利里系统架构图往往占一整页
