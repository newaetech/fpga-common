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
    input  wire [31:0]                  full_threshold_value, // TODO: connect to testbench
    input  wire [31:0]                  empty_threshold_value, // TODO: connect to testbench
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
    input  wire [24*8-1:0]              test_phase
);


   parameter pDUMP = 0;
   parameter pFWFT = 0;
   parameter pSYNC = 1;

   initial begin
      if (pDUMP) begin
          $dumpfile("results/fifos.fst");
          $dumpvars(0, fifos_cocowrapper);
      end
   end


generate
    if (pSYNC) begin : fifo_sync_instance
        fifo_sync #(
            .pDATA_WIDTH                (16),
            .pDEPTH                     (512),
            .pFALLTHROUGH               (pFWFT),
            .pFLOPS                     (1),
            .pBRAM                      (0),
            .pDISTRIBUTED               (0)
        ) U_fifo_sync (
            .clk                        (clk                  ),
            .rst_n                      (rst_n                ),
            .full_threshold_value       (32'd384              ),
            .empty_threshold_value      (32'd128              ),
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
            .pFLOPS                     (1),
            .pBRAM                      (0),
            .pDISTRIBUTED               (0)
        ) U_fifo_async (
            .wclk                       (wclk                 ),
            .rclk                       (rclk                 ),
            .wrst_n                     (rst_n                ),
            .rrst_n                     (rst_n                ),
            .wfull_threshold_value      (32'd384              ),
            .rempty_threshold_value     (32'd128              ),
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
endgenerate
        


endmodule
`default_nettype wire
