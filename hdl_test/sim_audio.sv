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
 * This is the top module for the simulator. It wraps the audio top module and creates a FT2232 simulator module.
 **********************************************************************************************************************/
`timescale 1ps/1ps
`default_nettype none

module sim_audio;
    //==================================================================================================================
    // Simulate the external clocks
    //==================================================================================================================
`ifdef CLK_PERIOD
    localparam CLK_24576000_PS = `CLK_PERIOD;
`else
    // Provide a default. 24.576MHz -> 40690 ps
    localparam CLK_24576000_PS = 40690;
`endif
    logic clk_24576000 = 1'b0;
    // Generate the simulator clock
    always #(CLK_24576000_PS/2) clk_24576000 = ~clk_24576000;

    localparam CLK_22579200_PS = 44288;
    logic clk_22579200 = 1'b0;
    // Generate the simulator clock
    always #(CLK_22579200_PS/2) clk_22579200 = ~clk_22579200;

    logic fifo_clk;
    logic btn_reset = 1'b0;
    logic ft2232_reset_n, fifo_oe_n, fifo_siwu, fifo_wr_n, fifo_rd_n, fifo_txe_n, fifo_rxf_n;
    wire [7:0] fifo_data;
`ifdef ENABLE_UART
    logic uart_rxd, uart_txd;
`endif
    logic led_0, led_1, led_reset, led_user;
    logic [45:0] extension;

    //==================================================================================================================
    // Create the top module
    //==================================================================================================================
    audio audio_m (
        // Reset button
        .btn_reset              (btn_reset),
        // Clocks
        .clk_24576000           (clk_24576000),
        .clk_22579200           (clk_22579200),
        // FT2232HQ FIFO
        .fifo_clk               (fifo_clk),
        .fifo_txe_n             (fifo_txe_n),
        .fifo_rxf_n             (fifo_rxf_n),
        .ft2232_reset_n         (ft2232_reset_n),
        .fifo_oe_n              (fifo_oe_n),
        .fifo_siwu              (fifo_siwu),
        .fifo_wr_n              (fifo_wr_n),
        .fifo_rd_n              (fifo_rd_n),
        .fifo_data              (fifo_data),
`ifdef ENABLE_UART
        //  UART
        .uart_rxd               (uart_rxd),
        .uart_txd               (uart_txd),
`endif // ENABLE_UART
        // Extension
        .extension              (extension),
        // LEDs
        .led_0                  (led_0),
        .led_1                  (led_1),
        .led_reset              (led_reset),
        .led_user               (led_user));

    //==================================================================================================================
    // Simulate the FT2232 in sync FIFO mode.
    //==================================================================================================================
    sim_ft2232 sim_ft2232_m (
        .ft2232_reset_n_i       (ft2232_reset_n),
        .fifo_clk_o             (fifo_clk),
        .fifo_txe_n_o           (fifo_txe_n),
        .fifo_rxf_n_o           (fifo_rxf_n),
        .fifo_oe_n_i            (fifo_oe_n),
        .fifo_siwu_i            (fifo_siwu),
        .fifo_wr_n_i            (fifo_wr_n),
        .fifo_rd_n_i            (fifo_rd_n),
        .fifo_data_io           (fifo_data));

    //==================================================================================================================
    // The initial block
    //==================================================================================================================
    initial begin
        $display ($time, " INIT:\tClock period %d(ps).", CLK_24576000_PS);

`ifdef GENERATE_VCD
        $dumpfile("out.vcd");
        $dumpvars(0, ft2232_reset_n);
        $dumpvars(0, fifo_clk);
        $dumpvars(0, fifo_oe_n);
`endif

        #5000000000

        $display($time, " SIM: ---------------------- Simulation end [Timeout] ------------------------");

        $finish (1);
    end

endmodule

