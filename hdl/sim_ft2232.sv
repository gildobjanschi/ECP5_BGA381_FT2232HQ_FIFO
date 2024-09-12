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

module sim_ft2232 (
    input logic ft2232_reset_n_i,
    output logic fifo_clk_o,
    output logic fifo_txe_n_o,
    output logic fifo_rxf_n_o,
    input logic fifo_oe_n_i,
    input logic fifo_siwu_i,
    input logic fifo_wr_n_i,
    input logic fifo_rd_n_i,
    inout wire [7:0] fifo_data_io);

    // Simulate the clock
    localparam CLK_60000000_PS = 16666;
    logic fifo_clk = 1'b0;
    // Generate the FIFO clock
    always #(CLK_60000000_PS/2) fifo_clk = ~fifo_clk;
    assign fifo_clk_o = ft2232_reset_n_i ? fifo_clk : 1'b0;

    // Input/output 8-bit data bus
    logic [7:0] fifo_data_i, fifo_data_o;
    // .T = 0 -> fifo_data_io is output; .T = 1 -> fifo_data_io is input.
    TRELLIS_IO #(.DIR("BIDIR")) fifo_d_io[7:0] (.B(fifo_data_io), .T(fifo_oe_n_i), .O(fifo_data_i), .I(fifo_data_o));

    logic [5:0] out_payload_bytes;
    logic [7:0] out_packets;
    logic [7:0] out_data;

    logic [5:0] in_payload_bytes, total_in_payload_bytes;
    logic [1:0] in_last_cmd;

`ifndef DATA_PACKETS_COUNT
    `define DATA_PACKETS_COUNT 8'd1
`endif

`ifndef DATA_PACKET_PAYLOAD
    `define DATA_PACKET_PAYLOAD 6'd63
`endif

    localparam STATE_OUT_START          = 3'b000;
    localparam STATE_OUT_START_PAYLOAD  = 3'b001;
    localparam STATE_OUT_DATA           = 3'b010;
    localparam STATE_OUT_DATA_PAYLOAD   = 3'b011;
    localparam STATE_OUT_STOP           = 3'b100;
    localparam STATE_OUT_IDLE           = 3'b101;
    logic [2:0] out_state_m;

    localparam STATE_IN_CMD             = 2'b00;
    localparam STATE_IN_PAYLOAD         = 2'b01;
    logic [1:0] in_state_m;

`ifdef TEST_MODE
    //==================================================================================================================
    // The task that output the next byte
    //==================================================================================================================
    task output_data_task (input logic rd);
        case (out_state_m)
            STATE_OUT_START: begin
                if (rd) begin
`ifdef D_FT2232
                    $display ($time, "\033[0;35m FT2232:\t[STATE_OUT_START] %d. \033[0;0m", {`CMD_TEST_START, 6'd1});
`endif
                    fifo_data_o <= {`CMD_TEST_START, 6'd1};
                    out_state_m <= STATE_OUT_START_PAYLOAD;

                    out_packets <= `DATA_PACKETS_COUNT;
                    out_data <= 8'd0;
                end else begin
`ifdef D_FT2232
                    $display ($time, "\033[0;35m FT2232:\t[STATE_OUT_START] %d [rd=0]. \033[0;0m", 6'd55);
`endif
                end
            end

            STATE_OUT_START_PAYLOAD: begin
                if (rd) begin
`ifdef D_FT2232
                    $display ($time, "\033[0;35m FT2232:\t[STATE_OUT_START_PAYLOAD] %d. \033[0;0m", `TEST_NUMBER);
`endif
                    fifo_data_o <= `TEST_NUMBER;
                    out_state_m <= STATE_OUT_DATA;
                end
            end

            STATE_OUT_DATA: begin
                if (rd) begin
`ifdef D_FT2232
                    $display ($time, "\033[0;35m FT2232:\t[STATE_OUT_DATA] %d. \033[0;0m", {`CMD_TEST_DATA, `DATA_PACKET_PAYLOAD});
`endif
                    fifo_data_o <= {`CMD_TEST_DATA, `DATA_PACKET_PAYLOAD};
                    out_payload_bytes <= `DATA_PACKET_PAYLOAD;

                    out_state_m <= STATE_OUT_DATA_PAYLOAD;
                end
            end

            STATE_OUT_DATA_PAYLOAD: begin
                if (rd) begin
`ifdef D_FT2232
                    $display ($time, "\033[0;35m FT2232:\t[STATE_OUT_DATA_PAYLOAD] %d (remaining %d). \033[0;0m", out_data, out_payload_bytes - 1);
`endif
                    fifo_data_o <= out_data;
                    out_data <= out_data + 8'd1;

                    out_payload_bytes <= out_payload_bytes - 6'd1;
                    if (out_payload_bytes == 6'd1) begin
                        out_packets <= out_packets - 8'd1;
                        if (out_packets == 8'd1) begin
                            out_state_m <= STATE_OUT_STOP;
                        end else begin
`ifdef D_FT2232
                            $display ($time, "\033[0;35m FT2232:\t[STATE_OUT_DATA_PAYLOAD] (start new packet). \033[0;0m");
`endif
                            out_state_m <= STATE_OUT_DATA;
                        end
                    end
                end
            end

            STATE_OUT_STOP: begin
                if (rd) begin
`ifdef D_FT2232
                    $display ($time, "\033[0;35m FT2232:\t[STATE_OUT_STOP] %d. \033[0;0m", {`CMD_TEST_STOP, 6'd0});
`endif
                    fifo_data_o <= {`CMD_TEST_STOP, 6'd0};

                    out_state_m <= STATE_OUT_IDLE;
                end
            end

            STATE_OUT_IDLE: begin
                fifo_rxf_n_o <= 1'b1;
            end
        endcase

    endtask

    //==================================================================================================================
    // The task that reads the next byte
    //==================================================================================================================
    task input_data_task;
        case (in_state_m)
            STATE_IN_CMD: begin
                case (fifo_data_i[7:6])
                    `CMD_TEST_STOPPED: begin
                        fifo_rxf_n_o <= 1'b1;
`ifdef D_FT2232
                        $display ($time, "\033[0;35m FT2232:\t[STATE_IN_CMD] CMD_TEST_STOPPED [payload bytes: %d]. \033[0;0m", fifo_data_i[5:0]);
`endif
                        total_in_payload_bytes <= fifo_data_i[5:0];
                        in_payload_bytes <= fifo_data_i[5:0];
                        in_state_m <= STATE_IN_PAYLOAD;
                    end

                    `CMD_TEST_DATA: begin
`ifdef D_FT2232
                        $display ($time, "\033[0;35m FT2232:\t[STATE_IN_CMD] CMD_TEST_DATA [payload bytes: %d]. \033[0;0m", fifo_data_i[5:0]);
`endif
                        total_in_payload_bytes <= fifo_data_i[5:0];
                        in_payload_bytes <= fifo_data_i[5:0];
                        in_state_m <= STATE_IN_PAYLOAD;
                    end

                    default: begin
`ifdef D_FT2232
                        $display ($time, "\033[0;35m FT2232:\t[STATE_IN_CMD] Unknown command %d. \033[0;0m", fifo_data_i[7:6]);
`endif
                    end
                endcase

                in_last_cmd <= fifo_data_i[7:6];
            end

            STATE_IN_PAYLOAD: begin
                case (in_last_cmd)
                    `CMD_TEST_STOPPED: begin
                        case (total_in_payload_bytes - in_payload_bytes)
                            6'd0: begin
`ifdef D_FT2232
                                $display ($time, "\033[0;35m FT2232:\t[STATE_IN_PAYLOAD] CMD_TEST_STOPPED: Error code: %d. \033[0;0m", fifo_data_i);
                                if (fifo_data_i == `TEST_ERROR_NONE) begin
                                    $display ($time, "\033[0;35m FT2232:\t==== TEST OK ====. \033[0;0m");
                                end else begin
                                    $display ($time, "\033[0;35m FT2232:\t==== TEST FAILED [code: %d] ====. \033[0;0m", fifo_data_i);
                                end
`endif
                            end

                            6'd1: begin
`ifdef D_FT2232
                                $display ($time, "\033[0;35m FT2232:\t[STATE_IN_PAYLOAD] CMD_TEST_STOPPED: Value received: %d. \033[0;0m", fifo_data_i);
`endif
                            end

                            6'd2: begin
`ifdef D_FT2232
                                $display ($time, "\033[0;35m FT2232:\t[STATE_IN_PAYLOAD] CMD_TEST_STOPPED: Value expected: %d. \033[0;0m", fifo_data_i);
`endif
                            end
                        endcase
                    end

                    `CMD_TEST_DATA: begin
`ifdef D_FT2232
                        $display ($time, "\033[0;35m FT2232:\t[STATE_IN_PAYLOAD] CMD_TEST_DATA: %d. \033[0;0m", fifo_data_i);
`endif
                    end
                endcase

                in_payload_bytes <= in_payload_bytes - 6'd1;
                if (in_payload_bytes == 6'd1) begin
`ifdef D_FT2232
                    $display ($time, "\033[0;35m FT2232:\t[STATE_IN_PAYLOAD] -> STATE_IN_CMD. \033[0;0m");
`endif
                    in_state_m <= STATE_IN_CMD;
                end
            end
        endcase
    endtask
`else
    //==================================================================================================================
    // The task that output the next byte
    //==================================================================================================================
    task output_data_task (input logic rd);
    endtask

    //==================================================================================================================
    // The task that reads the next byte
    //==================================================================================================================
    task input_data_task;
    endtask
`endif
    //==================================================================================================================
    // The FT2232 simulation
    //==================================================================================================================
    always @(posedge fifo_clk_o, negedge ft2232_reset_n_i) begin
        if (~ft2232_reset_n_i) begin
            out_state_m <= STATE_OUT_START;
            in_state_m <= STATE_IN_CMD;

            out_data <= 8'd0;

            fifo_txe_n_o <= 1'b0;
            fifo_rxf_n_o <= 1'b0;

`ifdef D_FT2232
            $display ($time, "\033[0;35m FT2232:\t-- Reset. \033[0;0m");
`endif
        end else begin
            if (~fifo_rxf_n_o && ~fifo_oe_n_i) begin
                output_data_task (~fifo_rd_n_i);
            end else if (~fifo_txe_n_o && fifo_oe_n_i && ~fifo_wr_n_i) begin
                input_data_task;
            end
        end
    end
endmodule
