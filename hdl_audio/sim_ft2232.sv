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
 * This is a simulator for the FT2232 synchronous FIFO interface. It sends audio from a file created by ft2232_file
 * host app.
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

    logic [3:0] in_payload_bytes, total_in_payload_bytes;
    logic [2:0] in_last_cmd;

    logic send_data, start_sending_data;
    logic [31:0] out_index;

    localparam STATE_IN_CMD             = 2'b00;
    localparam STATE_IN_PAYLOAD         = 2'b01;
    localparam STATE_IN_IDLE            = 2'b11;
    logic [1:0] in_state_m;

    //==================================================================================================================
    // The initial block
    //==================================================================================================================
    `define DATA_MEMORY 16000000
    // Memory space for sound data needs to be large enough to hold the sound.bin file.
    logic [7:0] sound_data[0:`DATA_MEMORY - 1];
    logic [31:0] sound_data_length;
    initial begin
        integer fd, bytes_read;
        logic [7:0] value_1;

        $display ($time, "\033[0;35m FT2232:\tOpen bin file: %s. \033[0;0m", `BIN_FILE_NAME);
        fd = $fopen(`BIN_FILE_NAME, "rb");
        if (fd) begin
            sound_data_length = 0;
            bytes_read = 1;

            while (bytes_read > 0) begin
                bytes_read = $fread(value_1, fd, sound_data_length, 1);
                if (bytes_read == 1) begin
                    sound_data[sound_data_length] = value_1;
                    sound_data_length = sound_data_length + 1;
                    if (sound_data_length >= `DATA_MEMORY) begin
                        $display ($time, "\033[0;35m FT2232:\tMemory to small to hold sound.bin data. \033[0;0m", );
                        $finish(1);
                    end
                end else begin
                    $display ($time, "\033[0;35m FT2232:\tLoaded sound.bin data: %d. \033[0;0m", sound_data_length);
                end
            end

            $fclose(fd);
        end else begin
            $display ($time, "\033[0;35m FT2232:\tCannot open sound.bin. \033[0;0m");
            $finish(1);
        end
    end

    //==================================================================================================================
    // The task that outputs the next byte
    //==================================================================================================================
    task output_data_task;
        if (out_index < sound_data_length) begin
`ifdef D_FT2232
            $display ($time, "\033[0;35m FT2232:\t%d bytes. \033[0;0m", out_index);
`endif
            fifo_data_o <= sound_data[out_index];
            out_index <= out_index + 1;
        end else begin
            send_data <= 1'b0;
        end
    endtask

    //==================================================================================================================
    // The task that reads the next byte
    //==================================================================================================================
    task input_data_task;
        case (in_state_m)
            STATE_IN_CMD: begin
                case (fifo_data_i[7:5])
                    `CMD_FPGA_STOPPED: begin
                        fifo_rxf_n_o <= 1'b1;
`ifdef D_FT2232
                        $display ($time, "\033[0;35m FT2232:\t<--- [STATE_IN_CMD] CMD_FPGA_STOPPED [payload bytes: %d]. \033[0;0m",
                                        fifo_data_i[4:0]);
`endif
                        total_in_payload_bytes <= fifo_data_i[3:0];
                        in_payload_bytes <= fifo_data_i[3:0];
                        in_state_m <= STATE_IN_PAYLOAD;
                    end

                    default: begin
`ifdef D_FT2232
                        $display ($time, "\033[0;35m FT2232:\t<--- [STATE_IN_CMD] Unknown command %d. \033[0;0m",
                                        fifo_data_i);
                        $display ($time, "\033[0;35m FT2232:\t==== PLAYBACK FAILED [Unknown command] ====. \033[0;0m");
`endif
                        in_state_m <= STATE_IN_IDLE;
                    end
                endcase

                in_last_cmd <= fifo_data_i[7:5];
            end

            STATE_IN_PAYLOAD: begin
                case (in_last_cmd)
                    `CMD_FPGA_STOPPED: begin
                        case (total_in_payload_bytes - in_payload_bytes)
                            4'd0: begin
`ifdef D_FT2232
                                $display ($time, "\033[0;35m FT2232:\t<--- [STATE_IN_PAYLOAD for CMD_FPGA_STOPPED] Error code: %d. \033[0;0m",
                                                    fifo_data_i);
                                if (fifo_data_i == `ERROR_NONE) begin
                                    $display ($time, "\033[0;35m FT2232:\t==== PLAYBACK STOPPED ====. \033[0;0m");
                                end else begin
                                    $display ($time, "\033[0;35m FT2232:\t==== PLAYBACK FAILED [code: %d] ====. \033[0;0m",
                                                    fifo_data_i);
                                end
`endif
                            end

                            4'd1: begin
`ifdef D_FT2232
                                $display ($time, "\033[0;35m FT2232:\t<--- [STATE_IN_PAYLOAD for CMD_FPGA_STOPPED] Value received: %d. \033[0;0m",
                                                    fifo_data_i);
`endif
                            end

                            4'd2: begin
`ifdef D_FT2232
                                $display ($time, "\033[0;35m FT2232:\t<--- [STATE_IN_PAYLOAD for CMD_FPGA_STOPPED] Value expected: %d. \033[0;0m",
                                                    fifo_data_i);
`endif
                            end
                        endcase

                        in_payload_bytes <= in_payload_bytes - 4'd1;
                        if (in_payload_bytes == 4'd1) begin
`ifdef D_FT2232_FINE
                            $display ($time, "\033[0;35m FT2232:\t[STATE_IN_PAYLOAD] -> STATE_IN_CMD. \033[0;0m");
`endif
                            in_state_m <= STATE_IN_CMD;
                        end
                    end
                endcase
            end

            STATE_IN_IDLE: begin
                // Stop accepting data
                fifo_txe_n_o <= 1'b1;
            end
        endcase
    endtask


    //==================================================================================================================
    // The FT2232 simulation
    //==================================================================================================================
    always @(posedge fifo_clk_o, negedge ft2232_reset_n_i) begin
        if (~ft2232_reset_n_i) begin
            in_state_m <= STATE_IN_CMD;

            send_data <= 1'b1;
            start_sending_data <= 1'b1;
            out_index <= 0;

            fifo_txe_n_o <= 1'b0;
            fifo_rxf_n_o <= 1'b1;

`ifdef D_FT2232
            $display ($time, "\033[0;35m FT2232:\t-- Reset. \033[0;0m");
`endif
        end else begin
            if (start_sending_data) begin
                // Output this value on OE = 0
                output_data_task;
                // There is data in the FIFO
                fifo_rxf_n_o <= 1'b0;
                start_sending_data <= 1'b0;
            end

            if (~fifo_oe_n_i) begin
                if (~fifo_rd_n_i) begin
                    if (send_data) begin
                        output_data_task;
                    end else begin
                        // No more data in the FIFO
                        fifo_rxf_n_o <= 1'b1;
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
