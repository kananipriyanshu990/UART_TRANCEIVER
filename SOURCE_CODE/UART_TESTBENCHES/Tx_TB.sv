`timescale 1ns/1ps

module Tx_TB;

    localparam integer DATA_BITS = 8;  // Test configuration
    localparam integer STOP_BITS = 1;  // Test configuration
    localparam integer PARITY_EN = 0;  // Test 8N1 operation

    logic clk;
    logic rst_n;
    logic baud_tick;

    logic [DATA_BITS-1:0] tx_data;
    logic tx_valid;
    logic tx_ready;

    logic tx_serial;
    logic tx_busy;
    logic tx_done;

    logic [10:0] expected_frame;  // 8N1 frame: start + 8 data + stop
    integer bit_index;
    integer baud_tick_count;

    UART_Tx #(.DATA_BITS  (DATA_BITS),
              .STOP_BITS  (STOP_BITS),
              .PARITY_EN  (PARITY_EN),
              .PARITY_ODD (0))
    UTX (.clk(clk),
         .rst_n(rst_n),
         .baud_tick(baud_tick),
         .tx_data(tx_data),
         .tx_valid(tx_valid),
         .tx_ready(tx_ready),
         .tx_serial(tx_serial),
         .tx_busy(tx_busy),
         .tx_done(tx_done));

    always #5 clk = ~clk;  // 100 MHz simulation clock

    initial begin
        clk = 1'b0;
        baud_tick = 1'b0;
        rst_n = 1'b0;
        tx_data = 8'h00;
        tx_valid = 1'b0;
        bit_index = 0;
        baud_tick_count = 0;

        repeat (3) @(posedge clk);
        #1;

        if (tx_serial !== 1'b1)
            $error("FAIL: TX output is not idle HIGH after reset.");

        if (tx_ready !== 1'b1)
            $error("FAIL: TX is not ready after reset.");

        rst_n = 1'b1;

        tx_data = 8'h96;
        tx_valid = 1'b1;

        @(posedge clk);
        #1;

        tx_valid = 1'b0;

        if (tx_ready !== 1'b0)
            $error("FAIL: TX accepted data but remained ready.");

        if (tx_busy !== 1'b1)
            $error("FAIL: TX did not enter busy state.");

        if (tx_serial !== 1'b0)
            $error("FAIL: Start bit is not LOW.");

        expected_frame = {1'b1, 8'h96, 1'b0};  // Stop + data + start

        bit_index = 0;

        repeat (10) begin
            repeat (10) @(posedge clk);
            baud_tick = 1'b1;

            @(posedge clk);
            #1;

            baud_tick = 1'b0;

            if (tx_serial !== expected_frame[bit_index + 1])
                $error("FAIL: Incorrect TX bit at frame position %0d.", bit_index + 1);

            bit_index = bit_index + 1;
            baud_tick_count = baud_tick_count + 1;
        end

        repeat (2) @(posedge clk);
        #1;

        if (tx_serial !== 1'b1)
            $error("FAIL: TX did not return to idle HIGH.");

        if (tx_busy !== 1'b0)
            $error("FAIL: TX remained busy after frame completion.");

        if (tx_ready !== 1'b1)
            $error("FAIL: TX did not become ready after frame completion.");

        if (tx_done !== 1'b1)
            $error("FAIL: tx_done was not asserted after frame completion.");

        @(posedge clk);
        #1;

        if (tx_done !== 1'b0)
            $error("FAIL: tx_done remained asserted for more than one clock.");

        $finish;
    end

endmodule