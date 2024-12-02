`timescale 1 ns / 1 ps
`default_nettype none
//======================================================================
// Derived from Joachim Strombergson's uart_core.v; recoded to Rx only,
// simplified (coding style-wise), and optimized for better timing closure.
//
// Author: Joachim Strombergson
// Copyright (c) 2014, NORDUnet A/S
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
// - Redistributions of source code must retain the above copyright notice,
//   this list of conditions and the following disclaimer.
//
// - Redistributions in binary form must reproduce the above copyright
//   notice, this list of conditions and the following disclaimer in the
//   documentation and/or other materials provided with the distribution.
//
// - Neither the name of the NORDUnet nor the names of its contributors may
//   be used to endorse or promote products derived from this software
//   without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
// IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
// TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
// PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
// TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
// PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
// LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
// NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
// *** summary of NewAE modifications:
// - change FSM coding style
// - support parity detection
// - support 9 data bits
// - optionally don't report received data when there is a parity error
// - remove Tx code
// - timing closure optimizations
//
//======================================================================

module uart_rx(
    input wire          clk,
    input wire          reset_n,

    input wire [15:0]   bit_rate,
    input wire [3:0]    data_bits,
    input wire [1:0]    stop_bits,
    input wire          parity_bit,
    input wire          parity_enabled,
    input wire          parity_accept_errors,

    input wire          rxd,

    output reg [8:0]    data,
    output wire         syn,
    input wire          ack,

    output wire [2:0]   state
);

/* 
NOTE: the signal widths above work for our use cases, but should be
parameterized at some point.
max bit_rate value supported: 1 / min baud rate / min clock period.
*/

    parameter pS_IDLE   = 0;
    parameter pS_START  = 1;
    parameter pS_BITS   = 2;
    parameter pS_STOP   = 3;
    parameter pS_SYN    = 4;
    parameter pS_PARITY = 5;

    reg rxd_reg;
    reg [4:0] bit_ctr;
    reg [15:0] bitrate_ctr;
    reg [2:0] state_reg = pS_IDLE;
    reg parity_bad;
    reg syn_reg = 1'b0;
    reg reset_bitrate_ctr = 1'b0;

    wire [15:0] half_bit_rate = {1'b0, bit_rate[15:1]};
    reg  [15:0] stop_bits_total;
    assign state = state_reg;
    assign syn = syn_reg;


    always @ (posedge clk) begin
        rxd_reg <= rxd;
        stop_bits_total <= bit_rate * stop_bits;
        if (state_reg == pS_IDLE)
            bitrate_ctr <= 0;
        else if (reset_bitrate_ctr)
            bitrate_ctr <= 1;
        else
            bitrate_ctr <= bitrate_ctr + 1;

        case (state_reg)
            pS_IDLE: begin
                syn_reg <= 1'b0;
                parity_bad <= 1'b0;
                reset_bitrate_ctr <= 1'b0;
                if (!rxd_reg) begin // Possible start bit detected.
                    bit_ctr <= 0;
                    state_reg <= pS_START;
                end
            end

            pS_START: begin
                data <= 9'b0;
                if (rxd_reg) 
                    state_reg <= pS_IDLE; // Just a glitch
                else if (bitrate_ctr == half_bit_rate) begin
                    // start bit assumed. We start sampling data.
                    reset_bitrate_ctr <= 1'b1;
                    bit_ctr <= 0;
                    state_reg <= pS_BITS;
                end
            end


            pS_BITS: begin
                if (bitrate_ctr == bit_rate) begin
                    reset_bitrate_ctr <= 1'b1;
                    data <= {rxd_reg, data[8:1]};
                    bit_ctr <= bit_ctr + 1;
                    if (bit_ctr == data_bits - 1) begin
                        if (parity_enabled)
                            state_reg <= pS_PARITY;
                        else
                            state_reg <= pS_STOP;
                    end
                end
                else
                    reset_bitrate_ctr <= 1'b0;
            end

            pS_PARITY: begin
                if (bitrate_ctr == bit_rate) begin
                    reset_bitrate_ctr <= 1'b1;
                    state_reg <= pS_STOP;
                    if (^{data, rxd_reg} != parity_bit)
                        parity_bad <= 1;
                end
                else
                    reset_bitrate_ctr <= 1'b0;
            end

            pS_STOP: begin
                if (parity_bad && ~parity_accept_errors)
                    state_reg <= pS_IDLE;
                else begin
                    if (bitrate_ctr == stop_bits_total) begin
                        reset_bitrate_ctr <= 1'b1;
                        syn_reg <= 1'b1;
                        state_reg <= pS_SYN;
                    end
                    else
                        reset_bitrate_ctr <= 1'b0;
                end
            end

            pS_SYN: begin
                if (ack) begin
                    syn_reg <= 1'b0;
                    state_reg <= pS_IDLE;
                end 
            end

        endcase
    end


    `ifdef ILA_UART_CORE
       ila_uart_core U_uart_ila (
        .clk            (clk),                          // input wire clk
        .probe0         (rxd),                          // input wire [0:0]  probe0  
        .probe1         (state_reg),                    // input wire [2:0]  probe1 
        .probe2         (syn),                          // input wire [0:0]  probe2 
        .probe3         (data),                         // input wire [8:0]  probe3 
        .probe4         (parity_bit),                   // input wire [0:0]  probe4 
        .probe5         (parity_enabled),               // input wire [0:0]  probe5 
        .probe6         (parity_accept_errors),         // input wire [0:0]  probe6 
        .probe7         (parity_bad),                   // input wire [0:0]  probe7 
        .probe8         (1'b0)                          // input wire [0:0]  probe8 
       );
    `endif

endmodule

`default_nettype wire

