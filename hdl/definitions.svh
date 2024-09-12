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

`ifdef TEST_MODE
// Commands from the host to the FPGA.
`define CMD_TEST_START          2'b00
`define CMD_TEST_DATA           2'b01
`define CMD_TEST_STOP           2'b10
// Commands from the FPGA to the host.
`define CMD_TEST_STOPPED        2'b11

`define TEST_RECEIVE            8'd0
`define TEST_RECEIVE_SEND       8'd1
`define TEST_SEND               8'd2

`define TEST_ERROR_NONE                     8'd0
`define TEST_ERROR_INVALID_START_PAYLOAD    8'd1
`define TEST_ERROR_INVALID_STOP_PAYLOAD     8'd2
`define TEST_ERROR_INVALID_CMD              8'd3
`define TEST_ERROR_INVALID_LAST_CMD         8'd4
`define TEST_ERROR_INVALID_TEST_DATA        8'd5
`define TEST_ERROR_INVALID_TEST_NUM         8'd6

`else // TEST_MODE

// Command byte bits[7:6]. Bits[5:0] represent the length of the frame.
`define CMD_SETUP_OUTPUT    2'b00
`define CMD_SETUP_INPUT     2'b00
`define CMD_STREAM          2'b01
`define CMD_SPDIF_CONTROL   2'b10

// CMD_SETUP_OUTPUT or CMD_SETUP_INPUT payload byte[0] bits[7:6]
`define IO_AES3             2'b00
`define IO_BNC              2'b01
`define IO_TOSLINK          2'b10
`define IO_I2S              2'b11

// CMD_SETUP_OUTPUT payload byte[0] bits[5:2]
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
`endif // TEST_MODE
