# --------------------------------------------------
# Document:  Makefile
# Project:   PJON_ASIC/PJON-HW
# Function:  Makefile for the PJON-HW implemenation
# Autor:     Pius Sieber
# Date:      31.03.2025
# Comments:  mostly copied from the pulp-croc-project, original file by "Philippe Sauter"
# --------------------------------------------------

# Tools
BENDER	  ?= bender
PYTHON3   ?= python3
VERILATOR ?= /foss/tools/bin/verilator
REGGEN    ?= $(PYTHON3) $(shell $(BENDER) path register_interface)/vendor/lowrisc_opentitan/util/regtool.py

# Directories
# directory of the path to the last called Makefile (this one)
PROJ_DIR  := $(realpath $(dir $(realpath $(lastword $(MAKEFILE_LIST)))))


default: help

################
# Dependencies #
################
## Checkout/update dependencies using Bender
checkout:
	$(BENDER) checkout
	git submodule update --init --recursive

## Reset dependencies (without updating Bender.lock)
clean-deps:
	rm -rf .bender
	git submodule deinit -f --all

.PHONY: checkout clean-deps


##################
# RTL Simulation #
##################
# Questasim/Modelsim/vsim
VLOG_ARGS  = -svinputport=compat
VSIM_ARGS  = -t 1ns -voptargs=+acc
VSIM_ARGS += -suppress vsim-3009 -suppress vsim-8683 -suppress vsim-8386

vsim/compile_rtl.tcl: Bender.lock Bender.yml
	$(BENDER) script vsim -t rtl -t vsim -t simulation -t verilator -DSYNTHESIS -DSIMULATION  --vlog-arg="$(VLOG_ARGS)" > $@

vsim/compile_netlist.tcl: Bender.lock Bender.yml
	$(BENDER) script vsim -t ihp13 -t vsim -t simulation -t verilator -t netlist_yosys -DSYNTHESIS -DSIMULATION > $@


# Verilator
VERILATOR_ARGS  = --binary -j 0 -Wno-fatal
VERILATOR_ARGS += -Wno-style
VERILATOR_ARGS += --timing --autoflush --trace --trace-structs --trace-depth 100 --assert

verilator/pjdl.f: Bender.lock Bender.yml
	$(BENDER) script verilator -t rtl -t verilator -DSYNTHESIS -DVERILATOR > $@

## Simulate RTL using Verilator
verilator/obj_dir/Vtb_pjdl: verilator/pjdl.f tb_pjdl.sv
	cd verilator; $(VERILATOR) $(VERILATOR_ARGS) -CFLAGS "-O0" --top tb_pjdl -f pjdl.f

verilator: verilator/obj_dir/Vtb_pjdl
	cd verilator; obj_dir/Vtb_pjdl

.PHONY: verilator vsim vsim-yosys verilator-yosys


#################
# Documentation #
#################

help: Makefile
	@printf "Available targets:\n------------------\n"
	@for mkfile in $(MAKEFILE_LIST); do \
		awk '/^[a-zA-Z\-\_0-9]+:/ { \
			helpMessage = match(lastLine, /^## (.*)/); \
			if (helpMessage) { \
				helpCommand = substr($$1, 0, index($$1, ":")-1); \
				helpMessage = substr(lastLine, RSTART + 3, RLENGTH); \
				printf "%-20s %s\n", helpCommand, helpMessage; \
			} \
		} \
		{ lastLine = $$0 }' $$mkfile; \
	done

.PHONY: help


###########
# Cleanup #
###########

clean: 
	rm -f $(SV_FLIST)
	rm -rf verilator/obj_dir/
	rm -f verilator/pjdl.f
	rm -f verilator/pdjl.vcd
	$(MAKE) ys_clean
	$(MAKE) or_clean

.PHONY: clean
