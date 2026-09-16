`timescale 1ns/1ps

module RX_TB;

    localparam integer DATA_BITS = 8;                                                         // Number of data bits
    localparam integer STOP_BITS = 1;                                                         // Number of stop bits
    localparam integer PARITY_EN = 0;                                                         // Disable parity for 8N1 operation

    localparam logic [DATA_BITS-1:0] TEST_DATA = 8'h96;                                       // Test byte

    logic clk;
    logic rst_n;
    logic baud16_tick;
    logic rx_in;

    logic [DATA_BITS-1:0] rx_data;
    logic rx_valid;
    logic rx_busy;
    logic parity_error;
    logic frame_error;

    UART_Rx #(.DATA_BITS(DATA_BITS),
              .STOP_BITS(STOP_BITS),
              .PARITY_EN(PARITY_EN),
              .PARITY_ODD(0)) 
    URX (.clk(clk),
         .rst_n(rst_n),
         .baud16_tick(baud16_tick),
         .rx_in (rx_in),
         .rx_data(rx_data),
         .rx_valid(rx_valid),
         .rx_busy(rx_busy),
         .parity_error(parity_error),
         .frame_error(frame_error));

    always #5 clk = ~clk;                                                                       // 100 MHz simulation clock

    initial begin
        baud16_tick = 1'b0;

        forever begin
            repeat (10) @(negedge clk);
            baud16_tick = 1'b1;                                                                 // Generate 10 MHz oversampling tick
            @(negedge clk);
            baud16_tick = 1'b0;
        end
    end

    task automatic send_uart_bit(input logic bit_value);
        begin
            rx_in = bit_value;                                                                  // Set UART line level
            repeat (16) @(posedge baud16_tick);                                                 // Hold bit for exactly 16 oversampling ticks
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        rx_in = 1'b1;

        repeat (5) @(posedge clk);
        #1;

        if (rx_data !== 8'h00)
            $error("FAIL: RX data is not reset.");

        if (rx_valid !== 1'b0)
            $error("FAIL: rx_valid is asserted during reset.");

        if (rx_busy !== 1'b0)
            $error("FAIL: rx_busy is asserted during reset.");

        if (parity_error !== 1'b0)
            $error("FAIL: parity_error is asserted during reset.");

        if (frame_error !== 1'b0)
            $error("FAIL: frame_error is asserted during reset.");

        rst_n = 1'b1;

        repeat (5) @(posedge clk);

        send_uart_bit(1'b0);                                                                       // Start bit
        send_uart_bit(TEST_DATA[0]);                                                               // D0
        send_uart_bit(TEST_DATA[1]);                                                               // D1
        send_uart_bit(TEST_DATA[2]);                                                               // D2
        send_uart_bit(TEST_DATA[3]);                                                               // D3
        send_uart_bit(TEST_DATA[4]);                                                               // D4
        send_uart_bit(TEST_DATA[5]);                                                               // D5
        send_uart_bit(TEST_DATA[6]);                                                               // D6
        send_uart_bit(TEST_DATA[7]);                                                               // D7
        send_uart_bit(1'b1);                                                                       // Stop bit

        @(posedge clk);
        #1;

        if (rx_data !== TEST_DATA)
            $error("FAIL: Received data mismatch. Expected 0x%02h, got 0x%02h.", TEST_DATA, rx_data);

        if (rx_valid !== 1'b1)
            $error("FAIL: rx_valid was not asserted after valid frame.");

        if (rx_busy !== 1'b0)
            $error("FAIL: rx_busy remained asserted after frame completion.");

        if (parity_error !== 1'b0)
            $error("FAIL: Unexpected parity error.");

        if (frame_error !== 1'b0)
            $error("FAIL: Unexpected frame error.");

        @(posedge clk);
        #1;

        if (rx_valid !== 1'b0)
            $error("FAIL: rx_valid remained asserted for more than one clock.");

        $finish;
    end
endmodule