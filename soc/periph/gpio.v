// soc/periph/gpio.v — 通用输入输出控制器 (GPIO)
`timescale 1ns/1ps

// ============================================================================
// 模块: gpio
// 功能: 通用输入输出 (GPIO) 控制器，支持 32 位双向 IO
// 描述:
//   本模块实现一个 32 位 GPIO 控制器，具备以下功能:
//   - 每个引脚可独立配置为输入或输出 (通过输出使能 OE 控制)
//   - 支持电平触发和边沿触发中断
//   - 中断标志支持写 1 清除
//
//   寄存器地址映射:
//     0x00: GPIO_OUT  - 输出数据寄存器
//     0x04: GPIO_OE   - 输出使能寄存器 (1=输出, 0=输入)
//     0x08: GPIO_IN   - 输入数据寄存器 (只读)
//     0x0C: GPIO_IE   - 中断使能寄存器
//     0x10: GPIO_EDGE - 边沿触发选择 (0=电平, 1=边沿)
//     0x14: GPIO_IF   - 中断标志寄存器 (写 1 清除)
// ============================================================================
module gpio (
    // ========== 系统接口 ==========
    input  wire        clk_i,              // 时钟信号
    input  wire        rst_n_i,            // 复位信号 (低电平有效)

    // ========== 总线接口 ==========
    input  wire        we_i,               // 写使能
    input  wire        re_i,               // 读使能
    input  wire [31:0] addr_i,             // 寄存器地址
    input  wire [31:0] wdata_i,            // 写数据
    output reg  [31:0] rdata_o,            // 读数据

    // ========== 外部引脚 ==========
    input  wire [31:0] gpio_in_i,          // GPIO 输入信号
    output wire [31:0] gpio_out_o,         // GPIO 输出数据
    output wire [31:0] gpio_oe_o,          // GPIO 输出使能 (1=输出)

    // ========== 中断输出 ==========
    output wire        interrupt_o,        // 中断信号 (任何使能的中断触发)

    // ========== 调试输出 ==========
    output wire [31:0] debug_gpio_out,     // 调试: 输出寄存器
    output wire [31:0] debug_gpio_oe,      // 调试: 输出使能寄存器
    output wire [31:0] debug_gpio_in,      // 调试: 输入寄存器
    output wire [31:0] debug_gpio_if       // 调试: 中断标志寄存器
);

// 寄存器地址偏移
localparam GPIO_OUT_ADDR  = 8'h00;
localparam GPIO_OE_ADDR   = 8'h04;
localparam GPIO_IN_ADDR   = 8'h08;
localparam GPIO_IE_ADDR   = 8'h0C;
localparam GPIO_EDGE_ADDR = 8'h10;
localparam GPIO_IF_ADDR   = 8'h14;

// 内部寄存器
reg [31:0] gpio_out;
reg [31:0] gpio_oe;
reg [31:0] gpio_ie;      // 中断使能
reg [31:0] gpio_edge;    // 0=电平触发, 1=边沿触发
reg [31:0] gpio_if;      // 中断标志
wire gpio_out_all;



// 输入同步 (两级同步器消除亚稳态)
reg [31:0] gpio_in_sync1, gpio_in_sync2;
always @(posedge clk_i) begin
    gpio_in_sync1 <= gpio_in_i;
    gpio_in_sync2 <= gpio_in_sync1;
end
wire [31:0] gpio_in_sync = gpio_in_sync2;

// 边沿检测
reg [31:0] gpio_in_prev;
wire [31:0] rising_edge;
wire [31:0] falling_edge;

always @(posedge clk_i) begin
    gpio_in_prev <= gpio_in_sync;
end

assign rising_edge  = gpio_in_sync & ~gpio_in_prev;     // 上升沿
assign falling_edge = ~gpio_in_sync & gpio_in_prev;     // 下降沿
wire [31:0] any_edge = rising_edge | falling_edge;

// 中断产生逻辑
wire [31:0] interrupt_cond;
genvar i;
generate
    for (i = 0; i < 32; i = i + 1) begin : gen_intr
        assign interrupt_cond[i] = gpio_ie[i] && (
            (gpio_edge[i] && any_edge[i]) ||          // 边沿触发
            (!gpio_edge[i] && gpio_in_sync[i])        // 电平触发 (高电平)
        );
    end
endgenerate

// 中断标志更新 (合并清除和置位为单一赋值，消除NBA覆盖问题)
always @(posedge clk_i) begin
    if (!rst_n_i) begin
        gpio_if <= 32'b0;
    end else begin
        // 先计算清除后的值，再 OR 新触发的中断条件
        if (we_i && (addr_i[7:0] == GPIO_IF_ADDR))
            gpio_if <= (gpio_if & ~wdata_i) | interrupt_cond;
        else
            gpio_if <= gpio_if | interrupt_cond;
    end
end

// 总中断输出 (只要有任何中断标志且使能)
assign interrupt_o = |(gpio_if & gpio_ie);

// 寄存器写操作
always @(posedge clk_i) begin
    if (!rst_n_i) begin
        gpio_out  <= 32'b0;
        gpio_oe   <= 32'b0;
        gpio_ie   <= 32'b0;
        gpio_edge <= 32'b0;
    end else if (we_i) begin
        case (addr_i[7:0])
            GPIO_OUT_ADDR:  gpio_out  <= wdata_i;
            GPIO_OE_ADDR:   gpio_oe   <= wdata_i;
            GPIO_IE_ADDR:   gpio_ie   <= wdata_i;
            GPIO_EDGE_ADDR: gpio_edge <= wdata_i;
            // GPIO_IF_ADDR 写在中断标志 always 块中独立处理
            default: ;
        endcase
    end
end

// 读数据
always @(*) begin
    case (addr_i[7:0])
        GPIO_OUT_ADDR:  rdata_o = gpio_out;
        GPIO_OE_ADDR:   rdata_o = gpio_oe;
        GPIO_IN_ADDR:   rdata_o = gpio_in_sync;
        GPIO_IE_ADDR:   rdata_o = gpio_ie;
        GPIO_EDGE_ADDR: rdata_o = gpio_edge;
        GPIO_IF_ADDR:   rdata_o = gpio_if;
        default:        rdata_o = 32'b0;
    endcase
end

// 输出 (使用 assign 透传, 端口已改为 wire)
assign gpio_out_o = gpio_out;
assign gpio_oe_o  = gpio_oe;

assign gpio_out_all = gpio_out & gpio_oe; // 实际输出到引脚的值 (仅供调试)

assign debug_gpio_out = gpio_out;
assign debug_gpio_oe  = gpio_oe;
assign debug_gpio_in  = gpio_in_sync;
assign debug_gpio_if  = gpio_if;

endmodule
