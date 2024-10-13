/***********************************************************************************************************************
 * Copyright (c) 2024 Virgil Dobjanschi dobjanschivirgil@gmail.com
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
 * documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
 * rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all copies or substantial portions of
 * the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
 * WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS
 * OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
 * OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 **********************************************************************************************************************/

/***********************************************************************************************************************
 * This module implements the FT2232 synchronous FIFO interface. Data received from the FT2232 is written to the
 * asynchronous IN FIFO and data from the asynchronous OUT FIFO is written to the FT2232.
 **********************************************************************************************************************/
`timescale 1ps/1ps
`default_nettype none

module ft2232_fifo (
    input logic reset_i,
    // FT2232HQ FIFO
    input logic fifo_clk_i,
    input logic fifo_txe_n_i,
    input logic fifo_rxf_n_i,
    output logic ft2232_reset_n_o,
    output logic fifo_oe_n_o,
    output logic fifo_siwu_o,
    output logic fifo_wr_n_o,
    output logic fifo_rd_n_o,
    inout logic [7:0] fifo_data_io,
    // Input FIFO ports
    output logic wr_in_fifo_clk_o,
    output logic wr_in_fifo_en_o,
    output logic [7:0] wr_in_fifo_data_o,
    input logic wr_in_fifo_full_i,
    input logic wr_in_fifo_afull_i,
    // Output FIFO ports
    output logic rd_out_fifo_clk_o,
    output logic rd_out_fifo_en_o,
    input logic [7:0] rd_out_fifo_data_i,
    input logic rd_out_fifo_empty_i);

    // Reset the FT2232HQ
    assign ft2232_reset_n_o = ~reset_i;
    assign fifo_siwu_o = 1'b1;
    assign wr_in_fifo_clk_o = fifo_clk_i;
    assign rd_out_fifo_clk_o = fifo_clk_i;

    logic can_read_from_ft2232_fifo, can_write_to_ft2232_fifo;
    assign can_read_from_ft2232_fifo = ~fifo_rxf_n_i && (~wr_in_fifo_full_i && ~wr_in_fifo_afull_i);
    assign can_write_to_ft2232_fifo = ~fifo_txe_n_i && ~rd_out_fifo_empty_i;

    // Input/output 8-bit data bus
    logic [7:0] fifo_data_i, fifo_data_o;
    // .T = 0 -> fifo_data_io is output; .T = 1 -> fifo_data_io is input.
    TRELLIS_IO #(.DIR("BIDIR")) fifo_d_io[7:0] (.B(fifo_data_io), .T(~fifo_oe_n_o), .O(fifo_data_i), .I(fifo_data_o));

    // Main state machine
    localparam STATE_RD_IDLE            = 3'd0;
    localparam STATE_RD_DATA            = 3'd1;
    localparam STATE_RD_TURNAROUND      = 3'd2;
    localparam STATE_RD_FLUSH_SAVED_DATA= 3'd3;
    localparam STATE_WR_IDLE            = 3'd4;
    localparam STATE_WR_DATA            = 3'd5;
    localparam STATE_WR_FLUSH_SAVED_DATA= 3'd6;
    logic [2:0] state_m;

    logic [7:0] saved_rd_data;
    logic have_saved_rd_data;

    logic [7:0] saved_wr_data;
    logic have_saved_wr_data;

    //==================================================================================================================
    // The FIFO state machine
    //==================================================================================================================
    always @(posedge fifo_clk_i, posedge reset_i) begin
        if (reset_i) begin
`ifdef D_FT_FIFO
            $display ($time, " FT_FIFO:\t-- Reset.");
`endif
            // Setup as if we just completed a write
            state_m <= STATE_WR_IDLE;
            fifo_oe_n_o <= 1'b1;

            fifo_wr_n_o <= 1'b1;
            fifo_rd_n_o <= 1'b1;

            wr_in_fifo_en_o <= 1'b0;
            rd_out_fifo_en_o <= 1'b0;

            have_saved_rd_data <= 1'b0;
            have_saved_wr_data <= 1'b0;
        end else begin
            case (state_m)
                STATE_RD_IDLE: begin
                    // Enter this state machine with fifo_oe_n_o = 1'b0.
                    wr_in_fifo_en_o <= 1'b0;
                    fifo_rd_n_o <= 1'b1;

                    // Check if there is data to write first
                    if (~fifo_txe_n_i && have_saved_wr_data) begin
                        // OE needs to be high (it is low since a read completed).
                        fifo_oe_n_o <= 1'b1;

                        state_m <= STATE_WR_FLUSH_SAVED_DATA;
                    end else if (can_write_to_ft2232_fifo) begin
                        // OE needs to be high (it is low since a read completed).
                        fifo_oe_n_o <= 1'b1;
`ifdef D_FT_FIFO_FINE
                        $display ($time, " FT_FIFO:\t[STATE_RD_IDLE -> STATE_WR_DATA] OE: 1.");
`endif
                        // Read from the OUT FIFO.
                        rd_out_fifo_en_o <= 1'b1;

                        state_m <= STATE_WR_DATA;
                    end else if (have_saved_rd_data) begin
                        // If there is saved data write it to the IN FIFO.
                        state_m <= STATE_RD_FLUSH_SAVED_DATA;
                    end else if (can_read_from_ft2232_fifo) begin
`ifdef D_FT_FIFO_FINE
                        $display ($time, " FT_FIFO:\t[STATE_RD_IDLE -> STATE_RD_DATA] (IN afull: %d, full: %d).",
                                            wr_in_fifo_afull_i, wr_in_fifo_full_i);
`endif
                        // Do another read
                        state_m <= STATE_RD_DATA;
                    end
                end

                STATE_RD_FLUSH_SAVED_DATA: begin
                    if (~wr_in_fifo_afull_i && ~wr_in_fifo_full_i) begin
                        if (have_saved_rd_data) begin
                            have_saved_rd_data <= 1'b0;

                            // Write the data to the input FIFO.
                            wr_in_fifo_en_o <= 1'b1;
                            wr_in_fifo_data_o <= saved_rd_data;
`ifdef D_FT_FIFO
                            $display ($time, " FT_FIFO:\t---> [STATE_RD_FLUSH_SAVED_DATA -> STATE_RD_IDLE] Wr IN: %d (IN afull: %d, full: %d).",
                                                saved_rd_data, wr_in_fifo_afull_i, wr_in_fifo_full_i);
`endif
                        end else begin
                            wr_in_fifo_en_o <= 1'b0;
                        end
                    end else begin
                        wr_in_fifo_en_o <= 1'b0;
                    end

                    state_m <= STATE_RD_IDLE;
                end

                STATE_RD_TURNAROUND: begin
`ifdef D_FT_FIFO_FINE
                    $display ($time, " FT_FIFO:\t[STATE_RD_TURNAROUND -> STATE_RD_DATA].");
`endif
                    state_m <= STATE_RD_DATA;
                end

                STATE_RD_DATA: begin
                    if (fifo_rxf_n_i) begin
                        // Stop reading; there is no data in the FT2232 FIFO.
                        fifo_rd_n_o <= 1'b1;
                        // Stop writting to the IN FIFO.
                        wr_in_fifo_en_o <= 1'b0;
`ifdef D_FT_FIFO_FINE
                        $display ($time, " FT_FIFO:\t---> [STATE_RD_DATA] fifo_rxf_n_i: 1. RD: 1 (IN afull: %d, full: %d).",
                                            wr_in_fifo_afull_i, wr_in_fifo_full_i);
`endif
                    end else if (wr_in_fifo_afull_i || wr_in_fifo_full_i) begin
                        // If the FIFO is almost full now it will become full with the value written
                        // in the previous cycle and therefore a new value cannot be written to the FIFO in this cycle.

                        // Advance the FT2232 FIFO pointer
                        fifo_rd_n_o <= 1'b0;
                        // Stop writting.
                        wr_in_fifo_en_o <= 1'b0;

                        // Save read data so we can write it to the IN FIFO when there will be room.
                        have_saved_rd_data <= 1'b1;
                        saved_rd_data <= fifo_data_i;
`ifdef D_FT_FIFO
                        $display ($time, " FT_FIFO:\t---> [STATE_RD_DATA] Wr IN delayed: %d. RD: 1 (IN afull: %d, full: %d).",
                                            fifo_data_i, wr_in_fifo_afull_i, wr_in_fifo_full_i);
`endif
                    end else begin
                        fifo_rd_n_o <= 1'b0;

                        wr_in_fifo_en_o <= 1'b1;
                        wr_in_fifo_data_o <= fifo_data_i;

`ifdef D_FT_FIFO
                        $display ($time, " FT_FIFO:\t---> [STATE_RD_DATA] Wr IN: %d (IN afull: %d, full: %d). RD : 0",
                                                fifo_data_i, wr_in_fifo_afull_i, wr_in_fifo_full_i);
`endif
                    end

                    state_m <= STATE_RD_IDLE;
                end

                STATE_WR_IDLE: begin
                    // Enter this state machine with fifo_oe_n_o = 1'b1
                    fifo_wr_n_o <= 1'b1;
                    if (have_saved_rd_data) begin
                        // OE needs to be low (switching to read).
                        fifo_oe_n_o <= 1'b0;
                        // If there is saved read data write it to the IN FIFO.
                        state_m <= STATE_RD_FLUSH_SAVED_DATA;
                    end else if (can_read_from_ft2232_fifo) begin
                        // OE needs to be low (switching to read).
                        fifo_oe_n_o <= 1'b0;
`ifdef D_FT_FIFO_FINE
                        $display ($time, " FT_FIFO:\t[STATE_WR_IDLE -> STATE_RD_TURNAROUND] OE: 0.");
`endif
                        state_m <= STATE_RD_TURNAROUND;
                    end else if (~fifo_txe_n_i && have_saved_wr_data) begin
                        state_m <= STATE_WR_FLUSH_SAVED_DATA;
                    end else if (can_write_to_ft2232_fifo) begin
                        // Read from the IN FIFO.
                        rd_out_fifo_en_o <= 1'b1;

                        state_m <= STATE_WR_DATA;
                    end
                end

                STATE_WR_FLUSH_SAVED_DATA: begin
                    if (~fifo_txe_n_i) begin
                        if (have_saved_wr_data) begin
                            have_saved_wr_data <= 1'b0;
                            fifo_wr_n_o <= 1'b0;
                            // Write data to the FT2232 FIFO.
                            fifo_data_o <= saved_wr_data;
`ifdef D_FT_FIFO
                            $display ($time, " FT_FIFO:\t<---- [STATE_WR_FLUSH_SAVED_DATA] Wr FT2232 (saved 0): %d.",
                                            saved_wr_data);
`endif
                        end else begin
                            fifo_wr_n_o <= 1'b1;
                        end
                    end else begin
                        fifo_wr_n_o <= 1'b1;
                    end

                    state_m <= STATE_WR_IDLE;
                end

                STATE_WR_DATA: begin
                    if (fifo_txe_n_i) begin
                        // The last value could not be written (the FT2232 FIFO became full).
                        have_saved_wr_data <= 1'b1;
                        saved_wr_data <= rd_out_fifo_data_i;
`ifdef D_FT_FIFO
                        $display ($time, " FT_FIFO:\t[STATE_WR_DATA] Delayed Wr FT2232 [0]: %d.", rd_out_fifo_data_i);
`endif
                        fifo_wr_n_o <= 1'b1;
                    end else if (~rd_out_fifo_empty_i) begin
`ifdef D_FT_FIFO
                        $display ($time, " FT_FIFO:\t<--- [STATE_WR_DATA] Wr FT2232: %d.", rd_out_fifo_data_i);
`endif
                        fifo_wr_n_o <= 1'b0;
                        // Write data to the FT2232 FIFO.
                        fifo_data_o <= rd_out_fifo_data_i;
                    end else begin
                        fifo_wr_n_o <= 1'b1;
                    end

                    rd_out_fifo_en_o <= 1'b0;
                    state_m <= STATE_WR_IDLE;
                end

                default: begin
                    // Impossible case
                end
            endcase
        end
    end
endmodule
