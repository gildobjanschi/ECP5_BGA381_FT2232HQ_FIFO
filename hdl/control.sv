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

module control (
    input logic reset_i,
    input logic clk_24576000_i,
    input logic clk_22579200_i,
    // Input FIFO access
    output logic rd_in_fifo_clk_o,
    output logic rd_in_fifo_en_o,
    input logic rd_in_fifo_empty_i,
    input logic [7:0] rd_in_fifo_data_i,
    // Output FIFO ports
    output logic wr_out_fifo_clk_o,
    output logic wr_out_fifo_en_o,
    output logic [7:0] wr_out_fifo_data_o,
    input logic wr_out_fifo_full_i,
    input logic wr_out_fifo_afull_i,
    output logic led_test_mode
`ifdef EXT_ENABLED
    ,
    output logic ext_led_app_ctrl_err_o,
    output logic ext_led_test_ok,
    output logic ext_led_test_fail
`endif
    );

    logic clk;
    assign clk = clk_24576000_i;

    assign rd_in_fifo_clk_o = clk;
    assign wr_out_fifo_clk_o = clk;

    // State machines
    localparam STATE_IDLE       = 3'b000;
    localparam STATE_RD         = 3'b001;
    localparam STATE_WR_BUFFER  = 3'b010;
    localparam STATE_WR         = 3'b011;
    localparam STATE_ERROR      = 3'b111;
    logic [2:0] state_m;

    // Protocol state machine
    localparam STATE_FIFO_CMD       = 1'b0;
    localparam STATE_FIFO_PAYLOAD   = 1'b1;
    logic fifo_state_m;

    logic [1:0] last_fifo_cmd;
    logic data_to_send;
    logic [5:0] rd_payload_bytes;
    logic [5:0] wr_data_index;
    logic [7:0] wr_data[0:3];

    //==================================================================================================================
    // The command handler
    //==================================================================================================================
    task handle_cmd_task (input logic [1:0] fifo_cmd, input logic [5:0] payload_length);
        (* parallel_case, full_case *)
        case (fifo_cmd)
            `CMD_SETUP_OUTPUT: begin
                if (payload_length == 6'd1) begin
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t--> CMD_SETUP_OUTPUT. \033[0;0m");
`endif
                    // Reset the output
`ifdef EXT_ENABLED
                    ext_led_app_ctrl_err_o <= 1'b0;
`endif
                end else begin
`ifdef D_CTRL
                    $display ($time, "\033[0;36m CTRL:\t[ERROR] --> CMD_SETUP_OUTPUT payload bytes: %d (expected 1). \033[0;0m",
                                    payload_length);
`endif
                    wr_data_index <= 6'd0;
                    wr_data[0] <= {`CMD_ERROR, 6'h1};
                    wr_data[1] <= `ERROR_INVALID_SETUP_OUTPUT_PAYLOAD;

                    rd_in_fifo_en_o <= 1'b0;
                    state_m <= STATE_ERROR;
                end
            end

            `CMD_STREAM_OUTPUT: begin
            end

            `CMD_SPDIF_CONTROL_OUTPUT: begin
                // Not supported yet
            end

            `CMD_SETUP_INPUT: begin
                // Not supported yet
            end
        endcase
    endtask

    //==================================================================================================================
    // The payload handler
    //==================================================================================================================
    task handle_payload_task (input logic [1:0] fifo_cmd, input logic [7:0] fifo_data);
        case (fifo_cmd)
            `CMD_SETUP_OUTPUT: begin
            end

            `CMD_STREAM_OUTPUT: begin
            end

            `CMD_SPDIF_CONTROL_OUTPUT: begin
                // Not supported yet
            end

            `CMD_SETUP_INPUT: begin
                // Not supported yet
            end
        endcase
    endtask

    //==================================================================================================================
    // The error handler
    //==================================================================================================================
    task handle_error_task;
        if (wr_data_index == 6'd0) begin
            if (wr_data[1] == `ERROR_NONE) begin
`ifdef D_CTRL
                $display ($time, "\033[0;36m CTRL:\t==== Done ====. \033[0;0m");
`endif
            end else begin
`ifdef D_CTRL
                $display ($time, "\033[0;36m CTRL:\t==== ERROR [code: %d] ====. \033[0;0m", wr_data[1]);
`endif
`ifdef EXT_ENABLED
                ext_led_app_ctrl_err_o <= 1'b1;
`endif
            end
        end

        write_buffer_task(STATE_RD);

    endtask

    //==================================================================================================================
    // The write data handler
    //==================================================================================================================
    task write_data_task;
    endtask

    //==================================================================================================================
    // The FIFO reader
    //==================================================================================================================
    task read_data_task (input logic [7:0] fifo_data);
        (* parallel_case, full_case *)
        case (fifo_state_m)
            STATE_FIFO_CMD: begin
                handle_cmd_task (fifo_data[7:6], fifo_data[5:0]);

                if (fifo_data[5:0] > 6'd0) begin
                    rd_payload_bytes <= fifo_data[5:0];
                    last_fifo_cmd <= fifo_data[7:6];
                    fifo_state_m <= STATE_FIFO_PAYLOAD;
                end
            end

            STATE_FIFO_PAYLOAD: begin
                handle_payload_task (last_fifo_cmd, fifo_data);

                rd_payload_bytes <= rd_payload_bytes - 2'd1;

                if (rd_payload_bytes == 2'd1) begin
                    fifo_state_m <= STATE_FIFO_CMD;
                end
            end
        endcase
    endtask

    //==================================================================================================================
    // The FIFO writter
    //==================================================================================================================
    task write_buffer_task (input logic [2:0] next_state_m);
        if (wr_data[0][5:0] + 6'd1 == wr_data_index) begin
`ifdef D_CTRL
            $display ($time, "\033[0;36m CTRL:\t[STATE_WR_BUFFER] Done. \033[0;0m");
`endif
            wr_out_fifo_en_o <= 1'b0;
            state_m <= next_state_m;
        end else begin
            if (~wr_out_fifo_full_i && ~wr_out_fifo_afull_i) begin
`ifdef D_CTRL
                $display ($time, "\033[0;36m CTRL:\t[STATE_WR_BUFFER] <-- [%d]: %d. \033[0;0m",
                                wr_data_index, wr_data[wr_data_index]);
`endif
                wr_out_fifo_en_o <= 1'b1;
                wr_out_fifo_data_o <= wr_data[wr_data_index];

                wr_data_index <= wr_data_index + 6'd1;
            end else begin
`ifdef D_CTRL
                $display ($time, "\033[0;36m CTRL:\tWrite buffer: Full. \033[0;0m");
`endif
                wr_out_fifo_en_o <= 1'b0;
            end
        end
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
            data_to_send <= 1'b0;
            led_test_mode <= 1'b0;

`ifdef EXT_ENABLED
            ext_led_app_ctrl_err_o <= 1'b0;
            ext_led_test_ok <= 1'b0;
            ext_led_test_fail <= 1'b0;
`endif
        end else begin
            case (state_m)
                STATE_IDLE: begin
                end

                STATE_RD: begin
                    if (~rd_in_fifo_empty_i) begin
                        // Read data out of the FIFO
                        rd_in_fifo_en_o <= 1'b1;
                        if (rd_in_fifo_en_o) begin
                            read_data_task (rd_in_fifo_data_i);
                        end
                    end else begin
                        // Stop reading
                        rd_in_fifo_en_o <= 1'b0;
                        // Go back to writting
                        if (data_to_send) begin
                            state_m <= STATE_WR;
                        end
                    end
                end

                STATE_WR: begin
                    write_data_task;
                end

                STATE_WR_BUFFER: begin
                    write_buffer_task (STATE_RD);
                end

                STATE_ERROR: begin
                    handle_error_task;
                end
            endcase
        end
    end
endmodule
