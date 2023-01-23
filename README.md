This repository contains Verilog modules that are common to multiple NewAE
projects.

# Notes regarding FIFOs
These FIFOs were developed to overcome issues with simulating the Xilinx FIFOs
with the Icarus Verilog simulator. They are not (yet) intended to be a full
replacement for Xilinx FIFOs in implementation. Tests show that the Xilinx
FIFOs result in better resource utilization and timing closure. However,
these FIFOs simulate *much* faster than the Xilinx ones.

The [fifo\_sync](hdl/fifo_sync.v) module aims to have the exact same
behaviour as the Xilinx synchronous FIFO, and while there is some limited
testing for this, this is not exhaustively tested or proven (yet).

The [fifo\_async](hdl/fifo_async.v) currently does *not* have the same
behaviour as the Xilinx asynchronous FIFO (i.e. in terms of timing of its
empty/full status signals).

