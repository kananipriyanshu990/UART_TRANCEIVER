module UART_Baud_Generator #(parameter integer CLK_FREQ  = 50_000_000,
                             parameter integer BAUD_RATE = 115200,
                             parameter integer ACC_WIDTH = 32)
                            (input  wire clk,
                             input  wire rst_n,
                             output reg  baud_tick,
                             output reg  baud16_tick);

    localparam integer BAUD_RATE_16 = BAUD_RATE * 16;
    localparam [ACC_WIDTH-1:0] PHASE_INC =
        (BAUD_RATE * (64'd1 << ACC_WIDTH)) / CLK_FREQ;
    localparam [ACC_WIDTH-1:0] PHASE_INC_16 =
        (BAUD_RATE_16 * (64'd1 << ACC_WIDTH)) / CLK_FREQ;

    reg [ACC_WIDTH-1:0] phase_acc;
    reg [ACC_WIDTH-1:0] phase_acc_16;

    wire [ACC_WIDTH:0] phase_sum =
        {1'b0, phase_acc} + {1'b0, PHASE_INC};
    wire [ACC_WIDTH:0] phase_sum_16 =
        {1'b0, phase_acc_16} + {1'b0, PHASE_INC_16};

    always @(posedge clk) begin
        if (rst_n == 1'b0) begin
            phase_acc <= {ACC_WIDTH{1'b0}};
            phase_acc_16 <= {ACC_WIDTH{1'b0}};

            baud_tick <= 1'b0;
            baud16_tick <= 1'b0;
        end
        else begin
            phase_acc <= phase_sum[ACC_WIDTH-1:0];
            baud_tick <= phase_sum[ACC_WIDTH];

            phase_acc_16 <= phase_sum_16[ACC_WIDTH-1:0];
            baud16_tick <= phase_sum_16[ACC_WIDTH];
        end
    end
endmodule