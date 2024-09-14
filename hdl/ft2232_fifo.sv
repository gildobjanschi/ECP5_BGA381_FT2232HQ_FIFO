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

module ft2232_fifo #(parameter IN_FIFO_ASIZE=4, parameter OUT_FIFO_ASIZE=4)(
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
    localparam STATE_IDLE_RD            = 4'd0;
    localparam STATE_RD_TURN_AROUND     = 4'd1;
    localparam STATE_RD_START           = 4'd2;
    localparam STATE_RD_DATA            = 4'd3;
    localparam STATE_RD_STOP            = 4'd4;
    localparam STATE_FLUSH_SAVED_RD_DATA= 4'd5;
    localparam STATE_IDLE_WR            = 4'd6;
    localparam STATE_WR_DATA            = 4'd7;
    localparam STATE_FLUSH_SAVED_WR_DATA= 4'd8;
    logic [3:0] state_m;

    localparam IN_THRESHOLD = 1<<(IN_FIFO_ASIZE-2);
    localparam OUT_THRESHOLD = 1<<(OUT_FIFO_ASIZE-2);
    logic [IN_FIFO_ASIZE-1:0] in_count;
    logic [OUT_FIFO_ASIZE-1:0] out_count;

    logic [7:0] saved_rd_data_0, saved_rd_data_1;
    logic [1:0] saved_rd_data_bits;
    logic have_saved_rd_data;
    assign have_saved_rd_data = saved_rd_data_bits[0] || saved_rd_data_bits[1];

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
            // -------------------------------------
            // Setup as if we just completed a write
            state_m <= STATE_IDLE_WR;
            fifo_oe_n_o <= 1'b1;
            // -------------------------------------
            fifo_wr_n_o <= 1'b1;
            fifo_rd_n_o <= 1'b1;

            wr_in_fifo_en_o <= 1'b0;
            rd_out_fifo_en_o <= 1'b0;

            saved_rd_data_bits <= 2'b00;
            have_saved_wr_data <= 1'b0;
`ifdef EXT_ENABLED
            led_ft2232_rd_data_o <= 1'b0;
            led_ft2232_wr_data_o <= 1'b0;
`endif
        end else begin
            case (state_m)
                STATE_IDLE_RD: begin
                    // Enter this state machine with fifo_oe_n_o = 1'b0.
`ifdef EXT_ENABLED
                    led_ft2232_rd_data_o <= 1'b0;
`endif
                    wr_in_fifo_en_o <= 1'b0;
                    // Check if there is data to write first
                    if (~fifo_txe_n_i && have_saved_wr_data) begin
                        state_m <= STATE_FLUSH_SAVED_WR_DATA;
                    end else if (can_write_to_ft2232_fifo) begin
                        // OE needs to be high (it is low since a read completed).
                        fifo_oe_n_o <= 1'b1;
`ifdef D_FT_FIFO_FINE
                        $display ($time, " FT_FIFO:\t[STATE_IDLE_RD] OE: 1.");
`endif
                        // Read from the OUT FIFO.
                        rd_out_fifo_en_o <= 1'b1;

                        out_count <= 0;
                        state_m <= STATE_WR_DATA;
                    end else if (have_saved_rd_data) begin
                        // If there is saved data write it to the IN FIFO.
                        state_m <= STATE_FLUSH_SAVED_RD_DATA;
                    end else if (can_read_from_ft2232_fifo) begin
`ifdef D_FT_FIFO_FINE
                        $display ($time, " FT_FIFO:\t[STATE_IDLE_RD] RD: 0.");
`endif
                        // Do another read
                        fifo_rd_n_o <= 1'b0;
                        state_m <= STATE_RD_START;
                    end
                end

                STATE_RD_TURN_AROUND: begin
                    // OE is now 0; read mode is entered. First, check if we need to flush the read saved data.
                    if (have_saved_rd_data) begin
`ifdef D_FT_FIFO_FINE
                        $display ($time, " FT_FIFO:\t[STATE_RD_TURN_AROUND] -> STATE_FLUSH_SAVED_RD_DATA.");
`endif
                        state_m <= STATE_FLUSH_SAVED_RD_DATA;
                    end else begin
                        // Assert the FT2232 FIFO read signal.
                        fifo_rd_n_o <= 1'b0;
`ifdef D_FT_FIFO_FINE
                        $display ($time, " FT_FIFO:\t[STATE_RD_TURN_AROUND] RD: 0.");
`endif
                        state_m <= STATE_RD_START;
                    end
                end

                STATE_RD_START: begin
                    in_count <= 0;
                    state_m <= STATE_RD_DATA;
                end

                STATE_FLUSH_SAVED_RD_DATA: begin
                    if (~wr_in_fifo_afull_i && ~wr_in_fifo_full_i) begin
                        if (saved_rd_data_bits[0]) begin
                            saved_rd_data_bits[0] <= 1'b0;

                            // Write the data to the input FIFO.
                            wr_in_fifo_en_o <= 1'b1;
                            wr_in_fifo_data_o <= saved_rd_data_0;
`ifdef D_FT_FIFO
                            $display ($time, " FT_FIFO:\t---> [STATE_FLUSH_SAVED_RD_DATA] Wr IN: %d (IN afull: %d, full: %d).",
                                                saved_rd_data_0, wr_in_fifo_afull_i, wr_in_fifo_full_i);
`endif
                        end else if (saved_rd_data_bits[1]) begin
                            saved_rd_data_bits[1] <= 1'b0;

                            // Write the data to the input FIFO.
                            wr_in_fifo_en_o <= 1'b1;
                            wr_in_fifo_data_o <= saved_rd_data_1;
`ifdef D_FT_FIFO
                            $display ($time, " FT_FIFO:\t---> [STATE_FLUSH_SAVED_RD_DATA] Wr IN: %d (IN afull: %d, full: %d).",
                                                saved_rd_data_1, wr_in_fifo_afull_i, wr_in_fifo_full_i);
`endif
                        end else begin
                            wr_in_fifo_en_o <= 1'b0;
                        end
                    end else begin
                        wr_in_fifo_en_o <= 1'b0;
                    end

                    state_m <= STATE_IDLE_RD;
                end

                STATE_RD_DATA: begin
`ifdef EXT_ENABLED
                    led_ft2232_rd_data_o <= 1'b1;
`endif
                    // If the FIFO is almost full now it will become full with the value written in the previous cycle
                    // and therefore a new value cannot be written to the FIFO in this cycle.
                    if (fifo_rxf_n_i) begin
                        // Stop reading from FT2232 FIFO.
                        fifo_rd_n_o <= 1'b1;
                        // Stop writting.
                        wr_in_fifo_en_o <= 1'b0;
                        // Stop reading; there is no more room in the IN FIFO.
                        state_m <= STATE_IDLE_RD;
                    end else if (wr_in_fifo_afull_i || wr_in_fifo_full_i) begin
                        // Stop reading from FT2232 FIFO.
                        fifo_rd_n_o <= 1'b1;
                        // Stop writting.
                        wr_in_fifo_en_o <= 1'b0;

                        // Save read data so we can write it to the IN FIFO later.
                        saved_rd_data_bits[0] <= 1'b1;
                        saved_rd_data_0 <= fifo_data_i;
`ifdef D_FT_FIFO
                        $display ($time, " FT_FIFO:\t---> [STATE_RD_DATA] Wr IN delayed [0]: %d (IN afull: %d, full: %d).",
                                            fifo_data_i, wr_in_fifo_afull_i, wr_in_fifo_full_i);
`endif
                        // Wait to get the value read (with a one cycle delay).
                        state_m <= STATE_RD_STOP;
                    end else begin
                        // Write the data to the input FIFO.
                        wr_in_fifo_en_o <= 1'b1;
                        wr_in_fifo_data_o <= fifo_data_i;
`ifdef D_FT_FIFO
                        $display ($time, " FT_FIFO:\t---> [STATE_RD_DATA] Wr IN: %d (IN afull: %d, full: %d).",
                                                fifo_data_i, wr_in_fifo_afull_i, wr_in_fifo_full_i);
`endif
                        in_count <= in_count + 1;
                        // If a quarter of the FIFO was writtten check if we can switch to write.
                        if ((in_count >= IN_THRESHOLD) && can_write_to_ft2232_fifo) begin
`ifdef D_FT_FIFO_FINE
                            $display ($time, " FT_FIFO:\t[STATE_RD_DATA] Wr IN %d bytes. Switch to read.", in_count);
`endif
                            // Stop reading from FT2232 FIFO.
                            fifo_rd_n_o <= 1'b1;

                            state_m <= STATE_RD_STOP;
                        end
                    end
                end

                STATE_RD_STOP: begin
                    if (~fifo_rxf_n_i) begin
`ifdef D_FT_FIFO
                        $display ($time, " FT_FIFO:\t---> [STATE_RD_STOP] Wr IN delayed [1]: %d (IN afull: %d, full: %d).",
                                                fifo_data_i, wr_in_fifo_afull_i, wr_in_fifo_full_i);
`endif
                        wr_in_fifo_en_o <= 1'b0;

                        saved_rd_data_bits[1] <= 1'b1;
                        saved_rd_data_1 <= fifo_data_i;
                    end

                    state_m <= STATE_IDLE_RD;
                end

                STATE_IDLE_WR: begin
                    // Enter this state machine with fifo_oe_n_o = 1'b1
`ifdef EXT_ENABLED
                    led_ft2232_wr_data_o <= 1'b0;
`endif
                    fifo_wr_n_o <= 1'b1;
                    // Check if there is data to read in the FT2232 FIFO.
                    if (can_read_from_ft2232_fifo || have_saved_rd_data) begin
                        // OE needs to be low (it is high since a write completed).
                        fifo_oe_n_o <= 1'b0;
`ifdef D_FT_FIFO_FINE
                        $display ($time, " FT_FIFO:\t[STATE_IDLE_WR] OE: 0.");
`endif
                        // Wait one cycle after changing OE.
                        state_m <= STATE_RD_TURN_AROUND;
                    end else if (~fifo_txe_n_i && have_saved_wr_data) begin
                        state_m <= STATE_FLUSH_SAVED_WR_DATA;
                    end else if (can_write_to_ft2232_fifo) begin
                        // Read from the IN FIFO.
                        rd_out_fifo_en_o <= 1'b1;

                        out_count <= 0;
                        state_m <= STATE_WR_DATA;
                    end
                end

                STATE_FLUSH_SAVED_WR_DATA: begin
`ifdef D_FT_FIFO
                    $display ($time, " FT_FIFO:\t<--- [STATE_FLUSH_SAVED_WR_DATA] Wr FT2232 saved data: %d.",
                                saved_wr_data);
`endif
                    fifo_wr_n_o <= 1'b0;
                    // Write data to the FT2232 FIFO.
                    fifo_data_o <= saved_wr_data;
                    have_saved_wr_data <= 1'b0;

                    state_m <= STATE_IDLE_WR;
                end

                STATE_WR_DATA: begin
`ifdef EXT_ENABLED
                    led_ft2232_wr_data_o <= 1'b1;
`endif
                    if (fifo_txe_n_i) begin
                        // The last value could not be written (the FT2232 IFO became full).
`ifdef D_FT_FIFO
                        $display ($time, " FT_FIFO:\t[STATE_WR_DATA] Delayed Wr FT2232: %d.", saved_wr_data);
`endif
                        have_saved_wr_data <= 1'b1;

                        fifo_wr_n_o <= 1'b1;
                        rd_out_fifo_en_o <= 1'b0;

                        state_m <= STATE_IDLE_WR;
                    end else if (~rd_out_fifo_empty_i) begin
`ifdef D_FT_FIFO
                        $display ($time, " FT_FIFO:\t<--- [STATE_WR_DATA] Wr FT2232: %d.", rd_out_fifo_data_i);
`endif
                        fifo_wr_n_o <= 1'b0;
                        // Write data to the FT2232 FIFO.
                        fifo_data_o <= rd_out_fifo_data_i;
                        saved_wr_data <= rd_out_fifo_data_i;

                        out_count <= out_count + 1;
                        // If half of the FIFO was writtten check if we can switch to read.
                        if (out_count >= OUT_THRESHOLD && can_read_from_ft2232_fifo) begin
`ifdef D_FT_FIFO_FINE
                            $display ($time, " FT_FIFO:\t[STATE_WR_DATA] Wrote FT2232 %d bytes.", out_count);
`endif
                            rd_out_fifo_en_o <= 1'b0;

                            state_m <= STATE_IDLE_WR;
                        end
                    end else begin
                        fifo_wr_n_o <= 1'b1;
                        rd_out_fifo_en_o <= 1'b0;

                        state_m <= STATE_IDLE_WR;
                    end
                end
            endcase
        end
    end
endmodule
