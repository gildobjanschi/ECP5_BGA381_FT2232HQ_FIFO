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
`timescale 1ps/1ps
`default_nettype none

`include "definitions.svh"

module tx_spdif (
    input logic reset_i,
    input logic byte_clk_i,
    input logic bit_clk_i,
    // Streaming configuration
    input logic [2:0] sample_rate_i,
    input logic [1:0] bit_depth_i,
    // Output FIFO ports
    input logic wr_output_FIFO_clk_i,
    input logic wr_output_FIFO_en_i,
    input logic [7:0] wr_output_FIFO_data_i,
    output logic wr_output_FIFO_afull_o,
    output logic wr_output_FIFO_full_o,
    output logic output_streaming_o,
    // SPDIF output
    output logic spdif_o);

    //==================================================================================================================
    // The output FIFO containing audio data from the control module.
    //==================================================================================================================
    logic [7:0] rd_output_FIFO_data;
    logic rd_output_FIFO_en, rd_output_FIFO_empty;
    async_fifo #(.ASIZE(4))audio_FIFO_m (
        // Write to FIFO
        .wr_reset_i         (reset_i),
        .wr_en_i            (wr_output_FIFO_en_i),
        .wr_clk_i           (wr_output_FIFO_clk_i),
        .wr_data_i          (wr_output_FIFO_data_i),
        .wr_awfull_o        (wr_output_FIFO_afull_o),
        .wr_full_o          (wr_output_FIFO_full_o),
        // Read from FIFO
        .rd_reset_i         (reset_i),
        .rd_en_i            (rd_output_FIFO_en && ~pause_rd_FIFO),
        .rd_clk_i           (byte_clk_i),
        .rd_data_o          (rd_output_FIFO_data),
        .rd_empty_o         (rd_output_FIFO_empty));

    // Bit that indicates that this module is streaming audio.
    // The module using this signal will have to use a metastability FF to read this bit in a different clock domain.
    assign output_streaming_o = rd_output_FIFO_en;

`ifdef D_SPDIF
    time prev_time = 0;
    time time_now;
`endif

    logic bclk_en, pause_rd_FIFO, parity_r, parity_l;
    logic [1:0] sample_byte_index;
    logic [2:0] stream_stopping_clocks;

    // These variables are written on the byte_clk_i clock and read on the bit clock.
    // The byte_clk_i and bit clock are synchronized (bit clock is divided by 32 to obtain byte_clk_i).
    logic tx_reset;
    // 1'b0 left channel, 1'b1 right channel
    logic sample_sel;
    // Left and right channel samples are used as ping pong buffers with the TX 'always' block.
    logic [31:0] sample_l, sample_r;

    //==================================================================================================================
    // The reset task
    //==================================================================================================================
    task reset_task;
        tx_reset <= 1'b0;
        bclk_en <= 1'b0;
        rd_output_FIFO_en <= 1'b0;
        pause_rd_FIFO <= 1'b0;
        sample_sel <= 1'b0;
        sample_byte_index <= 2'd0;
        stream_stopping_clocks <= 3'd0;
    endtask

    //==================================================================================================================
    // The SPDIF processor
    //==================================================================================================================
    always @(posedge byte_clk_i, posedge reset_i) begin
        if (reset_i) begin
`ifdef D_SPDIF
            $display ($time, " SPDIF:\t-- Reset.");
`endif
            reset_task;
        end else if (|stream_stopping_clocks) begin
            stream_stopping_clocks <= stream_stopping_clocks - 3'd1;
            if (stream_stopping_clocks == 3'd1) begin
`ifdef D_SPDIF
                $display ($time, " SPDIF:\t----- Streaming stopped.");
`endif
                reset_task;
            end
        end else if (rd_output_FIFO_en) begin
            if (tx_reset) tx_reset <= 1'b0;

`ifdef D_SPDIF
            prev_time <= $time;
            if (~pause_rd_FIFO) begin
                time_now = $time;
                $display (time_now, " SPDIF:\tByte: %d | %0d Hz", rd_output_FIFO_data,
                                            1000000000000 / (time_now - prev_time));
            end
`endif

            case (bit_depth_i)
                `BIT_DEPTH_16: begin
                    case (sample_byte_index)
                        2'd0: begin
                            if (sample_sel) begin
                                sample_r[31:24] <= 8'h0;
                                sample_r[23:16] <= rd_output_FIFO_data;
                                parity_r <= ^rd_output_FIFO_data;
                            end else begin
                                sample_r[31:24] <= 8'h0;
                                sample_l[23:16] <= rd_output_FIFO_data;
                                parity_l <= ^rd_output_FIFO_data;
                            end

                            sample_byte_index <= 2'd1;
                        end

                        2'd1: begin
                            if (sample_sel) begin
                                sample_r[15:8] <= rd_output_FIFO_data;
                                sample_r[7:0] <= {1'b0, 1'b0, 1'b0, ^rd_output_FIFO_data ^ parity_r, 4'h0};
                            end else begin
                                sample_l[15:8] <= rd_output_FIFO_data;
                                sample_l[7:0] <= {1'b0, 1'b0, 1'b0, ^rd_output_FIFO_data ^ parity_l, 4'h0};
                            end

                            // Stop reading from the FIFO.
                            pause_rd_FIFO <= 1'b1;

                            sample_byte_index <= 2'd2;
                        end

                        2'd2: begin
                            sample_byte_index <= 2'd3;
                        end

                        2'd3: begin
`ifdef D_SPDIF
                            $display ($time, " SPDIF:\t16-bit sample: %h [%4b]",
                                            sample_sel ? sample_r[23:8] : sample_l[23:8],
                                            sample_sel ? sample_r[7:4] : sample_l[7:4]);
`endif
                            sample_byte_index <= 2'd0;
                            sample_sel <= ~sample_sel;

                            bclk_en <= 1'b1;

                            if (rd_output_FIFO_empty) begin
                                stream_stopping_clocks <= 3'd4;
                            end else begin
                                // Continue to read from the fifo.
                                pause_rd_FIFO <= 1'b0;
                            end
                        end
                    endcase
                end

                `BIT_DEPTH_24: begin
                    case (sample_byte_index)
                        2'd0: begin
                            if (sample_sel) begin
                                sample_r[31:24] <= rd_output_FIFO_data;
                                parity_r <= ^rd_output_FIFO_data;
                            end else begin
                                sample_l[31:24] <= rd_output_FIFO_data;
                                parity_l <= ^rd_output_FIFO_data;
                            end

                            sample_byte_index <= 2'd1;
                        end

                        2'd1: begin
                            if (sample_sel) begin
                                sample_r[23:16] <= rd_output_FIFO_data;
                                parity_r <= ^rd_output_FIFO_data ^ parity_r;
                            end else begin
                                sample_l[23:16] <= rd_output_FIFO_data;
                                parity_l <= ^rd_output_FIFO_data ^ parity_l;
                            end

                            sample_byte_index <= 2'd2;
                        end

                        2'd2: begin
                            if (sample_sel) begin
                                sample_r[15:8] <= rd_output_FIFO_data;
                                sample_r[7:0] <= {1'b0, 1'b0, 1'b0, ^rd_output_FIFO_data ^ parity_r, 4'h0};
                            end else begin
                                sample_l[15:8] <= rd_output_FIFO_data;
                                sample_l[7:0] <= {1'b0, 1'b0, 1'b0, ^rd_output_FIFO_data ^ parity_l, 4'h0};
                            end

                            // Stop reading from the FIFO.
                            pause_rd_FIFO <= 1'b1;

                            sample_byte_index <= 2'd3;
                        end

                        2'd3: begin
`ifdef D_SPDIF
                            $display ($time, " SPDIF:\t24-bit sample : %h [%4b]",
                                                sample_sel ? sample_r[31:8] : sample_l[31:8],
                                                sample_sel ? sample_r[7:4] : sample_l[7:4]);
`endif
                            sample_byte_index <= 2'd0;
                            sample_sel <= ~sample_sel;

                            bclk_en <= 1'b1;

                            if (rd_output_FIFO_empty) begin
                                stream_stopping_clocks <= 3'd4;
                            end else begin
                                // Continue to read from the fifo.
                                pause_rd_FIFO <= 1'b0;
                            end
                        end
                    endcase
                end

                `BIT_DEPTH_32, `BIT_DEPTH_DOP: begin
                    // Invalid cases
                end
            endcase
        end else if (~rd_output_FIFO_empty) begin
            tx_reset <= 1'b1;
            rd_output_FIFO_en <= 1'b1;
`ifdef D_SPDIF
            prev_time <= $time;
            $display ($time, " SPDIF:\t----- Streaming started.");
`endif
        end else begin
            // The FIFO is empty and not even one full sample was received.
            // This happens at the beginning of a stream.
        end
    end

    //==================================================================================================================
    // SPDIF encoder.
    //==================================================================================================================
`ifdef D_SPDIF
    time prev_time_bit = 0;
`endif
    logic prev_sample_sel, first_channel;
    logic [7:0] preamble;
    logic [31:0] tx_sample;
    logic [8:0] sub_frame_count;
    logic [5:0] clk_count;

    // Preambles
    localparam PREAMBLE_B_0 = 8'b00010111;
    localparam PREAMBLE_B_1 = 8'b11101000;

    localparam PREAMBLE_M_0 = 8'b00011101;
    localparam PREAMBLE_M_1 = 8'b11100010;

    localparam PREAMBLE_W_0 = 8'b00011011;
    localparam PREAMBLE_W_1 = 8'b11100100;

    // State machines
    localparam TX_SUB_FRAME_BEGIN   = 2'b00;
    localparam TX_PREAMBLE          = 2'b01;
    localparam TX_SAMPLE            = 2'b10;
    localparam TX_CONTROL           = 2'b11;
    logic [1:0] state_m;

    //==================================================================================================================
    // The TX reset task
    //==================================================================================================================
    task tx_reset_task;
`ifdef D_SPDIF
        $display ($time, " SPDIF:\t--TX reset.");
`endif
        prev_sample_sel <= 1'b0;
        sub_frame_count <= 9'd0;
        first_channel <= 1'b1;
        state_m <= TX_SUB_FRAME_BEGIN;
        spdif_o <= 1'b0;
    endtask

    //==================================================================================================================
    // SPDIF encoder processor.
    //==================================================================================================================
    always @(posedge bclk_i, posedge reset_i, posedge tx_reset) begin
        if (reset_i) begin
            tx_reset_task;
        end else if (tx_reset) begin
            tx_reset_task;
        end else if (bclk_en) begin
            (* parallel_case, full_case *)
            case (state_m)
                TX_SUB_FRAME_BEGIN: begin
                    prev_sample_sel <= sample_sel;
                    if (prev_sample_sel != sample_sel) begin
`ifdef D_SPDIF
                        prev_time_bit <= $time;
                        $display ($time,
                                " SPDIF:\tTX_SUB_FRAME_BEGIN: sub-frame: %h + ctrl: %h. PREAMBLE[7] bit: %0d | %0d Hz",
                                prev_sample_sel ? sample_r[31:8] : sample_l[31:8],
                                prev_sample_sel ? sample_r[7:4] : sample_l[7:4],
                                ~spdif_o,
                                1000000000000 / ($time - prev_time_bit));
`endif
                        // Prepare the preamble.
                        sub_frame_count <= sub_frame_count + 9'd1;

                        if (sub_frame_count == 9'd383) begin
                            // This is the beginning of a block of 192 frames (384 sub-frames).
                            sub_frame_count <= 9'd0;

                            if (first_channel) begin
                                preamble <= spdif_o ? PREAMBLE_B_0 : PREAMBLE_B_1;
                            end else begin
                                preamble <= spdif_o ? PREAMBLE_W_0 : PREAMBLE_W_1;
                            end

                            first_channel <= 1'b1;
                        end else begin
                            if (first_channel) begin
                                preamble <= spdif_o ? PREAMBLE_M_0 : PREAMBLE_M_1;
                            end else begin
                                preamble <= spdif_o ? PREAMBLE_W_0 : PREAMBLE_W_1;
                            end

                            first_channel <= ~first_channel;
                        end

                        // Store the 24-bit sample bits to send in a sub-frame.
                        tx_sample <= prev_sample_sel ? sample_r : sample_l;

                        // First bit of the preamble is always the negated previous bit.
                        spdif_o <= ~spdif_o;
                        // Send 4 bits of preamble in 8 clocks (first one was sent above).
                        clk_count <= 6'd6;
                        state_m <= TX_PREAMBLE;
                    end else begin
`ifdef D_SPDIF
                        prev_time_bit <= $time;
                        $display ($time, " SPDIF:\tTX_SUB_FRAME_BEGIN: Error -- no data --. | %0d Hz",
                                                    1000000000000 / ($time - prev_time_bit));
`endif
                    end
                end

                TX_PREAMBLE: begin
`ifdef D_SPDIF
                    prev_time_bit <= $time;
                    $display ($time, " SPDIF:\tPREAMBLE[%0d] bit: %h. | %0d Hz", clk_count, preamble[clk_count],
                                                1000000000000 / ($time - prev_time_bit));
`endif
                    spdif_o <= preamble[clk_count];
                    if (clk_count == 6'd0) begin
                        // Send 24 bits in 48 clocks.
                        clk_count <= 6'd47;
                        state_m <= TX_SAMPLE;
                    end else begin
                        clk_count <= clk_count - 6'd1;
                    end
                end

                TX_SAMPLE: begin
                    if (clk_count[0]) begin
                        spdif_o <= ~spdif_o;
`ifdef D_SPDIF
                        prev_time_bit <= $time;
                        $display ($time, " SPDIF:\tSAMPLE[%0d] bit: %h. | %0d Hz", clk_count>>1, tx_sample[clk_count>>1],
                                                    1000000000000 / ($time - prev_time_bit));
`endif
                    end else begin
                        spdif_o <= tx_sample[clk_count>>1] ? ~spdif_o : spdif_o;
                    end

                    if (clk_count == 6'd0) begin
                        // Send 4 bits in 8 clocks (starting at index 7).
                        clk_count <= 6'd15;
                        state_m <= TX_CONTROL;
                    end else begin
                        clk_count <= clk_count - 6'd1;
                    end
                end

                TX_CONTROL: begin
                    if (clk_count[0]) begin
                        spdif_o <= ~spdif_o;
`ifdef D_SPDIF
                        prev_time_bit <= $time;
                        $display ($time, " SPDIF:\tCONTROL[%0d] bit: %h. | %0d Hz", clk_count>>1 - 4,
                                                    tx_sample[clk_count>>1], 1000000000000 / ($time - prev_time_bit));
`endif
                    end else begin
                        spdif_o <= tx_sample[clk_count>>1] ? ~spdif_o : spdif_o;
                    end

                    if (clk_count == 6'd8) begin
                        state_m <= TX_SUB_FRAME_BEGIN;
                    end else begin
                        clk_count <= clk_count - 6'd1;
                    end
                end

            endcase
        end
    end

endmodule
