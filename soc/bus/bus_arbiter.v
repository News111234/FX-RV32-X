// soc/bus/bus_arbiter.v — 总线仲裁器 (支持 RAM, UART, GPIO, Timer, SPI, I2C)
`timescale 1ns/1ps

// ============================================================================
// 模块: bus_arbiter
// 功能: 总线仲裁器，根据 CPU 发出的地址将内存访问请求路由到对应外设
// 描述:
//   本模块是 CPU 内存接口与各外设 (RAM, inst_bram, UART, GPIO, Timer, SPI, I2C)
//   之间的桥梁。接收 CPU 的读写请求，根据地址范围译码，产生对应外设的读写控制
//   信号，并将外设的读数据返回给 CPU。
//   特殊处理: UART 的写操作会被锁存，并启动一个超时计数器，等待 UART 发送就绪。
//   其余外设的读写操作为组合逻辑直连。
//
// 地址空间映射:
//   - RAM:      0x0000_0000 - 0x0000_FFFF (64KB)
//   - UART:     0x1000_0000 - 0x1000_0FFF (4KB)
//   - GPIO:     0x1000_1000 - 0x1000_1FFF (4KB)
//   - TIMER:    0x1000_2000 - 0x1000_2FFF (4KB)
//   - SPI:      0x1000_3000 - 0x1000_3FFF (4KB)
//   - I2C:      0x1000_4000 - 0x1000_4FFF (4KB)
//   - INST_BRAM: 0x2000_0000 - 0x2000_7FFF (32KB) — bootloader 写指令
// ============================================================================
module bus_arbiter (
    // ========== 系统接口 ==========
    input  wire        clk_i,              // 时钟信号
    input  wire        rst_n_i,            // 复位信号 (低电平有效)

    // ========== CPU 内存接口 ==========
    input  wire        mem_re_i,           // CPU 读请求信号
    input  wire        mem_we_i,           // CPU 写请求信号
    input  wire [31:0] mem_addr_i,         // CPU 访问地址
    input  wire [31:0] mem_wdata_i,        // CPU 写数据
    input  wire [2:0]  mem_width_i,        // CPU 访问宽度 (0: byte, 1: half-word, 2: word)
    output reg  [31:0] mem_rdata_o,        // CPU 读数据
    output wire        mem_ready_o,        // CPU 访问就绪信号 (始终为 1, RAM 直连)

    // ========== RAM 接口 ==========
    output wire        ram_re_o,           // RAM 读使能
    output wire        ram_we_o,           // RAM 写使能
    output wire [31:0] ram_addr_o,         // RAM 访问地址
    output wire [31:0] ram_wdata_o,        // RAM 写数据
    output wire [2:0]  ram_width_o,        // RAM 访问宽度
    input  wire [31:0] ram_rdata_i,        // RAM 读数据
    input  wire        ram_ready_i,        // RAM 就绪信号

    // ========== UART 接口 ==========
    output wire        uart_we_o,          // UART 写使能 (仅支持写)
    output wire        uart_re_o,          // UART 读使能
    output wire [31:0] uart_addr_o,        // UART 访问地址 (固定为基址)
    output wire [31:0] uart_wdata_o,       // UART 写数据 (仅低字节)
    input  wire [31:0] uart_rdata_i,       // UART 读数据

    // ========== GPIO 接口 ==========
    output wire        gpio_we_o,          // GPIO 写使能
    output wire        gpio_re_o,          // GPIO 读使能
    output wire [31:0] gpio_addr_o,        // GPIO 访问地址
    output wire [31:0] gpio_wdata_o,       // GPIO 写数据
    input  wire [31:0] gpio_rdata_i,       // GPIO 读数据

    // ========== TIMER 接口 ==========
    output wire        timer_we_o,         // TIMER 写使能
    output wire        timer_re_o,         // TIMER 读使能
    output wire [31:0] timer_addr_o,       // TIMER 访问地址
    output wire [31:0] timer_wdata_o,      // TIMER 写数据
    input  wire [31:0] timer_rdata_i,      // TIMER 读数据

    // ========== SPI 接口 ==========
    output wire        spi_we_o,           // SPI 写使能
    output wire        spi_re_o,           // SPI 读使能
    output wire [31:0] spi_addr_o,         // SPI 访问地址
    output wire [31:0] spi_wdata_o,        // SPI 写数据
    input  wire [31:0] spi_rdata_i,        // SPI 读数据

    // ========== I2C 接口 ==========
    output wire        i2c_we_o,           // I2C 写使能
    output wire        i2c_re_o,           // I2C 读使能
    output wire [31:0] i2c_addr_o,         // I2C 访问地址
    output wire [31:0] i2c_wdata_o,        // I2C 写数据
    input  wire [31:0] i2c_rdata_i,        // I2C 读数据

    // ========== inst_bram 接口 ==========
    output wire        inst_bram_we_o,     // inst_bram 写使能
    output wire        inst_bram_re_o,     // inst_bram 读使能
    output wire [31:0] inst_bram_addr_o,   // inst_bram 内部地址 (去偏移)
    output wire [31:0] inst_bram_wdata_o,  // inst_bram 写数据
    input  wire [31:0] inst_bram_rdata_i,  // inst_bram 读数据
    input  wire        inst_bram_ready_i,  // inst_bram 就绪信号

    // ========== SPI Flash 接口 ==========
    output wire        flash_re_o,         // Flash 读使能
    output wire [23:0] flash_addr_o,       // Flash 字节地址 (窗口内偏移)
    input  wire [31:0] flash_rdata_i,      // Flash 读数据
    input  wire        flash_ready_i       // Flash 就绪信号

);

// 地址空间划分
localparam RAM_BASE   = 32'h0000_0000;
localparam RAM_SIZE   = 32'h0001_0000;     // 64KB RAM
localparam UART_BASE  = 32'h1000_0000;
localparam UART_SIZE  = 32'h0000_1000;     // 4KB UART 空间
localparam GPIO_BASE  = 32'h1000_1000;
localparam GPIO_SIZE  = 32'h0000_1000;     // 4KB GPIO 空间
localparam TIMER_BASE = 32'h1000_2000;
localparam TIMER_SIZE = 32'h0000_1000;     // 4KB TIMER 空间
localparam SPI_BASE   = 32'h1000_3000;     // SPI 基地址
localparam SPI_SIZE   = 32'h0000_1000;     // 4KB
localparam I2C_BASE   = 32'h1000_4000;     // I2C 基地址
localparam I2C_SIZE   = 32'h0000_1000;     // 4KB
localparam INST_BRAM_BASE = 32'h2000_0000; // inst_bram 总线窗口
localparam INST_BRAM_SIZE = 32'h0000_8000; // 32KB
localparam FLASH_BASE     = 32'h3000_0000; // SPI Flash 直读窗口
localparam FLASH_SIZE     = 32'h0100_0000; // 16MB

// 地址译码
wire is_ram   = (mem_addr_i >= RAM_BASE)   && (mem_addr_i < RAM_BASE   + RAM_SIZE);
wire is_uart  = (mem_addr_i >= UART_BASE)  && (mem_addr_i < UART_BASE  + UART_SIZE);
wire is_gpio  = (mem_addr_i >= GPIO_BASE)  && (mem_addr_i < GPIO_BASE  + GPIO_SIZE);
wire is_timer = (mem_addr_i >= TIMER_BASE) && (mem_addr_i < TIMER_BASE + TIMER_SIZE);
wire is_spi   = (mem_addr_i >= SPI_BASE)   && (mem_addr_i < SPI_BASE   + SPI_SIZE);
wire is_i2c   = (mem_addr_i >= I2C_BASE)   && (mem_addr_i < I2C_BASE   + I2C_SIZE);
wire is_inst_bram = (mem_addr_i >= INST_BRAM_BASE) && (mem_addr_i < INST_BRAM_BASE + INST_BRAM_SIZE);
wire is_flash     = (mem_addr_i >= FLASH_BASE)     && (mem_addr_i < FLASH_BASE     + FLASH_SIZE);

// ========== RAM 接口 (组合逻辑直连) ==========
assign ram_re_o    = mem_re_i && is_ram;
assign ram_we_o    = mem_we_i && is_ram;
assign ram_addr_o  = mem_addr_i;
assign ram_wdata_o = mem_wdata_i;
assign ram_width_o = mem_width_i;

// ========== UART 写逻辑 (锁存机制 + 超时控制) ==========
// UART 写操作被锁存，等待 UART 报告 tx_ready (rdata[0]) 后释放，
// 带有 5 周期超时保护，防止 UART 无响应时死锁
reg         uart_we_latched;
reg  [31:0] uart_wdata_latched;
reg  [7:0]  uart_we_timeout;

// 读使能: 只要地址在 UART 范围且读操作有效
assign uart_re_o   = mem_re_i && is_uart;
assign uart_addr_o = mem_addr_i;  // 直通实际地址，让 UART 用 addr[7:0] 选择寄存器

always @(posedge clk_i) begin
    if (!rst_n_i) begin
        uart_we_latched    <= 1'b0;
        uart_wdata_latched <= 32'b0;
        uart_we_timeout    <= 8'h0;
    end else begin
        // 锁存 UART 写信号和数据
        if (mem_we_i && is_uart) begin
            uart_we_latched    <= 1'b1;
            uart_wdata_latched <= mem_wdata_i;
            uart_we_timeout    <= 8'd5;
        end
        // UART 控制器确认接收 (bit0 为 tx_ready) 后释放
        else if (uart_we_latched && uart_rdata_i[0]) begin
            uart_we_latched <= 1'b0;
            uart_we_timeout <= 8'h0;
        end
        // 超时倒计时
        else if (uart_we_latched && (uart_we_timeout > 0)) begin
            uart_we_timeout <= uart_we_timeout - 1;
            if (uart_we_timeout == 1)
                uart_we_latched <= 1'b0;
        end
    end
end

assign uart_we_o    = uart_we_latched;
assign uart_wdata_o = uart_wdata_latched;

// ========== GPIO 接口 (组合逻辑直连) ==========
assign gpio_we_o    = mem_we_i && is_gpio;
assign gpio_re_o    = mem_re_i && is_gpio;
assign gpio_addr_o  = mem_addr_i;
assign gpio_wdata_o = mem_wdata_i;

// ========== TIMER 接口 (组合逻辑直连) ==========
assign timer_we_o    = mem_we_i && is_timer;
assign timer_re_o    = mem_re_i && is_timer;
assign timer_addr_o  = mem_addr_i;
assign timer_wdata_o = mem_wdata_i;

// ========== SPI 接口 (组合逻辑直连) ==========
assign spi_we_o    = mem_we_i && is_spi;
assign spi_re_o    = mem_re_i && is_spi;
assign spi_addr_o  = mem_addr_i;
assign spi_wdata_o = mem_wdata_i;

// ========== I2C 接口 (组合逻辑直连) ==========
assign i2c_we_o    = mem_we_i && is_i2c;
assign i2c_re_o    = mem_re_i && is_i2c;
assign i2c_addr_o  = mem_addr_i;
assign i2c_wdata_o = mem_wdata_i;

// ========== inst_bram 接口 (组合逻辑直连) ==========
// 总线地址减去基址得到 inst_bram 内部地址
assign inst_bram_we_o    = mem_we_i && is_inst_bram;
assign inst_bram_re_o    = mem_re_i && is_inst_bram;
assign inst_bram_addr_o  = mem_addr_i - INST_BRAM_BASE;
assign inst_bram_wdata_o = mem_wdata_i;

// ========== SPI Flash 接口 (只读) ==========
// 字节地址偏移传入 flash 控制器
assign flash_re_o   = mem_re_i && is_flash;
assign flash_addr_o = (mem_addr_i - FLASH_BASE) & 24'hFF_FFFF;

// ========== 读数据多路选择 (组合逻辑) ==========
always @(*) begin
    mem_rdata_o = 32'b0;
    if (is_ram)
        mem_rdata_o = ram_rdata_i;
    else if (is_uart)
        mem_rdata_o = uart_rdata_i;
    else if (is_gpio)
        mem_rdata_o = gpio_rdata_i;
    else if (is_timer)
        mem_rdata_o = timer_rdata_i;
    else if (is_spi)
        mem_rdata_o = spi_rdata_i;
    else if (is_i2c)
        mem_rdata_o = i2c_rdata_i;
    else if (is_inst_bram)
        mem_rdata_o = inst_bram_rdata_i;
    else if (is_flash)
        mem_rdata_o = flash_rdata_i;
end

// ========== 就绪信号 ==========
assign mem_ready_o = is_ram       ? ram_ready_i :
                     is_inst_bram ? inst_bram_ready_i :
                     is_flash     ? flash_ready_i : 1'b1;

endmodule
