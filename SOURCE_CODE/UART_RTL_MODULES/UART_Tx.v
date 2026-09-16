module UART_Tx #(parameter integer DATA_BITS  = 8,  // Number of transmitted data bits
                 parameter integer STOP_BITS  = 1,  // Number of stop bits
                 parameter integer PARITY_EN  = 0,  // Enable parity bit
                 parameter integer PARITY_ODD = 0)   // 0 = even parity, 1 = odd parity
                (input  wire clk,
                 input  wire rst_n,
                 input  wire baud_tick,
                 input  wire [DATA_BITS-1:0] tx_data,
                 input  wire tx_valid,
                 output wire tx_ready,
                 output wire tx_serial,
                 output wire tx_busy,
                 output reg  tx_done);

    localparam integer DATA_CNT_WIDTH = (DATA_BITS <= 1) ? 1 : $clog2(DATA_BITS);  // Width required for data-bit counter
    localparam integer STOP_CNT_WIDTH = (STOP_BITS <= 1) ? 1 : $clog2(STOP_BITS);  // Width required for stop-bit counter

    localparam [2:0] ST_IDLE   = 3'd0;  // Waiting for a new transmission
    localparam [2:0] ST_START  = 3'd1;  // Transmitting start bit
    localparam [2:0] ST_DATA   = 3'd2;  // Transmitting data bits
    localparam [2:0] ST_PARITY = 3'd3;  // Transmitting parity bit
    localparam [2:0] ST_STOP   = 3'd4;  // Transmitting stop bit(s)

    reg [2:0] state;

    reg [DATA_BITS-1:0] data_reg;  // Latched transmit data
    reg [DATA_CNT_WIDTH-1:0] data_count;  // Current data-bit index
    reg [STOP_CNT_WIDTH-1:0] stop_count;  // Current stop-bit index
    reg parity_bit;  // Calculated parity for the current frame

    assign tx_ready = (state == ST_IDLE);  // New data can be accepted only while idle
    assign tx_busy = (state != ST_IDLE);  // Transmitter is active outside idle state

    assign tx_serial = ((state == ST_IDLE)   ? 1'b1 :
                        (state == ST_START)  ? 1'b0 :
                        (state == ST_DATA)   ? data_reg[data_count] :
                        (state == ST_PARITY) ? parity_bit :
                         1'b1);  // Stop state and all unused states drive the idle level

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            data_reg <= {DATA_BITS{1'b0}};
            data_count <= {DATA_CNT_WIDTH{1'b0}};
            stop_count <= {STOP_CNT_WIDTH{1'b0}};
            parity_bit <= 1'b0;
            tx_done <= 1'b0;
        end
        else begin
            tx_done <= 1'b0;  // Completion indication is a one-clock pulse

            case (state)

                ST_IDLE: begin
                    if (tx_valid) begin
                        data_reg <= tx_data;  // Capture data when valid and ready
                        data_count <= {DATA_CNT_WIDTH{1'b0}};
                        stop_count <= {STOP_CNT_WIDTH{1'b0}};
                        parity_bit <= PARITY_ODD ? ~(^tx_data) : ^tx_data;  // Calculate selected parity
                        state <= ST_START;
                    end
                end

                ST_START: begin
                    if (baud_tick) begin
                        data_count <= {DATA_CNT_WIDTH{1'b0}};  // Start transmitting from D0
                        state <= ST_DATA;
                    end
                end

                ST_DATA: begin
                    if (baud_tick) begin
                        if (data_count == DATA_BITS - 1) begin
                            data_count <= {DATA_CNT_WIDTH{1'b0}};
                            state <= PARITY_EN ? ST_PARITY : ST_STOP;
                        end
                        else begin
                            data_count <= data_count + 1'b1;  // Advance to the next data bit
                        end
                    end
                end

                ST_PARITY: begin
                    if (baud_tick) begin
                        stop_count <= {STOP_CNT_WIDTH{1'b0}};  // Begin stop-bit sequence
                        state <= ST_STOP;
                    end
                end

                ST_STOP: begin
                    if (baud_tick) begin
                        if (stop_count == STOP_BITS - 1) begin
                            state <= ST_IDLE;
                            tx_done <= 1'b1;  // Signal completion after the final stop bit
                        end
                        else begin
                            stop_count <= stop_count + 1'b1;  // Advance to the next stop bit
                        end
                    end
                end

                default: begin
                    state <= ST_IDLE;  // Recover safely from an invalid state
                end
            endcase
        end
    end
endmodule