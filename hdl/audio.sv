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
`ifdef ENABLE_UART
    // UART
    input logic uart_rxd,
    output logic uart_txd,
    output logic led_uart_tx_overflow,
    output logic led_uart_rx_overflow,
`endif
    // Extension
    inout logic [45:0] extension,
    // LEDs
    output logic led_reset,
    output logic led_user);

    logic ext_led_app_in_fifo_rd_o, ext_led_app_in_fifo_full_o, ext_led_app_in_fifo_has_data_o;
    logic ext_led_ft2232_in_data_o, ext_led_ft2232_out_fifo_has_data_o, ext_led_ft2232_in_fifo_is_full_o,
            ext_led_ft2232_out_data_o;
    logic ext_led_app_out_fifo_wr_o, ext_led_app_out_fifo_full_o, ext_led_app_out_fifo_has_data_o;
    logic ext_led_test_ok_o, ext_led_test_fail_o;
    logic ext_led_app_ctrl_err_o;
    logic spdif, i2s_sdata, i2s_bclk, i2s_lrck, i2s_mclk;
    logic ext_led_sr_48000Hz, ext_led_sr_96000Hz, ext_led_sr_192000Hz, ext_led_sr_384000Hz;
    logic ext_led_sr_44100Hz, ext_led_sr_88200Hz, ext_led_sr_176400Hz, ext_led_sr_352800Hz;
    logic ext_led_br_dop, ext_led_br_16_bit, ext_led_br_24_bit, ext_led_br_32_bit;
    logic ext_led_t_spdif, ext_led_t_i2s;
    logic ext_led_streaming_spdif, ext_led_streaming_i2s;

`ifdef EXT_A_ENABLED
    //==================================================================================================================
    // Extension
    // .T = 0 -> extension is output; .T = 1 -> extension is input.
    //==================================================================================================================
    logic ext_btn_reset, ext_btn_reset_meta;
    TRELLIS_IO #(.DIR("INPUT")) extension_0(.B(extension[0]), .T(1'b1), .O(ext_btn_reset));
    DFF_META extension_fpga_reset_meta_m (1'b0, ext_btn_reset, clk, ext_btn_reset_meta);

    // Input FIFO
    TRELLIS_IO #(.DIR("OUTPUT")) extension_1(.B(extension[1]), .T(1'b0), .I(ext_led_ft2232_in_data_o));

    TRELLIS_IO #(.DIR("OUTPUT")) extension_2(.B(extension[2]), .T(1'b0), .I(ext_led_app_in_fifo_rd_o));
    assign ext_led_app_in_fifo_rd_o = rd_in_fifo_en;

    TRELLIS_IO #(.DIR("OUTPUT")) extension_3(.B(extension[3]), .T(1'b0), .I(ext_led_app_in_fifo_full_o));
    assign ext_led_app_in_fifo_full_o = wr_in_fifo_full;

    TRELLIS_IO #(.DIR("OUTPUT")) extension_4(.B(extension[4]), .T(1'b0), .I(ext_led_app_in_fifo_has_data_o));
    assign ext_led_app_in_fifo_has_data_o = ~rd_in_fifo_empty;

    TRELLIS_IO #(.DIR("OUTPUT")) extension_5(.B(extension[5]), .T(1'b0), .I(ext_led_ft2232_out_fifo_has_data_o));
    assign ext_led_ft2232_out_fifo_has_data_o = ~fifo_rxf_n;

    // Output FIFO
    TRELLIS_IO #(.DIR("OUTPUT")) extension_8(.B(extension[8]), .T(1'b0), .I(ext_led_ft2232_out_data_o));

    TRELLIS_IO #(.DIR("OUTPUT")) extension_9(.B(extension[9]), .T(1'b0), .I(ext_led_app_out_fifo_wr_o));
    assign ext_led_app_out_fifo_wr_o = wr_out_fifo_en;

    TRELLIS_IO #(.DIR("OUTPUT")) extension_10(.B(extension[10]), .T(1'b0), .I(ext_led_app_out_fifo_full_o));
    assign ext_led_app_out_fifo_full_o = wr_out_fifo_full;

    TRELLIS_IO #(.DIR("OUTPUT")) extension_11(.B(extension[11]), .T(1'b0), .I(ext_led_app_out_fifo_has_data_o));
    assign ext_led_app_out_fifo_has_data_o = ~rd_out_fifo_empty;

    TRELLIS_IO #(.DIR("OUTPUT")) extension_12(.B(extension[12]), .T(1'b0), .I(ext_led_ft2232_in_fifo_is_full_o));
    assign ext_led_ft2232_in_fifo_is_full_o = fifo_txe_n;

    // Test
    TRELLIS_IO #(.DIR("OUTPUT")) extension_16(.B(extension[16]), .T(1'b0), .I(ext_led_test_ok_o));
    TRELLIS_IO #(.DIR("OUTPUT")) extension_17(.B(extension[17]), .T(1'b0), .I(ext_led_test_fail_o));
`ifndef TEST_MODE
    assign ext_led_test_ok_o = 1'b0;
    assign ext_led_test_fail_o = 1'b0;
`endif

    // TX
    TRELLIS_IO #(.DIR("OUTPUT")) extension_18(.B(extension[18]), .T(1'b0), .I(ext_led_app_ctrl_err_o));

    // Audio outputs
    TRELLIS_IO #(.DIR("OUTPUT")) extension_19(.B(extension[19]), .T(1'b0), .I(spdif));
    TRELLIS_IO #(.DIR("OUTPUT")) extension_20(.B(extension[20]), .T(1'b0), .I(i2s_sdata));
    TRELLIS_IO #(.DIR("OUTPUT")) extension_21(.B(extension[21]), .T(1'b0), .I(i2s_bclk));
    TRELLIS_IO #(.DIR("OUTPUT")) extension_22(.B(extension[22]), .T(1'b0), .I(i2s_lrck));
    TRELLIS_IO #(.DIR("OUTPUT")) extension_23(.B(extension[23]), .T(1'b0), .I(i2s_mclk));

    // Sample rate LEDs
    TRELLIS_IO #(.DIR("OUTPUT")) extension_24(.B(extension[24]), .T(1'b0), .I(ext_led_sr_48000Hz));
    TRELLIS_IO #(.DIR("OUTPUT")) extension_25(.B(extension[25]), .T(1'b0), .I(ext_led_sr_96000Hz));
    TRELLIS_IO #(.DIR("OUTPUT")) extension_26(.B(extension[26]), .T(1'b0), .I(ext_led_sr_192000Hz));
    TRELLIS_IO #(.DIR("OUTPUT")) extension_27(.B(extension[27]), .T(1'b0), .I(ext_led_sr_384000Hz));
    TRELLIS_IO #(.DIR("OUTPUT")) extension_28(.B(extension[28]), .T(1'b0), .I(ext_led_sr_44100Hz));
    TRELLIS_IO #(.DIR("OUTPUT")) extension_29(.B(extension[29]), .T(1'b0), .I(ext_led_sr_88200Hz));
    TRELLIS_IO #(.DIR("OUTPUT")) extension_30(.B(extension[30]), .T(1'b0), .I(ext_led_sr_176400Hz));
    TRELLIS_IO #(.DIR("OUTPUT")) extension_31(.B(extension[31]), .T(1'b0), .I(ext_led_sr_352800Hz));

    // Bit rate LEDs
    TRELLIS_IO #(.DIR("OUTPUT")) extension_32(.B(extension[32]), .T(1'b0), .I(ext_led_br_dop));
    TRELLIS_IO #(.DIR("OUTPUT")) extension_33(.B(extension[33]), .T(1'b0), .I(ext_led_br_16_bit));
    TRELLIS_IO #(.DIR("OUTPUT")) extension_34(.B(extension[34]), .T(1'b0), .I(ext_led_br_24_bit));
    TRELLIS_IO #(.DIR("OUTPUT")) extension_35(.B(extension[35]), .T(1'b0), .I(ext_led_br_32_bit));

    // Output type LEDs
    TRELLIS_IO #(.DIR("OUTPUT")) extension_36(.B(extension[36]), .T(1'b0), .I(ext_led_t_spdif));
    TRELLIS_IO #(.DIR("OUTPUT")) extension_37(.B(extension[37]), .T(1'b0), .I(ext_led_t_i2s));

    // Streaming LEDs
    TRELLIS_IO #(.DIR("OUTPUT")) extension_38(.B(extension[38]), .T(1'b0), .I(ext_led_streaming_spdif));
    TRELLIS_IO #(.DIR("OUTPUT")) extension_39(.B(extension[39]), .T(1'b0), .I(ext_led_streaming_i2s));
`endif

`ifdef TEST_MODE
    assign led_user = 1'b1;
`else
    assign led_user = 1'b0;
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
    localparam IN_FIFO_ASIZE = 6;
    localparam OUT_FIFO_ASIZE = 6;

    logic wr_in_fifo_en, wr_in_fifo_clk, wr_in_fifo_afull, wr_in_fifo_full;
    logic rd_in_fifo_en, rd_in_fifo_clk, rd_in_fifo_empty;
    logic [7:0] wr_in_fifo_data, rd_in_fifo_data;

    logic wr_out_fifo_en, wr_out_fifo_clk, wr_out_fifo_afull, wr_out_fifo_full;
    logic rd_out_fifo_en, rd_out_fifo_clk, rd_out_fifo_empty;
    logic [7:0] wr_out_fifo_data, rd_out_fifo_data;

    // The FIFO used by the FPGA to read from the FT2232 FIFO.
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

    // The FIFO used by the FPGA to write to the FT2232 FIFO.
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

    // FT2232 FIFO
    ft2232_fifo #(.IN_FIFO_ASIZE(IN_FIFO_ASIZE), .OUT_FIFO_ASIZE(OUT_FIFO_ASIZE)) ft2232_fifo_m (
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
        .rd_out_fifo_empty_i (rd_out_fifo_empty),
        .led_ft2232_rd_data_o   (ext_led_ft2232_in_data_o),
        .led_ft2232_wr_data_o   (ext_led_ft2232_out_data_o)
        );

    // Audio transmission module
    control control_m (
        .reset_i                (reset),
        .clk_24576000_i         (clk_24576000_i),
        .clk_22579200_i         (clk_22579200_i),
        // Input FIFO ports
        .rd_in_fifo_clk_o       (rd_in_fifo_clk),
        .rd_in_fifo_en_o        (rd_in_fifo_en),
        .rd_in_fifo_empty_i     (rd_in_fifo_empty),
        .rd_in_fifo_data_i      (rd_in_fifo_data),
        // Output FIFO ports
        .wr_out_fifo_clk_o      (wr_out_fifo_clk),
        .wr_out_fifo_en_o       (wr_out_fifo_en),
        .wr_out_fifo_full_i     (wr_out_fifo_full),
        .wr_out_fifo_afull_i    (wr_out_fifo_afull),
        .wr_out_fifo_data_o     (wr_out_fifo_data),
        // Audio ouputs
        .spdif_o                (spdif),
        .i2s_sdata_o            (i2s_sdata),
        .i2s_bclk_o             (i2s_bclk),
        .i2s_lrck_o             (i2s_lrck),
        .i2s_mclk_o             (i2s_mclk),
`ifdef TEST_MODE
        .led_test_ok            (ext_led_test_ok_o),
        .led_test_fail          (ext_led_test_fail_o)
`else
        .led_app_ctrl_err_o     (ext_led_app_ctrl_err_o),
        // Sample rate LEDs
        .led_sr_48000Hz         (ext_led_sr_48000Hz),
        .led_sr_96000Hz         (ext_led_sr_96000Hz),
        .led_sr_192000Hz        (ext_led_sr_192000Hz),
        .led_sr_384000Hz        (ext_led_sr_384000Hz),
        .led_sr_44100Hz         (ext_led_sr_44100Hz),
        .led_sr_88200Hz         (ext_led_sr_88200Hz),
        .led_sr_176400Hz        (ext_led_sr_176400Hz),
        .led_sr_352800Hz        (ext_led_sr_352800Hz),
        // Bit depth LEDs
        .led_br_dop             (ext_led_br_dop),
        .led_br_16_bit          (ext_led_br_16_bit),
        .led_br_24_bit          (ext_led_br_24_bit),
        .led_br_32_bit          (ext_led_br_32_bit),
        // Output type
        .led_t_spdif            (ext_led_t_spdif),
        .led_t_i2s              (ext_led_t_i2s),
        // Streaming status LEDs
        .led_streaming_spdif    (ext_led_streaming_spdif),
        .led_streaming_i2s      (ext_led_streaming_i2s)
`endif // TEST_MODE
        );

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

    // The duration of reset expressed in number of clock cycles (24.576MHz -> 40.69nS; 7 * 40.69ns = 284.83nS).
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
