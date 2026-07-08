VERILATOR ?= verilator
CXXFLAGS += -std=c++11 -O2

CORE_TOP = mips_core
CORE_EXE = obj_dir/V$(CORE_TOP)
BUS_TOP = soc_bus
BUS_EXE = obj_dir/V$(BUS_TOP)

.PHONY: all core-sample isa-directed lab1 kernel-c3 soc-bus clean

all: core-sample isa-directed lab1 soc-bus

$(CORE_EXE): mips_core_sim.cpp ../src/soc/mips_core.v
	$(VERILATOR) --cc --exe -Wall -Wno-fatal --top-module $(CORE_TOP) \
		-CFLAGS "$(CXXFLAGS)" ../src/soc/mips_core.v mips_core_sim.cpp
	$(MAKE) -C obj_dir -f V$(CORE_TOP).mk

$(BUS_EXE): soc_bus_sim.cpp ../src/soc/soc_bus.v ../src/soc/async.v
	$(VERILATOR) --cc --exe -Wall -Wno-fatal --top-module $(BUS_TOP) \
		-CFLAGS "$(CXXFLAGS)" ../src/soc/soc_bus.v ../src/soc/async.v soc_bus_sim.cpp
	$(MAKE) -C obj_dir -f V$(BUS_TOP).mk

core-sample: $(CORE_EXE) ../asm/user-sample.bin
	TRACE=$(TRACE) $(CORE_EXE) ../asm/user-sample.bin

isa-directed: $(CORE_EXE) ../asm/isa-directed.bin
	TRACE=$(TRACE) $(CORE_EXE) ../asm/isa-directed.bin

lab1: $(CORE_EXE) ../asm/lab1.bin
	TRACE=$(TRACE) $(CORE_EXE) ../asm/lab1.bin

kernel-c3: $(CORE_EXE) ../asm/c3-user.bin
	TRACE=$(TRACE) $(CORE_EXE) /home/luoshuang/下载/kernel.bin ../asm/c3-user.bin

soc-bus: $(BUS_EXE)
	$(BUS_EXE)

clean:
	rm -rf obj_dir
