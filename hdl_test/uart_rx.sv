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
 * Receive data from UART operating in 8N1 mode.
 *
 * reset_i      -- Reset active high.
 * clk_i        -- The clock signal.
 * stb_i        -- The transaction starts on the posedge of this signal.
 * data_o       -- The byte received.
 * ack_o        -- The transaction completes successfully on the posedge of this signal.
 * uart_rxd_i   -- The UART RX line.
 **********************************************************************************************************************/
`timescale 1ps/1ps
`default_nettype none

module uart_rx #(parameter integer CLK_FREQUENCY_HZ = 60000000, parameter integer BAUD_RATE_HZ = 3000000,
                parameter integer FIFO_BITS = 4) (
    input logic reset_i,
    input logic clk_i,
    input logic stb_i,
    output logic [7:0] data_o,
    output logic ack_o,
    // Tx FIFO overflow LED
    output logic led_rx_err_o,
    // The UART RX line
    input logic uart_rxd_i);

    localparam CLKS_PER_BIT = CLK_FREQUENCY_HZ/BAUD_RATE_HZ;

    // Negate the ack_o as soon as the stb_i is deactivated.
    logic sync_ack_o = 1'b0;
    assign ack_o = sync_ack_o & stb_i;

    //==================================================================================================================
    // Prevent metastability problems.
    //==================================================================================================================
    logic uart_rxd_p, uart_rxd_q, uart_rxd_data;

    always @(posedge clk_i) begin
        if (reset_i) begin
            {uart_rxd_p, uart_rxd_q, uart_rxd_data} <= 3'b111;
        end else begin
            uart_rxd_p <= uart_rxd_i;
            uart_rxd_q <= uart_rxd_p;
            uart_rxd_data <= uart_rxd_q;
        end
    end

    // State machine
    localparam RX_IDLE      = 2'b00;
    localparam RX_START_BIT = 2'b01;
    localparam RX_DATA_BITS = 2'b10;
    localparam RX_STOP_BIT  = 2'b11;
    logic [1:0] state_m;

    logic [15:0] clock_count;
    logic [2:0] bit_index;
    logic [7:0] rx_byte;
    logic save_rx_byte;

    // RX FIFO
    localparam FIFO_SIZE = 2**FIFO_BITS;
    logic [FIFO_BITS-1:0] rx_fifo_rd_ptr, rx_fifo_wr_ptr, next_rx_fifo_wr_ptr, next_rx_fifo_rd_ptr;
    logic [7:0] rx_fifo[0:FIFO_SIZE-1];

    logic rx_fifo_full;
    assign rx_fifo_full = rx_fifo_rd_ptr == next_rx_fifo_wr_ptr;

    logic rx_fifo_has_bytes;
    assign rx_fifo_has_bytes = (rx_fifo_rd_ptr != rx_fifo_wr_ptr) | rx_fifo_full;

    //==================================================================================================================
    // Combinatorial
    //==================================================================================================================
    always_comb begin
        next_rx_fifo_wr_ptr = rx_fifo_wr_ptr + 1;
        next_rx_fifo_rd_ptr = rx_fifo_rd_ptr + 1;
    end

    //==================================================================================================================
    // UART RX
    //==================================================================================================================
    always @(posedge clk_i) begin
        if (reset_i) begin
            rx_fifo_rd_ptr <= 0;
            rx_fifo_wr_ptr <= 0;

            sync_ack_o <= 1'b0;
            save_rx_byte <= 1'b0;

            state_m <= RX_IDLE;

            led_rx_err_o <= 1'b0;
        end else begin
            if (sync_ack_o) sync_ack_o <= stb_i;

            (* parallel_case, full_case *)
            case (state_m)
                RX_IDLE: begin
                    if (~uart_rxd_data) begin
                        clock_count <= 16'h1;
                        bit_index <= 3'h0;
                        state_m <= RX_START_BIT;
                    end
                end

                RX_START_BIT: begin
                    if (~uart_rxd_data) begin
                        if (clock_count == CLKS_PER_BIT/2) begin
                            clock_count <= 16'h1;
                            state_m <= RX_DATA_BITS;
                        end else begin
                            clock_count <= clock_count + 16'h1;
                        end
                    end else begin
                        state_m <= RX_IDLE;
                    end
                end

                RX_DATA_BITS: begin
                    if (clock_count == CLKS_PER_BIT) begin
                        clock_count <= 16'h1;
                        rx_byte[bit_index] <= uart_rxd_data;

                        if (bit_index < 3'h7) begin
                            bit_index <= bit_index + 3'h1;
                        end else begin
                            state_m <= RX_STOP_BIT;
                        end
                    end else begin
                        clock_count <= clock_count + 16'h1;
                    end
                end

                RX_STOP_BIT: begin
                    if (clock_count == CLKS_PER_BIT) begin
                        if (uart_rxd_data) begin
                            save_rx_byte <= 1'b1;
                        end

                        state_m <= RX_IDLE;
                    end else begin
                        clock_count <= clock_count + 16'h1;
                    end
                end
            endcase

            if (save_rx_byte) begin
                save_rx_byte <= 1'b0;

                if (~rx_fifo_full) begin
                    rx_fifo[rx_fifo_wr_ptr] <= rx_byte;
                    rx_fifo_wr_ptr <= next_rx_fifo_wr_ptr;
`ifdef D_UART
                    $display($time, " UART: Rx byte: %h", rx_byte);
`endif
                end else begin
`ifdef D_UART
                    $display($time, " UART: Rx FIFO is full. Dropping byte: %h", rx_byte);
`endif
                end

                led_rx_err_o <= rx_fifo_full;
            end else begin
                if (stb_i & ~sync_ack_o & rx_fifo_has_bytes) begin
                    data_o <= rx_fifo[rx_fifo_rd_ptr];
                    sync_ack_o <= 1'b1;

                    rx_fifo_rd_ptr <= next_rx_fifo_rd_ptr;
                end
            end
        end
    end
endmodule
