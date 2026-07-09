// uvm_tb_top.sv — UVM 顶层 Testbench
// DUT: core_top (CPU 核心)
// 包含: 指令 ROM (4096x32bit), 数据 RAM (64KB), 时钟/复位生成
`timescale 1ns/1ps

module uvm_tb_top;

    import uvm_pkg::*;
    import riscv_uvm_pkg::*;

    // ========== 时钟与复位 ==========
    reg clk;
    reg rst_n;

    // 200MHz 时钟: 周期 5ns
    always #2.5 clk = ~clk;

    // ========== 接口实例化 ==========
    cpu_if vif (.clk(clk), .rst_n(rst_n));

    // ========== 指令 ROM (4096 x 32bit, 16KB) ==========
    logic [31:0] inst_rom [0:4095];

    // ========== 数据 RAM (16384 x 32bit, 64KB) ==========
    logic [31:0] data_ram [0:16383];

    // ========== 总线接口连接 ==========
    logic [31:0] bus_rdata_mux;
    logic        bus_ready_mux;

    // 组合逻辑: 根据地址选择 ROM 或 RAM
    // 0x0000_0000 ~ 0x0000_3FFF: 指令 ROM
    // 0x0000_0000 ~ 0x0000_FFFF: 数据 RAM
    // 注意: ROM 和 RAM 地址重叠区域, 取指访问 ROM, 数据访问 RAM
    always_comb begin
        // 默认值
        bus_rdata_mux = 32'b0;
        bus_ready_mux = 1'b0;
        vif.if_instr  = 32'h00000013;  // NOP

        // 取指: 从 ROM 读取
        if (vif.if_pc[31:2] < 4096)
            vif.if_instr = inst_rom[vif.if_pc[31:2]];

        // 总线读: 从 RAM 读取 (单周期响应)
        if (vif.bus_re && !vif.bus_we) begin
            if (vif.bus_addr[31:2] < 16384) begin
                bus_rdata_mux = data_ram[vif.bus_addr[31:2]];
                bus_ready_mux = 1'b1;
            end
        end

        // 总线写: 写入 RAM (单周期写入)
        if (vif.bus_re && vif.bus_we) begin
            if (vif.bus_addr[31:2] < 16384) begin
                // 注: 实际写入在时钟上升沿完成 (见下方时序块)
                bus_ready_mux = 1'b1;
            end
        end
    end

    // 总线写时序 (时钟上升沿写入 RAM)
    always @(posedge clk) begin
        if (vif.bus_re && vif.bus_we) begin
            if (vif.bus_addr[31:2] < 16384) begin
                case (vif.bus_width)
                    3'b010: data_ram[vif.bus_addr[31:2]] <= vif.bus_wdata;  // SW
                    3'b001: begin  // SH
                        if (vif.bus_addr[1])
                            data_ram[vif.bus_addr[31:2]][31:16] <= vif.bus_wdata[15:0];
                        else
                            data_ram[vif.bus_addr[31:2]][15:0]  <= vif.bus_wdata[15:0];
                    end
                    3'b000: begin  // SB
                        case (vif.bus_addr[1:0])
                            2'b00: data_ram[vif.bus_addr[31:2]][7:0]   <= vif.bus_wdata[7:0];
                            2'b01: data_ram[vif.bus_addr[31:2]][15:8]  <= vif.bus_wdata[7:0];
                            2'b10: data_ram[vif.bus_addr[31:2]][23:16] <= vif.bus_wdata[7:0];
                            2'b11: data_ram[vif.bus_addr[31:2]][31:24] <= vif.bus_wdata[7:0];
                        endcase
                    end
                    default: data_ram[vif.bus_addr[31:2]] <= vif.bus_wdata;  // fallback
                endcase
            end
        end
    end

    assign vif.bus_rdata = bus_rdata_mux;
    assign vif.bus_ready = bus_ready_mux;

    // 中断线默认拉低 (load-use 测试不需要中断)
    assign vif.intr_timer    = 1'b0;
    assign vif.intr_software = 1'b0;
    assign vif.intr_external = 1'b0;
    assign vif.intr_spi      = 1'b0;
    assign vif.intr_i2c      = 1'b0;

    // ========== DUT 实例化 ==========
    core_top u_dut (
        .clk_i          (clk),
        .rst_n_i        (rst_n),
        .if_pc_o        (vif.if_pc),
        .if_instr_i     (vif.if_instr),
        .bus_re_o       (vif.bus_re),
        .bus_we_o       (vif.bus_we),
        .bus_addr_o     (vif.bus_addr),
        .bus_wdata_o    (vif.bus_wdata),
        .bus_width_o    (vif.bus_width),
        .bus_rdata_i    (vif.bus_rdata),
        .bus_ready_i    (vif.bus_ready),
        .intr_timer_i   (vif.intr_timer),
        .intr_software_i(vif.intr_software),
        .intr_external_i(vif.intr_external),
        .intr_spi_i     (vif.intr_spi),
        .intr_i2c_i     (vif.intr_i2c)
    );

    // ========== 暴露内部信号供 Monitor 层次路径访问 ==========
    // core_top 内部连线已在模块头部声明为 wire，
    // Monitor 可通过 $root.uvm_tb_top.u_dut.<signal> 直接访问以下信号:
    //   stall_if, stall_id          — hazard_unit 停顿输出
    //   wb_reg_we_out, wb_rd_addr_out, wb_data  — WB 阶段写回信号
    //   if_pc                       — IF 阶段 PC
    //   if_id_pc                    — IF/ID 寄存器输出的 PC (ID 阶段 PC)

    // ========== 初始化和复位 ==========
    initial begin
        clk   = 0;
        rst_n = 0;

        // 初始化 ROM: 全部填充 NOP
        for (int i = 0; i < 4096; i++)
            inst_rom[i] = 32'h00000013;

        // 初始化 RAM: 全部填 0, 避免 X 值干扰测试判断
        for (int i = 0; i < 16384; i++)
            data_ram[i] = 32'h00000000;

        // 100ns 复位
        #100;
        rst_n = 1;
    end

    // ========== UVM 启动 ==========
    initial begin
        uvm_config_db #(virtual cpu_if)::set(null, "*", "vif", vif);
        run_test();
    end

endmodule
