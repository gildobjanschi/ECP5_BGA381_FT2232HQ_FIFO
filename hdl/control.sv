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
    output logic spdif_o,
    output logic i2s_sdata_o,
    output logic i2s_bclk_o,
    output logic i2s_lrck_o,
    output logic i2s_mclk_o,
    output logic led_app_ctrl_err_o);

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
    48000   1536000	    2304000	    3072000	    12288000
    96000   3072000	    4608000	    6144000	    24576000
    192000  6144000	    9216000	    12288000	49152000
    384000  12288000	18432000	24576000	98304000

    44100   1411200	    2116800	    2822400	    11289600
    88200   2822400	    4233600	    5644800	    22579200
    176400  5644800	    8467200	    11289600	45158400
    352800  11289600	16934400	22579200	90316800
    ==================================================================================================================*/

    // 32 bit @24.576000 MHz
    logic [3:0] clk_24576000_32;
    // 384 KHz 32 bit: 24576000 Hz
    assign clk_24576000_32[3] = clk_24576000_i;
    // 192 KHz 32 bit: 12288000 Hz
    divide_by_2 divide_by_2_1_m (reset_i, clk_24576000_32[3], clk_24576000_32[2]);
    // 96 KHz 32 bit: 6144000 Hz
    divide_by_2 divide_by_2_2_m (reset_i, clk_24576000_32[2], clk_24576000_32[1]);
    // 48 KHz 32 bit: 3072000
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
    // 48 KHZ MCLK: 12288000 hz
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
    // 44.1 KHz MCLK: 11289600 hz
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
    assign i2s_mclk = io_en[IO_TYPE_I2S_BIT] ? (sample_rate[2] ? clk_24576000_mclk[sample_rate[1:0]] :
                                                                clk_22579200_mclk[sample_rate[1:0]]) : 1'b0;

    logic i2s_rd_output_FIFO_clk;
    // From the FIFO we read 8 bits at the bit clock divided by 8.
    divide_by_8 divide_by_8_m (.reset_i(reset_i), .clk_i(i2s_bit_clk), .clk_o(i2s_rd_output_FIFO_clk));

    /*==================================================================================================================
    SPDIF bit clock rates
    --------------------------------------------------------------------------------------------------------------------
    SR      16/24-bit (32x bit data) 2x channels, 2x bi-phase encoding. bit rate = sample rate x 128.
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
    assign spdif_bit_clk = io_en[IO_TYPE_SPDIF_BIT]? (sample_rate[2] ? clk_24576000_spdif[sample_rate[1:0]] :
                                                            clk_22579200_spdif[sample_rate[1:0]]) : 1'b0;

    logic spdif_rd_output_FIFO_clk;
    // From the FIFO we read 8 bits at the bit clock divided by 8.
    divide_by_16 divide_by_16_m (.reset_i(reset_i), .clk_i(spdif_bit_clk), .clk_o(spdif_rd_output_FIFO_clk));
    /*================================================================================================================*/
    logic clk;
    // For this module use a frequency that is higher than any byte_clk. For I2S the maximum byte_clk is 24576000/8.
    // For SPDIF the maximum byte_clk is 24576000/8. 24.576MHz clk fits the bill.
    assign clk = clk_24576000_i;

    // State machines
    localparam STATE_IDLE       = 2'b00;
    localparam STATE_RD         = 2'b01;
    localparam STATE_WR_BUFFER  = 2'b10;
    localparam STATE_WR         = 2'b11;
    logic [1:0] state_m, next_state_m;

    // Protocol state machine
    localparam STATE_FIFO_CMD       = 1'b0;
    localparam STATE_FIFO_PAYLOAD   = 1'b1;
    logic fifo_state_m;

    logic [1:0] last_fifo_cmd;
    logic [5:0] rd_payload_bytes;
    logic [5:0] wr_data_index;
    logic [7:0] wr_data[0:1];

    // Audio configuration
    // The io_en index of the bit indicating what type of input/output is enabled.
    localparam IO_TYPE_SPDIF_BIT    = 0;
    localparam IO_TYPE_I2S_BIT      = 1;

    logic [1:0] io_en;
    logic [1:0] wr_output_FIFO_full;

    logic wr_output_en;
    assign wr_output_FIFO_full = {wr_output_FIFO_afull_i2s || wr_output_FIFO_full_i2s,      // IO_TYPE_I2S_BIT index
                                    wr_output_FIFO_afull_spdif || wr_output_FIFO_full_spdif}; // IO_TYPE_SPDIF_BIT index

    logic channels;
    logic [2:0] sample_rate;
    logic [1:0] bit_depth;

    //==================================================================================================================
    // The SPDIF module
    //==================================================================================================================
    logic [7:0] wr_output_FIFO_data;
    logic wr_output_FIFO_full_spdif, wr_output_FIFO_afull_spdif, rd_output_FIFO_streaming_spdif;
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
        .rd_output_FIFO_streaming_o (rd_output_FIFO_streaming_spdif),
        // SPDIF output
        .spdif_o                (spdif_o));

    //==================================================================================================================
    // The I2S module
    //==================================================================================================================
    logic wr_output_FIFO_full_i2s, wr_output_FIFO_afull_i2s, rd_output_FIFO_streaming_i2s;
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
        .rd_output_FIFO_streaming_o (rd_output_FIFO_streaming_i2s),
        // I2S outputs
        .sdata_o                (i2s_sdata_o),
        .bclk_o                 (i2s_bclk_o),
        .lrck_o                 (i2s_lrck_o),
        .mclk_o                 (i2s_mclk_o));

    //==================================================================================================================
    // The command handler
    //==================================================================================================================
    task handle_cmd_task (input logic [1:0] fifo_cmd, input logic [5:0] payload_length);
        (* parallel_case, full_case *)
        case (fifo_cmd)
            `CMD_SETUP_OUTPUT: begin
                if (payload_length == 6'd1) begin
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t---> [STATE_FIFO_CMD] Rd IN: CMD_SETUP_OUTPUT. \033[0;0m");
`endif
                    // Reset the output
                end else begin
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t[ERROR] ---> [STATE_FIFO_CMD] Rd IN: CMD_SETUP_OUTPUT payload bytes: %d (expected 1). \033[0;0m",
                                        payload_length);
`endif
                    error_task (`ERROR_INVALID_SETUP_OUTPUT_PAYLOAD);

                    rd_in_fifo_en_o <= 1'b0;
                end
            end

            `CMD_SETUP_INPUT: begin
                // Not supported yet
            end

            `CMD_STREAM_OUTPUT: begin
`ifdef D_CTRL
                $display ($time, "\033[0;36m CTRL:\t---> [STATE_FIFO_CMD] Rd IN: CMD_STREAM_OUTPUT (%d payload bytes). \033[0;0m",
                                        payload_length);
`endif
            end

            `CMD_STOP: begin
                if (payload_length == 6'd0) begin
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t---> [STATE_FIFO_CMD] Rd IN: CMD_STOPPED. \033[0;0m");
`endif
                    stopped_task;
                end else begin
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t[ERROR] ---> [STATE_FIFO_CMD] Rd IN: CMD_STOPPED payload bytes: %d (expected 0). \033[0;0m",
                                        payload_length);
`endif
                    error_task (`ERROR_INVALID_STOP_PAYLOAD);
                end

                rd_in_fifo_en_o <= 1'b0;
            end
        endcase
    endtask

    //==================================================================================================================
    // The payload handler
    //==================================================================================================================
    task handle_payload_task (input logic [1:0] fifo_cmd, input logic [7:0] fifo_data);
        (* parallel_case, full_case *)
        case (fifo_cmd)
            `CMD_SETUP_OUTPUT: begin
`ifdef D_CTRL
                $display ($time, "\033[0;36m CTRL:\t---> [STATE_FIFO_PAYLOAD for CMD_SETUP_OUTPUT] Rd IN: Channels: %1b, type: %2b; sample rate: %3b; bit depth: %2b. \033[0;0m",
                                    fifo_data[7], fifo_data[6:5], fifo_data[4:2], fifo_data[1:0]);
`endif
                // For now the IO_TYPEs are mapped to SPDIF or I2S. The code can use the IO_TYPEs for additional
                // meanings for example: physical output, special handling in SPDIF for AES3.
                (* parallel_case, full_case *)
                case (fifo_data[7:6])
                    `IO_TYPE_AES3: io_en <= 2'b01; // IO_TYPE_SPDIF_BIT set
                    `IO_TYPE_BNC: io_en <= 2'b01; // IO_TYPE_SPDIF_BIT set
                    `IO_TYPE_TOSLINK: io_en <= 2'b01; // IO_TYPE_SPDIF_BIT set
                    `IO_TYPE_I2S: io_en <= 2'b10; // IO_TYPE_I2S_BIT set
                endcase

                channels <= fifo_data[5];
                sample_rate <= fifo_data[4:2];
                bit_depth <= fifo_data[1:0];
            end

            `CMD_SETUP_INPUT: begin
                // Not supported yet
            end

            `CMD_STREAM_OUTPUT: begin
`ifdef D_CTRL
                $display ($time, "\033[0;36m CTRL:\t---> [STATE_FIFO_PAYLOAD for CMD_STREAM_OUTPUT] Rd IN: %d. \033[0;0m",
                                    fifo_data);
`endif
                if (~wr_output_FIFO_full) begin
                    wr_output_FIFO_data <= fifo_data;
                    wr_output_en <= 1'b1;
                end
            end

            `CMD_STOP: begin
                // Does not have a payload.
            end
        endcase
    endtask

    //==================================================================================================================
    // The write to the OUT FIFO (to FT2232) data handler. Use it for host audio input.
    //==================================================================================================================
    task write_data_task;
        // Not supported yet.
    endtask

    //==================================================================================================================
    // Playback complete task.
    //==================================================================================================================
    task stopped_task;
`ifdef D_CTRL
        $display ($time, "\033[0;36m CTRL:\t==== PLAYBACK STOPPED ====. \033[0;0m");
`endif
        wr_data_index <= 6'd0;
        wr_data[0] <= {`CMD_STOPPED, 6'h1};
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
        led_app_ctrl_err_o <= 1'b1;

        wr_data_index <= 6'd0;
        wr_data[0] <= {`CMD_STOPPED, 6'h1};
        wr_data[1] <= error;

        state_m <= STATE_WR_BUFFER;
        next_state_m <= STATE_IDLE;
    endtask

    //==================================================================================================================
    // The FIFO writter sends a small buffer to the host.
    //==================================================================================================================
    task write_buffer_task;
        if (wr_data[0][5:0] + 6'd1 == wr_data_index) begin
`ifdef D_CTRL_FINE
            $display ($time, "\033[0;36m CTRL:\t[STATE_WR_BUFFER] Done. \033[0;0m");
`endif
            wr_out_fifo_en_o <= 1'b0;
            state_m <= STATE_RD;
        end else begin
            if (~wr_out_fifo_full_i && ~wr_out_fifo_afull_i) begin
`ifdef D_CTRL
                $display ($time, "\033[0;36m CTRL:\t<--- [STATE_WR_BUFFER] [%d]: %d. \033[0;0m",
                                wr_data_index, wr_data[wr_data_index]);
`endif
                wr_out_fifo_en_o <= 1'b1;
                wr_out_fifo_data_o <= wr_data[wr_data_index];

                wr_data_index <= wr_data_index + 6'd1;
            end else begin
                wr_out_fifo_en_o <= 1'b0;
            end
        end
    endtask

    //==================================================================================================================
    // The FIFO reader gets the data from the F2232.
    //==================================================================================================================
    task read_data_task (input logic [7:0] fifo_data);
        (* parallel_case, full_case *)
        case (fifo_state_m)
            STATE_FIFO_CMD: begin
                handle_cmd_task (fifo_data[7:6], fifo_data[5:0]);

                if (fifo_data[5:0] > 6'd0) begin
                    rd_payload_bytes <= fifo_data[5:0];
                    last_fifo_cmd <= fifo_data[7:6];
                    fifo_state_m <= STATE_FIFO_PAYLOAD;
                end
            end

            STATE_FIFO_PAYLOAD: begin
                handle_payload_task (last_fifo_cmd, fifo_data);

                rd_payload_bytes <= rd_payload_bytes - 2'd1;

                if (rd_payload_bytes == 2'd1) begin
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

            state_m <= STATE_RD;
            fifo_state_m <= STATE_FIFO_CMD;
            led_app_ctrl_err_o <= 1'b0;
        end else begin
            wr_output_en <= 1'b0;

            (* parallel_case, full_case *)
            case (state_m)
                STATE_IDLE: begin
                    // Ned to reset the device to make the device operational.
                    wr_out_fifo_en_o <= 1'b0;
                    rd_in_fifo_en_o <= 1'b0;
                end

                STATE_RD: begin
                    if (~rd_in_fifo_empty_i) begin
                        // Read data out of the FIFO
                        rd_in_fifo_en_o <= 1'b1;
                        if (rd_in_fifo_en_o) begin
                            read_data_task (rd_in_fifo_data_i);
                        end
                    end else begin
                        // Stop reading
                        rd_in_fifo_en_o <= 1'b0;
                    end
                end

                STATE_WR: begin
                    write_data_task;
                end

                STATE_WR_BUFFER: begin
                    write_buffer_task;
                end
            endcase
        end
    end
endmodule
