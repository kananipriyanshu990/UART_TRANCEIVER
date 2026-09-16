`timescale 1ns/1ps

module FIFO_TB;

    localparam integer DATA_WIDTH = 8;  // FIFO data width
    localparam integer DEPTH      = 4;  // Small depth for complete boundary testing

    localparam integer CNT_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1);  // FIFO count width

    logic clk;
    logic rst_n;

    logic                  wr_en;
    logic [DATA_WIDTH-1:0] wr_data;
    logic                  full;

    logic                  rd_en;
    logic [DATA_WIDTH-1:0] rd_data;
    logic                  empty;

    logic [CNT_WIDTH-1:0] count;

    UART_FIFO #(.DATA_WIDTH(DATA_WIDTH),
                .DEPTH(DEPTH))
    UFIFO (.clk(clk),
           .rst_n(rst_n),
           .wr_en(wr_en),
           .wr_data(wr_data),
           .full(full),
           .rd_en(rd_en),
           .rd_data(rd_data),
           .empty(empty),
           .count(count));

    always #5 clk = ~clk;  // 100 MHz simulation clock

    task automatic write_fifo(input logic [DATA_WIDTH-1:0] data);
        begin
            @(negedge clk);
            wr_data = data;
            wr_en = 1'b1;
            @(posedge clk);
            #1;
            wr_en = 1'b0;
        end
    endtask

    task automatic read_fifo(input logic [DATA_WIDTH-1:0] expected);
        begin
            @(negedge clk);
            rd_en = 1'b1;
            @(posedge clk);
            #1;

            if (rd_data !== expected)
                $error("FAIL: Expected 0x%02h, received 0x%02h.", expected, rd_data);

            rd_en = 1'b0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        wr_en = 1'b0;
        wr_data = 8'h00;
        rd_en = 1'b0;

        repeat (3) @(posedge clk);
        #1;

        if (empty !== 1'b1)
            $error("FAIL: FIFO is not empty after reset.");

        if (full !== 1'b0)
            $error("FAIL: FIFO is full after reset.");

        if (count !== 0)
            $error("FAIL: FIFO count is not zero after reset.");

        rst_n = 1'b1;

        write_fifo(8'h11);
        write_fifo(8'h22);
        write_fifo(8'h33);
        write_fifo(8'h44);

        if (full !== 1'b1)
            $error("FAIL: FIFO did not assert full after DEPTH writes.");

        if (count !== DEPTH)
            $error("FAIL: FIFO count is incorrect at full condition.");

        @(negedge clk);
        wr_data = 8'h55;
        wr_en = 1'b1;

        @(posedge clk);
        #1;

        if (count !== DEPTH)
            $error("FAIL: FIFO accepted a write while full.");

        wr_en = 1'b0;

        read_fifo(8'h11);
        read_fifo(8'h22);
        read_fifo(8'h33);
        read_fifo(8'h44);

        if (empty !== 1'b1)
            $error("FAIL: FIFO did not assert empty after reading all entries.");

        if (count !== 0)
            $error("FAIL: FIFO count is not zero after all reads.");

        write_fifo(8'hA1);
        write_fifo(8'hB2);
        write_fifo(8'hC3);
        write_fifo(8'hD4);

        read_fifo(8'hA1);
        read_fifo(8'hB2);

        write_fifo(8'hE5);
        write_fifo(8'hF6);

        read_fifo(8'hC3);
        read_fifo(8'hD4);
        read_fifo(8'hE5);
        read_fifo(8'hF6);

        if (empty !== 1'b1)
            $error("FAIL: FIFO wraparound test did not end empty.");

        @(negedge clk);
        wr_data = 8'hAA;
        wr_en   = 1'b1;
        rd_en   = 1'b1;

        @(posedge clk);
        #1;

        wr_en = 1'b0;
        rd_en = 1'b0;

        write_fifo(8'hBB);
        read_fifo(8'hAA);

        if (count !== 1)
            $error("FAIL: Simultaneous read/write handling is incorrect.");

        read_fifo(8'hBB);

        if (empty !== 1'b1)
            $error("FAIL: FIFO did not return to empty after simultaneous operation.");

        $finish;
    end
endmodule