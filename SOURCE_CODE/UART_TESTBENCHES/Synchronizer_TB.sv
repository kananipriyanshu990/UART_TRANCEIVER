`timescale 1ns/1ps

module Synchronizer_TB;

    logic clk;
    logic rst_n;
    logic async_in;
    logic sync_out;

    UART_Synchronizer USYNC (.clk(clk),
                             .rst_n(rst_n),
                             .async_in (async_in),
                             .sync_out (sync_out));

    always #5 clk = ~clk;  // 100 MHz simulation clock

    initial begin
        clk      = 1'b0;
        rst_n    = 1'b0;
        async_in = 1'b0;

        repeat (2) @(posedge clk);
        #1;

        if (sync_out !== 1'b0)
            $error("FAIL: Synchronizer output is not reset.");

        rst_n = 1'b1;

        @(negedge clk);
        async_in = 1'b1;

        @(posedge clk);
        #1;

        if (sync_out !== 1'b0)
            $error("FAIL: Synchronizer output changed before two clock stages.");

        @(posedge clk);
        #1;

        if (sync_out !== 1'b1)
            $error("FAIL: Synchronizer output did not propagate after two clock stages.");

        @(negedge clk);
        async_in = 1'b0;

        @(posedge clk);
        #1;

        if (sync_out !== 1'b1)
            $error("FAIL: Synchronizer output changed before two clock stages.");

        @(posedge clk);
        #1;

        if (sync_out !== 1'b0)
            $error("FAIL: Synchronizer output did not propagate low after two clock stages.");

        $finish;
    end

    always @(posedge clk) begin
        if ((sync_out !== 1'b0) && (sync_out !== 1'b1))
            $error("FAIL: sync_out contains X/Z.");
    end
endmodule
