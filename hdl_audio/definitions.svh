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

// Commands from the host to the FPGA.
// Command byte bits[7:6]. Bits[5:0] represent the length of the frame.
`define CMD_HOST_SETUP_OUTPUT            2'b00
`define CMD_HOST_STREAM_OUTPUT           2'b10
`define CMD_HOST_STOP                    2'b11

// Commands from the FPGA to the host.
`define CMD_FPGA_STOPPED                 2'b11

// Error codes to the host
`define ERROR_NONE                          8'd0
`define ERROR_INVALID_SETUP_OUTPUT_PAYLOAD  8'd1
`define ERROR_INVALID_STOP_PAYLOAD          8'd2

// CMD_SETUP_OUTPUT or CMD_SETUP_INPUT payload byte[0] bits[6:5].
`define OUTPUT_A     2'b00
`define OUTPUT_B     2'b01
`define OUTPUT_C     2'b10
`define OUTPUT_D     2'b11

// CMD_SETUP_OUTPUT payload byte[0] bits[4:2]
`define STREAM_44100_HZ    3'b000
`define STREAM_88200_HZ    3'b001
`define STREAM_176400_HZ   3'b010
`define STREAM_352800_HZ   3'b011

`define STREAM_48000_HZ    3'b100
`define STREAM_96000_HZ    3'b101
`define STREAM_192000_HZ   3'b110
`define STREAM_384000_HZ   3'b111

// CMD_SETUP_OUTPUT payload byte[0] bits[1:0]
`define BIT_DEPTH_DOP       2'b00
`define BIT_DEPTH_16        2'b01
`define BIT_DEPTH_24        2'b10
`define BIT_DEPTH_32        2'b11
