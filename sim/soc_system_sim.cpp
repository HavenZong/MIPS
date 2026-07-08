#include "Vsoc_system_tb.h"
#include "verilated.h"

#include <cstdio>
#include <string>

namespace {

const char kWelcome[] = "MONITOR for MIPS32 - initialized.";

void tick(Vsoc_system_tb* dut) {
    dut->clk = 0;
    dut->eval();
    dut->clk = 1;
    dut->eval();
}

}  // namespace

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    Vsoc_system_tb* dut = new Vsoc_system_tb;
    dut->clk = 0;
    dut->reset = 1;
    dut->rxd = 1;
    dut->eval();

    for (int i = 0; i < 8; ++i) {
        tick(dut);
    }
    dut->reset = 0;

    std::string out;
    int tx_prev = 1;
    for (unsigned cycle = 0; cycle < 2000000 && out.size() < sizeof(kWelcome) - 1u; ++cycle) {
        tick(dut);

        if (tx_prev == 1 && dut->txd == 0) {
            unsigned value = 0;
            for (unsigned bit = 0; bit < 8; ++bit) {
                tick(dut);
                if (dut->txd) {
                    value |= (1u << bit);
                }
            }
            tick(dut);
            out.push_back(static_cast<char>(value & 0xffu));
            std::printf("uart char %02x '%c'\n", value & 0xffu,
                        (value >= 32 && value <= 126) ? static_cast<char>(value) : '.');
        }
        tx_prev = dut->txd;
    }

    std::printf("system welcome: %s\n", out.c_str());
    if (out != kWelcome) {
        std::fprintf(stderr, "system welcome mismatch, pc=%08x len=%zu\n", dut->debug_pc, out.size());
        return 1;
    }

    std::printf("soc-system kernel welcome check passed\n");
    delete dut;
    return 0;
}
