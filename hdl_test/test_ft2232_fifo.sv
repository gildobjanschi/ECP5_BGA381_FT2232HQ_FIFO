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
 * This module implements the synchronous FIFO interface for FT2232.
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
    inout wire [7:0] fifo_data_io,
    // LEDs
    output logic led_ft2232_rd_data_o,
    output logic led_ft2232_wr_data_o);

    assign led_ft2232_rd_data_o = ~fifo_rxf_n_i;
    assign led_ft2232_wr_data_o = ~fifo_txe_n_i;

    // Reset the FT2232HQ
    assign ft2232_reset_n_o = ~reset_i;
    assign fifo_siwu_o = 1'b1;

    logic have_byte_to_write;
    logic [7:0] byte_to_write;

    // Input/output 8-bit data bus
    logic [7:0] fifo_data_i;
    logic [7:0] fifo_data_o;
    // .T = 0 -> fifo_data_io is output; .T = 1 -> fifo_data_io is input.
    TRELLIS_IO #(.DIR("BIDIR")) fifo_d_io[7:0] (.B(fifo_data_io), .T(~fifo_oe_n_o), .O(fifo_data_i), .I(fifo_data_o));

    // Main state machine
    localparam STATE_RD                 = 2'd0;
    localparam STATE_RD_TURN_AROUND     = 2'd1;
    localparam STATE_WR                 = 2'd2;
    logic [1:0] state_m;

    //==================================================================================================================
    // The FIFO state machine
    //==================================================================================================================
    always @(posedge fifo_clk_i, posedge reset_i) begin
        if (reset_i) begin
`ifdef D_FT_FIFO
            $display ($time, " FT_FIFO:\t-- Reset.");
`endif
            state_m <= STATE_WR;
            fifo_oe_n_o <= 1'b1;

            fifo_wr_n_o <= 1'b1;
            fifo_rd_n_o <= 1'b1;

            have_byte_to_write <= 1'b0;
        end else begin
            case (state_m)
                STATE_WR: begin
                    fifo_wr_n_o <= 1'b1;
                    // Enter this state machine with fifo_oe_n_o = 1'b1
                    if (have_byte_to_write) begin
                        if (~fifo_txe_n_i) begin
`ifdef D_FT_FIFO
                            $display ($time, " FT_FIFO:\t[STATE_WR] Wrote: %d. ", byte_to_write);
`endif
                            fifo_data_o <= byte_to_write;
                            // Write the value
                            fifo_wr_n_o <= 1'b0;

                            have_byte_to_write <= 1'b0;
                        end
                    end else if (~fifo_rxf_n_i) begin
                        // OE needs to be low one cycle before RD.
                        fifo_oe_n_o <= 1'b0;
`ifdef D_FT_FIFO_FINE
                        $display ($time, " FT_FIFO:\t[STATE_WR -> STATE_RD_TURN_AROUND] OE 1 -> 0. ");
`endif
                        // Wait one cycle after changing OE.
                        state_m <= STATE_RD_TURN_AROUND;
                    end
                end

                STATE_RD_TURN_AROUND: begin
                    // Assert the FT2232 FIFO read signal.
                    fifo_rd_n_o <= 1'b0;
`ifdef D_FT_FIFO_FINE
                    $display ($time, " FT_FIFO:\t[STATE_RD_TURN_AROUND] RD 1 -> 0.");
`endif
                    state_m <= STATE_RD;
                end

                STATE_RD: begin
                    // Enter this state machine with fifo_oe_n_o = 1'b0 and fifo_rd_n_o = 1'b0 if fifo_rxf_n_i = 1'b0
`ifdef D_FT_FIFO
                    $display ($time, " FT_FIFO:\t[STATE_RD] Read: %d. ", fifo_data_i);
`endif
                    byte_to_write <= fifo_data_i;
                    have_byte_to_write <= 1'b1;
                    // Switch to write
                    fifo_oe_n_o <= 1'b1;
                    fifo_rd_n_o <= 1'b1;
                    state_m <= STATE_WR;
                end

                default: begin
                end
            endcase
        end
    end
endmodule
