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
`define CMD_HOST_START          3'b000
`define CMD_HOST_DATA           3'b001
`define CMD_HOST_STOP           3'b010

// Commands from the FPGA to the host.
`define CMD_FPGA_DATA           3'b001
`define CMD_FPGA_LOOPBACK       3'b010
`define CMD_FPGA_STOPPED        3'b011

// CMD byte least significant bits if two bytes payload length follows after command byte.
`define PAYLOAD_LENGTH_FOLLOWS  5'b10000
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
`define TEST_ERROR_INVALID_DATA_PAYLOAD     8'd6
`define TEST_ERROR_INVALID_TEST_NUM         8'd7
`define TEST_ERROR_STOP_PACKETS_RECEIVED    8'd8
