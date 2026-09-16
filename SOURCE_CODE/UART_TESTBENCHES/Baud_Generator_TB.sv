`timescale 1ns/1ps

module UART_Baud_Generator_tb;

    localparam integer CLK_FREQ  = 100_000_000;
    localparam integer BAUD_RATE = 1_000_000;
    localparam integer ACC_WIDTH = 32;

    localparam integer SIM_CYCLES = 10_000;
    localparam integer EXPECTED_BAUD_TICKS   = (SIM_CYCLES * BAUD_RATE) / CLK_FREQ;
    localparam integer EXPECTED_BAUD16_TICKS = (SIM_CYCLES * BAUD_RATE * 16) / CLK_FREQ;
    localparam integer TOLERANCE = 1;

    logic clk;
    logic rst_n;

    logic baud_tick;
    logic baud16_tick;

    integer baud_tick_count;
    integer baud16_tick_count;

    UART_Baud_Generator #(.CLK_FREQ  (CLK_FREQ),
                          .BAUD_RATE (BAUD_RATE),
                          .ACC_WIDTH (ACC_WIDTH)) 
    BAUD_GEN (.clk(clk),
              .rst_n(rst_n),
              .baud_tick(baud_tick),
              .baud16_tick(baud16_tick));

    always #5 clk = ~clk;  // 100 MHz simulation clock

    always @(negedge clk) begin
        if (rst_n) begin
            if (baud_tick)
                baud_tick_count = baud_tick_count + 1;

            if (baud16_tick)
                baud16_tick_count = baud16_tick_count + 1;

            if ((baud_tick !== 1'b0) && (baud_tick !== 1'b1))
                $error("FAIL: baud_tick contains X/Z.");

            if ((baud16_tick !== 1'b0) && (baud16_tick !== 1'b1))
                $error("FAIL: baud16_tick contains X/Z.");
        end
    end

    property baud_tick_single_cycle;
        @(posedge clk) disable iff (!rst_n)
        baud_tick |=> !baud_tick;
    endproperty

    property baud16_tick_single_cycle;
        @(posedge clk) disable iff (!rst_n)
        baud16_tick |=> !baud16_tick;
    endproperty

    assert property (baud_tick_single_cycle)
        else $error("FAIL: baud_tick is wider than one clock cycle.");

    assert property (baud16_tick_single_cycle)
        else $error("FAIL: baud16_tick is wider than one clock cycle.");

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;

        baud_tick_count   = 0;
        baud16_tick_count = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        repeat (SIM_CYCLES) @(posedge clk);
        @(negedge clk);

        if ((baud_tick_count < EXPECTED_BAUD_TICKS - TOLERANCE) ||
            (baud_tick_count > EXPECTED_BAUD_TICKS + TOLERANCE))
            $error("FAIL: baud_tick count outside tolerance.");

        if ((baud16_tick_count < EXPECTED_BAUD16_TICKS - TOLERANCE) ||
            (baud16_tick_count > EXPECTED_BAUD16_TICKS + TOLERANCE))
            $error("FAIL: baud16_tick count outside tolerance.");
        $finish;
    end
endmodule