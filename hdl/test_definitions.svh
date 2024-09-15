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

// Command from the host to the FPGA.
`define CMD_TEST_START          2'b00
// Command for both directions.
`define CMD_TEST_DATA           2'b01
// Command from the FPGA to the host.
`define CMD_TEST_STOP           2'b10
// Command from the FPGA to the host to respond to CMD_TEST_STOP.
`define CMD_TEST_STOPPED        2'b11

// Test number definitions.
`define TEST_RECEIVE            8'd0
`define TEST_RECEIVE_SEND       8'd1
`define TEST_SEND               8'd2

// Error codes from the FPGA to the host.
`define TEST_ERROR_NONE                     8'd0
`define TEST_ERROR_INVALID_START_PAYLOAD    8'd1
`define TEST_ERROR_INVALID_STOP_PAYLOAD     8'd2
`define TEST_ERROR_INVALID_CMD              8'd3
`define TEST_ERROR_INVALID_LAST_CMD         8'd4
`define TEST_ERROR_INVALID_TEST_DATA        8'd5
`define TEST_ERROR_INVALID_TEST_NUM         8'd6
