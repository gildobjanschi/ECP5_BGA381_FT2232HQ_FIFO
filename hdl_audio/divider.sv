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
 * This module implements the clock divider for 24.576MHz and 22.5972MHz down to 48KHz, 96KHz, 192KHz, 384KHz and
 * 44.1KHz, 88.2KHz, 176.4KHz and 352.8KHz respectively.
 **********************************************************************************************************************/
`timescale 1ps/1ps
`default_nettype none

//==================================================================================================================
// Devide a clock by 2.
//==================================================================================================================
module divide_by_2(input wire reset_i, input wire clk_i, output logic clk_o);
    always @(posedge clk_i, posedge reset_i) begin
        if (reset_i) clk_o <= 1'b0;
        else clk_o <= ~clk_o;
    end
endmodule

//==================================================================================================================
// Divide by 8 the input clock
//==================================================================================================================
module divide_by_8(input wire reset_i, input wire clk_i, output logic clk_o);
    logic clk_out_1, clk_out_2;

    divide_by_2 divide_by_2_1_m (.reset_i(reset_i), .clk_i(clk_i), .clk_o(clk_out_1));
    divide_by_2 divide_by_2_2_m (.reset_i(reset_i), .clk_i(clk_out_1), .clk_o(clk_out_2));
    divide_by_2 divide_by_2_3_m (.reset_i(reset_i), .clk_i(clk_out_2), .clk_o(clk_o));
endmodule

//==================================================================================================================
// Divide by 16 the input clock
//==================================================================================================================
module divide_by_16(input wire reset_i, input wire clk_i, output logic clk_o);
    logic clk_out_1, clk_out_2, clk_out_3;

    divide_by_2 divide_by_2_1_m (.reset_i(reset_i), .clk_i(clk_i), .clk_o(clk_out_1));
    divide_by_2 divide_by_2_2_m (.reset_i(reset_i), .clk_i(clk_out_1), .clk_o(clk_out_2));
    divide_by_2 divide_by_2_3_m (.reset_i(reset_i), .clk_i(clk_out_2), .clk_o(clk_out_3));
    divide_by_2 divide_by_2_4_m (.reset_i(reset_i), .clk_i(clk_out_3), .clk_o(clk_o));
endmodule
