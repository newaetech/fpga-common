`timescale 1 ns / 1 ps
`default_nettype none

/***********************************************************************
This file is part of the ChipWhisperer Project. See www.newae.com for more
details, or the codebase at http://www.chipwhisperer.com

Copyright (c) 2022, NewAE Technology Inc. All rights reserved.
Author: Jean-Pierre Thibault <jpthibault@newae.com>

  chipwhisperer is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  chipwhisperer is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU Lesser General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with chipwhisperer.  If not, see <http://www.gnu.org/licenses/>.
*************************************************************************/

module fifos_cocowrapper(
    // sync fifo:
    input  wire                         clk, 
    input  wire                         rst_n,
    input  wire [31:0]                  full_threshold_value,
    input  wire [31:0]                  empty_threshold_value,
    input  wire                         wen, 
    input  wire [15:0]                  wdata,
    output wire                         full,
    output wire                         almost_full,
    output wire                         overflow,
    output wire                         full_threshold,
    input  wire                         ren, 
    output wire [15:0]                  rdata,
    output wire                         empty,
    output wire                         almost_empty,
    output wire                         underflow,
    output wire                         empty_threshold,

    input  wire                         rclk, 
    input  wire                         wclk, 

    // testbench stuff:
    input  wire [31:0]                  errors,
    input  wire [31:0]                  actual_fill_state,
    input  wire [24*8-1:0]              test_phase,
    output wire [31:0]                  xilinx_mismatches_out,
    output wire                         xilinx_mismatch
);


   parameter pDUMP = 0;
   parameter pFWFT = 0;
   parameter pDEPTH = 512;
   parameter pSYNC = 1;
   parameter pXILINX_FIFOS = 0;
   parameter pBRAM = 0;
   parameter pDISTRIBUTED = 0;
   parameter pFLOPS = 1;

   initial begin
      if (pDUMP) begin
          $dumpfile("results/fifos.fst");
          $dumpvars(0, fifos_cocowrapper);
      end
   end

   reg [31:0] xilinx_mismatch_rcount = 32'b0;
   reg [31:0] xilinx_mismatch_wcount = 32'b0;


generate
    if (pSYNC) begin : fifo_sync_instance
        fifo_sync #(
            .pDATA_WIDTH                (16),
            .pDEPTH                     (pDEPTH),
            .pFALLTHROUGH               (pFWFT),
            .pFLOPS                     (pFLOPS),
            .pBRAM                      (pBRAM),
            .pDISTRIBUTED               (pDISTRIBUTED)
        ) U_fifo_sync (
            .clk                        (clk                  ),
            .rst_n                      (rst_n                ),
            .full_threshold_value       (full_threshold_value ),
            .empty_threshold_value      (empty_threshold_value),
            .wen                        (wen                  ),
            .wdata                      (wdata                ),
            .full                       (full                 ),
            .almost_full                (almost_full          ),
            .overflow                   (overflow             ),
            .full_threshold             (full_threshold       ),
            .ren                        (ren                  ),
            .rdata                      (rdata                ),
            .empty                      (empty                ),
            .almost_empty               (almost_empty         ),
            .empty_threshold            (empty_threshold      ),
            .underflow                  (underflow            )
        );


    end

    else begin : fifo_async_instance
        fifo_async #(
            .pDATA_WIDTH                (16),
            .pDEPTH                     (512),
            .pFALLTHROUGH               (pFWFT),
            .pFLOPS                     (pFLOPS),
            .pBRAM                      (pBRAM),
            .pDISTRIBUTED               (pDISTRIBUTED)
        ) U_fifo_async (
            .wclk                       (wclk                 ),
            .rclk                       (rclk                 ),
            .wrst_n                     (rst_n                ),
            .rrst_n                     (rst_n                ),
            .wfull_threshold_value      (full_threshold_value ),
            .rempty_threshold_value     (empty_threshold_value),
            .wen                        (wen                  ),
            .wdata                      (wdata                ),
            .wfull                      (full                 ),
            .walmost_full               (almost_full          ),
            .woverflow                  (overflow             ),
            .wfull_threshold            (full_threshold       ),
            .ren                        (ren                  ),
            .rdata                      (rdata                ),
            .rempty                     (empty                ),
            .ralmost_empty              (almost_empty         ),
            .rempty_threshold           (empty_threshold      ),
            .runderflow                 (underflow            )
        );
    end

    if (pXILINX_FIFOS) begin: xilinx_instances
        wire xilinx_full;
        wire xilinx_almost_full;
        wire xilinx_overflow;
        wire xilinx_full_threshold;
        wire [15:0] xilinx_rdata;
        wire xilinx_empty;
        wire xilinx_almost_empty;
        wire xilinx_underflow;
        wire xilinx_empty_threshold;

        wire mismatch_full              = xilinx_full           !== full;
        wire mismatch_almost_full       = xilinx_almost_full    !== almost_full;
        wire mismatch_overflow          = xilinx_overflow       !== overflow;
        wire mismatch_full_threshold    = xilinx_full_threshold !== full_threshold;
        wire mismatch_rdata             = xilinx_rdata          !== rdata;
        wire mismatch_empty             = xilinx_empty          !== empty;
        wire mismatch_almost_empty      = xilinx_almost_empty   !== almost_empty;
        wire mismatch_underflow         = xilinx_underflow      !== underflow;
        wire mismatch_empty_threshold   = xilinx_empty_threshold!== empty_threshold;

        //reg mismatch_rdata;
        //always @(posedge rclk)
        //    mismatch_rdata <= xilinx_rdata !== rdata;

        // this is best for *visualizing* but stubbornly doesn't work well for
        // reporting mismatches from cocotb
        assign xilinx_mismatch = mismatch_full ||
                               //mismatch_almost_full ||
                               mismatch_overflow ||
                               mismatch_full_threshold ||
                               mismatch_rdata ||
                               mismatch_empty ||
                               //mismatch_almost_empty ||
                               mismatch_underflow ||
                               mismatch_empty_threshold;

        always @(posedge rclk) 
            if (mismatch_rdata ||
                mismatch_empty ||
                //mismatch_almost_empty ||
                mismatch_underflow ||
                mismatch_empty_threshold)
                xilinx_mismatch_rcount <= xilinx_mismatch_rcount + 1;

        always @(posedge wclk) 
            if (mismatch_full ||
                //mismatch_almost_full ||
                mismatch_overflow ||
                mismatch_full_threshold)
                xilinx_mismatch_wcount <= xilinx_mismatch_wcount + 1;

        if (pSYNC && pFWFT) begin : xilinx_sync_fwft
            xilinx_sync_fifo_fwft U_xilinx_fifo_sync (
                .clk                        (clk),
                .rst                        (~rst_n),
                .din                        (wdata),
                .wr_en                      (wen),
                .rd_en                      (ren),
                .dout                       (xilinx_rdata),
                .full                       (xilinx_full),
                .empty                      (xilinx_empty),
                .overflow                   (xilinx_overflow),
                .underflow                  (xilinx_underflow),
                .prog_full                  (xilinx_full_threshold),
                .prog_empty                 (xilinx_empty_threshold)
            );
        end

        else if (pSYNC && ~pFWFT) begin: xilinx_sync_normal
            xilinx_sync_fifo_standard U_xilinx_fifo_sync (
                .clk                        (clk),
                .rst                        (~rst_n),
                .din                        (wdata),
                .wr_en                      (wen),
                .rd_en                      (ren),
                .dout                       (xilinx_rdata),
                .full                       (xilinx_full),
                .empty                      (xilinx_empty),
                .overflow                   (xilinx_overflow),
                .underflow                  (xilinx_underflow),
                .prog_full                  (xilinx_full_threshold),
                .prog_empty                 (xilinx_empty_threshold)
            );
        end

        else if (~pSYNC && pFWFT) begin : xilinx_async_fwft
            xilinx_async_fifo_fwft U_xilinx_fifo_sync (
                .rd_clk                     (rclk),
                .wr_clk                     (wclk),
                .rst                        (~rst_n),
                .din                        (wdata),
                .wr_en                      (wen),
                .rd_en                      (ren),
                .dout                       (xilinx_rdata),
                .full                       (xilinx_full),
                .empty                      (xilinx_empty),
                .overflow                   (xilinx_overflow),
                .underflow                  (xilinx_underflow),
                .prog_full                  (xilinx_full_threshold),
                .prog_empty                 (xilinx_empty_threshold)
            );
        end

        else if (~pSYNC && ~pFWFT) begin : xilinx_async_normal
            xilinx_async_fifo_normal U_xilinx_fifo_sync (
                .rd_clk                     (rclk),
                .wr_clk                     (wclk),
                .rst                        (~rst_n),
                .din                        (wdata),
                .wr_en                      (wen),
                .rd_en                      (ren),
                .dout                       (xilinx_rdata),
                .full                       (xilinx_full),
                .empty                      (xilinx_empty),
                .overflow                   (xilinx_overflow),
                .underflow                  (xilinx_underflow),
                .prog_full                  (xilinx_full_threshold),
                .prog_empty                 (xilinx_empty_threshold)
            );
        end
    end

    else begin: no_xilinx
        assign xilinx_mismatch = 1'b0;
    end

    assign xilinx_mismatches_out = xilinx_mismatch_rcount + xilinx_mismatch_wcount;


endgenerate
        


endmodule
`default_nettype wire
