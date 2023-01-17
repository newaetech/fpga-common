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
	-P fifos_cocowrapper.pSYNC=$(SYNC) \
	-o $(EXEFILE) \
	/$(VIVADO_PATH)/$(VIVADO_VERSION)/ids_lite/ISE/verilog/src/glbl.v \
	../hdl/fifo_sync.v \
	../hdl/fifo_async.v \
	fifos_cocowrapper.v \

lint:
	verilator --lint-only -Wall \
	--error-limit 0 \
	-Wno-PINCONNECTEMPTY \
	-Wno-ASSIGNDLY \
	-f cmdfile_coco_nofifo \
	-D__ICARUS__ \
	--top-module cwhusky_cw310_top \
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
