// soc/top/soc_top.v — SoC 顶层 (仿真用), 集成 core_top 和外设
//
// 参数:
//   USE_INST_ROM = 0 (默认): 使用 inst_bram (同步读, 1周期延迟)
//                            适用于 FPGA 上板 — bootloader + 双端口总线加载
//   USE_INST_ROM = 1       : 使用 inst_rom  (组合读, 零延迟)
//                            适用于仿真验证 — 2周期中断延迟, $readmemh 加载
`timescale 1ns/1ps

module soc_top #(
    parameter USE_INST_ROM  = 0,         // 0=inst_bram, 1=inst_rom
    parameter SHADOW_BANKS  = 4,         // 影子Bank数量 (默认4, 支持3级嵌套)
    parameter OVERFLOW_POLICY = 0        // Bank溢出策略: 0=硬限制, 1=降级复用
) (
    // ========== 系统接口 ==========
    input  wire        clk_i,
    input  wire        rst_n_i,

    // ========== UART 输出 ==========
    output wire        uart_tx_o,
    input  wire        uart_rx_i,

    // ========== GPIO 外部接口 ==========
    inout  wire [31:0] gpio_io,
    input  wire [31:0] gpio_in,
    output wire [31:0] gpio_out,
    output wire [31:0] gpio_oe,

    // ========== SPI 接口 ==========
    output wire        spi_sclk_o,
    output wire        spi_mosi_o,
    input  wire        spi_miso_i,
    output wire        spi_cs_o,

    // ========== I2C 接口 ==========
    inout  wire        i2c_sda_io,
    inout  wire        i2c_scl_io,

    // ========== 软件中断 (仿真用) ==========
    input  wire        intr_software_i

    // ... 可根据需要添加更多扩展信号

);

// ==========================================================================
// 内部信号
// ==========================================================================

// CPU 核心接口
wire [31:0] core_if_pc;
wire [31:0] core_if_instr;
wire        core_bus_re;
wire        core_bus_we;
wire [31:0] core_bus_addr;
wire [31:0] core_bus_wdata;
wire [2:0]  core_bus_width;
wire [31:0] core_bus_rdata;
wire        core_bus_ready;

wire        core_intr_timer;
wire        core_intr_software;
assign      core_intr_software = intr_software_i;
wire        core_intr_external;
wire        core_intr_spi;
wire        core_intr_i2c;

wire [31:0] core_perf_total_time;
wire [31:0] core_perf_score;
wire [31:0] core_perf_iterations;
wire [31:0] core_perf_data_size;
wire [31:0] core_perf_seedcrc;
wire [31:0] core_perf_total_errors;

// 总线仲裁器到外设接口
wire        bus_ram_re;
wire        bus_ram_we;
wire [31:0] bus_ram_addr;
wire [31:0] bus_ram_wdata;
wire [2:0]  bus_ram_width;
wire [31:0] bus_ram_rdata;
wire        bus_ram_ready;

wire        bus_uart_we;
wire        bus_uart_re;
wire [31:0] bus_uart_addr;
wire [31:0] bus_uart_wdata;
wire [31:0] bus_uart_rdata;

wire        bus_gpio_we;
wire        bus_gpio_re;
wire [31:0] bus_gpio_addr;
wire [31:0] bus_gpio_wdata;
wire [31:0] bus_gpio_rdata;

wire        bus_timer_we;
wire        bus_timer_re;
wire [31:0] bus_timer_addr;
wire [31:0] bus_timer_wdata;
wire [31:0] bus_timer_rdata;

wire        bus_spi_we;
wire        bus_spi_re;
wire [31:0] bus_spi_addr;
wire [31:0] bus_spi_wdata;
wire [31:0] bus_spi_rdata;

wire        bus_i2c_we;
wire        bus_i2c_re;
wire [31:0] bus_i2c_addr;
wire [31:0] bus_i2c_wdata;
wire [31:0] bus_i2c_rdata;

wire        bus_inst_bram_we;
wire        bus_inst_bram_re;
wire [31:0] bus_inst_bram_addr;
wire [31:0] bus_inst_bram_wdata;
wire [31:0] bus_inst_bram_rdata;
wire        bus_inst_bram_ready;

wire        bus_flash_re;
wire [23:0] bus_flash_addr;
wire [31:0] bus_flash_rdata;
wire        bus_flash_ready;

// 外设中断
wire        gpio_interrupt;
wire        timer_interrupt;
wire        spi_interrupt;
wire        i2c_interrupt;

// ==========================================================================
// 实例化 CPU 核心
// ==========================================================================
core_top #(
    .SYNC_INST_MEM(!USE_INST_ROM),       // ROM=组合读(0), BRAM=同步读(1)
    .SHADOW_BANKS(SHADOW_BANKS),
    .OVERFLOW_POLICY(OVERFLOW_POLICY)
) u_core (
    .clk_i            (clk_i),
    .rst_n_i          (rst_n_i),

    .if_pc_o          (core_if_pc),
    .if_instr_i       (core_if_instr),

    .bus_re_o         (core_bus_re),
    .bus_we_o         (core_bus_we),
    .bus_addr_o       (core_bus_addr),
    .bus_wdata_o      (core_bus_wdata),
    .bus_width_o      (core_bus_width),
    .bus_rdata_i      (core_bus_rdata),
    .bus_ready_i      (core_bus_ready),

    .intr_timer_i     (timer_interrupt),
    .intr_software_i  (core_intr_software),
    .intr_external_i  (gpio_interrupt | spi_interrupt | i2c_interrupt),
    .intr_spi_i       (spi_interrupt),
    .intr_i2c_i       (i2c_interrupt)


);

// ==========================================================================
// 指令存储器: inst_bram (同步读) 或 inst_rom (组合读)
// ==========================================================================
generate
    if (USE_INST_ROM) begin : gen_inst_rom
        // ---- inst_rom: 组合读, 零延迟, $readmemh 加载 ----
        inst_rom u_inst_rom (
            .addr_i   (core_if_pc),
            .data_o   (core_if_instr)
        );
        // ROM 无总线接口 — 总线侧信号固定为 0
        assign bus_inst_bram_rdata = 32'b0;
        assign bus_inst_bram_ready = 1'b0;
    end else begin : gen_inst_bram
        // ---- inst_bram: 同步读, 1周期延迟, 双端口 ----
        inst_bram u_inst_bram (
            .clk_i        (clk_i),
            .if_addr_i    (core_if_pc),
            .if_instr_o   (core_if_instr),
            .bus_we_i     (bus_inst_bram_we),
            .bus_re_i     (bus_inst_bram_re),
            .bus_addr_i   (bus_inst_bram_addr),
            .bus_wdata_i  (bus_inst_bram_wdata),
            .bus_rdata_o  (bus_inst_bram_rdata),
            .bus_ready_o  (bus_inst_bram_ready)
        );
    end
endgenerate

// ==========================================================================
// 数据 RAM (64KB)
// ==========================================================================
data_ram u_data_ram (
    .clk_i   (clk_i),
    .rst_n_i (rst_n_i),
    .we_i    (bus_ram_we),
    .re_i    (bus_ram_re),
    .width_i (bus_ram_width),
    .addr_i  (bus_ram_addr),
    .wdata_i (bus_ram_wdata),
    .rdata_o (bus_ram_rdata),
    .ready_o (bus_ram_ready)
);

// ==========================================================================
// 总线仲裁器
// ==========================================================================
bus_arbiter u_bus_arbiter (
    .clk_i          (clk_i),
    .rst_n_i        (rst_n_i),
    .mem_re_i       (core_bus_re),
    .mem_we_i       (core_bus_we),
    .mem_addr_i     (core_bus_addr),
    .mem_wdata_i    (core_bus_wdata),
    .mem_width_i    (core_bus_width),
    .mem_rdata_o    (core_bus_rdata),
    .mem_ready_o    (core_bus_ready),

    .ram_re_o       (bus_ram_re),
    .ram_we_o       (bus_ram_we),
    .ram_addr_o     (bus_ram_addr),
    .ram_wdata_o    (bus_ram_wdata),
    .ram_width_o    (bus_ram_width),
    .ram_rdata_i    (bus_ram_rdata),
    .ram_ready_i    (bus_ram_ready),

    .uart_we_o      (bus_uart_we),
    .uart_re_o      (bus_uart_re),
    .uart_addr_o    (bus_uart_addr),
    .uart_wdata_o   (bus_uart_wdata),
    .uart_rdata_i   (bus_uart_rdata),

    .gpio_we_o      (bus_gpio_we),
    .gpio_re_o      (bus_gpio_re),
    .gpio_addr_o    (bus_gpio_addr),
    .gpio_wdata_o   (bus_gpio_wdata),
    .gpio_rdata_i   (bus_gpio_rdata),

    .timer_we_o     (bus_timer_we),
    .timer_re_o     (bus_timer_re),
    .timer_addr_o   (bus_timer_addr),
    .timer_wdata_o  (bus_timer_wdata),
    .timer_rdata_i  (bus_timer_rdata),

    .spi_we_o       (bus_spi_we),
    .spi_re_o       (bus_spi_re),
    .spi_addr_o     (bus_spi_addr),
    .spi_wdata_o    (bus_spi_wdata),
    .spi_rdata_i    (bus_spi_rdata),

    .i2c_we_o       (bus_i2c_we),
    .i2c_re_o       (bus_i2c_re),
    .i2c_addr_o     (bus_i2c_addr),
    .i2c_wdata_o    (bus_i2c_wdata),
    .i2c_rdata_i    (bus_i2c_rdata),

    .inst_bram_we_o   (bus_inst_bram_we),
    .inst_bram_re_o   (bus_inst_bram_re),
    .inst_bram_addr_o (bus_inst_bram_addr),
    .inst_bram_wdata_o(bus_inst_bram_wdata),
    .inst_bram_rdata_i(bus_inst_bram_rdata),
    .inst_bram_ready_i(bus_inst_bram_ready),

    .flash_re_o       (bus_flash_re),
    .flash_addr_o     (bus_flash_addr),
    .flash_rdata_i    (bus_flash_rdata),
    .flash_ready_i    (bus_flash_ready)
);

// ==========================================================================
// 外设实例化
// ==========================================================================
uart_ctrl #(
    .CLK_FREQ(200_000_000),
    .BAUD_RATE(115200)
) u_uart_ctrl (
    .clk_i      (clk_i),
    .rst_n_i    (rst_n_i),
    .we_i       (bus_uart_we),
    .addr_i     (bus_uart_addr),
    .wdata_i    (bus_uart_wdata),
    .rdata_o    (bus_uart_rdata),
    .tx_pin_o   (uart_tx_o),
    .rx_pin_i   (uart_rx_i),
    .tx_busy_o  (),
    .tx_ready_o (),
    .debug_fifo_count_o(),
    .debug_fifo_full_o (),
    .debug_fifo_empty_o(),
    .debug_rx_valid_o  (),
    .debug_rx_ready_o  ()
);

gpio u_gpio (
    .clk_i        (clk_i),
    .rst_n_i      (rst_n_i),
    .we_i         (bus_gpio_we),
    .re_i         (bus_gpio_re),
    .addr_i       (bus_gpio_addr),
    .wdata_i      (bus_gpio_wdata),
    .rdata_o      (bus_gpio_rdata),
    .gpio_in_i    (gpio_in),
    .gpio_out_o   (gpio_out),
    .gpio_oe_o    (gpio_oe),
    .interrupt_o  (gpio_interrupt)
);

// ==========================================================================
// SPI Flash 专用读控制器 (Flash CS/SCLK/MOSI/MISO 由此模块管理)
// ==========================================================================
spi_flash_ctrl u_spi_flash (
    .clk_i          (clk_i),
    .rst_n_i        (rst_n_i),
    .re_i           (bus_flash_re),
    .addr_i         (bus_flash_addr),
    .rdata_o        (bus_flash_rdata),
    .ready_o        (bus_flash_ready),
    .flash_sclk_o   (spi_sclk_o),
    .flash_mosi_o   (spi_mosi_o),
    .flash_miso_i   (spi_miso_i),
    .flash_cs_o     (spi_cs_o)
);

timer u_timer (
    .clk_i        (clk_i),
    .rst_n_i      (rst_n_i),
    .we_i         (bus_timer_we),
    .re_i         (bus_timer_re),
    .addr_i       (bus_timer_addr),
    .wdata_i      (bus_timer_wdata),
    .rdata_o      (bus_timer_rdata),
    .interrupt_o  (timer_interrupt)
);

spi_master u_spi_master (
    .clk_i          (clk_i),
    .rst_n_i        (rst_n_i),
    .we_i           (bus_spi_we),
    .re_i           (bus_spi_re),
    .addr_i         (bus_spi_addr),
    .wdata_i        (bus_spi_wdata),
    .rdata_o        (bus_spi_rdata),
    .sclk_o         (),                  // unused: Flash 由 spi_flash_ctrl 独占
    .mosi_o         (),                  // unused
    .miso_i         (1'b0),             // unused
    .cs_o           (),                  // unused
    .interrupt_o    (spi_interrupt)
);

i2c_master u_i2c_master (
    .clk_i          (clk_i),
    .rst_n_i        (rst_n_i),
    .we_i           (bus_i2c_we),
    .re_i           (bus_i2c_re),
    .addr_i         (bus_i2c_addr),
    .wdata_i        (bus_i2c_wdata),
    .rdata_o        (bus_i2c_rdata),
    .sda_io         (i2c_sda_io),
    .scl_io         (i2c_scl_io),
    .interrupt_o    (i2c_interrupt)
);

// 其余扩展信号可根据需要添加...


endmodule
