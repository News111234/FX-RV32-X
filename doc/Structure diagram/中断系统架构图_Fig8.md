# 图8: FX-RV32 中断系统架构图

> 对应论文 III.E 节

```mermaid
graph TB
    subgraph Interrupt_Sources [Interrupt Sources]
        SW[Software Interrupt<br/>ID=3]
        TIMER[Timer Interrupt<br/>ID=7]
        EXT[External Interrupt<br/>ID=11]
    end

    subgraph CSR_Regfile [CSR Register File]
        CSR[csr_regfile<br/>mstatus / mtvec<br/>mepc / mcause<br/>mie / mip]
    end

    subgraph Interrupt_Controller [Interrupt Controller]
        IC[interrupt_controller<br/>Priority Encoder<br/>MEI>MTI>MSI<br/>Vector Address Calculation<br/>handler_addr = BASE + cause×4]
    end

    subgraph Interrupt_Pipeline [Interrupt Pipeline Controller]
        IP[interrupt_pipeline<br/>2-State FSM<br/>mepc selection + bus_ready dispatch<br/>CSR update control<br/>shadow_save / shadow_restore generation]
    end

    subgraph IFU [Instruction Fetch Unit]
        IFU_BLK[ifu_top<br/>next_pc priority:<br/>intr_take_now > interrupt_taken ><br/>branch > jump > stall > pc+4]
    end

    subgraph Hazard_Unit [Hazard Unit]
        HAZ[hazard_unit<br/>intr_flush_id/ex/mem/wb = NOP (flushed)<br/>control_hazard_r extends flush 2 cycles<br/>for BRAM read latency]
    end

    subgraph Regfile [Register File]
        RF[regfile<br/>32 GPR + 31 Shadow Registers<br/>Write Priority:<br/>shadow_restore > WB > shadow_save]
    end

    SW --> IC
    TIMER --> IC
    EXT --> IC

    CSR -- "mie / mip / mstatus / mtvec" --> IC
    IC -- "intr_pending / intr_cause" --> IP
    IC -- "intr_handler_addr" --> IFU_BLK

    IP -- "intr_take_now / interrupt_taken" --> IFU_BLK
    IP -- "interrupt_flush" --> HAZ
    IP -- "mepc / mcause / mstatus write" --> CSR
    IP -- "shadow_save / shadow_restore" --> RF

    HAZ -- "flush control" --> IFU_BLK

    style IC fill:#D5E8D4,stroke:#82B366
    style IP fill:#DAE8FC,stroke:#6C8EBF
    style CSR fill:#FFF2CC,stroke:#D6B656
    style RF fill:#E1D5E7,stroke:#9673A6
    style IFU_BLK fill:#F8CECC,stroke:#B85450
    style HAZ fill:#D5E8D4,stroke:#82B366
```

## 与旧版图的区别

1. **中断源**：从 5 个（SW/Timer/Ext/SPI/I2C）改为 3 个（SW/Timer/Ext），SPI 和 I2C 标注为在 SoC 级合并到外部中断
2. **IFU 信号**：`interrupt_taken` → `intr_take_now / interrupt_taken`，体现组合逻辑立即跳转 + 寄存器挡旧信号的两级机制
3. **Hazard Unit**：明确标注 IF/ID **不**参与中断冲刷（`intr_flush_id = 1'b0`），ISR 第一条指令直接通过。旧程序残留由 ID/EX 的 `intr_flush_ex` 杀死。`control_hazard_r` 将分支 flush 延长至 2 周期补偿 BRAM 延迟。
4. **优先级**：`MEI>MTI>SPI>I2C>MSI` → `MEI>MTI>MSI`（与 3 个中断源对应）
5. **寄存器堆**：标注三级写优先级
