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
 * This module implements the loopback verification. Any byte received, including host commands,
 * are sent back with a CMD_FPGA_LOOPBACK command.
 *
 * This code was useful during debugging to ensure that the control module receives the expected data from the host.
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

    // State machine
    localparam STATE_RD         = 1'b1;
    localparam STATE_WR_BUFFER  = 1'b0;
    logic state_m, next_state_m;

    logic [5:0] wr_data_index;
    logic [7:0] wr_data[0:1];
    //==================================================================================================================
    // The FIFO reader
    //==================================================================================================================
    task read_data_task (input logic [7:0] fifo_data);
        // Write back the byte received
        wr_data_index <= 6'd0;
        wr_data[0] <= {`CMD_FPGA_LOOPBACK, 6'd1};
        wr_data[1] <= fifo_data;

        state_m <= STATE_WR_BUFFER;
        next_state_m <= STATE_RD;
    endtask

    //==================================================================================================================
    // The FIFO writter
    //==================================================================================================================
    task write_buffer_task;
        if (wr_data_index == 6'd2) begin
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

                wr_data_index <= wr_data_index + 6'd1;
            end else begin
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

            led_ctrl_err_o <= 1'b0;
        end else begin
            (* parallel_case, full_case *)
            case (state_m)
                STATE_RD: begin
                    if (~rd_in_fifo_empty_i) begin
                        if (rd_in_fifo_en_o) begin
                            // Stop reading from the FIFO
                            rd_in_fifo_en_o <= 1'b0;

                            read_data_task (rd_in_fifo_data_i);
                        end else begin
                            rd_in_fifo_en_o <= 1'b1;
                        end
                    end else begin
                        // Stop reading
                        rd_in_fifo_en_o <= 1'b0;
                    end
                end

                STATE_WR_BUFFER: begin
                    write_buffer_task;
                end
            endcase
        end
    end
endmodule
