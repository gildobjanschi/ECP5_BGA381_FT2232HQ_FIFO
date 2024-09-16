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

module tx_i2s (
    input wire reset_i,
    input wire byte_clk_i,
    input wire bit_clk_i,
    input wire mclk_i,
    // Streaming configuration
    input wire [2:0] sample_rate_i,
    input wire [1:0] bit_depth_i,
    // Output FIFO ports
    input wire wr_output_FIFO_clk_i,
    input wire wr_output_FIFO_en_i,
    input wire [7:0] wr_output_FIFO_data_i,
    output logic wr_output_FIFO_afull_o,
    output logic wr_output_FIFO_full_o,
    output logic rd_output_FIFO_streaming_o,
    // I2S outputs
    output logic sdata_o,
    output logic bclk_o,
    output logic lrck_o,
    output logic mclk_o);

    assign bclk_o = bclk_en ? bit_clk_i : 1'b1;
    assign mclk_o = bclk_en ? mclk_i : 1'b0;

    //==================================================================================================================
    // The output FIFO containing audio data.
    //==================================================================================================================
    logic [7:0] rd_output_FIFO_data;
    logic rd_output_FIFO_en, rd_output_FIFO_empty;
    async_fifo #(.ASIZE(4)) audio_FIFO_m (
        // Write to FIFO
        .wr_reset_i         (reset_i),
        .wr_en_i            (wr_output_FIFO_en_i),
        .wr_clk_i           (wr_output_FIFO_clk_i),
        .wr_data_i          (wr_output_FIFO_data_i),
        .wr_awfull_o        (wr_output_FIFO_afull_o),
        .wr_full_o          (wr_output_FIFO_full_o),
        // Read from FIFO
        .rd_reset_i         (reset_i),
        .rd_en_i            (rd_output_FIFO_en),
        .rd_clk_i           (byte_clk_i),
        .rd_data_o          (rd_output_FIFO_data),
        .rd_empty_o         (rd_output_FIFO_empty));

    // The module using this signal will have to use a metastability FF to read this bit in a different clock domain.
    assign rd_output_FIFO_streaming_o = rd_output_FIFO_en;

    logic bclk_en;
    logic [1:0] sample_byte_index;
    logic [2:0] stream_stopping_clocks;

    // These variables are written on the byte_clk_i clock and read on the bit clock.
    // The byte_clk_i and bit clock are synchronized (bit clock is divided by 8 to obtain
    // byte_clk_i).
    logic tx_reset;
    // 1'b0 left channel, 1'b1 right channel
    logic sample_sel;
    // Left and right channel samples are used as ping pong buffers with the TX always block.
    logic [31:0] sample_l, sample_r;

`ifdef D_I2S
    time prev_time = 0;
`endif

    //==================================================================================================================
    // The reset task
    //==================================================================================================================
    task reset_task;
        tx_reset <= 1'b0;
        bclk_en <= 1'b0;
        rd_output_FIFO_en <= 1'b0;
        // Start with the left channel
        sample_sel <= 1'b0;
        sample_byte_index <= 2'd0;
        stream_stopping_clocks <= 3'd0;
    endtask

    //==================================================================================================================
    // Audio sample receiver
    //==================================================================================================================
    always @(posedge byte_clk_i, posedge reset_i) begin
        if (reset_i) begin
`ifdef D_I2S
            $display ($time, " I2S:\t-- Reset.");
`endif
            reset_task;
        end else if (|stream_stopping_clocks) begin
            stream_stopping_clocks <= stream_stopping_clocks - 3'd1;
            if (stream_stopping_clocks == 3'd1) begin
`ifdef D_I2S
                $display ($time, " I2S:\t----- Streaming stopped.");
`endif
                reset_task;
            end
        end else if (rd_output_FIFO_en) begin
            if (tx_reset) tx_reset <= 1'b0;

            (* parallel_case, full_case *)
            case (bit_depth_i)
                `BIT_DEPTH_16: begin
                    case (sample_byte_index)
                        0: begin
                            if (sample_sel) sample_r[15:8] <= rd_output_FIFO_data;
                            else sample_l[15:8] <= rd_output_FIFO_data;

                            sample_byte_index <= 2'd1;
                        end

                        1: begin
                            if (sample_sel) sample_r[7:0] <= rd_output_FIFO_data;
                            else sample_l[7:0] <= rd_output_FIFO_data;

                            sample_byte_index <= 2'd0;
                            // Switch channels
                            sample_sel <= ~sample_sel;

                            bclk_en <= 1'b1;
`ifdef D_I2S_FRAME
                            $display ($time, " I2S:\t16-bit sample: %h | %0d Hz",
                                        {sample_sel ? sample_r[15:8] : sample_l[15:8], rd_output_FIFO_data},
                                        1000000000000 / ($time - prev_time));
`endif
                        end
                    endcase
                end

                `BIT_DEPTH_24, `BIT_DEPTH_DOP: begin
                    case (sample_byte_index)
                        0: begin
                            if (sample_sel) sample_r[23:16] <= rd_output_FIFO_data;
                            else sample_l[23:16] <= rd_output_FIFO_data;

                            sample_byte_index <= 2'd1;
                        end

                        1: begin
                            if (sample_sel) sample_r[15:8] <= rd_output_FIFO_data;
                            else sample_l[15:8] <= rd_output_FIFO_data;

                            sample_byte_index <= 2'd2;
                        end

                        2: begin
                            if (sample_sel) sample_r[7:0] <= rd_output_FIFO_data;
                            else sample_l[7:0] <= rd_output_FIFO_data;

                            sample_byte_index <= 2'd0;
                            sample_sel <= ~sample_sel;
                            bclk_en <= 1'b1;
`ifdef D_I2S_FRAME
                            $display ($time, " I2S:\t24-bit sample: %h | %0d Hz",
                                        {sample_sel ? sample_r[23:8] : sample_l[23:8], rd_output_FIFO_data},
                                        1000000000000 / ($time - prev_time));
`endif
                        end
                    endcase
                end


                `BIT_DEPTH_32: begin
                    case (sample_byte_index)
                        0: begin
                            if (sample_sel) sample_r[31:24] <= rd_output_FIFO_data;
                            else sample_l[31:24] <= rd_output_FIFO_data;

                            sample_byte_index <= 2'd1;
                        end

                        1: begin
                            if (sample_sel) sample_r[23:16] <= rd_output_FIFO_data;
                            else sample_l[23:16] <= rd_output_FIFO_data;

                            sample_byte_index <= 2'd2;
                        end

                        2: begin
                            if (sample_sel) sample_r[15:8] <= rd_output_FIFO_data;
                            else sample_l[15:8] <= rd_output_FIFO_data;

                            sample_byte_index <= 2'd3;
                        end

                        3: begin
                            if (sample_sel) sample_r[7:0] <= rd_output_FIFO_data;
                            else sample_l[7:0] <= rd_output_FIFO_data;

                            sample_byte_index <= 2'd0;
                            sample_sel <= ~sample_sel;
                            bclk_en <= 1'b1;
`ifdef D_I2S_FRAME
                            $display ($time, " I2S:\t32-bit sample: %h | %0d Hz",
                                        {sample_sel ? sample_r[31:8] : sample_l[31:8], rd_output_FIFO_data},
                                        1000000000000 / ($time - prev_time));
`endif
                        end
                    endcase
                end
            endcase

            if (rd_output_FIFO_empty) begin
                (* parallel_case, full_case *)
                case (bit_depth_i)
                    `BIT_DEPTH_16: stream_stopping_clocks <= 3'd2;
                    `BIT_DEPTH_24, `BIT_DEPTH_DOP: stream_stopping_clocks <= 3'd3;
                    `BIT_DEPTH_32: stream_stopping_clocks <= 3'd4;
                    default: stream_stopping_clocks <= 3'd1;
                endcase
            end

        end else if (~rd_output_FIFO_empty) begin
            tx_reset <= 1'b1;
            rd_output_FIFO_en <= 1'b1;
`ifdef D_I2S
            prev_time <= $time;
            $display ($time, " I2S:\t----- Streaming started.");
`endif
        end else begin
            // The FIFO is empty and not even one full sample was received.
            // This happens at the beginning of a stream.
        end
    end

`ifdef D_I2S_BC
    time prev_time_bit = 0;
`endif
    logic prev_sample_sel;
    logic [4:0] next_bit_to_send;
    logic [31:0] tx_sample;


    //==================================================================================================================
    // TX reset task
    //==================================================================================================================
    task tx_reset_task;
`ifdef D_I2S_BC
        //$display ($time, " I2C_BC:\tTX reset.");
`endif
        prev_sample_sel <= 1'b0;
        sdata_o <= 1'b1;
        // Make the lrck signal go low before the first bit.
        next_bit_to_send <= 5'd31;
    endtask

    //==================================================================================================================
    // Audio sample transmitter
    //==================================================================================================================
    always @(posedge bclk_o, posedge reset_i, posedge tx_reset) begin
        if (reset_i) begin
            tx_reset_task;
        end else if (tx_reset) begin
            tx_reset_task;
        end else begin
            prev_sample_sel <= sample_sel;
            if (prev_sample_sel != sample_sel) begin
                tx_sample <= prev_sample_sel ? sample_r : sample_l;

                (* parallel_case, full_case *)
                case (bit_depth_i)
                    `BIT_DEPTH_16: begin
`ifdef D_I2S_BC
                        prev_time_bit <= $time;
                        $display ($time, " I2S_BC:\t16-bit sample: %h. Sending bit: 15 | %0d Hz",
                                                    prev_sample_sel ? sample_r[15:0] : sample_l[15:0],
                                                    1000000000000 / ($time - prev_time_bit));
`endif
                        sdata_o <= prev_sample_sel ? sample_r[5'd15] : sample_l[5'd15];
                        next_bit_to_send <= 5'd14;
                    end

                    `BIT_DEPTH_24, `BIT_DEPTH_DOP: begin
`ifdef D_I2S_BC
                        prev_time_bit <= $time;
                        $display ($time, " I2S_BC:\t24-bit sample: %h. Sending bit: 23 | %0d Hz",
                                                    prev_sample_sel ? sample_r[23:0] : sample_l[23:0],
                                                    1000000000000 / ($time - prev_time_bit));
`endif
                        sdata_o <= prev_sample_sel ? sample_r[5'd23] : sample_l[5'd23];

                        next_bit_to_send <= 5'd22;
                    end

                    `BIT_DEPTH_32: begin
`ifdef D_I2S_BC
                        prev_time_bit <= $time;
                        $display ($time, " I2S_BC:\t32-bit sample: %h. Sending bit: 31 | %0d Hz",
                                                    prev_sample_sel ? sample_r : sample_l,
                                                    1000000000000 / ($time - prev_time_bit));
`endif
                        sdata_o <= prev_sample_sel ? sample_r[5'd31] : sample_l[5'd31];

                        next_bit_to_send <= 5'd30;
                    end
                endcase
            end else begin
`ifdef D_I2S_BC
                prev_time_bit <= $time;
                $display ($time, " I2S_BC:\tSending bit: %0d | %0d Hz", next_bit_to_send,
                                            1000000000000 / ($time - prev_time_bit));
`endif
                sdata_o <= tx_sample[next_bit_to_send];
                // After bit 0 is sent next_bit_to_send == 5'd31. See below the generation of lrck_o.
                next_bit_to_send <= next_bit_to_send - 5'd1;
            end
        end
    end

    //==================================================================================================================
    // Generate the left/right clock.
    //==================================================================================================================
    always @(negedge bclk_o, posedge reset_i, posedge tx_reset) begin
        if (reset_i) begin
            lrck_o <= 1'b1;
        end else if (tx_reset) begin
            lrck_o <= 1'b1;
        end else if (next_bit_to_send == 5'd31) begin
`ifdef D_I2S_BC
            $display ($time, " I2S_BC:\tlrck %h.", ~lrck_o);
`endif
            lrck_o <= ~lrck_o;
        end
    end
endmodule
