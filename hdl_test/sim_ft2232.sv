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

    logic [15:0] out_payload_bytes, out_packets;
    logic [7:0] out_data;
    logic out_byte_in_word;

    logic [15:0] in_payload_bytes, total_in_payload_bytes;
    logic [2:0] in_last_cmd;
    logic [7:0] in_data;

    localparam STATE_OUT_START_CMD          = 4'd0;
    localparam STATE_OUT_START_PAYLOAD_1    = 4'd1;
    localparam STATE_OUT_START_PAYLOAD_2    = 4'd2;
    localparam STATE_OUT_START_PAYLOAD_3    = 4'd3;
    localparam STATE_OUT_DATA_CMD           = 4'd4;
    localparam STATE_OUT_DATA_PAYLOAD_LENGTH= 4'd5;
    localparam STATE_OUT_DATA_PAYLOAD       = 4'd6;
    localparam STATE_OUT_STOP_CMD           = 4'd7;
    localparam STATE_OUT_IDLE               = 4'd8;
    logic [3:0] out_state_m;

    localparam STATE_IN_CMD             = 2'd0;
    localparam STATE_IN_PAYLOAD         = 2'd1;
    localparam STATE_IN_PAYLOAD_LENGTH  = 2'd2;
    localparam STATE_IN_IDLE            = 2'd3;
    logic [1:0] in_state_m;

`ifdef DATA_PACKETS_COUNT
    localparam DATA_PACKETS_COUNT = `DATA_PACKETS_COUNT;
`else
    // Provide a default of one packet.
    localparam DATA_PACKETS_COUNT = 1;
`endif

`ifdef DATA_PACKET_PAYLOAD
    localparam DATA_PACKET_PAYLOAD = `DATA_PACKET_PAYLOAD;
`else
    // Provide a default of 1 byte.
    localparam DATA_PACKET_PAYLOAD = 1;
`endif
    logic in_byte_in_word;

    //==================================================================================================================
    // The task that outputs the next byte
    //==================================================================================================================
    task output_data_task;
        case (out_state_m)
            STATE_OUT_START_CMD: begin
                fifo_data_o <= {`CMD_HOST_START, 5'd5};
`ifdef D_FT2232
                $display ($time, "\033[0;35m FT2232:\t---> [STATE_OUT_START_CMD] %d. \033[0;0m",
                                    {`CMD_HOST_START, 5'd5});
`endif
                out_state_m <= STATE_OUT_START_PAYLOAD_1;

                out_packets <= DATA_PACKETS_COUNT;
                out_data <= 8'd0;
                in_data <= 8'd0;
            end

            STATE_OUT_START_PAYLOAD_1: begin
                fifo_data_o <= `TEST_NUMBER;
`ifdef D_FT2232
                $display ($time, "\033[0;35m FT2232:\t---> [STATE_OUT_START_PAYLOAD_1] [Test number] %d. \033[0;0m",
                                    `TEST_NUMBER);
`endif
                out_byte_in_word <= 1'b0;
                out_state_m <= STATE_OUT_START_PAYLOAD_2;
            end

            STATE_OUT_START_PAYLOAD_2: begin
                fifo_data_o <= out_byte_in_word ? DATA_PACKET_PAYLOAD[7:0] : DATA_PACKET_PAYLOAD[15:8];
`ifdef D_FT2232
                $display ($time, "\033[0;35m FT2232:\t---> [STATE_OUT_START_PAYLOAD_2] [Packet length] %d. \033[0;0m",
                                    out_byte_in_word ? DATA_PACKET_PAYLOAD[7:0] : DATA_PACKET_PAYLOAD[15:8]);
`endif
                if (out_byte_in_word) begin
                    out_byte_in_word <= 1'b0;
                    out_state_m <= STATE_OUT_START_PAYLOAD_3;
                end else begin
                    out_byte_in_word <= 1'b1;
                end
            end

            STATE_OUT_START_PAYLOAD_3: begin
                fifo_data_o <= out_byte_in_word ? DATA_PACKETS_COUNT[7:0] : DATA_PACKETS_COUNT[15:8];
`ifdef D_FT2232
                $display ($time, "\033[0;35m FT2232:\t---> [STATE_OUT_START_PAYLOAD_3] [Packet count] %d. \033[0;0m",
                                    out_byte_in_word ? DATA_PACKETS_COUNT[7:0] : DATA_PACKETS_COUNT[15:8]);
`endif
                if (out_byte_in_word) begin
                    if (`TEST_NUMBER == `TEST_RECEIVE || `TEST_NUMBER == `TEST_RECEIVE_SEND) begin
                        out_state_m <= STATE_OUT_DATA_CMD;
                    end else begin
                        send_data <= 1'b0;
                        out_state_m <= STATE_OUT_IDLE;
                    end
                end else begin
                    out_byte_in_word <= 1'b1;
                end
            end

            STATE_OUT_DATA_CMD: begin
                fifo_data_o <= {`CMD_HOST_DATA, `PAYLOAD_LENGTH_FOLLOWS};
`ifdef D_FT2232
                $display ($time, "\033[0;35m FT2232:\t---> [STATE_OUT_DATA_CMD] %d. \033[0;0m",
                                    {`CMD_HOST_DATA, `PAYLOAD_LENGTH_FOLLOWS});
`endif
                out_payload_bytes <= DATA_PACKET_PAYLOAD;

                out_byte_in_word <= 1'b0;
                out_state_m <= STATE_OUT_DATA_PAYLOAD_LENGTH;
            end

            STATE_OUT_DATA_PAYLOAD_LENGTH: begin
                fifo_data_o <= out_byte_in_word ? DATA_PACKET_PAYLOAD[7:0] : DATA_PACKET_PAYLOAD[15:8];
`ifdef D_FT2232
                $display ($time, "\033[0;35m FT2232:\t---> [STATE_OUT_DATA_PAYLOAD_LENGTH] [Packet length] %d. \033[0;0m",
                                    out_byte_in_word ? DATA_PACKET_PAYLOAD[7:0] : DATA_PACKET_PAYLOAD[15:8]);
`endif
                if (out_byte_in_word) begin
                    out_state_m <= STATE_OUT_DATA_PAYLOAD;
                end else begin
                    out_byte_in_word <= 1'b1;
                end
            end

            STATE_OUT_DATA_PAYLOAD: begin
                fifo_data_o <= out_data;
`ifdef D_FT2232
                $display ($time, "\033[0;35m FT2232:\t---> [STATE_OUT_DATA_PAYLOAD] %d (remaining %d). \033[0;0m",
                                    out_data, out_payload_bytes - 1);
`endif
                out_data <= out_data + 8'd1;

                out_payload_bytes <= out_payload_bytes - 16'd1;
                if (out_payload_bytes == 16'd1) begin
                    out_packets <= out_packets - 16'd1;
                    if (out_packets == 16'd1) begin
                        out_state_m <= STATE_OUT_STOP_CMD;
                    end else begin
                        out_state_m <= STATE_OUT_DATA_CMD;
                    end
                end
            end

            STATE_OUT_STOP_CMD: begin
                fifo_data_o <= {`CMD_HOST_STOP, 5'd0};
`ifdef D_FT2232
                $display ($time, "\033[0;35m FT2232:\t---> [STATE_OUT_STOP_CMD] %d. \033[0;0m", {`CMD_HOST_STOP, 5'd0});
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
                case (fifo_data_i[7:5])
                    `CMD_FPGA_DATA: begin
                        if (fifo_data_i[4]) begin
`ifdef D_FT2232
                            $display ($time, "\033[0;35m FT2232:\t<--- [STATE_IN_CMD] CMD_FPGA_DATA. \033[0;0m");
`endif
                            // 2 byte payload length follows.
                            in_byte_in_word <= 1'b0;
                            in_state_m <= STATE_IN_PAYLOAD_LENGTH;
                        end else begin
`ifdef D_FT2232
                            $display ($time, "\033[0;35m FT2232:\t<--- [STATE_IN_CMD] CMD_FPGA_DATA [payload bytes: %d]. \033[0;0m",
                                        {12'b0, fifo_data_i[3:0]});
`endif
                            total_in_payload_bytes <= {12'b0, fifo_data_i[3:0]};
                            in_payload_bytes <= {12'b0, fifo_data_i[3:0]};
                            in_state_m <= STATE_IN_PAYLOAD;
                        end
                    end

                    `CMD_FPGA_LOOPBACK: begin
`ifdef D_FT2232
                        $display ($time, "\033[0;35m FT2232:\t<--- [STATE_IN_CMD] CMD_FPGA_LOOPBACK [payload bytes: %d]. \033[0;0m",
                                        fifo_data_i[3:0]);
`endif
                        // Bit [4] should be 1'b0 (CMD_FPGA_LOOPBACK has a 1 byte payload).
                        total_in_payload_bytes <= {12'b0, fifo_data_i[3:0]};
                        in_payload_bytes <= {12'b0, fifo_data_i[3:0]};
                        in_state_m <= STATE_IN_PAYLOAD;
                    end

                    `CMD_FPGA_STOPPED: begin
                        fifo_rxf_n_o <= 1'b1;
`ifdef D_FT2232
                        $display ($time, "\033[0;35m FT2232:\t<--- [STATE_IN_CMD] CMD_FPGA_STOPPED [payload bytes: %d]. \033[0;0m",
                                        fifo_data_i[3:0]);
`endif
                        // Bit [4] should be 1'b0 (CMD_FPGA_STOPPED has between 1 and 3 bytes of payload).
                        total_in_payload_bytes <= {12'b0, fifo_data_i[3:0]};
                        in_payload_bytes <= {12'b0, fifo_data_i[3:0]};
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

                in_last_cmd <= fifo_data_i[7:5];
            end

            STATE_IN_PAYLOAD_LENGTH: begin
                if (in_byte_in_word) begin
                    total_in_payload_bytes[7:0] <= fifo_data_i;
                    in_payload_bytes[7:0] <= fifo_data_i;
`ifdef D_FT2232
                    $display ($time, "\033[0;35m FT2232:\t<--- [STATE_IN_PAYLOAD_LENGTH] payload bytes: %d. \033[0;0m",
                                        {total_in_payload_bytes[15:8], fifo_data_i});
`endif

                    in_state_m <= STATE_IN_PAYLOAD;
                end else begin
                    total_in_payload_bytes[15:8] <= fifo_data_i;
                    in_payload_bytes[15:8] <= fifo_data_i;

                    in_byte_in_word <= 1'b1;
                end
            end

            STATE_IN_PAYLOAD: begin
 `ifdef D_FT2232
               case (in_last_cmd)
                    `CMD_FPGA_STOPPED: begin
                        case (total_in_payload_bytes - in_payload_bytes)
                            16'd0: begin
                                $display ($time, "\033[0;35m FT2232:\t<--- [STATE_IN_PAYLOAD for CMD_FPGA_STOPPED] Error code: %d. \033[0;0m",
                                                    fifo_data_i);
                                if (fifo_data_i == `TEST_ERROR_NONE) begin
                                    $display ($time, "\033[0;35m FT2232:\t==== TEST OK ====. \033[0;0m");
                                end else begin
                                    $display ($time, "\033[0;35m FT2232:\t==== TEST FAILED [code: %d] ====. \033[0;0m",
                                                    fifo_data_i);
                                end
                            end

                            16'd1: begin
                                $display ($time, "\033[0;35m FT2232:\t<--- [STATE_IN_PAYLOAD for CMD_FPGA_STOPPED] Value received: %d. \033[0;0m",
                                                    fifo_data_i);
                            end

                            16'd2: begin
                                $display ($time, "\033[0;35m FT2232:\t<--- [STATE_IN_PAYLOAD for CMD_FPGA_STOPPED] Value expected: %d. \033[0;0m",
                                                    fifo_data_i);
                            end

                            default: begin
                                $display ($time, "\033[0;35m FT2232:\t<--- [STATE_IN_PAYLOAD for CMD_FPGA_STOPPED] Invalid index: %d. \033[0;0m",
                                                    total_in_payload_bytes - in_payload_bytes);
                            end
                        endcase
`endif
                        in_payload_bytes <= in_payload_bytes - 16'd1;
                        if (in_payload_bytes == 16'd1) begin
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

                            in_payload_bytes <= in_payload_bytes - 16'd1;
                            if (in_payload_bytes == 16'd1) begin
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
                        // Looped back data is not checked.
                        in_payload_bytes <= in_payload_bytes - 16'd1;
                        if (in_payload_bytes == 16'd1) begin
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

            out_data <= 8'd0;
            in_data <= 8'd0;

            fifo_txe_n_o <= 1'b0;
            fifo_rxf_n_o <= 1'b1;

            start_sending_data <= 1'b1;
            send_data <= 1'b1;
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
