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
 * This module implements the tests for FT2232:
 * Test TEST_RECEIVE (0): Receive data from FT2232.
 * Test TEST_SEND_RECEIVE (1): Receive data from FT2232 and send it back to the host.
 * Test TEST_SEND (2): Send data to FT2232.
 **********************************************************************************************************************/
`timescale 1ps/1ps
`default_nettype none

`include "test_definitions.svh"

module control (
    input logic reset_i,
    input logic clk_24576000_i,
    input logic clk_22579200_i,
    // Input FIFO access
    output logic rd_in_fifo_clk_o,
    output logic rd_in_fifo_en_o,
    input logic [7:0] rd_in_fifo_data_i,
    input logic rd_in_fifo_empty_i,
    // Output FIFO ports
    output logic wr_out_fifo_clk_o,
    output logic wr_out_fifo_en_o,
    output logic [7:0] wr_out_fifo_data_o,
    input logic wr_out_fifo_full_i,
    input logic wr_out_fifo_afull_i,
    // LEDs
    output logic led_ctrl_err_o);

    logic clk;
    assign clk = clk_24576000_i;

    assign rd_in_fifo_clk_o = clk;
    assign wr_out_fifo_clk_o = clk;

    // State machines
    localparam STATE_IDLE       = 2'b00;
    localparam STATE_RD         = 2'b01;
    localparam STATE_WR_BUFFER  = 2'b10;
    localparam STATE_WR         = 2'b11;
    logic [1:0] state_m, next_state_m;

    // Protocol state machine
    localparam STATE_FIFO_CMD               = 2'b00;
    localparam STATE_FIFO_PAYLOAD_LENGTH_1  = 2'b01;
    localparam STATE_FIFO_PAYLOAD_LENGTH_2  = 2'b10;
    localparam STATE_FIFO_PAYLOAD           = 2'b11;
    logic [1:0] fifo_state_m;

    // Write state machines
    localparam STATE_WR_CMD                 = 2'd0;
    localparam STATE_WR_PAYLOAD_LENGTH_1    = 2'd1;
    localparam STATE_WR_PAYLOAD_LENGTH_2    = 2'd2;
    localparam STATE_WR_PAYLOAD             = 2'd3;
    logic [1:0] wr_state_m;

    logic [2:0] last_fifo_cmd;
    logic [4:0] wr_data_index;
    logic [7:0] wr_data[0:3];

    logic [7:0] test_number;
    logic [15:0] host_packet_count, host_packet_length;
    logic [15:0] wr_payload_bytes, rd_payload_bytes, rd_packets, wr_packets;
    logic [7:0] expected_test_data;

    //==================================================================================================================
    // The command handler
    //==================================================================================================================
    task handle_cmd_task (input logic [2:0] fifo_cmd, input logic [4:0] payload_length);
        (* parallel_case, full_case *)
        case (fifo_cmd)
            `CMD_HOST_START: begin
                led_ctrl_err_o <= 1'b0;
                rd_packets <= 16'd0;

                if (payload_length == 5'd5) begin
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t---> [STATE_FIFO_CMD] Rd IN: CMD_HOST_START. \033[0;0m");
`endif
                    // Reset the test data
                    expected_test_data <= 8'd0;
                end else begin
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t[ERROR] ---> [STATE_FIFO_CMD] Rd IN: CMD_HOST_START payload bytes: %d (expected 5). \033[0;0m",
                                        payload_length);
`endif
                    wr_data[0] <= {`CMD_FPGA_STOPPED, 5'd2};
                    wr_data[1] <= `TEST_ERROR_INVALID_START_PAYLOAD;
                    // Send back the payload received.
                    wr_data[2] <= {3'b00, payload_length};

                    test_fail_task;
                end
            end

            `CMD_HOST_DATA: begin
                if (payload_length == 5'b10000) begin
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t---> [STATE_FIFO_CMD] Rd IN: CMD_HOST_DATA. \033[0;0m");
`endif
                    rd_packets <= rd_packets + 16'd1;
                end else begin
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t[ERROR] ---> [STATE_FIFO_CMD] Rd IN: CMD_HOST_DATA payload bytes: %d (expected 5'b10000). \033[0;0m",
                                    payload_length);
`endif
                    wr_data[0] <= {`CMD_FPGA_STOPPED, 5'd2};
                    wr_data[1] <= `TEST_ERROR_INVALID_DATA_PAYLOAD;
                    // Send back what was received.
                    wr_data[2] <= {3'b00, payload_length};

                    test_fail_task;
                end
            end

            `CMD_HOST_STOP: begin
                if (payload_length == 5'd0) begin
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t---> [STATE_FIFO_CMD] Rd IN: CMD_HOST_STOP. \033[0;0m");
`endif
                    if (rd_packets == host_packet_count) begin
                        test_ok_task;
                    end else begin
`ifdef D_CTRL
                        $display ($time, "\033[0;36m CTRL:\t[ERROR] ---> [STATE_FIFO_CMD] Rd IN: CMD_HOST_STOP payload bytes: %d (expected 0). \033[0;0m",
                                    payload_length);
`endif
                        wr_data[0] <= {`CMD_FPGA_STOPPED, 5'd3};
                        wr_data[1] <= `TEST_ERROR_STOP_PACKETS_RECEIVED;
                        // Send back how many packets were received.
                        wr_data[2] <= rd_packets[15:8];
                        wr_data[3] <= rd_packets[7:0];

                        test_fail_task;
                    end
                end else begin
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t[ERROR] ---> [STATE_FIFO_CMD] Rd IN: CMD_HOST_STOP payload bytes: %d (expected 0). \033[0;0m",
                                    payload_length);
`endif
                    wr_data[0] <= {`CMD_FPGA_STOPPED, 5'd2};
                    wr_data[1] <= `TEST_ERROR_INVALID_STOP_PAYLOAD;
                    // Send back what you received.
                    wr_data[2] <= {3'b00, payload_length};

                    test_fail_task;
                end
            end

            default: begin
`ifdef D_CTRL
                $display ($time, "\033[0;36m CTRL:\t[ERROR] ---> [STATE_FIFO_CMD] Rd IN: invalid command: %d. \033[0;0m",
                                    fifo_cmd);
`endif
                wr_data[0] <= {`CMD_FPGA_STOPPED, 5'd1};
                wr_data[1] <= `TEST_ERROR_INVALID_CMD;

                test_fail_task;
            end
        endcase
    endtask

    //==================================================================================================================
    // The payload handler
    //==================================================================================================================
    task handle_payload_task (input logic [2:0] fifo_cmd, input logic [7:0] fifo_data);
        (* parallel_case, full_case *)
        case (fifo_cmd)
            `CMD_HOST_START: begin
                case (rd_payload_bytes)
                    16'd5: begin
`ifdef D_CTRL
                        $display ($time, "\033[0;36m CTRL:\t---> [STATE_FIFO_PAYLOAD for CMD_HOST_START] [Test number] Rd IN: %d. \033[0;0m",
                                            fifo_data);
`endif
                        test_number <= fifo_data;
                        case (fifo_data)
                            `TEST_RECEIVE, `TEST_RECEIVE_SEND, `TEST_SEND: begin
                            end

                            default: begin
                                wr_data[0] <= {`CMD_FPGA_STOPPED, 5'd2};
                                wr_data[1] <= `TEST_ERROR_INVALID_TEST_NUM;
                                wr_data[2] <= fifo_data;

                                test_fail_task;
                            end
                        endcase
                    end

                    16'd4: begin
                        host_packet_length[15:8] <= fifo_data;
                    end

                    16'd3: begin
                        host_packet_length[7:0] <= fifo_data;
`ifdef D_CTRL
                        $display ($time, "\033[0;36m CTRL:\t---> [STATE_FIFO_PAYLOAD for CMD_HOST_START] [Packet length] Rd IN: %d. \033[0;0m",
                                            {host_packet_length[15:8], fifo_data});
`endif
                    end

                    16'd2: begin
                        host_packet_count[15:8] <= fifo_data;
                    end

                    16'd1: begin
                        host_packet_count[7:0] <= fifo_data;
`ifdef D_CTRL
                        $display ($time, "\033[0;36m CTRL:\t---> [STATE_FIFO_PAYLOAD for CMD_HOST_START] [Packet count] Rd IN: %d. \033[0;0m",
                                            {host_packet_count[15:8], fifo_data});
`endif

                        if (test_number == `TEST_SEND) begin
                            wr_payload_bytes <= host_packet_length;
                            wr_packets <= { host_packet_count[15:8], fifo_data};
                            rd_in_fifo_en_o <= 1'b0;

                            wr_state_m <= STATE_WR_CMD;
                            state_m <= STATE_WR;
                        end
                    end
                endcase
            end

            `CMD_HOST_DATA: begin
                if (fifo_data == expected_test_data) begin
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t---> [STATE_FIFO_PAYLOAD for CMD_HOST_DATA] Rd IN: %d. \033[0;0m",
                                    fifo_data);
`endif
                    // For the loop back test write back the byte that was just received.
                    if (test_number == `TEST_RECEIVE_SEND) begin
                        // Write back the byte received
                        wr_data_index <= 5'd0;
                        wr_data[0] <= {`CMD_FPGA_DATA, 5'd1};
                        wr_data[1] <= fifo_data;

                        rd_in_fifo_en_o <= 1'b0;

                        state_m <= STATE_WR_BUFFER;
                        next_state_m <= STATE_RD;
                    end

                    expected_test_data <= expected_test_data + 8'd1;
                end else begin
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t[ERROR] ---> [STATE_FIFO_PAYLOAD for CMD_HOST_DATA] Rd IN: bad payload: %d (expected %d). \033[0;0m",
                                fifo_data, expected_test_data);
`endif
                    wr_data[0] <= {`CMD_FPGA_STOPPED, 5'd3};
                    wr_data[1] <= `TEST_ERROR_INVALID_TEST_DATA;
                    // Actually data received
                    wr_data[2] <= fifo_data;
                    // Expected data
                    wr_data[3] <= expected_test_data;

                    test_fail_task;
                end
            end

            `CMD_HOST_STOP: begin
                // Does not have a payload.
            end

            default: begin
`ifdef D_CTRL
                $display ($time, "\033[0;36m CTRL:\t[ERROR] ---> [STATE_FIFO_PAYLOAD] Rd IN: invalid command: %d. \033[0;0m",
                                fifo_cmd);
`endif
                wr_data[0] <= {`CMD_FPGA_STOPPED, 5'd1};
                wr_data[1] <= `TEST_ERROR_INVALID_LAST_CMD;

                test_fail_task;
            end
        endcase
    endtask

    //==================================================================================================================
    // The write data handler
    //==================================================================================================================
    task write_data_task;
        if (~wr_out_fifo_afull_i && ~wr_out_fifo_full_i) begin
            (* parallel_case, full_case *)
            case (wr_state_m)
                STATE_WR_CMD: begin
                    // The beginning of a packet
                    wr_out_fifo_en_o <= 1'b1;
                    wr_out_fifo_data_o <= {`CMD_FPGA_DATA, 5'b10000};
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t<--- [STATE_WR_CMD] Wr OUT: %d. \033[0;0m",
                                {`CMD_FPGA_DATA, host_packet_length});
`endif
                    wr_state_m <= STATE_WR_PAYLOAD_LENGTH_1;
                end

                STATE_WR_PAYLOAD_LENGTH_1: begin
                    wr_out_fifo_en_o <= 1'b1;
                    wr_out_fifo_data_o <= host_packet_length[15:8];
                    wr_state_m <= STATE_WR_PAYLOAD_LENGTH_2;
                end

                STATE_WR_PAYLOAD_LENGTH_2: begin
                    wr_out_fifo_en_o <= 1'b1;
                    wr_out_fifo_data_o <= host_packet_length[7:0];
                    wr_state_m <= STATE_WR_PAYLOAD;
                end

                STATE_WR_PAYLOAD: begin
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t<--- [STATE_WR_PAYLOAD] Wr OUT: %d. \033[0;0m",
                                    expected_test_data);
`endif
                    // Send data from the packet
                    wr_out_fifo_en_o <= 1'b1;
                    wr_out_fifo_data_o <= expected_test_data;

                    expected_test_data <= expected_test_data + 8'd1;

                    wr_payload_bytes <= wr_payload_bytes - 16'd1;
                    if (wr_payload_bytes == 16'd1) begin
                        wr_packets <= wr_packets - 16'd1;
                        if (wr_packets == 16'd1) begin
                            test_ok_task;
                        end else begin
`ifdef D_CTRL_FINE
                            $display ($time, "\033[0;36m CTRL:\t[STATE_WR_PAYLOAD] Packet sent. \033[0;0m");
`endif
                            wr_payload_bytes <= host_packet_length;
                            wr_state_m <= STATE_WR_CMD;
                        end
                    end
                end
            endcase
        end else begin
            wr_out_fifo_en_o <= 1'b0;
        end
  endtask

    //==================================================================================================================
    // The FIFO writter
    //==================================================================================================================
    task write_buffer_task;
        if (wr_data[0][4:0] + 5'd1 == wr_data_index) begin
            wr_out_fifo_en_o <= 1'b0;
            state_m <= next_state_m;
        end else begin
            if (~wr_out_fifo_full_i && ~wr_out_fifo_afull_i) begin
`ifdef D_CTRL
                $display ($time, "\033[0;36m CTRL:\t<--- [STATE_WR_BUFFER] Wr OUT [%d]: %d. \033[0;0m",
                                wr_data_index, wr_data[wr_data_index]);
`endif
                wr_out_fifo_en_o <= 1'b1;
                wr_out_fifo_data_o <= wr_data[wr_data_index];

                wr_data_index <= wr_data_index + 5'd1;
            end else begin
                wr_out_fifo_en_o <= 1'b0;
            end
        end
    endtask

    //==================================================================================================================
    // The test completed successfully
    //==================================================================================================================
    task test_ok_task;
        // Stop reading from the FIFO until we send the CMD_FPGA_STOPPED
        rd_in_fifo_en_o <= 1'b0;

`ifdef D_CTRL
        $display ($time, "\033[0;36m CTRL:\t==== TEST OK ====. \033[0;0m");
`endif
        wr_data_index <= 5'd0;
        wr_data[0] <= {`CMD_FPGA_STOPPED, 5'd1};
        wr_data[1] <= `TEST_ERROR_NONE;

        state_m <= STATE_WR_BUFFER;
        next_state_m <= STATE_RD;
    endtask

    //==================================================================================================================
    // The test fail
    //==================================================================================================================
    task test_fail_task;
        // Stop reading from the FIFO; there is an error.
        rd_in_fifo_en_o <= 1'b0;
        wr_data_index <= 5'd0;

`ifdef D_CTRL
        $display ($time, "\033[0;36m CTRL:\t==== TEST FAILED [code: %d] ====. \033[0;0m", wr_data[1]);
`endif
        led_ctrl_err_o <= 1'b1;

        state_m <= STATE_WR_BUFFER;
        next_state_m <= STATE_IDLE;
    endtask

    //==================================================================================================================
    // The FIFO reader
    //==================================================================================================================
    task read_data_task (input logic [7:0] fifo_data);
        (* parallel_case, full_case *)
        case (fifo_state_m)
            STATE_FIFO_CMD: begin
                handle_cmd_task (fifo_data[7:5], fifo_data[4:0]);

                last_fifo_cmd <= fifo_data[7:5];
                if (fifo_data[4]) begin
                    fifo_state_m <= STATE_FIFO_PAYLOAD_LENGTH_1;
                end else if (fifo_data[3:0] > 4'd0) begin
                    rd_payload_bytes <= {12'b0, fifo_data[3:0]};
                    fifo_state_m <= STATE_FIFO_PAYLOAD;
                end
            end

            STATE_FIFO_PAYLOAD_LENGTH_1: begin
                rd_payload_bytes[15:8] <= fifo_data;
                fifo_state_m <= STATE_FIFO_PAYLOAD_LENGTH_2;
            end

            STATE_FIFO_PAYLOAD_LENGTH_2: begin
                rd_payload_bytes[7:0] <= fifo_data;
                fifo_state_m <= STATE_FIFO_PAYLOAD;
`ifdef D_CTRL
                $display ($time, "\033[0;36m CTRL:\t---> [STATE] Packet length [%d]: \033[0;0m",
                                {rd_payload_bytes[15:8], fifo_data});
`endif
            end

            STATE_FIFO_PAYLOAD: begin
                handle_payload_task (last_fifo_cmd, fifo_data);

                rd_payload_bytes <= rd_payload_bytes - 16'd1;
                if (rd_payload_bytes == 16'd1) begin
                    fifo_state_m <= STATE_FIFO_CMD;
                end
            end
        endcase
    endtask


    //==================================================================================================================
    // FIFO read/write
    //==================================================================================================================
    always @(posedge clk, posedge reset_i) begin
        if (reset_i) begin
`ifdef D_CTRL
            $display ($time, "\033[0;36m CTRL:\t-- Reset. \033[0;0m");
`endif
            rd_in_fifo_en_o <= 1'b0;
            wr_out_fifo_en_o <= 1'b0;

            state_m <= STATE_RD;
            fifo_state_m <= STATE_FIFO_CMD;

            led_ctrl_err_o <= 1'b0;
        end else begin
            (* parallel_case, full_case *)
            case (state_m)
                STATE_IDLE: begin
                end

                STATE_RD: begin
                    if (~rd_in_fifo_empty_i) begin
                        if (rd_in_fifo_en_o) begin
                            rd_in_fifo_en_o <= 1'b0;
                            read_data_task (rd_in_fifo_data_i);
                        end else begin
                            // Read data out of the FIFO
                            rd_in_fifo_en_o <= 1'b1;
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
                    write_buffer_task (STATE_RD);
                end
            endcase
        end
    end
endmodule
