`timescale 1 ns / 1 ps
`default_nettype none

/***********************************************************************
This file is part of the ChipWhisperer Project. See www.newae.com for more
details, or the codebase at http://www.chipwhisperer.com

This code originates from:
Cummings, Clifford E., and Don Mills. "Synchronous Resets? Asynchronous Resets?
I am so confused! How will I ever know which to use?." SNUG 2002 (Synopsys
Users Group Conference, San Jose, CA, 2002) User Papers. 2002.
Edited for style.

*************************************************************************/

module async_resetFFstyle2 (
    input  wire clk, 
    input  wire asyncrst_n,
    output reg  rst_n
);

    reg rff1;

    always @(posedge clk or negedge asyncrst_n) begin
        if (!asyncrst_n) 
            {rst_n,rff1} <= 2'b0;
        else 
            {rst_n,rff1} <= {rff1,1'b1};
    end

endmodule

`default_nettype wire

