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
 * This module implements the FIFO interface to the FT2232.
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
    input logic rd_out_fifo_empty_i
`ifdef EXT_ENABLED
    ,
    output logic led_ft2232_rd_data_o,
    output logic led_ft2232_wr_data_o
`endif
    );

    // Reset the FT2232HQ
    assign ft2232_reset_n_o = ~reset_i;

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
    localparam STATE_IDLE_RD            = 4'd0;
    localparam STATE_RD_TURN_AROUND     = 4'd1;
    localparam STATE_RD_WAIT            = 4'd2;
    localparam STATE_RD_DATA            = 4'd3;
    localparam STATE_RD_PENDING         = 4'd4;
    localparam STATE_RD_WAIT_IN_ROOM    = 4'd5;
    localparam STATE_RD_MAKE_OUT_ROOM   = 4'd6;
    localparam STATE_IDLE_WR            = 4'd7;
    localparam STATE_WR_DATA            = 4'd8;
    logic [3:0] state_m;

    logic [7:0] saved_data, saved_data_sec;
    logic [1:0] saved_data_bits;
    //==================================================================================================================
    // The FIFO state machine
    //==================================================================================================================
    always @(posedge fifo_clk_i, posedge reset_i) begin
        if (reset_i) begin
`ifdef D_FT_FIFO
            $display ($time, " FT_FIFO:\t-- Reset.");
`endif
            // -------------------------------------
            // Setup as if we just completed a write
            state_m <= STATE_IDLE_WR;
            fifo_oe_n_o <= 1'b1;
            // -------------------------------------
            fifo_wr_n_o <= 1'b1;
            fifo_rd_n_o <= 1'b1;
            fifo_siwu_o <= 1'b1;

            wr_in_fifo_en_o <= 1'b0;
            rd_out_fifo_en_o <= 1'b0;

`ifdef EXT_ENABLED
            led_ft2232_rd_data_o <= 1'b0;
            led_ft2232_wr_data_o <= 1'b0;
`endif
        end else begin
            case (state_m)
                STATE_IDLE_RD: begin
                    // Enter this state machine with fifo_oe_n_o = 1'b0
`ifdef EXT_ENABLED
                    led_ft2232_rd_data_o <= 1'b0;
`endif
                    wr_in_fifo_en_o <= 1'b0;
                    // Check if there is data to write first
                    if (can_write_to_ft2232_fifo) begin
                        // OE needs to be high (it is low since a read completed)
                        fifo_oe_n_o <= 1'b1;

                        // Read from the app FIFO.
                        rd_out_fifo_en_o <= 1'b1;

                        state_m <= STATE_WR_DATA;
                    end else if (can_read_from_ft2232_fifo) begin
`ifdef D_FT_FIFO
                        $display ($time, " FT_FIFO:\t[STATE_IDLE_RD] RD: 0.");
`endif
                        // Do another read
                        fifo_rd_n_o <= 1'b0;
                        state_m <= STATE_RD_WAIT;
                    end
                end

                STATE_RD_TURN_AROUND: begin
                    // Assert the FT2232 FIFO read signal.
                    fifo_rd_n_o <= 1'b0;
`ifdef D_FT_FIFO
                    $display ($time, " FT_FIFO:\t[STATE_RD_TURN_AROUND] RD: 0.");
`endif
                    state_m <= STATE_RD_WAIT;
                end

                STATE_RD_WAIT: begin
                    state_m <= STATE_RD_DATA;
                end

                STATE_RD_DATA: begin
`ifdef EXT_ENABLED
                    led_ft2232_rd_data_o <= 1'b1;
`endif
                    // Check if there is data to write first
                    if (can_write_to_ft2232_fifo) begin
                        // Stop reading
                        fifo_rd_n_o <= 1'b1;

                        wr_in_fifo_en_o <= 1'b0;
                        saved_data <= fifo_data_i;
                        saved_data_bits <= 2'b01;
`ifdef D_FT_FIFO
                        $display ($time, " FT_FIFO:\t---> [STATE_RD_DATA] Wr IN: store[0]: %d (need to write) -> STATE_RD_PENDING.",
                                                    fifo_data_i);
`endif

                        state_m <= STATE_RD_PENDING;
                    end else if (fifo_rxf_n_i) begin
                        // Stop reading; there is no more data to read.
                        fifo_rd_n_o <= 1'b1;

                        // Write the data to the input FIFO.
                        wr_in_fifo_en_o <= 1'b1;
                        wr_in_fifo_data_o <= fifo_data_i;
`ifdef D_FT_FIFO
                        $display ($time, " FT_FIFO:\t---> [STATE_RD_DATA] Wr IN: %d (IN afull: %d, full: %d) -> STATE_IDLE_RD.",
                                                    fifo_data_i, wr_in_fifo_afull_i, wr_in_fifo_full_i);
`endif
                        state_m <= STATE_IDLE_RD;
                    end else if (wr_in_fifo_full_i || wr_in_fifo_afull_i) begin
                        // Stop reading; there is no room in the IN FIFO.
                        fifo_rd_n_o <= 1'b1;

                        // Value was read but there is no room in the FIFO. Save it until there is room in the IN FIFO.
                        wr_in_fifo_en_o <= 1'b0;
                        saved_data <= fifo_data_i;
                        saved_data_bits <= 2'b01;
`ifdef D_FT_FIFO
                        $display ($time, " FT_FIFO:\t---> [STATE_RD_DATA] Wr IN: store[0]: %d (IN afull: %d, full: %d) -> STATE_RD_PENDING.",
                                                    fifo_data_i, wr_in_fifo_afull_i, wr_in_fifo_full_i);
`endif

                        state_m <= STATE_RD_PENDING;
                    end else begin
                        // Write the data to the input FIFO.
                        wr_in_fifo_en_o <= 1'b1;
                        wr_in_fifo_data_o <= fifo_data_i;
`ifdef D_FT_FIFO
                        $display ($time, " FT_FIFO:\t---> [STATE_RD_DATA] Wr IN: %d (IN afull: %d, full: %d).", fifo_data_i,
                                                    wr_in_fifo_afull_i, wr_in_fifo_full_i);
`endif
                    end
                end

                STATE_RD_PENDING: begin
                    if (~fifo_rxf_n_i) begin
                        // FT2232 puts out one more byte.
`ifdef D_FT_FIFO
                        $display ($time, " FT_FIFO:\t---> [STATE_RD_PENDING] store[1]: %d.", fifo_data_i);
`endif
                        saved_data_sec <= fifo_data_i;
                        saved_data_bits[1] <= 1'b1;
                    end
                    state_m <= STATE_RD_WAIT_IN_ROOM;
                end

                STATE_RD_WAIT_IN_ROOM: begin
                    if (~wr_in_fifo_full_i && ~wr_in_fifo_afull_i) begin
                        if (saved_data_bits[0]) begin
                            // Write the data to the input FIFO.
                            wr_in_fifo_en_o <= 1'b1;
                            wr_in_fifo_data_o <= saved_data;
                            saved_data_bits[0] <= 1'b0;
`ifdef D_FT_FIFO
                            $display ($time, " FT_FIFO:\t---> [STATE_RD_WAIT_IN_ROOM 0] Wr IN: %d (IN afull: %d, full: %d).",
                                                        saved_data, wr_in_fifo_afull_i, wr_in_fifo_full_i);
`endif
                        end else if (saved_data_bits[1]) begin
                            // Write the data to the input FIFO.
                            wr_in_fifo_en_o <= 1'b1;
                            wr_in_fifo_data_o <= saved_data_sec;
                            saved_data_bits[1] <= 1'b0;
`ifdef D_FT_FIFO
                            $display ($time, " FT_FIFO:\t---> [STATE_RD_WAIT_IN_ROOM 1] Wr IN: %d (IN afull: %d, full: %d).",
                                                        saved_data_sec, wr_in_fifo_afull_i, wr_in_fifo_full_i);
`endif
                        end else begin
                            wr_in_fifo_en_o <= 1'b0;
                            state_m <= STATE_IDLE_RD;
                        end
                    end else begin
                        wr_in_fifo_en_o <= 1'b0;
                        // Send data from the OUT FIFO to ensure the the modue that is using the IN and OUT FIFO
                        // does not deadlock (data cannot be written to IN from here and the OUT FIFO is full).
                        state_m <= STATE_RD_MAKE_OUT_ROOM;
                    end
                end

                STATE_RD_MAKE_OUT_ROOM: begin
                    if (can_write_to_ft2232_fifo) begin
                        rd_out_fifo_en_o <= 1'b1;
                        if (rd_out_fifo_en_o) begin
`ifdef D_FT_FIFO
                            $display ($time, " FT_FIFO:\t<--- [STATE_RD_MAKE_OUT_ROOM] Rd OUT: %d.", rd_out_fifo_data_i);
`endif
                            fifo_wr_n_o <= 1'b0;
                            // Write data to the FT2232 FIFO.
                            fifo_data_o <= rd_out_fifo_data_i;

                            rd_out_fifo_en_o <= 1'b0;
                            state_m <= STATE_RD_WAIT_IN_ROOM;
                        end
                    end else begin
                        state_m <= STATE_RD_WAIT_IN_ROOM;
                    end
                end

                STATE_IDLE_WR: begin
                    // Enter this state machine with fifo_oe_n_o = 1'b1
`ifdef EXT_ENABLED
                    led_ft2232_wr_data_o <= 1'b0;
`endif
                    fifo_wr_n_o <= 1'b1;
                    // Check if there is data to read in the FT2232 FIFO.
                    if (can_read_from_ft2232_fifo) begin
                        // OE needs to be low (it is high since a write completed).
                        fifo_oe_n_o <= 1'b0;
`ifdef D_FT_FIFO
                        $display ($time, " FT_FIFO:\t[STATE_IDLE_WR] OE: 0.");
`endif

                        // Wait one cycle after changing OE.
                        state_m <= STATE_RD_TURN_AROUND;
                    end else if (can_write_to_ft2232_fifo) begin
                        // Read from the app FIFO
                        rd_out_fifo_en_o <= 1'b1;

                        state_m <= STATE_WR_DATA;
                    end
                end

                STATE_WR_DATA: begin
`ifdef EXT_ENABLED
                    led_ft2232_wr_data_o <= 1'b1;
`endif
                    // Check if there is data to read in the FT2232 FIFO.
                    if (can_read_from_ft2232_fifo) begin
                        rd_out_fifo_en_o <= 1'b0;

                        fifo_wr_n_o <= 1'b0;
                        // Write data to the FT2232 FIFO.
                        fifo_data_o <= rd_out_fifo_data_i;
`ifdef D_FT_FIFO
                        $display ($time, " FT_FIFO:\t<--- [STATE_WR_DATA] Rd OUT: %d -> STATE_IDLE_WR.", rd_out_fifo_data_i);
`endif
                        state_m <= STATE_IDLE_WR;
                    end else if (~can_write_to_ft2232_fifo) begin
                        rd_out_fifo_en_o <= 1'b0;

                        fifo_wr_n_o <= 1'b1;

                        state_m <= STATE_IDLE_WR;
                    end else begin
`ifdef D_FT_FIFO
                        $display ($time, " FT_FIFO:\t<--- [STATE_WR_DATA] Rd OUT: %d.", rd_out_fifo_data_i);
`endif
                        fifo_wr_n_o <= 1'b0;
                        // Write data to the FT2232 FIFO.
                        fifo_data_o <= rd_out_fifo_data_i;
                    end
                end
            endcase
        end
    end
endmodule
