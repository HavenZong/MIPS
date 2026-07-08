#include "Vsoc_bus.h"
#include "verilated.h"

#include <cstdio>

namespace {

void tick(Vsoc_bus& dut) {
    dut.clk = 0;
    dut.eval();
    dut.clk = 1;
    dut.eval();
}

bool wait_ready(Vsoc_bus& dut, int max_cycles) {
    for (int i = 0; i < max_cycles; ++i) {
        tick(dut);
        if (dut.cpu_ready) {
            return true;
        }
    }
    return false;
}

}  // namespace

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    Vsoc_bus dut;
    dut.clk = 0;
    dut.reset = 1;
    dut.cpu_valid = 0;
    dut.cpu_write = 0;
    dut.cpu_size = 0;
    dut.cpu_addr = 0;
    dut.cpu_wdata = 0;
    dut.rxd = 1;
    dut.eval();

    for (int i = 0; i < 4; ++i) {
        tick(dut);
    }

    dut.reset = 0;
    tick(dut);

    dut.cpu_valid = 1;
    dut.cpu_write = 0;
    dut.cpu_size = 0;
    dut.cpu_addr = 0xbfd003fc;
    bool ready = wait_ready(dut, 8);

    unsigned status = dut.cpu_rdata & 0x3u;
    std::printf("uart status = 0x%x\n", status);
    if (!ready || status != 0x1u) {
        std::fprintf(stderr, "uart status check failed: ready=%u status=0x%x\n",
                     ready, status);
        return 1;
    }

    std::printf("soc-bus uart status check passed\n");
    return 0;
}
