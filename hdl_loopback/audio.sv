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
 * This module implements the top of the audio transmission application.
 **********************************************************************************************************************/
`timescale 1ps/1ps
`default_nettype none

module audio (
    // Reset button
    input logic btn_reset,
    // Clocks
    input logic clk_24576000,
    input logic clk_22579200,
    // FT2232HQ FIFO
    input logic fifo_clk,
    input logic fifo_txe_n,
    input logic fifo_rxf_n,
    output logic ft2232_reset_n,
    output logic fifo_oe_n,
    output logic fifo_siwu,
    output logic fifo_wr_n,
    output logic fifo_rd_n,
    inout wire [7:0] fifo_data,
    // LEDs
    output logic led_0,
    output logic led_1,
    output logic led_reset,
    output logic led_user);

    //==================================================================================================================
    // Assign main board LEDs
    //==================================================================================================================
    assign led_user = 1'b0;

    //==================================================================================================================
    // Definitions
    //==================================================================================================================
    // Reset
    logic reset = 1'b0;

    // Stop the clocks during reset
    logic fifo_clk_i, clk_24576000_i, clk_22579200_i;
    assign fifo_clk_i = reset ? 1'b0: fifo_clk;
    assign clk_24576000_i = reset ? 1'b0: clk_24576000;
    assign clk_22579200_i = reset ? 1'b0: clk_22579200;
    // Assign the clock for this module
    logic clk;
    assign clk = clk_24576000;

    //==================================================================================================================
    // This module implements the FT2232 synchronous FIFO interface.
    //==================================================================================================================
    ft2232_fifo ft2232_fifo_m (
        .reset_i            (reset),
        // FT2232HQ FIFO
        .ft2232_reset_n_o   (ft2232_reset_n),
        .fifo_clk_i         (fifo_clk_i),
        .fifo_oe_n_o        (fifo_oe_n),
        .fifo_siwu_o        (fifo_siwu),
        .fifo_wr_n_o        (fifo_wr_n),
        .fifo_rd_n_o        (fifo_rd_n),
        .fifo_txe_n_i       (fifo_txe_n),
        .fifo_rxf_n_i       (fifo_rxf_n),
        .fifo_data_io       (fifo_data),
        // LEDs
        .led_ft2232_rd_data_o   (led_0),
        .led_ft2232_wr_data_o   (led_1));

    logic btn_reset_meta;
    DFF_META fpga_reset_meta_m (1'b0, btn_reset, clk, btn_reset_meta);

    // The application state machines
    localparam STATE_RESET      = 1'b0;
    localparam STATE_RUNNING    = 1'b1;
    logic state_m = STATE_RESET;

    //==================================================================================================================
    // The main state machine
    //==================================================================================================================
    always @(posedge clk) begin
        (* parallel_case, full_case *)
        case (state_m)
            STATE_RESET: begin
                reset_task;
            end

            STATE_RUNNING: begin
                if (btn_reset_meta) begin
                    // Entering reset.
                    state_m <= STATE_RESET;
                    reset_state_m <= STATE_RESET_BEGIN;
                end
            end
        endcase
    end

    // The RESET state machines
    localparam STATE_RESET_BEGIN                = 2'b00;
    localparam STATE_RESET_WAIT_FOR_BTN_RELEASE = 2'b01;
    localparam STATE_RESET_IN_PROGRESS          = 2'b10;
    localparam STATE_RESET_END                  = 2'b11;
    logic [1:0] reset_state_m = STATE_RESET_BEGIN;

    // The duration of reset expressed in number of clock cycles (24.576MHz_o -> 40.69nS; 7 * 40.69ns = 284.83nS).
    localparam RESET_CLKS = 7;
    logic [2:0] reset_clks;

    //==================================================================================================================
    // The reset task
    //==================================================================================================================
    task reset_task;
        (* parallel_case, full_case *)
        case (reset_state_m)
            STATE_RESET_BEGIN: begin
`ifdef D_CORE
                $display ($time, " CORE:\t-- STATE_RESET_BEGIN");
`endif
                // Reset is in progress
                reset <= 1'b1;
                // Reset variables
                led_reset <= 1'b1;

                // Wait one clock so that the Reset button meta value is initialized after power on.
                reset_state_m <= STATE_RESET_WAIT_FOR_BTN_RELEASE;
            end

            STATE_RESET_WAIT_FOR_BTN_RELEASE: begin
                // If the Reset button is still pressed remain in this state machine.
                if (~btn_reset_meta) begin
                    reset_state_m <= STATE_RESET_IN_PROGRESS;
                    reset_clks <= RESET_CLKS;
                end else begin
`ifdef D_CORE
                    $display ($time, " CORE:\t-- STATE_RESET_WAIT_FOR_BTN_RELEASE");
`endif
                end
            end

            STATE_RESET_IN_PROGRESS: begin
                reset_clks <= reset_clks - 3'd1;
                if (~|reset_clks) begin
                    reset_state_m <= STATE_RESET_END;
                end
            end

            STATE_RESET_END: begin
                // Reset is complete
                reset <= 1'b0;

                led_reset <= 1'b0;

`ifdef D_CORE
                $display ($time, " CORE:\t-- STATE_RESET_END");
`endif

                state_m <= STATE_RUNNING;
            end
        endcase
    endtask
endmodule
