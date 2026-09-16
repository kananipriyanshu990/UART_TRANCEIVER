module UART_Top #(parameter integer CLK_FREQ   = 50_000_000,  // System clock frequency
                  parameter integer BAUD_RATE  = 115200,     // UART baud rate
                  parameter integer ACC_WIDTH  = 32,         // Baud-generator accumulator width
                  parameter integer DATA_BITS  = 8,          // UART data width
                  parameter integer STOP_BITS  = 1,          // UART stop-bit count
                  parameter integer PARITY_EN  = 0,          // UART parity enable
                  parameter integer PARITY_ODD = 0,          // UART parity type
                  parameter integer FIFO_DEPTH = 16)          // TX and RX FIFO depth
                 (input wire clk,
                  input wire rst_n,

                  input wire [DATA_BITS-1:0] tx_data,
                  input wire tx_valid,
                  output wire tx_ready,
                  output wire tx,

                  input wire rx,
                  output wire [DATA_BITS-1:0] rx_data,
                  output wire rx_valid,
                  input wire rx_ready,

                  output wire parity_error,
                  output wire frame_error);

    wire baud_tick;  // One-cycle enable at the UART baud rate
    wire baud16_tick;  // One-cycle enable at 16 times the UART baud rate
    wire rx_sync;  // Synchronized UART RX signal

    wire [DATA_BITS-1:0] tx_fifo_rd_data;  // Data returned by TX FIFO
    wire tx_fifo_full;  // TX FIFO full status
    wire tx_fifo_empty;  // TX FIFO empty status
    wire tx_fifo_wr_en;  // TX FIFO write request
    wire tx_fifo_rd_en;  // TX FIFO read request

    reg [DATA_BITS-1:0] tx_data_reg;  // Prefetched TX data
    reg tx_data_valid;  // Indicates valid prefetched TX data
    reg tx_load_pending;  // Indicates an outstanding TX FIFO read

    wire tx_core_ready;  // UART TX ready status
    wire tx_core_valid;  // UART TX data-valid handshake

    wire [DATA_BITS-1:0] rx_core_data;  // Data produced by UART RX
    wire rx_core_valid;  // One-cycle valid pulse from UART RX
    wire rx_core_parity_error;  // Current-frame parity error
    wire rx_core_frame_error;  // Current-frame framing error

    wire rx_fifo_full;  // RX FIFO full status
    wire rx_fifo_empty;  // RX FIFO empty status
    wire rx_fifo_wr_en;  // RX FIFO write request
    wire rx_fifo_rd_en;  // RX FIFO read request
    wire [DATA_BITS-1:0] rx_fifo_rd_data;  // Data returned by RX FIFO

    reg [DATA_BITS-1:0] rx_data_reg;  // Prefetched RX data
    reg rx_data_valid;  // Indicates valid data available to external interface
    reg rx_load_pending;  // Indicates an outstanding RX FIFO read

    assign tx_ready = rst_n && !tx_fifo_full;  // Accept TX data while FIFO has space
    assign tx_fifo_wr_en = tx_valid && tx_ready;  // Write accepted TX transfer into FIFO

    assign tx_fifo_rd_en = !tx_data_valid && !tx_load_pending && !tx_fifo_empty;  // Request TX FIFO prefetch when TX path is idle
    assign tx_core_valid = tx_data_valid;  // Present prefetched data to UART TX

    assign rx_fifo_wr_en = rx_core_valid && !rx_fifo_full;  // Store successfully received data
    assign rx_fifo_rd_en = !rx_data_valid && !rx_load_pending && !rx_fifo_empty;  // Request RX FIFO prefetch when output is available

    assign rx_valid = rst_n && rx_data_valid;  // Present buffered RX data to external interface
    assign rx_data = rx_data_reg;  // Present buffered RX data
    assign parity_error = rx_core_parity_error;  // Propagate RX parity error pulse
    assign frame_error = rx_core_frame_error;  // Propagate RX framing error pulse

    UART_Baud_Generator #(.CLK_FREQ  (CLK_FREQ),
                          .BAUD_RATE (BAUD_RATE),
                          .ACC_WIDTH (ACC_WIDTH))
    URT_BAUD_GEN (.clk(clk),
                  .rst_n(rst_n),
                  .baud_tick(baud_tick),
                  .baud16_tick(baud16_tick));

    UART_Synchronizer URT_SYNC (.clk(clk),
                                .rst_n(rst_n),
                                .async_in(rx),
                                .sync_out(rx_sync));

    UART_FIFO #(.DATA_WIDTH(DATA_BITS),
                .DEPTH(FIFO_DEPTH))
    URT_TX_FIFO (.clk(clk),
                 .rst_n(rst_n),
                 .wr_en(tx_fifo_wr_en),
                 .wr_data(tx_data),
                 .full(tx_fifo_full),
                 .rd_en(tx_fifo_rd_en),
                 .rd_data(tx_fifo_rd_data),
                 .empty(tx_fifo_empty),
                 .count());

    UART_Tx #(.DATA_BITS(DATA_BITS),
              .STOP_BITS(STOP_BITS),
              .PARITY_EN(PARITY_EN),
              .PARITY_ODD(PARITY_ODD))
    URT_TX (.clk(clk),
            .rst_n(rst_n),
            .baud_tick(baud_tick),
            .tx_data(tx_data_reg),
            .tx_valid(tx_core_valid),
            .tx_ready(tx_core_ready),
            .tx_serial(tx),
            .tx_busy(),
            .tx_done());

    UART_Rx #(.DATA_BITS(DATA_BITS),
              .STOP_BITS(STOP_BITS),
              .PARITY_EN(PARITY_EN),
              .PARITY_ODD(PARITY_ODD))
    URT_RX (.clk(clk),
            .rst_n(rst_n),
            .baud16_tick(baud16_tick),
            .rx_in(rx_sync),
            .rx_data(rx_core_data),
            .rx_valid(rx_core_valid),
            .rx_busy(),
            .parity_error(rx_core_parity_error),
            .frame_error(rx_core_frame_error));

    UART_FIFO #(.DATA_WIDTH(DATA_BITS),
                .DEPTH(FIFO_DEPTH))
    URT_RX_FIFO (.clk(clk),
                 .rst_n(rst_n),
                 .wr_en(rx_fifo_wr_en),
                 .wr_data(rx_core_data),
                 .full(rx_fifo_full),
                 .rd_en(rx_fifo_rd_en),
                 .rd_data(rx_fifo_rd_data),
                 .empty(rx_fifo_empty),
                 .count());

    always @(posedge clk) begin
        if (!rst_n) begin
            tx_data_reg     <= {DATA_BITS{1'b0}};
            tx_data_valid   <= 1'b0;
            tx_load_pending <= 1'b0;
        end
        else begin
            if (tx_fifo_rd_en)
                tx_load_pending <= 1'b1;  // Record outstanding TX FIFO read

            if (tx_load_pending) begin
                tx_data_reg     <= tx_fifo_rd_data;  // Capture synchronously-read TX FIFO data
                tx_data_valid   <= 1'b1;  // Present captured data to UART TX
                tx_load_pending <= 1'b0;  // Complete TX FIFO prefetch
            end

            if (tx_data_valid && tx_core_ready)
                tx_data_valid <= 1'b0;  // Complete UART TX handshake
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            rx_data_reg     <= {DATA_BITS{1'b0}};
            rx_data_valid   <= 1'b0;
            rx_load_pending <= 1'b0;
        end
        else begin
            if (rx_fifo_rd_en)
                rx_load_pending <= 1'b1;  // Record outstanding RX FIFO read

            if (rx_load_pending) begin
                rx_data_reg     <= rx_fifo_rd_data;  // Capture synchronously-read RX FIFO data
                rx_data_valid   <= 1'b1;  // Present captured data to external interface
                rx_load_pending <= 1'b0;  // Complete RX FIFO prefetch
            end

            if (rx_data_valid && rx_ready)
                rx_data_valid <= 1'b0;  // Complete external RX handshake
        end
    end
endmodule