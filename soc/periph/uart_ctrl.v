// soc/periph/uart_ctrl.v - FIFO-based UART controller (TX + RX)
`timescale 1ns/1ps

// ============================================================================
// Module: uart_ctrl
// Function: UART controller with configurable-depth TX FIFO and RX support
//
// Register map:
//   0x00: TX_DATA  - Write: push byte[7:0] into TX FIFO
//   0x04: STATUS   - Read:  [0]=tx_wr_ready, [1]=tx_idle, [2]=rx_ready,
//                            [3]=fifo_full, [10:4]=fifo_count
//   0x08: CTRL     - Read/Write: [0]=tx_enable, [1]=rx_enable
//   0x0C: BAUD_DIV - Baud rate divider (reserved, baud set at compile time)
//   0x10: RX_DATA  - Read:  [7:0]=received byte (read clears rx_ready)
//   0x14: IRQ_FLAG - Read:  [0]=tx_done, [1]=rx_done (write 1 to clear)
//
// Parameters:
//   FIFO_DEPTH  - TX FIFO depth (default 16)
//   CLK_FREQ    - System clock frequency in Hz
//   BAUD_RATE   - UART baud rate
// ============================================================================
module uart_ctrl #(
    parameter CLK_FREQ         = 200_000_000,
    parameter BAUD_RATE        = 115200,
    parameter FIFO_DEPTH       = 16,
    parameter FIFO_ADDR_WIDTH  = 6          // ceil(log2(FIFO_DEPTH))
) (
    // ========== System ==========
    input  wire        clk_i,
    input  wire        rst_n_i,

    // ========== CPU bus ==========
    input  wire        we_i,
    input  wire [31:0] addr_i,
    input  wire [31:0] wdata_i,
    output reg  [31:0] rdata_o,

    // ========== UART pins ==========
    output wire        tx_pin_o,
    input  wire        rx_pin_i,

    // ========== Debug ==========
    output wire        tx_busy_o,
    output wire        tx_ready_o,
    output wire [FIFO_ADDR_WIDTH:0] debug_fifo_count_o,
    output wire        debug_fifo_full_o,
    output wire        debug_fifo_empty_o,
    output wire        debug_rx_valid_o,
    output wire        debug_rx_ready_o
);

// ============================================================================
// Register addresses
// ============================================================================
localparam REG_TX_DATA  = 8'h00;
localparam REG_STATUS   = 8'h04;
localparam REG_CTRL     = 8'h08;
localparam REG_BAUD_DIV = 8'h0C;
localparam REG_RX_DATA  = 8'h10;
localparam REG_IRQ_FLAG = 8'h14;

// ============================================================================
// State machine
// ============================================================================
localparam ST_IDLE    = 2'b00;  // Waiting for data
localparam ST_SENDING = 2'b01;  // Character being transmitted by uart_tx

reg [1:0] state;

// ============================================================================
// TX FIFO
// ============================================================================
reg  [7:0]  fifo_mem [0:FIFO_DEPTH-1];
reg  [FIFO_ADDR_WIDTH-1:0] wr_ptr;
reg  [FIFO_ADDR_WIDTH-1:0] rd_ptr;
reg  [FIFO_ADDR_WIDTH:0]   fifo_count;

wire fifo_full;
wire fifo_empty;

assign fifo_full  = (fifo_count == FIFO_DEPTH);
assign fifo_empty = (fifo_count == 0);

// Next-pointer helpers (circular)
wire [FIFO_ADDR_WIDTH-1:0] next_wr_ptr;
wire [FIFO_ADDR_WIDTH-1:0] next_rd_ptr;

assign next_wr_ptr = (wr_ptr == FIFO_DEPTH-1) ? 0 : (wr_ptr + 1);
assign next_rd_ptr = (rd_ptr == FIFO_DEPTH-1) ? 0 : (rd_ptr + 1);

// ============================================================================
// Write edge detection (bus_arbiter holds we_i high until ack)
// ============================================================================
reg we_prev;
wire we_rising;

always @(posedge clk_i) begin
    if (!rst_n_i)
        we_prev <= 1'b0;
    else
        we_prev <= we_i;
end

assign we_rising = we_i && !we_prev;

// ============================================================================
// Control registers
// ============================================================================
reg        tx_enable;
reg        tx_irq_enable;
reg        rx_enable;
reg [15:0] baud_divider;

// ============================================================================
// RX data path
// ============================================================================
reg [7:0]  rx_data_reg;
reg        rx_ready_reg;

// uart_rx handshake
wire [7:0] uart_rx_data;
wire       uart_rx_valid;

// ============================================================================
// IRQ flags
// ============================================================================
reg        irq_flag_tx;
reg        irq_flag_rx;

// ============================================================================
// TX data path
// ============================================================================
reg [7:0]  tx_data_reg;
reg        tx_valid_reg;

// uart_tx handshake
wire tx_ready;

// ============================================================================
// Main control block
// ============================================================================
integer i;

always @(posedge clk_i) begin
    if (!rst_n_i) begin
        state         <= ST_IDLE;
        tx_enable     <= 1'b1;
        tx_irq_enable <= 1'b0;
        rx_enable     <= 1'b1;
        baud_divider  <= CLK_FREQ / BAUD_RATE;

        wr_ptr      <= 0;
        rd_ptr      <= 0;
        fifo_count  <= 0;

        tx_data_reg  <= 8'b0;
        tx_valid_reg <= 1'b0;

        rx_data_reg  <= 8'b0;
        rx_ready_reg <= 1'b0;
        irq_flag_tx  <= 1'b0;
        irq_flag_rx  <= 1'b0;

        rdata_o <= 32'b0;

        for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
            fifo_mem[i] <= 8'b0;
        end

    end else begin
        // --- Defaults ---
        tx_valid_reg <= 1'b0;

        // --- FIFO write (single-cycle, edge-triggered) ---
        if (we_rising && (addr_i[7:0] == REG_TX_DATA) && tx_enable && !fifo_full) begin
            fifo_mem[wr_ptr] <= wdata_i[7:0];
            wr_ptr     <= next_wr_ptr;
            fifo_count <= fifo_count + 1;
        end

        // --- Register writes ---
        if (we_i) begin
            case (addr_i[7:0])
                REG_CTRL: begin
                    tx_enable     <= wdata_i[0];
                    rx_enable     <= wdata_i[1];
                    tx_irq_enable <= 1'b0;  // deprecated, use IRQ_FLAG instead
                end
                REG_BAUD_DIV: begin
                    baud_divider <= wdata_i[15:0];
                end
                default: ;
            endcase
        end

        // --- IRQ flag clear (write 1 to clear) ---
        if (we_i && (addr_i[7:0] == REG_IRQ_FLAG)) begin
            if (wdata_i[0]) irq_flag_tx <= 1'b0;
            if (wdata_i[1]) irq_flag_rx <= 1'b0;
        end

        // --- RX data capture from uart_rx ---
        if (uart_rx_valid && rx_enable) begin
            rx_data_reg  <= uart_rx_data;
            rx_ready_reg <= 1'b1;
            irq_flag_rx  <= 1'b1;
        end

        // --- RX read clears rx_ready ---
        if (rx_ready_reg && (addr_i[7:0] == REG_RX_DATA)) begin
            rx_ready_reg <= 1'b0;
        end

        // --- State machine ---
        case (state)
            ST_IDLE: begin
                if (!fifo_empty && tx_ready && tx_enable) begin
                    // Pop FIFO and start transmission
                    tx_data_reg  <= fifo_mem[rd_ptr];
                    tx_valid_reg <= 1'b1;
                    rd_ptr       <= next_rd_ptr;
                    fifo_count   <= fifo_count - 1;
                    state        <= ST_SENDING;
                end
            end

            ST_SENDING: begin
                // Wait for uart_tx to finish (tx_ready goes low then high)
                if (tx_ready) begin
                    if (!fifo_empty && tx_enable) begin
                        // Immediately start next byte
                        tx_data_reg  <= fifo_mem[rd_ptr];
                        tx_valid_reg <= 1'b1;
                        rd_ptr       <= next_rd_ptr;
                        fifo_count   <= fifo_count - 1;
                        irq_flag_tx  <= 1'b1;      // TX done IRQ
                        // stay in ST_SENDING
                    end else begin
                        irq_flag_tx  <= 1'b1;      // TX done IRQ (last byte)
                        state <= ST_IDLE;
                    end
                end
            end

            default: state <= ST_IDLE;
        endcase

        // --- Register reads ---
        case (addr_i[7:0])
            REG_TX_DATA:  rdata_o <= {24'b0, 8'b0};     // TX_DATA is write-only
            REG_STATUS:   rdata_o <= {21'b0,
                                fifo_count,              // [10:4] 7-bit FIFO count
                                fifo_full,               // [3]
                                rx_ready_reg,            // [2] rx_ready
                                (state == ST_IDLE && tx_ready),  // [1] tx_idle
                                !fifo_full};             // [0] tx_wr_ready
            REG_CTRL:     rdata_o <= {30'b0, rx_enable, tx_enable};
            REG_BAUD_DIV: rdata_o <= {16'b0, baud_divider};
            REG_RX_DATA:  rdata_o <= {24'b0, rx_data_reg};
            REG_IRQ_FLAG: rdata_o <= {30'b0, irq_flag_rx, irq_flag_tx};
            default:      rdata_o <= 32'b0;
        endcase

    end
end

// ============================================================================
// uart_tx instance
// ============================================================================
uart_tx #(
    .CLK_FREQ (CLK_FREQ),
    .BAUD_RATE(BAUD_RATE)
) u_uart_tx (
    .clk_i           (clk_i),
    .rst_n_i         (rst_n_i),
    .tx_data_i       (tx_data_reg),
    .tx_valid_i      (tx_valid_reg),
    .tx_ready_o      (tx_ready),
    .tx_pin_o        (tx_pin_o),
    .debug_state_o   (),
    .debug_baud_cnt_o(),
    .debug_bit_cnt_o (),
    .debug_shift_reg_o()
);

// ============================================================================
// uart_rx instance
// ============================================================================
uart_rx #(
    .CLK_FREQ (CLK_FREQ),
    .BAUD_RATE(BAUD_RATE)
) u_uart_rx (
    .clk_i           (clk_i),
    .rst_n_i         (rst_n_i),
    .rx_pin_i        (rx_pin_i),
    .rx_data_o       (uart_rx_data),
    .rx_valid_o      (uart_rx_valid),
    .debug_state_o   (),
    .debug_sample_cnt_o(),
    .debug_bit_cnt_o ()
);

// ============================================================================
// Debug outputs
// ============================================================================
assign tx_busy_o           = (state != ST_IDLE);
assign tx_ready_o          = tx_ready;
assign debug_fifo_count_o  = fifo_count;
assign debug_fifo_full_o   = fifo_full;
assign debug_fifo_empty_o  = fifo_empty;
assign debug_rx_valid_o    = uart_rx_valid;
assign debug_rx_ready_o    = rx_ready_reg;

endmodule
