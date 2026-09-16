module UART_FIFO #(parameter integer DATA_WIDTH = 8,                                // FIFO data width
                   parameter integer DEPTH = 16)                                    // Number of FIFO entries
                  (input  wire clk,
                   input  wire rst_n,

                   input  wire wr_en,
                   input  wire [DATA_WIDTH-1:0] wr_data,
                   output wire full,

                   input  wire rd_en,
                   output reg  [DATA_WIDTH-1:0] rd_data,
                   output wire empty,

                   output wire [$clog2(DEPTH+1)-1:0] count);

    localparam integer PTR_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH);                 // Width required for FIFO pointers
    localparam integer CNT_WIDTH = (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1);             // Width required for entry count

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];                                            // FIFO storage array
    reg [PTR_WIDTH-1:0] wr_ptr;                                                      // Write pointer
    reg [PTR_WIDTH-1:0] rd_ptr;                                                      // Read pointer
    reg [CNT_WIDTH-1:0] count_reg;                                                   // Number of occupied entries

    wire write_fire = wr_en && !full;                                                // Write occurs only when FIFO is not full
    wire read_fire = rd_en && !empty;                                                // Read occurs only when FIFO is not empty

    assign full = (count_reg == DEPTH);                                              // FIFO is full when all entries are occupied
    assign empty = (count_reg == 0);                                                 // FIFO is empty when no entries are occupied
    assign count = count_reg;                                                        // Expose current FIFO occupancy

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr <= {PTR_WIDTH{1'b0}};
            rd_ptr <= {PTR_WIDTH{1'b0}};
            count_reg <= {CNT_WIDTH{1'b0}};
            rd_data <= {DATA_WIDTH{1'b0}};
        end
        else begin
            if (write_fire) begin
                mem[wr_ptr] <= wr_data;                                              // Store incoming data
                if (wr_ptr == DEPTH - 1)
                    wr_ptr <= {PTR_WIDTH{1'b0}};                                     // Wrap write pointer
                else
                    wr_ptr <= wr_ptr + 1'b1;                                         // Advance write pointer
            end

            if (read_fire) begin
                rd_data <= mem[rd_ptr];                                              // Return oldest stored entry
                if (rd_ptr == DEPTH - 1)
                    rd_ptr <= {PTR_WIDTH{1'b0}};                                     // Wrap read pointer
                else
                    rd_ptr <= rd_ptr + 1'b1;                                         // Advance read pointer
            end

            case ({write_fire, read_fire})
                2'b10: count_reg <= count_reg + 1'b1;                                // Write without read increases occupancy
                2'b01: count_reg <= count_reg - 1'b1;                                // Read without write decreases occupancy
                default: count_reg <= count_reg;                                     // Simultaneous or idle operation preserves occupancy
            endcase
        end
    end
endmodule