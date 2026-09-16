module UART_Synchronizer (input  wire clk,
                          input  wire rst_n,
                          input  wire async_in,
                          output wire sync_out);

    reg sync_ff1;  // First stage may enter metastability
    reg sync_ff2;  // Second stage provides the synchronized output

    always @(posedge clk) begin
        if (!rst_n) begin
            sync_ff1 <= 1'b0;  // Initialize synchronizer chain
            sync_ff2 <= 1'b0;  // Initialize synchronized output
        end
        else begin
            sync_ff1 <= async_in;  // Capture asynchronous input
            sync_ff2 <= sync_ff1;  // Synchronize through second stage
        end
    end

    assign sync_out = sync_ff2;  // Expose synchronized signal
endmodule