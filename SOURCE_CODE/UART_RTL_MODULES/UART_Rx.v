module UART_Rx #(parameter integer DATA_BITS = 8,  // Number of received data bits
                 parameter integer STOP_BITS = 1,  // Number of stop bits
                 parameter integer PARITY_EN = 0,  // Enable parity checking
                 parameter integer PARITY_ODD = 0)   // 0 = even parity, 1 = odd parity
                (input wire clk,
                 input wire rst_n,
                 input wire baud16_tick,
                 input wire rx_in,
                
                 output reg [DATA_BITS-1:0] rx_data,
                 output reg rx_valid,
                 output reg rx_busy,
                 output reg parity_error,
                 output reg frame_error);

    localparam integer DATA_CNT_WIDTH = (DATA_BITS <= 1) ? 1 : $clog2(DATA_BITS);  // Width required for data counter
    localparam integer STOP_CNT_WIDTH = (STOP_BITS <= 1) ? 1 : $clog2(STOP_BITS);  // Width required for stop counter

    localparam [2:0] ST_IDLE = 3'd0;  // Waiting for start bit
    localparam [2:0] ST_START = 3'd1;  // Validating start bit
    localparam [2:0] ST_DATA = 3'd2;  // Receiving data bits
    localparam [2:0] ST_PARITY = 3'd3;  // Receiving parity bit
    localparam [2:0] ST_STOP = 3'd4;  // Receiving stop bit

    reg [2:0] state;

    reg [3:0] sample_count;  // Counts oversampling ticks within one UART bit
    reg [DATA_CNT_WIDTH-1:0] data_count;  // Current data-bit index
    reg [STOP_CNT_WIDTH-1:0] stop_count;  // Current stop-bit index

    reg [DATA_BITS-1:0] data_reg;  // Temporary received data
    reg parity_bad;  // Records parity failure during current frame
    reg stop_bad;  // Records stop-bit failure during current frame

    wire calculated_parity = PARITY_ODD ? ~(^data_reg) : ^data_reg;  // Calculate expected parity

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            sample_count <= 4'd0;
            data_count <= {DATA_CNT_WIDTH{1'b0}};
            stop_count <= {STOP_CNT_WIDTH{1'b0}};
            data_reg <= {DATA_BITS{1'b0}};
            rx_data <= {DATA_BITS{1'b0}};
            parity_bad <= 1'b0;
            stop_bad <= 1'b0;
            rx_valid <= 1'b0;
            rx_busy <= 1'b0;
            parity_error <= 1'b0;
            frame_error <= 1'b0;
        end
        else begin
            rx_valid <= 1'b0;  // Generate one-clock receive pulse
            parity_error <= 1'b0;  // Generate one-clock parity-error pulse
            frame_error <= 1'b0;  // Generate one-clock frame-error pulse

            case (state)

                ST_IDLE: begin
                    rx_busy <= 1'b0;

                    if (!rx_in) begin
                        sample_count <= 4'd0;  // Begin measuring start-bit duration
                        data_count <= {DATA_CNT_WIDTH{1'b0}};
                        stop_count <= {STOP_CNT_WIDTH{1'b0}};
                        parity_bad <= 1'b0;
                        stop_bad <= 1'b0;
                        rx_busy <= 1'b1;
                        state <= ST_START;
                    end
                end

                ST_START: begin
                    if (baud16_tick) begin
                        if (sample_count == 4'd7) begin
                            if (!rx_in) begin
                                sample_count <= 4'd0;  // Wait one full bit before sampling D0
                                state <= ST_DATA;
                            end
                            else begin
                                sample_count <= 4'd0;
                                state <= ST_IDLE;  // Reject false start
                                rx_busy <= 1'b0;
                            end
                        end
                        else begin
                            sample_count <= sample_count + 1'b1;  // Advance toward start-bit center
                        end
                    end
                end

                ST_DATA: begin
                    if (baud16_tick) begin
                        if (sample_count == 4'd15) begin
                            data_reg[data_count] <= rx_in;  // Sample current data bit
                            sample_count <= 4'd0;  // Begin timing the next bit

                            if (data_count == DATA_BITS - 1) begin
                                data_count <= {DATA_CNT_WIDTH{1'b0}};
                                state <= PARITY_EN ? ST_PARITY : ST_STOP;
                            end
                            else begin
                                data_count <= data_count + 1'b1;  // Advance to next data bit
                            end
                        end
                        else begin
                            sample_count <= sample_count + 1'b1;  // Advance toward data-bit center
                        end
                    end
                end

                ST_PARITY: begin
                    if (baud16_tick) begin
                        if (sample_count == 4'd15) begin
                            if (rx_in != calculated_parity) begin
                                parity_bad <= 1'b1;
                                parity_error <= 1'b1;
                            end

                            sample_count <= 4'd0;
                            stop_count <= {STOP_CNT_WIDTH{1'b0}};
                            state <= ST_STOP;
                        end
                        else begin
                            sample_count <= sample_count + 1'b1;  // Advance toward parity-bit center
                        end
                    end
                end

                ST_STOP: begin
                    if (baud16_tick) begin
                        if (sample_count == 4'd15) begin
                            if (!rx_in) begin
                                stop_bad <= 1'b1;
                                frame_error <= 1'b1;
                            end

                            sample_count <= 4'd0;

                            if (stop_count == STOP_BITS - 1) begin
                                rx_data <= data_reg;  // Transfer completed frame to output

                                if (rx_in && !parity_bad && !stop_bad)
                                    rx_valid <= 1'b1;  // Accept frame only when error-free

                                state <= ST_IDLE;
                                rx_busy <= 1'b0;
                            end
                            else begin
                                stop_count <= stop_count + 1'b1;  // Advance to next stop bit
                            end
                        end
                        else begin
                            sample_count <= sample_count + 1'b1;  // Advance toward stop-bit center
                        end
                    end
                end

                default: begin
                    state <= ST_IDLE;  // Recover from invalid state
                    rx_busy <= 1'b0;
                end
            endcase
        end
    end
endmodule