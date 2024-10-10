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
 * This is a simulator for the FT2232 synchronous FIFO interface. It implements 3 tests.
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

`include "test_definitions.svh"

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

    logic send_data, start_sending_data;

    logic [5:0] out_payload_bytes;
    logic [7:0] out_packets;
    logic [7:0] out_data;
    logic [31:0] out_index;

    logic [5:0] in_payload_bytes, total_in_payload_bytes;
    logic [1:0] in_last_cmd;
    logic [7:0] in_data;

    localparam STATE_OUT_START_CMD          = 3'b000;
    localparam STATE_OUT_START_PAYLOAD_1    = 3'b001;
    localparam STATE_OUT_START_PAYLOAD_2    = 3'b010;
    localparam STATE_OUT_START_PAYLOAD_3    = 3'b011;
    localparam STATE_OUT_DATA_CMD           = 3'b100;
    localparam STATE_OUT_DATA_PAYLOAD       = 3'b101;
    localparam STATE_OUT_STOP_CMD           = 3'b110;
    localparam STATE_OUT_IDLE               = 3'b111;
    logic [2:0] out_state_m;

    localparam STATE_IN_CMD             = 2'b00;
    localparam STATE_IN_PAYLOAD         = 2'b01;
    localparam STATE_IN_IDLE            = 2'b11;
    logic [1:0] in_state_m;

`ifdef DATA_PACKETS_COUNT
    localparam DATA_PACKETS_COUNT = `DATA_PACKETS_COUNT;
`else
    // Provide a default of one packet.
    localparam DATA_PACKETS_COUNT = 8'd1;
`endif

`ifdef DATA_PACKET_PAYLOAD
    localparam DATA_PACKET_PAYLOAD = `DATA_PACKET_PAYLOAD;
`else
    // Provide a default of 63 bytes.
    localparam DATA_PACKET_PAYLOAD = 6'd63;
`endif

    //==================================================================================================================
    // The task that outputs the next byte
    //==================================================================================================================
    task output_data_task;
        case (out_state_m)
            STATE_OUT_START_CMD: begin
                fifo_data_o <= {`CMD_HOST_START, 6'd3};
`ifdef D_FT2232
                $display ($time, "\033[0;35m FT2232:\t---> [STATE_OUT_START_CMD] %d. \033[0;0m",
                                    {`CMD_HOST_START, 6'd3});
`endif
                out_state_m <= STATE_OUT_START_PAYLOAD_1;

                out_packets <= DATA_PACKETS_COUNT;
                out_data <= 8'd0;
                in_data <= 8'd0;
            end

            STATE_OUT_START_PAYLOAD_1: begin
                fifo_data_o <= `TEST_NUMBER;
`ifdef D_FT2232
                $display ($time, "\033[0;35m FT2232:\t---> [STATE_OUT_START_PAYLOAD] [Test number] %d. \033[0;0m",
                                    `TEST_NUMBER);
`endif
                out_state_m <= STATE_OUT_START_PAYLOAD_2;
            end

            STATE_OUT_START_PAYLOAD_2: begin
                fifo_data_o <= DATA_PACKET_PAYLOAD;
`ifdef D_FT2232
                $display ($time, "\033[0;35m FT2232:\t---> [STATE_OUT_START_PAYLOAD] [Packet length] %d. \033[0;0m",
                                    DATA_PACKET_PAYLOAD);
`endif
                out_state_m <= STATE_OUT_START_PAYLOAD_3;
            end

            STATE_OUT_START_PAYLOAD_3: begin
                fifo_data_o <= DATA_PACKETS_COUNT;
`ifdef D_FT2232
                $display ($time, "\033[0;35m FT2232:\t---> [STATE_OUT_START_PAYLOAD] [Packet count] %d. \033[0;0m",
                                    DATA_PACKETS_COUNT);
`endif
                if (`TEST_NUMBER == `TEST_RECEIVE || `TEST_NUMBER == `TEST_RECEIVE_SEND) begin
                    out_state_m <= STATE_OUT_DATA_CMD;
                end else begin
                    send_data <= 1'b0;
                    out_state_m <= STATE_OUT_IDLE;
                end
            end

            STATE_OUT_DATA_CMD: begin
                fifo_data_o <= {`CMD_HOST_DATA, DATA_PACKET_PAYLOAD};
`ifdef D_FT2232
                $display ($time, "\033[0;35m FT2232:\t---> [STATE_OUT_DATA_CMD] %d. \033[0;0m", {`CMD_HOST_DATA,
                                    DATA_PACKET_PAYLOAD});
`endif
                out_payload_bytes <= DATA_PACKET_PAYLOAD;

                out_state_m <= STATE_OUT_DATA_PAYLOAD;
            end

            STATE_OUT_DATA_PAYLOAD: begin
                fifo_data_o <= out_data;
`ifdef D_FT2232
                $display ($time, "\033[0;35m FT2232:\t---> [STATE_OUT_DATA_PAYLOAD] %d (remaining %d). \033[0;0m",
                                    out_data, out_payload_bytes - 1);
`endif
                out_data <= out_data + 8'd1;

                out_payload_bytes <= out_payload_bytes - 6'd1;
                if (out_payload_bytes == 6'd1) begin
                    out_packets <= out_packets - 8'd1;
                    if (out_packets == 8'd1) begin
                        out_state_m <= STATE_OUT_STOP_CMD;
                    end else begin
                        out_state_m <= STATE_OUT_DATA_CMD;
                    end
                end
            end

            STATE_OUT_STOP_CMD: begin
                fifo_data_o <= {`CMD_HOST_STOP, 6'd0};
`ifdef D_FT2232
                $display ($time, "\033[0;35m FT2232:\t---> [STATE_OUT_STOP_CMD] %d. \033[0;0m", {`CMD_HOST_STOP, 6'd0});
`endif
                send_data <= 1'b0;
                out_state_m <= STATE_OUT_IDLE;
            end

            STATE_OUT_IDLE: begin
                // This task shall not be called in this state machine (send_data == 0);
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
                    `CMD_FPGA_STOPPED: begin
                        fifo_rxf_n_o <= 1'b1;
`ifdef D_FT2232
                        $display ($time, "\033[0;35m FT2232:\t<--- [STATE_IN_CMD] CMD_FPGA_STOPPED [payload bytes: %d]. \033[0;0m",
                                        fifo_data_i[5:0]);
`endif
                        total_in_payload_bytes <= fifo_data_i[5:0];
                        in_payload_bytes <= fifo_data_i[5:0];
                        in_state_m <= STATE_IN_PAYLOAD;
                    end

                    `CMD_FPGA_DATA: begin
`ifdef D_FT2232
                        $display ($time, "\033[0;35m FT2232:\t<--- [STATE_IN_CMD] CMD_FPGA_DATA [payload bytes: %d]. \033[0;0m",
                                        fifo_data_i[5:0]);
`endif
                        total_in_payload_bytes <= fifo_data_i[5:0];
                        in_payload_bytes <= fifo_data_i[5:0];
                        in_state_m <= STATE_IN_PAYLOAD;
                    end

                    `CMD_FPGA_LOOPBACK: begin
`ifdef D_FT2232
                        $display ($time, "\033[0;35m FT2232:\t<--- [STATE_IN_CMD] CMD_FPGA_LOOPBACK [payload bytes: %d]. \033[0;0m",
                                        fifo_data_i[5:0]);
`endif
                        total_in_payload_bytes <= fifo_data_i[5:0];
                        in_payload_bytes <= fifo_data_i[5:0];
                        in_state_m <= STATE_IN_PAYLOAD;
                    end

                    default: begin
`ifdef D_FT2232
                        $display ($time, "\033[0;35m FT2232:\t<--- [STATE_IN_CMD] Unknown command %d. \033[0;0m",
                                        fifo_data_i);
                        $display ($time, "\033[0;35m FT2232:\t==== TEST FAILED [Unknown command] ====. \033[0;0m");
`endif
                        in_state_m <= STATE_IN_IDLE;
                        out_state_m <= STATE_OUT_IDLE;
                    end
                endcase

                in_last_cmd <= fifo_data_i[7:6];
            end

            STATE_IN_PAYLOAD: begin
                case (in_last_cmd)
                    `CMD_FPGA_STOPPED: begin
                        case (total_in_payload_bytes - in_payload_bytes)
                            6'd0: begin
`ifdef D_FT2232
                                $display ($time, "\033[0;35m FT2232:\t<--- [STATE_IN_PAYLOAD for CMD_FPGA_STOPPED] Error code: %d. \033[0;0m",
                                                    fifo_data_i);
                                if (fifo_data_i == `TEST_ERROR_NONE) begin
                                    $display ($time, "\033[0;35m FT2232:\t==== TEST OK ====. \033[0;0m");
                                end else begin
                                    $display ($time, "\033[0;35m FT2232:\t==== TEST FAILED [code: %d] ====. \033[0;0m",
                                                    fifo_data_i);
                                end
`endif
                            end

                            6'd1: begin
`ifdef D_FT2232
                                $display ($time, "\033[0;35m FT2232:\t<--- [STATE_IN_PAYLOAD for CMD_FPGA_STOPPED] Value received: %d. \033[0;0m",
                                                    fifo_data_i);
`endif
                            end

                            6'd2: begin
`ifdef D_FT2232
                                $display ($time, "\033[0;35m FT2232:\t<--- [STATE_IN_PAYLOAD for CMD_FPGA_STOPPED] Value expected: %d. \033[0;0m",
                                                    fifo_data_i);
`endif
                            end
                        endcase

                        in_payload_bytes <= in_payload_bytes - 6'd1;
                        if (in_payload_bytes == 6'd1) begin
`ifdef D_FT2232_FINE
                            $display ($time, "\033[0;35m FT2232:\t[STATE_IN_PAYLOAD] -> STATE_IN_CMD. \033[0;0m");
`endif
                            in_state_m <= STATE_IN_CMD;
                        end
                    end

                    `CMD_FPGA_DATA: begin
`ifdef D_FT2232
                        $display ($time, "\033[0;35m FT2232:\t<--- [STATE_IN_PAYLOAD for CMD_FPGA_DATA]: %d. \033[0;0m",
                                                fifo_data_i);
`endif
                        if (in_data == fifo_data_i) begin
                            in_data <= in_data + 8'd1;

                            in_payload_bytes <= in_payload_bytes - 6'd1;
                            if (in_payload_bytes == 6'd1) begin
`ifdef D_FT2232_FINE
                                $display ($time, "\033[0;35m FT2232:\t[STATE_IN_PAYLOAD for CMD_FPGA_DATA] -> STATE_IN_CMD. \033[0;0m");
`endif
                                in_state_m <= STATE_IN_CMD;
                            end
                        end else begin
`ifdef D_FT2232
                            $display ($time, "\033[0;35m FT2232:\t==== TEST FAILED. [Received: %d, expected %d].==== \033[0;0m",
                                                fifo_data_i, in_data);
`endif
                            in_state_m <= STATE_IN_IDLE;
                            out_state_m <= STATE_OUT_IDLE;
                        end
                    end

                    `CMD_FPGA_LOOPBACK: begin
`ifdef D_FT2232
                        $display ($time, "\033[0;35m FT2232:\t<--- [STATE_IN_PAYLOAD for CMD_FPGA_LOOPBACK]: %d. \033[0;0m",
                                                fifo_data_i);
`endif
                        // TODO: Find a way to check the loopback data.
                        in_payload_bytes <= in_payload_bytes - 6'd1;
                        if (in_payload_bytes == 6'd1) begin
`ifdef D_FT2232_FINE
                            $display ($time, "\033[0;35m FT2232:\t[STATE_IN_PAYLOAD for CMD_FPGA_LOOPBACK] -> STATE_IN_CMD. \033[0;0m");
`endif
                            in_state_m <= STATE_IN_CMD;
                        end
                    end

                    default: begin
`ifdef D_FT2232
                        $display ($time, "\033[0;35m FT2232:\t<--- [STATE_IN_PAYLOAD] Unknown command %d. \033[0;0m",
                                        fifo_data_i);
                        $display ($time, "\033[0;35m FT2232:\t==== TEST FAILED [Unknown payload command] ====. \033[0;0m");
`endif
                        in_state_m <= STATE_IN_IDLE;
                        out_state_m <= STATE_OUT_IDLE;
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
            out_state_m <= STATE_OUT_START_CMD;
            in_state_m <= STATE_IN_CMD;

            send_data <= 1'b1;

            out_data <= 8'd0;
            out_index <= 0;
            in_data <= 8'd0;

            fifo_txe_n_o <= 1'b0;
            fifo_rxf_n_o <= 1'b1;

            start_sending_data <= 1'b1;
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
