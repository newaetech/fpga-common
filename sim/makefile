LOGFILE=make.log
EXEFILE=a.out
WAVEFORMAT=fst
SEED=1
TIMEOUT_CYCLES=50000
DUMP=0
COCOTB_LOG_LEVEL=INFO
VIVADO_VERSION=2020.2
FIFOTEST=1
FWFT=0
SYNC=1
DEPTH=512
BRAM=0
DISTRIBUTED=0
FLOPS=1
XILINX_FIFOS=0

all: compile run

ifeq ($(VIVADO_PATH),)
  ifeq ($(OS), Windows_NT)
    VIVADO_PATH=/mnt/c/Xilinx/Vivado/
  else
    UNAME_S := $(shell uname -s)
    ifeq ($(UNAME_S),Linux)
      VIVADO_PATH=/tools/Xilinx/Vivado/
    endif
    ifeq ($(UNAME_S),Darwin)
      VIVADO_PATH=$(HOME)/tools/Xilinx/Vivado/
    endif
  endif
endif

compile:
	iverilog -g2005-sv \
	-gsupported-assertions \
	-y/$(VIVADO_PATH)/$(VIVADO_VERSION)/ids_lite/ISE/verilog/src/unisims/ \
	-s fifos_cocowrapper \
	-s glbl \
	-Wportbind \
	-Wselect-range \
	-DCOCOTB_SIM=1 \
	-P fifos_cocowrapper.pDUMP=$(DUMP) \
	-P fifos_cocowrapper.pFWFT=$(FWFT) \
	-P fifos_cocowrapper.pDEPTH=$(DEPTH) \
	-P fifos_cocowrapper.pSYNC=$(SYNC) \
	-P fifos_cocowrapper.pBRAM=$(BRAM) \
	-P fifos_cocowrapper.pDISTRIBUTED=$(DISTRIBUTED) \
	-P fifos_cocowrapper.pFLOPS=$(FLOPS) \
	-P fifos_cocowrapper.pXILINX_FIFOS=$(XILINX_FIFOS) \
	-o $(EXEFILE) \
	../hdl/fifo_sync.v \
	../hdl/fifo_async.v \
	../vivado/xilinx_sync_fifo_standard_sim_netlist.v \
	../vivado/xilinx_sync_fifo_fwft_sim_netlist.v \
	../vivado/xilinx_async_fifo_fwft_sim_netlist.v \
	../vivado/xilinx_async_fifo_normal_sim_netlist.v \
	../vivado/xpm_memory.sv \
	fifos_cocowrapper.v \

lint:
	verilator --lint-only -Wall \
	--error-limit 0 \
	-Wno-PINCONNECTEMPTY \
	-Wno-MULTITOP \
	../hdl/fifo_sync.v \
	../hdl/fifo_async.v \
	../hdl/cdc_pulse.v \
	../hdl/cdc_bus.v \
	../hdl/cdc_simple.v \
	-D__ICARUS__ \
	2>&1 | tee lint.out \

# note that -M and -m arguments must immediately follow vvp, otherwise Python doesn't start!
run:
	COCOTB_RESOLVE_X=RANDOM \
	TOPLEVEL=fifos_cocowrapper \
	TOPLEVEL_LANG=verilog \
	FIFOTEST=$(FIFOTEST) \
	MODULE=test_fifo \
	COCOTB_LOG_LEVEL=$(COCOTB_LOG_LEVEL) \
	LIBPYTHON_LOC=$(shell cocotb-config --libpython) \
	vvp -M $(shell cocotb-config --lib-dir) \
	-m $(shell cocotb-config --lib-name vpi icarus) \
	-l$(LOGFILE) $(EXEFILE) -$(WAVEFORMAT) \

clean:
	rm -f a.out results/*.vvp
