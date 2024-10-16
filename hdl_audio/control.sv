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
 * This module implements the reading out of the async FIFO at the appropriate audio frequency and sends the audio
 * samples to the digital audio module. It only supports playback at this time.
 **********************************************************************************************************************/
`timescale 1ps/1ps
`default_nettype none

`include "definitions.svh"

module control (
    input logic reset_i,
    input logic clk_24576000_i,
    input logic clk_22579200_i,
    // Input FIFO access
    output logic rd_in_fifo_clk_o,
    output logic rd_in_fifo_en_o,
    input logic rd_in_fifo_empty_i,
    input logic [7:0] rd_in_fifo_data_i,
    // Output FIFO ports
    output logic wr_out_fifo_clk_o,
    output logic wr_out_fifo_en_o,
    output logic [7:0] wr_out_fifo_data_o,
    input logic wr_out_fifo_full_i,
    input logic wr_out_fifo_afull_i,
    // Audio output
    output logic spdif_o,
    output logic i2s_sdata_o,
    output logic i2s_bclk_o,
    output logic i2s_lrck_o,
    output logic i2s_mclk_o,
    output logic dsd_o,
    // Sample rate LEDs
    output logic led_ctrl_err_o,
    output logic led_sr_48000Hz_o,
    output logic led_sr_96000Hz_o,
    output logic led_sr_192000Hz_o,
    output logic led_sr_384000Hz_o,
    output logic led_sr_44100Hz_o,
    output logic led_sr_88200Hz_o,
    output logic led_sr_176400Hz_o,
    output logic led_sr_352800Hz_o,
    // Bit depth LEDs
    output logic led_br_dop_o,
    output logic led_br_16_bit_o,
    output logic led_br_24_bit_o,
    output logic led_br_32_bit_o,
    // Streaming status
    output logic led_streaming_spdif_o,
    output logic led_streaming_i2s_o,
    // Test point
    output logic tp_control_1_o,
    output logic tp_control_2_o);

    // Assign test points as needed
    assign tp_control_1_o = spdif_rd_output_FIFO_clk;
    assign tp_control_2_o = i2s_rd_output_FIFO_clk;

    assign rd_in_fifo_clk_o = clk;
    assign wr_out_fifo_clk_o = clk;

`ifdef SIMULATION
    logic [3:0] pll_clocks_24576000 = 4'b0000;
    // Max bit clock for 24 bit @24.576000 MHz
    localparam CLK_18432000_PS = 54253;
    always #(CLK_18432000_PS/2) pll_clocks_24576000[0] = ~pll_clocks_24576000[0];
    // Max frequency which is a multiple of 2 @24.576000 MHz
    localparam CLK_98304000_PS = 10172;
    always #(CLK_98304000_PS/2) pll_clocks_24576000[1] = ~pll_clocks_24576000[1];

    logic [3:0] pll_clocks_22579200 = 4'b0000;
    // Max bit clock for 24 bit @22.579200 MHz
    localparam CLK_16934400_PS = 59051;
    always #(CLK_16934400_PS/2) pll_clocks_22579200[0] = ~pll_clocks_22579200[0];
    // Max frequency which is a multiple of 2 of @22.579200 MHz
    localparam CLK_90316800_PS = 11072;
    always #(CLK_90316800_PS/2) pll_clocks_22579200[1] = ~pll_clocks_22579200[1];
`else
    logic [3:0] pll_clocks_24576000;
    logic pll1_locked;
    ecp5pll #(.in_hz(24576000),
            // Max bit clock for 24 bit @24.576000 MHz
            .out0_hz(18432000),
            // Max frequency which is a multiple of 2 @24.576000 MHz
            .out1_hz(98304000)) pll_1(
            .clk_i(clk_24576000_i),
            .clk_o(pll_clocks_24576000),
            .reset(reset_i),
            .standby(1'b0),
            .phasesel(2'b00),
            .phasedir(1'b0),
            .phasestep(1'b0),
            .phaseloadreg(1'b0),
            .locked(pll1_locked));

    logic [3:0] pll_clocks_22579200;
    logic pll2_locked;
    ecp5pll #(.in_hz(22579200),
            // Max bit clock for 24 bit @22.579200 MHz
            .out0_hz(16934400),
            // Max frequency which is a multiple of 2 of @22.579200 MHz
            .out1_hz(90316800)) pll_2(
            .clk_i(clk_22579200_i),
            .clk_o(pll_clocks_22579200),
            .reset(reset_i),
            .standby(1'b0),
            .phasesel(2'b00),
            .phasedir(1'b0),
            .phasestep(1'b0),
            .phaseloadreg(1'b0),
            .locked(pll2_locked));
`endif

    /*==================================================================================================================
    Bit clock frequencies for all supported I2S modes (2 channels).
    --------------------------------------------------------------------------------------------------------------------
    SR      16-bit      24-bit      32-bit      MCLK
    --------------------------------------------------------------------------------------------------------------------
    48000   1536000     2304000     3072000     12288000
    96000   3072000     4608000     6144000     24576000
    192000  6144000     9216000     12288000    49152000
    384000  12288000    18432000    24576000    98304000

    44100   1411200     2116800     2822400     11289600
    88200   2822400     4233600     5644800     22579200
    176400  5644800     8467200     11289600    45158400
    352800  11289600    16934400    22579200    90316800
    ==================================================================================================================*/

    // 32 bit @24.576000 MHz
    logic [3:0] clk_24576000_32;
    // 384 KHz 32 bit: 24576000 Hz
    assign clk_24576000_32[3] = clk_24576000_i;
    // 192 KHz 32 bit: 12288000 Hz
    divide_by_2 divide_by_2_1_m (reset_i, clk_24576000_32[3], clk_24576000_32[2]);
    // 96 KHz 32 bit: 6144000 Hz
    divide_by_2 divide_by_2_2_m (reset_i, clk_24576000_32[2], clk_24576000_32[1]);
    // 48 KHz 32 bit: 3072000 Hz
    divide_by_2 divide_by_2_3_m (reset_i, clk_24576000_32[1], clk_24576000_32[0]);

    // 24 bit @24.576000 MHz
    logic [3:0] clk_24576000_24;
    // 384 KHz 24 bit: 18432000 Hz
    assign clk_24576000_24[3] = pll_clocks_24576000[0];
    // 192 KHz 24 bit: 9216000 Hz
    divide_by_2 divide_by_2_4_m (reset_i, clk_24576000_24[3], clk_24576000_24[2]);
    // 96 KHz 24 bit: 4608000 Hz
    divide_by_2 divide_by_2_5_m (reset_i, clk_24576000_24[2], clk_24576000_24[1]);
    // 48 KHz 24 bit: 2304000 Hz
    divide_by_2 divide_by_2_6_m (reset_i, clk_24576000_24[1], clk_24576000_24[0]);

    // 16 bit @24.576000 MHz
    logic [3:0] clk_24576000_16;
    // 384 KHz 16 bit: 12288000 Hz
    assign clk_24576000_16[3] = clk_24576000_32[2];
    // 192 KHz 16 bit: 6144000 Hz
    assign clk_24576000_16[2] = clk_24576000_32[1];
    // 96 KHz 16 bit: 3072000 Hz
    assign clk_24576000_16[1] = clk_24576000_32[0];
    // 48 KHz 16 bit: 1536000 Hz
    divide_by_2 divide_by_2_7_m (reset_i, clk_24576000_16[1], clk_24576000_16[0]);

    // MCLK @24.576000 MHz
    logic [3:0] clk_24576000_mclk;
    // 384 KHz MCLK: 98304000 Hz
    assign clk_24576000_mclk[3] = pll_clocks_24576000[1];
    // 192 KHz MCLK: 49152000 Hz
    divide_by_2 divide_by_2_8_m (reset_i, clk_24576000_mclk[3], clk_24576000_mclk[2]);
    // 96 KHz MCLK: 24576000 Hz
    assign clk_24576000_mclk[1] = clk_24576000_i;
    // 48 KHZ MCLK: 12288000 Hz
    assign clk_24576000_mclk[0] = clk_24576000_32[2];

    // 32 bit @22.579200 MHz
    logic [3:0] clk_22579200_32;
    // 352.8 KHz 32 bit: 22579200 Hz
    assign clk_22579200_32[3] = clk_22579200_i;
    // 176.4 KHz 32 bit: 11289600 Hz
    divide_by_2 divide_by_2_20_m (reset_i, clk_22579200_32[3], clk_22579200_32[2]);
    // 88.2 KHz 32 bit: 5644800 Hz
    divide_by_2 divide_by_2_21_m (reset_i, clk_22579200_32[2], clk_22579200_32[1]);
    // 44.1 KHz 32 bit: 2822400 Hz
    divide_by_2 divide_by_2_22_m (reset_i, clk_22579200_32[1], clk_22579200_32[0]);

    // 24 bit @22.579200 MHz
    logic [3:0] clk_22579200_24;
    // 352.8 KHz 24 bit: 16934400 Hz
    assign clk_22579200_24[3] = pll_clocks_22579200[0];
    // 176.4 KHz 24 bit: 8467200 Hz
    divide_by_2 divide_by_2_23_m (reset_i, clk_22579200_24[3], clk_22579200_24[2]);
    // 88.2 KHz 24 bit: 4233600 Hz
    divide_by_2 divide_by_2_24_m (reset_i, clk_22579200_24[2], clk_22579200_24[1]);
    // 44.1 KHz 24 bit: 2116800 Hz
    divide_by_2 divide_by_2_25_m (reset_i, clk_22579200_24[1], clk_22579200_24[0]);

    // 16 bit @22.579200 MHz
    logic [3:0] clk_22579200_16;
    // 352.8 KHz 16 bit: 11289600 Hz
    assign clk_22579200_16[3] = clk_22579200_32[2];
    // 176.4 KHz 16 bit: 5644800 Hz
    assign clk_22579200_16[2] = clk_22579200_32[1];
    // 88.2 KHz 16 bit: 2822400 Hz
    assign clk_22579200_16[1] = clk_22579200_32[0];
    // 44.1 KHz 16 bit: 1411200 Hz
    divide_by_2 divide_by_2_26_m (reset_i, clk_22579200_16[1], clk_22579200_16[0]);

    // MCLK @22.579200 MHz
    logic [3:0] clk_22579200_mclk;
    // 352.8 KHz MCLK: 90316800 Hz
    assign clk_22579200_mclk[3] = pll_clocks_22579200[1];
    // 176.4 KHz MCLK: 45158400 Hz
    divide_by_2 divide_by_2_27_m (reset_i, clk_22579200_mclk[3], clk_22579200_mclk[2]);
    // 88.2 KHz MCLK: 22579200 Hz
    assign clk_22579200_mclk[1] = clk_22579200_i;
    // 44.1 KHz MCLK: 11289600 Hz
    assign clk_22579200_mclk[0] = clk_22579200_32[2];

    // The I2S bit clock
    logic [15:0] i_clk_24576000;
    assign i_clk_24576000 = {clk_24576000_32, clk_24576000_24, clk_24576000_16, 4'b0000};
    logic [15:0] i_clk_22579200;
    assign i_clk_22579200 = {clk_22579200_32, clk_22579200_24, clk_22579200_16, 4'b0000};
    logic [3:0] bc_index;
    assign bc_index = {bit_depth, sample_rate[1:0]};
    logic i2s_bit_clk;
    assign i2s_bit_clk = io_en[IO_TYPE_I2S_BIT] ? sample_rate[2] ? i_clk_24576000[bc_index] :
                                                                    i_clk_22579200[bc_index] : 1'b0;

    // The I2S MCLK
    logic i2s_mclk;
    assign i2s_mclk = io_en[IO_TYPE_I2S_BIT] ? sample_rate[2] ? clk_24576000_mclk[sample_rate[1:0]] :
                                                                clk_22579200_mclk[sample_rate[1:0]] : 1'b0;

    logic i2s_rd_output_FIFO_clk;
    // From the FIFO we read 8 bits at the bit clock divided by 8.
    divide_by_8 divide_by_8_m (.reset_i(reset_i), .clk_i(i2s_bit_clk), .clk_o(i2s_rd_output_FIFO_clk));

    /*==================================================================================================================
    SPDIF bit clock rates
    --------------------------------------------------------------------------------------------------------------------
    SR      16/24-bit (32x bit data) 2x channels, 2x bi-phase encoding. Symbol rate = sample rate x 128.
    --------------------------------------------------------------------------------------------------------------------
    48000   6144000
    96000   12288000
    192000  24576000

    44100   5644800
    88200   11289600
    176400  22579200
    ==================================================================================================================*/
    // @22.579200 MHz
    logic [3:0] clk_22579200_spdif;
    // 352.8 KHz is not supported for SPDIF
    assign clk_22579200_spdif[3] = 1'b0;
    // 176.4 KHz: 22579200 Hz
    assign clk_22579200_spdif[2] = clk_22579200_32[3];
    // 88.2 KHz: 11289600 Hz
    assign clk_22579200_spdif[1] = clk_22579200_32[2];
    // 44.1 KHz: 5644800 Hz
    assign clk_22579200_spdif[0] = clk_22579200_32[1];

    // @24.576000 MHz
    logic [3:0] clk_24576000_spdif;
    // 384 KHz is not supported for SPDIF
    assign clk_24576000_spdif[3] = 1'b0;
    // 192 KHz: 24576000 Hz
    assign clk_24576000_spdif[2] = clk_24576000_32[3];
    // 96 KHz: 12288000 Hz
    assign clk_24576000_spdif[1] = clk_24576000_32[2];
    // 48 KHz: 6144000 Hz
    assign clk_24576000_spdif[0] = clk_24576000_32[1];

    logic spdif_bit_clk;
    assign spdif_bit_clk = io_en[IO_TYPE_SPDIF_BIT] ? (sample_rate[2] ? clk_24576000_spdif[sample_rate[1:0]] :
                                                            clk_22579200_spdif[sample_rate[1:0]]) : 1'b0;

    logic spdif_rd_output_FIFO_clk;
    // From the FIFO we read 8 bits at the symbol clock divided by 16 (/8 bits and /2 for bi-phase encoding).
    divide_by_16 divide_by_16_m (.reset_i(reset_i), .clk_i(spdif_bit_clk), .clk_o(spdif_rd_output_FIFO_clk));
    /*================================================================================================================*/
    logic clk;
    // For this module use a frequency that is higher than any byte_clk. For I2S the maximum byte_clk is 24576000/8.
    // For SPDIF the maximum byte_clk is 24576000/8. 24.576MHz clk fits the bill.
    assign clk = clk_24576000_i;

    // State machines
    localparam STATE_IDLE                   = 2'b00;
    localparam STATE_RD                     = 2'b01;
    localparam STATE_WR_BUFFER              = 2'b10;
    localparam STATE_WAIT_OUTPUT_TO_STOP    = 2'b11;
    logic [1:0] state_m, next_state_m;

    // Protocol state machine
    localparam STATE_FIFO_CMD               = 2'b00;
    localparam STATE_FIFO_PAYLOAD_LENGTH_1  = 2'b01;
    localparam STATE_FIFO_PAYLOAD_LENGTH_2  = 2'b10;
    localparam STATE_FIFO_PAYLOAD           = 2'b11;
    logic [1:0] fifo_state_m;

    logic [2:0] last_fifo_cmd;
    logic [15:0] rd_payload_bytes;
    logic [4:0] wr_data_index;
    logic [7:0] wr_data[0:1];

    // Audio configuration
    // The io_en index of the bit indicating what type of input/output is enabled.
    localparam IO_TYPE_SPDIF_BIT    = 0;
    localparam IO_TYPE_I2S_BIT      = 1;

    logic wr_output_en;
    logic [1:0] io_en;
    logic [1:0] wr_output_FIFO_full;

    assign wr_output_FIFO_full = {wr_output_FIFO_afull_i2s || wr_output_FIFO_full_i2s,      // IO_TYPE_I2S_BIT index
                                    wr_output_FIFO_afull_spdif || wr_output_FIFO_full_spdif}; // IO_TYPE_SPDIF_BIT index
    logic is_wr_output_FIFO_full;
    assign is_wr_output_FIFO_full = |(wr_output_FIFO_full & io_en);

    logic [2:0] sample_rate;
    logic [1:0] bit_depth;
    logic [7:0] saved_rd_data;
    logic have_saved_rd_data;

    //==================================================================================================================
    // The SPDIF module
    //==================================================================================================================
    logic [7:0] wr_output_FIFO_data;
    logic wr_output_FIFO_full_spdif, wr_output_FIFO_afull_spdif, output_streaming_spdif;
    tx_spdif tx_spdif_m (
        .reset_i                (reset_i),
        .byte_clk_i             (spdif_rd_output_FIFO_clk),
        .bit_clk_i              (spdif_bit_clk),
        // Streaming configuration
        .sample_rate_i          (sample_rate),
        .bit_depth_i            (bit_depth),
        // Clock to write to the output FIFO
        .wr_output_FIFO_clk_i   (clk),
        .wr_output_FIFO_en_i    (io_en[IO_TYPE_SPDIF_BIT] && wr_output_en),
        .wr_output_FIFO_data_i  (wr_output_FIFO_data),
        .wr_output_FIFO_afull_o (wr_output_FIFO_afull_spdif),
        .wr_output_FIFO_full_o  (wr_output_FIFO_full_spdif),
        .output_streaming_o     (output_streaming_spdif),
        // SPDIF output
        .spdif_o                (spdif_o));

    //==================================================================================================================
    // The I2S module
    //==================================================================================================================
    logic wr_output_FIFO_full_i2s, wr_output_FIFO_afull_i2s, output_streaming_i2s;
    tx_i2s tx_i2s_m (
        .reset_i                (reset_i),
        .byte_clk_i             (i2s_rd_output_FIFO_clk),
        .bit_clk_i              (i2s_bit_clk),
        .mclk_i                 (i2s_mclk),
        // Streaming configuration
        .sample_rate_i          (sample_rate),
        .bit_depth_i            (bit_depth),
        // Clock to write to the output FIFO
        .wr_output_FIFO_clk_i   (clk),
        .wr_output_FIFO_en_i    (io_en[IO_TYPE_I2S_BIT] && wr_output_en),
        .wr_output_FIFO_data_i  (wr_output_FIFO_data),
        .wr_output_FIFO_afull_o (wr_output_FIFO_afull_i2s),
        .wr_output_FIFO_full_o  (wr_output_FIFO_full_i2s),
        .output_streaming_o     (output_streaming_i2s),
        // I2S outputs
        .sdata_o                (i2s_sdata_o),
        .bclk_o                 (i2s_bclk_o),
        .lrck_o                 (i2s_lrck_o),
        .mclk_o                 (i2s_mclk_o),
        .dsd_o                  (dsd_o));

    logic output_streaming_meta_spdif, output_streaming_meta_i2s;
    DFF_META streaming_spdif_m (1'b0, output_streaming_spdif, clk, output_streaming_meta_spdif);
    DFF_META streaming_i2s_m (1'b0, output_streaming_i2s, clk, output_streaming_meta_i2s);

    logic output_streaming;
    assign output_streaming = output_streaming_meta_spdif | output_streaming_meta_i2s;

    // Sample rate LEDs
    assign led_sr_48000Hz_o = |io_en && sample_rate == `STREAM_48000_HZ;
    assign led_sr_96000Hz_o = |io_en && sample_rate == `STREAM_96000_HZ;
    assign led_sr_192000Hz_o = |io_en && sample_rate == `STREAM_192000_HZ;
    assign led_sr_384000Hz_o = |io_en && sample_rate == `STREAM_384000_HZ;
    assign led_sr_44100Hz_o = |io_en && sample_rate == `STREAM_44100_HZ;
    assign led_sr_88200Hz_o = |io_en && sample_rate == `STREAM_88200_HZ;
    assign led_sr_176400Hz_o = |io_en && sample_rate == `STREAM_176400_HZ;
    assign led_sr_352800Hz_o = |io_en && sample_rate == `STREAM_352800_HZ;
    // Bit depth LEDs
    assign led_br_dop_o = |io_en && bit_depth == `BIT_DEPTH_DOP;
    assign led_br_16_bit_o = |io_en && bit_depth == `BIT_DEPTH_16;
    assign led_br_24_bit_o = |io_en && bit_depth == `BIT_DEPTH_24;
    assign led_br_32_bit_o = |io_en && bit_depth == `BIT_DEPTH_32;
    // Streaming status LEDs
    assign led_streaming_spdif_o = output_streaming_meta_spdif;
    assign led_streaming_i2s_o = output_streaming_meta_i2s;

    //==================================================================================================================
    // The command handler
    //==================================================================================================================
    task handle_cmd_task (input logic [2:0] fifo_cmd, input logic [4:0] payload_length);
        (* parallel_case, full_case *)
        case (fifo_cmd)
            `CMD_HOST_SETUP_OUTPUT: begin
                led_ctrl_err_o <= 1'b0;
                if (payload_length == 5'd1) begin
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t---> [STATE_FIFO_CMD] Rd IN: CMD_HOST_SETUP_OUTPUT. \033[0;0m");
`endif
                    // Reset the output
                end else begin
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t[ERROR] ---> [STATE_FIFO_CMD] Rd IN: CMD_HOST_SETUP_OUTPUT payload bytes: %d (expected 1). \033[0;0m",
                                        payload_length);
`endif
                    error_task (`ERROR_INVALID_SETUP_OUTPUT_PAYLOAD);
                end
            end

            `CMD_HOST_STREAM_OUTPUT: begin
                if (payload_length[4]) begin
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t---> [STATE_FIFO_CMD] Rd IN: CMD_HOST_STREAM_OUTPUT. \033[0;0m");
`endif
                    // 2 byte payload length follows
                end else begin
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t---> [STATE_FIFO_CMD] Rd IN: CMD_HOST_STREAM_OUTPUT invalid payload length %h. \033[0;0m",
                                payload_length);
`endif
                    error_task (`ERROR_INVALID_STREAM_OUTPUT_PAYLOAD);
                end
            end

            `CMD_HOST_STOP: begin
                if (payload_length == 5'd0) begin
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t---> [STATE_FIFO_CMD] Rd IN: CMD_HOST_STOP. \033[0;0m");
`endif

                    rd_in_fifo_en_o <= 1'b0;
                    state_m <= STATE_WAIT_OUTPUT_TO_STOP;
                end else begin
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t[ERROR] ---> [STATE_FIFO_CMD] Rd IN: CMD_HOST_STOP payload bytes: %d (expected 0). \033[0;0m",
                                        payload_length);
`endif
                    error_task (`ERROR_INVALID_STOP_PAYLOAD);
                end
            end
        endcase
    endtask

    //==================================================================================================================
    // The payload handler.
    //==================================================================================================================
    task handle_payload_task (input logic [2:0] fifo_cmd, input logic [7:0] fifo_data);
        (* parallel_case, full_case *)
        case (fifo_cmd)
            `CMD_HOST_SETUP_OUTPUT: begin
`ifdef D_CTRL
                $display ($time, "\033[0;36m CTRL:\t---> [STATE_FIFO_PAYLOAD for CMD_HOST_SETUP_OUTPUT] Rd IN: Type: %2b; sample rate: %3b; bit depth: %2b. \033[0;0m",
                                    fifo_data[6:5], fifo_data[4:2], fifo_data[1:0]);
`endif
                // The inputs are mapped to SPDIF or I2S types.
                (* parallel_case, full_case *)
                case (fifo_data[7:6])
                    `OUTPUT_I2S: begin
                        io_en[IO_TYPE_I2S_BIT] <= 1'b1; io_en[IO_TYPE_SPDIF_BIT] <= 1'b0;
                    end

                    `OUTPUT_COAX: begin
                        io_en[IO_TYPE_I2S_BIT] <= 1'b0; io_en[IO_TYPE_SPDIF_BIT] <= 1'b1;
                        if (fifo_data[1:0] == `BIT_DEPTH_32 || fifo_data[1:0] == `BIT_DEPTH_DOP) begin
                            error_task (`ERROR_INVALID_SETUP_STREAM);
                        end
                    end

                    `OUTPUT_TOSLINK: begin
                        io_en[IO_TYPE_I2S_BIT] <= 1'b0; io_en[IO_TYPE_SPDIF_BIT] <= 1'b1;
                        if (fifo_data[1:0] == `BIT_DEPTH_32 || fifo_data[1:0] == `BIT_DEPTH_DOP) begin
                            error_task (`ERROR_INVALID_SETUP_STREAM);
                        end else if (fifo_data[4:2] == `STREAM_352800_HZ || fifo_data[4:2] == `STREAM_384000_HZ) begin
                            error_task (`ERROR_INVALID_SAMPLE_RATE);
                        end
                    end

                    `OUTPUT_AES3: begin
                        io_en[IO_TYPE_I2S_BIT] <= 1'b0; io_en[IO_TYPE_SPDIF_BIT] <= 1'b1;
                        if (fifo_data[1:0] == `BIT_DEPTH_32 || fifo_data[1:0] == `BIT_DEPTH_DOP) begin
                            error_task (`ERROR_INVALID_SETUP_STREAM);
                        end
                    end
                endcase

                sample_rate <= fifo_data[4:2];
                bit_depth <= fifo_data[1:0];
            end

            `CMD_HOST_STREAM_OUTPUT: begin
                if (~is_wr_output_FIFO_full) begin
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t---> [STATE_FIFO_PAYLOAD for CMD_HOST_STREAM_OUTPUT] Rd IN: %d. \033[0;0m",
                                    fifo_data);
`endif
                    wr_output_FIFO_data <= fifo_data;
                    wr_output_en <= 1'b1;
                end
            end

            `CMD_HOST_STOP: begin
                // Does not have a payload.
            end

            default: begin
                error_task (`ERROR_INVALID_PAYLOAD_CMD);
            end
        endcase
    endtask

    //==================================================================================================================
    // Playback complete task.
    //==================================================================================================================
    task stopped_task;
`ifdef D_CTRL
        $display ($time, "\033[0;36m CTRL:\t==== PLAYBACK STOPPED ====. \033[0;0m");
`endif
        wr_data_index <= 5'd0;
        wr_data[0] <= {`CMD_FPGA_STOPPED, 5'd1};
        wr_data[1] <= `ERROR_NONE;

        state_m <= STATE_WR_BUFFER;
        next_state_m <= STATE_RD;
    endtask

    //==================================================================================================================
    // The error handler.
    //==================================================================================================================
    task error_task (input logic [7:0] error);
`ifdef D_CTRL
        $display ($time, "\033[0;36m CTRL:\t==== ERROR [code: %d] ====. \033[0;0m", error);
`endif
        rd_in_fifo_en_o <= 1'b0;
        // Turn on the error LED
        led_ctrl_err_o <= 1'b1;

        wr_data_index <= 5'd0;
        wr_data[0] <= {`CMD_FPGA_STOPPED, 5'd1};
        wr_data[1] <= error;

        state_m <= STATE_WR_BUFFER;
        next_state_m <= STATE_IDLE;
    endtask

    //==================================================================================================================
    // The FIFO writter sends a small buffer to the host.
    //==================================================================================================================
    task write_buffer_task;
        if (wr_data[0][4:0] + 5'd1 == wr_data_index) begin
            wr_out_fifo_en_o <= 1'b0;
            state_m <= next_state_m;
        end else begin
            if (~wr_out_fifo_full_i && ~wr_out_fifo_afull_i) begin
`ifdef D_CTRL
                $display ($time, "\033[0;36m CTRL:\t<--- [STATE_WR_BUFFER] [%d]: %d. \033[0;0m",
                                wr_data_index, wr_data[wr_data_index]);
`endif
                wr_out_fifo_en_o <= 1'b1;
                wr_out_fifo_data_o <= wr_data[wr_data_index];

                wr_data_index <= wr_data_index + 5'd1;
            end else begin
                wr_out_fifo_en_o <= 1'b0;
            end
        end
    endtask

    //==================================================================================================================
    // The FIFO reader
    //==================================================================================================================
    task read_data_task (input logic [7:0] fifo_data);
        (* parallel_case, full_case *)
        case (fifo_state_m)
            STATE_FIFO_CMD: begin
                handle_cmd_task (fifo_data[7:5], fifo_data[4:0]);

                last_fifo_cmd <= fifo_data[7:5];
                if (fifo_data[4]) begin
                    fifo_state_m <= STATE_FIFO_PAYLOAD_LENGTH_1;
                end else if (fifo_data[3:0] > 4'd0) begin
                    rd_payload_bytes <= {12'b0, fifo_data[3:0]};
                    fifo_state_m <= STATE_FIFO_PAYLOAD;
                end
            end

            STATE_FIFO_PAYLOAD_LENGTH_1: begin
                rd_payload_bytes[15:8] <= fifo_data;
                fifo_state_m <= STATE_FIFO_PAYLOAD_LENGTH_2;
            end

            STATE_FIFO_PAYLOAD_LENGTH_2: begin
                rd_payload_bytes[7:0] <= fifo_data;
                fifo_state_m <= STATE_FIFO_PAYLOAD;
`ifdef D_CTRL
                $display ($time, "\033[0;36m CTRL:\t---> [STATE] Packet length [%d]: \033[0;0m",
                                {rd_payload_bytes[15:8], fifo_data});
`endif
            end

            STATE_FIFO_PAYLOAD: begin
                handle_payload_task (last_fifo_cmd, fifo_data);

                rd_payload_bytes <= rd_payload_bytes - 16'd1;
                if (rd_payload_bytes == 16'd1) begin
                    fifo_state_m <= STATE_FIFO_CMD;
                end
            end
        endcase
    endtask

    //==================================================================================================================
    // The app FIFO processor.
    //==================================================================================================================
    always @(posedge clk, posedge reset_i) begin
        if (reset_i) begin
`ifdef D_CTRL
            $display ($time, "\033[0;36m CTRL:\t-- Reset. \033[0;0m");
`endif
            rd_in_fifo_en_o <= 1'b0;
            wr_out_fifo_en_o <= 1'b0;

            io_en <= 2'b00;
            wr_output_en <= 1'b0;
            have_saved_rd_data <= 1'b0;

            state_m <= STATE_RD;
            fifo_state_m <= STATE_FIFO_CMD;
            led_ctrl_err_o <= 1'b0;
        end else begin
            wr_output_en <= 1'b0;

            (* parallel_case, full_case *)
            case (state_m)
                STATE_IDLE: begin
                    // Need to reset the device to make it operational again.
                    wr_out_fifo_en_o <= 1'b0;
                    if (~rd_in_fifo_empty_i) begin
                        // Read data and thow it away. If you don't do this FT_Write will block if there is an
                        // FPGA error.
                        rd_in_fifo_en_o <= 1'b1;
                    end else begin
                        rd_in_fifo_en_o <= 1'b0;
                    end
                end

                STATE_RD: begin
                    if (have_saved_rd_data) begin
                        if (~is_wr_output_FIFO_full) begin
`ifdef D_CTRL_FINE
                            $display ($time, "\033[0;36m CTRL:\t[STATE_RD] Wr saved: %d. \033[0;0m", saved_rd_data);
`endif
                            read_data_task (saved_rd_data);
                            have_saved_rd_data <= 1'b0;
                        end
                    end else if (~rd_in_fifo_empty_i) begin
                        if (~is_wr_output_FIFO_full) begin
                            if (rd_in_fifo_en_o) begin
                                rd_in_fifo_en_o <= 1'b0;
                                read_data_task (rd_in_fifo_data_i);
                            end else begin
                                // Read data out of the FIFO
                                rd_in_fifo_en_o <= 1'b1;
                            end
                        end else begin
                            if (rd_in_fifo_en_o) begin
                                // Save the value that was read so you can write it to output later.
                                saved_rd_data <= rd_in_fifo_data_i;
                                have_saved_rd_data <= 1'b1;
`ifdef D_CTRL_FINE
                                $display ($time, "\033[0;36m CTRL:\t[STATE_RD] Saved: %d. \033[0;0m",
                                        rd_in_fifo_data_i);
`endif
                                // Stop reading
                                rd_in_fifo_en_o <= 1'b0;
                            end
                        end
                    end else begin
                        // Stop reading
                        rd_in_fifo_en_o <= 1'b0;
                    end
                end

                STATE_WAIT_OUTPUT_TO_STOP: begin
                    if (~output_streaming) begin
                        io_en <= 2'b00;
                        stopped_task;
                    end
                end

                STATE_WR_BUFFER: begin
                    write_buffer_task;
                end
            endcase
        end
    end
endmodule
