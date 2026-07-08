VERILATOR ?= verilator
CXXFLAGS += -std=c++11 -O2
KERNEL_C3_BIN ?= /home/luoshuang/下载/kernel.bin

CORE_TOP = mips_core
CORE_EXE = obj_dir/V$(CORE_TOP)
BUS_TOP = soc_bus
BUS_EXE = obj_dir/V$(BUS_TOP)
SYSTEM_TOP = soc_system_tb
SYSTEM_EXE = obj_dir/V$(SYSTEM_TOP)
SYSTEM_REAL_UART_EXE = obj_dir/V$(SYSTEM_TOP)_real_uart

.PHONY: all core-sample isa-directed lab1 perf-matrix cryptonight kernel-c3 kernel-perf soc-bus soc-system soc-system-perf soc-system-real-uart clean

all: core-sample isa-directed lab1 soc-bus

$(CORE_EXE): mips_core_sim.cpp ../src/soc/mips_core.v
	$(VERILATOR) --cc --exe -Wall -Wno-fatal --top-module $(CORE_TOP) \
		-CFLAGS "$(CXXFLAGS)" ../src/soc/mips_core.v mips_core_sim.cpp
	$(MAKE) -C obj_dir -f V$(CORE_TOP).mk

$(BUS_EXE): soc_bus_sim.cpp ../src/soc/soc_bus.v ../src/soc/async.v
	$(VERILATOR) --cc --exe -Wall -Wno-fatal --top-module $(BUS_TOP) \
		-CFLAGS "$(CXXFLAGS)" ../src/soc/soc_bus.v ../src/soc/async.v soc_bus_sim.cpp
	$(MAKE) -C obj_dir -f V$(BUS_TOP).mk

$(SYSTEM_EXE): soc_system_sim.cpp soc_system_tb.v ../src/soc/mips_core.v ../src/soc/soc_bus.v ../src/soc/async.v
	$(VERILATOR) --cc --exe -Wall -Wno-fatal -DSIMULATION --top-module $(SYSTEM_TOP) \
		-CFLAGS "$(CXXFLAGS) -DFAST_UART" soc_system_tb.v ../src/soc/mips_core.v ../src/soc/soc_bus.v ../src/soc/async.v soc_system_sim.cpp
	$(MAKE) -C obj_dir -f V$(SYSTEM_TOP).mk

$(SYSTEM_REAL_UART_EXE): soc_system_sim.cpp soc_system_tb.v ../src/soc/mips_core.v ../src/soc/soc_bus.v ../src/soc/async.v
	$(VERILATOR) --cc --exe -Wall -Wno-fatal --top-module $(SYSTEM_TOP) \
		-CFLAGS "$(CXXFLAGS)" -Mdir obj_dir_real_uart soc_system_tb.v ../src/soc/mips_core.v ../src/soc/soc_bus.v ../src/soc/async.v soc_system_sim.cpp
	$(MAKE) -C obj_dir_real_uart -f V$(SYSTEM_TOP).mk
	mkdir -p obj_dir
	cp obj_dir_real_uart/V$(SYSTEM_TOP) $(SYSTEM_REAL_UART_EXE)

core-sample: $(CORE_EXE) ../asm/user-sample.bin
	TRACE=$(TRACE) $(CORE_EXE) ../asm/user-sample.bin

isa-directed: $(CORE_EXE) ../asm/isa-directed.bin
	TRACE=$(TRACE) $(CORE_EXE) ../asm/isa-directed.bin

lab1: $(CORE_EXE) ../asm/lab1.bin
	TRACE=$(TRACE) $(CORE_EXE) ../asm/lab1.bin

perf-matrix: $(CORE_EXE) ../asm/perf-matrix.bin
	unzip -p /home/luoshuang/下载/supervisor_mips.zip supervisor_mips/utility/matrix.in > /tmp/matrix.in
	unzip -p /home/luoshuang/下载/supervisor_mips.zip supervisor_mips/utility/matrix.out > /tmp/matrix.out
	TRACE=$(TRACE) $(CORE_EXE) ../asm/perf-matrix.bin

cryptonight: $(CORE_EXE) ../asm/cryptonight.bin
	TRACE=$(TRACE) BUS_DELAY=$(BUS_DELAY) $(CORE_EXE) ../asm/cryptonight.bin

kernel-c3: $(CORE_EXE) ../asm/c3-user.bin
	TRACE=$(TRACE) $(CORE_EXE) "$(KERNEL_C3_BIN)" ../asm/c3-user.bin

kernel-perf: $(CORE_EXE) ../asm/perf-matrix.bin
	unzip -p /home/luoshuang/下载/supervisor_mips.zip supervisor_mips/utility/matrix.in > /tmp/matrix.in
	unzip -p /home/luoshuang/下载/supervisor_mips.zip supervisor_mips/utility/matrix.out > /tmp/matrix.out
	TRACE=$(TRACE) $(CORE_EXE) "$(KERNEL_C3_BIN)" ../asm/perf-matrix.bin

soc-bus: $(BUS_EXE)
	$(BUS_EXE)

soc-system: $(SYSTEM_EXE)
	od -An -tx4 -v "$(KERNEL_C3_BIN)" > /tmp/kernel_mips.hex
	$(SYSTEM_EXE)

soc-system-perf: $(SYSTEM_EXE)
	unzip -p /home/luoshuang/下载/supervisor_mips.zip supervisor_mips/utility/matrix.in > /tmp/matrix.in
	unzip -p /home/luoshuang/下载/supervisor_mips.zip supervisor_mips/utility/matrix.out > /tmp/matrix.out
	od -An -tx4 -v "$(KERNEL_C3_BIN)" > /tmp/kernel_mips.hex
	$(SYSTEM_EXE) ../asm/perf-matrix.bin +EXT_HEX=/tmp/matrix.in

soc-system-real-uart: $(SYSTEM_REAL_UART_EXE)
	od -An -tx4 -v "$(KERNEL_C3_BIN)" > /tmp/kernel_mips.hex
	$(SYSTEM_REAL_UART_EXE)

clean:
	rm -rf obj_dir obj_dir_real_uart
