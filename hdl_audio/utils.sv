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

//======================================================================================================================
// Metastability flip-flop
//======================================================================================================================
module DFF_META (input logic reset, input logic D, input logic clk, output logic Q);
    logic Q_pipe = 1'b0;
    always @(posedge clk) begin
        if (reset) begin
            Q <= 1'b0;
            Q_pipe <= 1'b0;
        end else begin
            Q_pipe <= D;
            Q <= Q_pipe;
        end
    end
endmodule

//======================================================================================================================
// LED illumination amplification for fast signals that do not yield enough LED lighting.
//======================================================================================================================
module led_illum (input logic reset_i, input logic clk_i, input logic signal_i, output logic led_o);
    logic [3:0] sample;
    always @(posedge clk_i) begin
        if (reset_i) begin
            led_o <= 1'b0;
            sample <= 4'h0;
        end else begin
            if (signal_i) begin
                sample <= 4'b1000;
                led_o <= 1'b1;
            end else begin
                if (sample == 4'h0) begin
                    led_o <= 1'b0;
                end else begin
                    sample <= sample >> 1;
                end
            end
        end
    end
endmodule
