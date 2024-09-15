/***********************************************************************************************************************
 * Source: https://github.com/dpretet/async_fifo/tree/master/rtl
 * Modified by Virgil Dobjanschi dobjanschivirgil@gmail.com to have all functionality in one file.
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
 * This module implements the dual port FIFO.
 **********************************************************************************************************************/
`timescale 1ps/1ps
`default_nettype none

//==================================================================================================================
// Dual port FIFO.
//==================================================================================================================
module async_fifo #(parameter DSIZE = 8, parameter ASIZE = 8, parameter FALLTHROUGH = "TRUE")(
        // Write
        input  wire             wr_clk_i,
        input  wire             wr_reset_i,
        input  wire             wr_en_i,
        input  wire [DSIZE-1:0] wr_data_i,
        output wire             wr_full_o,
        output wire             wr_awfull_o,
        // Read
        input  wire             rd_clk_i,
        input  wire             rd_reset_i,
        input  wire             rd_en_i,
        output wire [DSIZE-1:0] rd_data_o,
        output wire             rd_empty_o,
        output wire             rd_arempty_o);

    wire [ASIZE-1:0] waddr, raddr;
    wire [ASIZE  :0] wptr, rptr, wq2_rptr, rq2_wptr;

    sync_r2w #(ASIZE) sync_r2w (
        .wq2_rptr (wq2_rptr),
        .rptr     (rptr),
        .wclk     (wr_clk_i),
        .wrst_n   (~wr_reset_i));

    sync_w2r #(ASIZE) sync_w2r (
        .rq2_wptr (rq2_wptr),
        .wptr     (wptr),
        .rclk     (rd_clk_i),
        .rrst_n   (~rd_reset_i));

    wptr_full #(ASIZE) wptr_full (
        .awfull   (wr_awfull_o),
        .wfull    (wr_full_o),
        .waddr    (waddr),
        .wptr     (wptr),
        .wq2_rptr (wq2_rptr),
        .winc     (wr_en_i),
        .wclk     (wr_clk_i),
        .wrst_n   (~wr_reset_i));

    fifomem #(DSIZE, ASIZE, FALLTHROUGH) fifomem (
        .rclken   (rd_en_i),
        .rclk     (rd_clk_i),
        .rdata    (rd_data_o),
        .rempty   (rd_empty_o),
        .wdata    (wr_data_i),
        .waddr    (waddr),
        .raddr    (raddr),
        .wclken   (wr_en_i),
        .wfull    (wr_full_o),
        .wclk     (wr_clk_i));

    rptr_empty #(ASIZE) rptr_empty (
        .arempty  (rd_arempty_o),
        .rempty   (rd_empty_o),
        .raddr    (raddr),
        .rptr     (rptr),
        .rq2_wptr (rq2_wptr),
        .rinc     (rd_en_i),
        .rclk     (rd_clk_i),
        .rrst_n   (~rd_reset_i));

endmodule

//==================================================================================================================
// The module synchronizing the read point from read to write domain
//==================================================================================================================
module sync_r2w #(parameter ASIZE = 4)(
    input  wire           wclk,
    input  wire           wrst_n,
    input  wire [ASIZE:0] rptr,
    output reg  [ASIZE:0] wq2_rptr);

    reg [ASIZE:0] wq1_rptr;

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
`ifdef D_FIFO
            $display ($time, " FIFO:\t-- Wr reset.");
`endif
            {wq2_rptr, wq1_rptr} <= 0;
        end else begin
            {wq2_rptr, wq1_rptr} <= {wq1_rptr, rptr};
        end
    end
endmodule

//==================================================================================================================
// The module synchronizing the write point from write to read domain
//==================================================================================================================
module sync_w2r #(parameter ASIZE = 4)(
    input  wire           rclk,
    input  wire           rrst_n,
    output reg  [ASIZE:0] rq2_wptr,
    input  wire [ASIZE:0] wptr);

    reg [ASIZE:0] rq1_wptr;

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
`ifdef D_FIFO
            $display ($time, " FIFO:\t-- Rd reset.");
`endif
            {rq2_wptr, rq1_wptr} <= 0;
        end else begin
            {rq2_wptr, rq1_wptr} <= {rq1_wptr, wptr};
        end
    end
endmodule

//==================================================================================================================
// The module handling read requests
//==================================================================================================================
module rptr_empty #(parameter ADDRSIZE = 4)(
    input  wire                rclk,
    input  wire                rrst_n,
    input  wire                rinc,
    input  wire [ADDRSIZE  :0] rq2_wptr,
    output reg                 rempty,
    output reg                 arempty,
    output wire [ADDRSIZE-1:0] raddr,
    output reg  [ADDRSIZE  :0] rptr);

    reg  [ADDRSIZE:0] rbin;
    wire [ADDRSIZE:0] rgraynext, rbinnext, rgraynextm1;
    wire              arempty_val, rempty_val;

    //-------------------
    // GRAYSTYLE2 pointer
    //-------------------
    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) {rbin, rptr} <= 0;
        else {rbin, rptr} <= {rbinnext, rgraynext};
    end

    // Memory read-address pointer (okay to use binary to address memory)
    assign raddr     = rbin[ADDRSIZE-1:0];
    assign rbinnext  = rbin + (rinc & ~rempty);
    assign rgraynext = (rbinnext >> 1) ^ rbinnext;
    assign rgraynextm1 = ((rbinnext + 1'b1) >> 1) ^ (rbinnext + 1'b1);

    //---------------------------------------------------------------
    // FIFO empty when the next rptr == synchronized wptr or on reset
    //---------------------------------------------------------------
    assign rempty_val = (rgraynext == rq2_wptr);
    assign arempty_val = (rgraynextm1 == rq2_wptr);

    always @ (posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            arempty <= 1'b0;
            rempty <= 1'b1;
        end else begin
            arempty <= arempty_val;
            rempty <= rempty_val;

`ifdef D_FIFO
            if (rempty_val && ~rempty) begin
                $display ($time, " FIFO:\tFIFO is empty.");
            end
`endif
        end
    end
endmodule

//==================================================================================================================
// The module handling the write requests
//==================================================================================================================
module wptr_full #(parameter ADDRSIZE = 4)(
        input  wire                wclk,
        input  wire                wrst_n,
        input  wire                winc,
        input  wire [ADDRSIZE  :0] wq2_rptr,
        output reg                 wfull,
        output reg                 awfull,
        output wire [ADDRSIZE-1:0] waddr,
        output reg  [ADDRSIZE  :0] wptr);

    reg  [ADDRSIZE:0] wbin;
    wire [ADDRSIZE:0] wgraynext, wbinnext, wgraynextp1;
    wire              awfull_val, wfull_val;

    // GRAYSTYLE2 pointer
    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) {wbin, wptr} <= 0;
        else {wbin, wptr} <= {wbinnext, wgraynext};
    end

    // Memory write-address pointer (okay to use binary to address memory)
    assign waddr = wbin[ADDRSIZE-1:0];
    assign wbinnext  = wbin + (winc & ~wfull);
    assign wgraynext = (wbinnext >> 1) ^ wbinnext;
    assign wgraynextp1 = ((wbinnext + 1'b1) >> 1) ^ (wbinnext + 1'b1);

    //------------------------------------------------------------------
    // Simplified version of the three necessary full-tests:
    // assign wfull_val=((wgnext[ADDRSIZE] !=wq2_rptr[ADDRSIZE] ) &&
    //                   (wgnext[ADDRSIZE-1]  !=wq2_rptr[ADDRSIZE-1]) &&
    // (wgnext[ADDRSIZE-2:0]==wq2_rptr[ADDRSIZE-2:0]));
    //------------------------------------------------------------------
    assign wfull_val = (wgraynext == {~wq2_rptr[ADDRSIZE:ADDRSIZE-1], wq2_rptr[ADDRSIZE-2:0]});
    assign awfull_val = (wgraynextp1 == {~wq2_rptr[ADDRSIZE:ADDRSIZE-1], wq2_rptr[ADDRSIZE-2:0]});

    always @(posedge wclk or negedge wrst_n) begin

        if (!wrst_n) begin
            awfull <= 1'b0;
            wfull  <= 1'b0;
        end else begin
            awfull <= awfull_val;
            wfull  <= wfull_val;

`ifdef D_FIFO
            if (awfull_val && ~awfull) begin
                $display ($time, " FIFO:\tFIFO is almost full.");
            end
            if (wfull_val && ~wfull) begin
                $display ($time, " FIFO:\tFIFO is full.");
            end
`endif
        end
    end
endmodule

//==================================================================================================================
// The DC-RAM
//==================================================================================================================
module fifomem #(
        parameter  DATASIZE = 8,            // Memory data word width
        parameter  ADDRSIZE = 4,            // Number of mem address bits
        parameter  FALLTHROUGH = "TRUE")(   // First word fall-through
        input  wire                wclk,
        input  wire                wclken,
        input  wire [ADDRSIZE-1:0] waddr,
        input  wire [DATASIZE-1:0] wdata,
        input  wire                wfull,
        input  wire                rclk,
        input  wire                rclken,
        input  wire [ADDRSIZE-1:0] raddr,
        input  wire                rempty,
        output wire [DATASIZE-1:0] rdata);

    localparam DEPTH = 1<<ADDRSIZE;

    reg [DATASIZE-1:0] mem [0:DEPTH-1];
    reg [DATASIZE-1:0] rdata_r;

    always @(posedge wclk) begin
        if (wclken && !wfull) begin
            mem[waddr] <= wdata;
`ifdef D_FIFO
            $display ($time, " FIFO:\tWr: %d @%h.", wdata, raddr);
`endif
        end

`ifdef D_FIFO
        if (wclken && wfull) begin
            $display ($time, " FIFO:\t==== Cannot write: %d.", wdata);
        end
`endif
    end

    generate
        if (FALLTHROUGH == "TRUE")
        begin : fallthrough
            assign rdata = rclken ? mem[raddr] : 8'hbb;
`ifdef D_FIFO
            always @(posedge rclk) begin
                if (rclken && ~rempty) begin
                    $display ($time, " FIFO:\tRd: %d.", mem[raddr]);
                end
            end
`endif
        end
        else
        begin : registered_read
            always @(posedge rclk) begin
                if (rclken && ~rempty) begin
                    rdata_r <= mem[raddr];
`ifdef D_FIFO
                    $display ($time, " FIFO:\tRd: %d @%h.", mem[raddr], raddr);
`endif
                end
            end
            assign rdata = rdata_r;
        end
    endgenerate
endmodule

