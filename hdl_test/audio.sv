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
 * This module implements the top of the test application.
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
    // Extension
    inout logic [45:0] extension,
    // LEDs
    output logic led_0,
    output logic led_1,
    output logic led_reset,
    output logic led_user);

    logic ext_led_ctrl_err_o;
`ifdef EXT_A_ENABLED
    logic ext_led_app_in_fifo_rd_o, ext_led_app_in_fifo_full_o, ext_led_app_in_fifo_has_data_o;
    logic ext_led_rd_ft2232_data_o, ext_led_ft2232_out_fifo_has_data_o, ext_led_ft2232_in_fifo_is_full_o,
            ext_led_wr_ft2232_data_o;
    logic ext_led_app_out_fifo_wr_o, ext_led_app_out_fifo_full_o, ext_led_app_out_fifo_has_data_o;

    //==================================================================================================================
    // Extension
    // .T = 0 -> extension is output; .T = 1 -> extension is input.
    //==================================================================================================================
    logic ext_btn_reset, ext_btn_reset_meta;
    TRELLIS_IO #(.DIR("INPUT")) extension_0(.B(extension[0]), .T(1'b1), .O(ext_btn_reset));
    DFF_META extension_fpga_reset_meta_m (1'b0, ext_btn_reset, clk, ext_btn_reset_meta);

    // Input FIFO
    TRELLIS_IO #(.DIR("OUTPUT")) extension_42(.B(extension[42]), .T(1'b0), .I(ext_led_rd_ft2232_data_o));
    led_illum led_illum_fifo_rd_m (.reset_i(reset), .clk_i(fifo_clk), .signal_i(~fifo_rd_n),
                        .led_o(ext_led_rd_ft2232_data_o));

    TRELLIS_IO #(.DIR("OUTPUT")) extension_44(.B(extension[44]), .T(1'b0), .I(ext_led_ft2232_out_fifo_has_data_o));
    assign ext_led_ft2232_out_fifo_has_data_o = ~fifo_rxf_n;

    TRELLIS_IO #(.DIR("OUTPUT")) extension_39(.B(extension[39]), .T(1'b0), .I(ext_led_app_in_fifo_full_o));
    assign ext_led_app_in_fifo_full_o = wr_in_fifo_full;

    TRELLIS_IO #(.DIR("OUTPUT")) extension_35(.B(extension[35]), .T(1'b0), .I(ext_led_app_in_fifo_has_data_o));
    assign ext_led_app_in_fifo_has_data_o = ~rd_in_fifo_empty;

    TRELLIS_IO #(.DIR("OUTPUT")) extension_31(.B(extension[31]), .T(1'b0), .I(ext_led_app_in_fifo_rd_o));
    led_illum led_illum_app_in_fifo_rd_m (.reset_i(reset), .clk_i(fifo_clk), .signal_i(rd_in_fifo_en),
                .led_o(ext_led_app_in_fifo_rd_o));

    // Output FIFO
    TRELLIS_IO #(.DIR("OUTPUT")) extension_43(.B(extension[43]), .T(1'b0), .I(ext_led_wr_ft2232_data_o));
    led_illum led_illum_fifo_wr_m (.reset_i(reset), .clk_i(fifo_clk), .signal_i(~fifo_wr_n),
                        .led_o(ext_led_wr_ft2232_data_o));

    TRELLIS_IO #(.DIR("OUTPUT")) extension_45(.B(extension[45]), .T(1'b0), .I(ext_led_ft2232_in_fifo_is_full_o));
    assign ext_led_ft2232_in_fifo_is_full_o = ~fifo_txe_n;

    TRELLIS_IO #(.DIR("OUTPUT")) extension_33(.B(extension[33]), .T(1'b0), .I(ext_led_app_out_fifo_wr_o));
    led_illum led_illum_app_out_fifo_wr_m (.reset_i(reset), .clk_i(fifo_clk), .signal_i(wr_out_fifo_en),
                .led_o(ext_led_app_out_fifo_wr_o));

    TRELLIS_IO #(.DIR("OUTPUT")) extension_37(.B(extension[37]), .T(1'b0), .I(ext_led_app_out_fifo_full_o));
    assign ext_led_app_out_fifo_full_o = wr_out_fifo_full;

    TRELLIS_IO #(.DIR("OUTPUT")) extension_41(.B(extension[41]), .T(1'b0), .I(ext_led_app_out_fifo_has_data_o));
    assign ext_led_app_out_fifo_has_data_o = ~rd_out_fifo_empty;

    // Control error LED
    TRELLIS_IO #(.DIR("OUTPUT")) extension_29(.B(extension[29]), .T(1'b0), .I(ext_led_ctrl_err_o));

    //==================================================================================================================
    // Assign main board LEDs
    //==================================================================================================================
    assign led_0 = 1'b0;
    assign led_1 = 1'b0;
    assign led_user = 1'b0;
`else
    //==================================================================================================================
    // Assign main board LEDs
    //==================================================================================================================
    assign led_0 = fifo_rxf_n;
    assign led_1 = fifo_txe_n;
    assign led_user = ext_led_ctrl_err_o;
`endif

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
    // Modules
    //==================================================================================================================
    // FIFO address sizes.
`ifdef FIFO_ADDR_BITS
    localparam IN_FIFO_ASIZE = `FIFO_ADDR_BITS;
    localparam OUT_FIFO_ASIZE = `FIFO_ADDR_BITS;
`else
    // Default FIFO address bits
    localparam IN_FIFO_ASIZE = 5;
    localparam OUT_FIFO_ASIZE = 5;
`endif

    logic wr_in_fifo_en, wr_in_fifo_clk, wr_in_fifo_afull, wr_in_fifo_full;
    logic rd_in_fifo_en, rd_in_fifo_clk, rd_in_fifo_empty;
    logic [7:0] wr_in_fifo_data, rd_in_fifo_data;

    logic wr_out_fifo_en, wr_out_fifo_clk, wr_out_fifo_afull, wr_out_fifo_full;
    logic rd_out_fifo_en, rd_out_fifo_clk, rd_out_fifo_empty;
    logic [7:0] wr_out_fifo_data, rd_out_fifo_data;

    //==================================================================================================================
    // The FIFO used by the FPGA to read from the FT2232 FIFO.
    //==================================================================================================================
    async_fifo #(.ASIZE(IN_FIFO_ASIZE)) in_async_fifo_m (
        // Write to FIFO
        .wr_reset_i         (reset),
        .wr_en_i            (wr_in_fifo_en),
        .wr_clk_i           (wr_in_fifo_clk),
        .wr_data_i          (wr_in_fifo_data),
        .wr_full_o          (wr_in_fifo_full),
        .wr_awfull_o        (wr_in_fifo_afull),
        // Read from FIFO
        .rd_reset_i         (reset),
        .rd_en_i            (rd_in_fifo_en),
        .rd_clk_i           (rd_in_fifo_clk),
        .rd_data_o          (rd_in_fifo_data),
        .rd_empty_o         (rd_in_fifo_empty));

    //==================================================================================================================
    // The FIFO used by the FPGA to write to the FT2232 FIFO.
    //==================================================================================================================
    async_fifo #(.ASIZE(OUT_FIFO_ASIZE)) out_async_fifo_m (
        // Write to FIFO
        .wr_reset_i         (reset),
        .wr_en_i            (wr_out_fifo_en),
        .wr_clk_i           (wr_out_fifo_clk),
        .wr_data_i          (wr_out_fifo_data),
        .wr_full_o          (wr_out_fifo_full),
        .wr_awfull_o        (wr_out_fifo_afull),
        // Read from FIFO
        .rd_reset_i         (reset),
        .rd_en_i            (rd_out_fifo_en),
        .rd_clk_i           (rd_out_fifo_clk),
        .rd_data_o          (rd_out_fifo_data),
        .rd_empty_o         (rd_out_fifo_empty));

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
        // Input FIFO ports
        .wr_in_fifo_clk_o   (wr_in_fifo_clk),
        .wr_in_fifo_en_o    (wr_in_fifo_en),
        .wr_in_fifo_data_o  (wr_in_fifo_data),
        .wr_in_fifo_full_i  (wr_in_fifo_full),
        .wr_in_fifo_afull_i (wr_in_fifo_afull),
        // Output FIFO ports
        .rd_out_fifo_clk_o   (rd_out_fifo_clk),
        .rd_out_fifo_en_o    (rd_out_fifo_en),
        .rd_out_fifo_data_i  (rd_out_fifo_data),
        .rd_out_fifo_empty_i (rd_out_fifo_empty));

    //==================================================================================================================
    // The control module sends and receives data from FT2232 using two asynchronous FIFOs.
    //==================================================================================================================
    control control_m (
        .reset_i                (reset),
        .clk_24576000_i         (clk_24576000_i),
        .clk_22579200_i         (clk_22579200_i),
        // Input FIFO ports
        .rd_in_fifo_clk_o       (rd_in_fifo_clk),
        .rd_in_fifo_en_o        (rd_in_fifo_en),
        .rd_in_fifo_data_i      (rd_in_fifo_data),
        .rd_in_fifo_empty_i     (rd_in_fifo_empty),
        // Output FIFO ports
        .wr_out_fifo_clk_o      (wr_out_fifo_clk),
        .wr_out_fifo_en_o       (wr_out_fifo_en),
        .wr_out_fifo_data_o     (wr_out_fifo_data),
        .wr_out_fifo_full_i     (wr_out_fifo_full),
        .wr_out_fifo_afull_i    (wr_out_fifo_afull),
        .led_ctrl_err_o         (ext_led_ctrl_err_o));

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
`ifdef EXT_A_ENABLED
                if (btn_reset_meta || ~ext_btn_reset_meta) begin
`else
                if (btn_reset_meta) begin
`endif
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
`ifdef EXT_A_ENABLED
                if (~btn_reset_meta || ext_btn_reset_meta) begin
`else
                if (~btn_reset_meta) begin
`endif
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
