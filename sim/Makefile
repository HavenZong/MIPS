VERILATOR ?= verilator
CXXFLAGS += -std=c++11 -O2

CORE_TOP = mips_core
CORE_EXE = obj_dir/V$(CORE_TOP)

.PHONY: all core-sample isa-directed clean

all: core-sample isa-directed

$(CORE_EXE): mips_core_sim.cpp ../src/soc/mips_core.v
	$(VERILATOR) --cc --exe -Wall -Wno-fatal --top-module $(CORE_TOP) \
		-CFLAGS "$(CXXFLAGS)" ../src/soc/mips_core.v mips_core_sim.cpp
	$(MAKE) -C obj_dir -f V$(CORE_TOP).mk

core-sample: $(CORE_EXE) ../asm/user-sample.bin
	TRACE=$(TRACE) $(CORE_EXE) ../asm/user-sample.bin

isa-directed: $(CORE_EXE) ../asm/isa-directed.bin
	TRACE=$(TRACE) $(CORE_EXE) ../asm/isa-directed.bin

clean:
	rm -rf obj_dir
