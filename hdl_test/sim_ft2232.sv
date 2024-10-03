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
 * This is a simulator for the FT2232 synchronous FIFO interface. It implements 3 tests in TEST_MODE else it simulates
 * audio samples send.
 *
 * Simulation rules:
 *
 * OE#: The 8-bit bus lines are normally input unless OE# is low. The OE# pin must be driven low at least 1 clock period
 * before asserting RD# low. Should be driven low at least 1 clock period before driving RD# low to allow for
 * data buffer turn-around.
 *
 * RXF#: When high, do not read data from the FIFO. When low, there is data available in the FIFO which can be read by
 * driving RD# low. Data is transferred on every clock that RXF# and RD# are both low.
 *
 * TXE#: When high, do not write data into the FIFO. When low, data can be written into the FIFO by driving WR# low.
 * Data is transferred on every clock that TXE# and WR# are both low.
 *
 * RD#: Enables the current FIFO data byte to be driven onto the bus when RD# goes low. The next FIFO data byte
 * (if available) is fetched from the receive FIFO buffer each CLKOUT cycle until RD# goes high.
 *
 * WR#: Enables the data byte on the BUS pins to be written into the transmit FIFO buffer when WR# is low. The next FIFO
 * data byte is written to the transmit FIFO buffer each CLKOUT cycle until WR# goes high.
 **********************************************************************************************************************/
 `timescale 1ps/1ps
`default_nettype none

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

    logic [7:0] out_data, in_data;
    logic send_data;

`ifndef DATA_BYTES_TO_SEND
`define DATA_BYTES_TO_SEND 1
`endif

    //==================================================================================================================
    // The task that outputs the next byte
    //==================================================================================================================
    task output_data_task;
        if (send_data) begin
    `ifdef D_FT2232
            $display ($time, "\033[0;35m FT2232:\t---> Sending: %d. \033[0;0m", out_data);
    `endif
            fifo_data_o <= out_data;
            out_data = out_data + 8'd1;

            if (out_data == `DATA_BYTES_TO_SEND) begin
                // Stop sending data
                send_data <= 1'b0;
    `ifdef D_FT2232
                $display ($time, "\033[0;35m FT2232:\tDone sending. \033[0;0m");
    `endif
            end
        end else begin
            // Stop sending data
            fifo_rxf_n_o <= 1'b1;
        end
    endtask

    //==================================================================================================================
    // The task that reads the next byte
    //==================================================================================================================
    task input_data_task;
        if (in_data == fifo_data_i) begin
`ifdef D_FT2232
            $display ($time, "\033[0;35m FT2232:\t<--- Received: %d. \033[0;0m", fifo_data_i);
`endif
        end else begin
`ifdef D_FT2232
            $display ($time, "\033[0;35m FT2232:\t<--- Received: %d; expected :%d. \033[0;0m", fifo_data_i, in_data);
`endif
            // Stop sending data
            fifo_rxf_n_o <= 1'b1;
            // Stop accepting data
            fifo_txe_n_o <= 1'b1;
        end

        in_data <= in_data + 8'd1;
    endtask

    logic first_val;
    //==================================================================================================================
    // The FT2232 simulation
    //==================================================================================================================
    always @(posedge fifo_clk_o, negedge ft2232_reset_n_i) begin
        if (~ft2232_reset_n_i) begin
            first_val <= 1'b1;

            out_data <= 8'd0;
            in_data <= 8'd0;
            send_data <= 1'b1;

            fifo_txe_n_o <= 1'b0;
            fifo_rxf_n_o <= 1'b0;

`ifdef D_FT2232
            $display ($time, "\033[0;35m FT2232:\t-- Reset. \033[0;0m");
`endif
        end else begin
            if (~fifo_rxf_n_o) begin
                if (~fifo_oe_n_i) begin
                    if (~fifo_rd_n_i) begin
                        output_data_task;
                    end else begin
                        if (first_val) begin
                            output_data_task;
                            first_val <= 1'b0;
                        end
                    end
                end
            end

            if (~fifo_txe_n_o) begin
                if (fifo_oe_n_i && ~fifo_wr_n_i) begin
                    input_data_task;
                end
            end
        end
    end
endmodule
