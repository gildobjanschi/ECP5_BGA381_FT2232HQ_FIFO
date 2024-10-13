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
 * Bidirectional signal module (used only in SIMULATION mode).
 **********************************************************************************************************************/
module TRELLIS_IO((* iopad_external_pin *) inout B, input I, input T, output O);
    parameter DIR = "INPUT";
    reg T_pd;
    always @(*) if (T === 1'bz) T_pd <= 1'b0; else T_pd <= T;

    generate
        if (DIR == "INPUT") begin
            assign B = 1'bz;
            assign O = B;
        end else if (DIR == "OUTPUT") begin
            assign B = T_pd ? 1'bz : I;
            assign O = 1'bx;
        end else if (DIR == "BIDIR") begin
            assign B = T_pd ? 1'bz : I;
            assign O = B;
        end else begin
            ERROR_UNKNOWN_IO_MODE error();
        end
    endgenerate
endmodule
