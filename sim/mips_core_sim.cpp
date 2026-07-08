#include "Vmips_core.h"
#include "verilated.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <string>
#include <vector>

namespace {

const uint32_t kResetPc = 0x80100000u;
const uint32_t kMemSize = 8u * 1024u * 1024u;

uint32_t phys_addr(uint32_t addr) {
    return addr & (kMemSize - 1u);
}

uint32_t load_word(const std::vector<uint8_t>& mem, uint32_t addr) {
    uint32_t a = phys_addr(addr);
    return static_cast<uint32_t>(mem[a]) |
           (static_cast<uint32_t>(mem[phys_addr(a + 1u)]) << 8) |
           (static_cast<uint32_t>(mem[phys_addr(a + 2u)]) << 16) |
           (static_cast<uint32_t>(mem[phys_addr(a + 3u)]) << 24);
}

void store_word(std::vector<uint8_t>& mem, uint32_t addr, uint32_t data) {
    uint32_t a = phys_addr(addr);
    mem[a] = data & 0xffu;
    mem[phys_addr(a + 1u)] = (data >> 8) & 0xffu;
    mem[phys_addr(a + 2u)] = (data >> 16) & 0xffu;
    mem[phys_addr(a + 3u)] = (data >> 24) & 0xffu;
}

void store_byte(std::vector<uint8_t>& mem, uint32_t addr, uint32_t data) {
    mem[phys_addr(addr)] = data & 0xffu;
}

void load_bin(std::vector<uint8_t>& mem, const std::string& path, uint32_t addr) {
    std::ifstream file(path.c_str(), std::ios::binary);
    if (!file) {
        std::fprintf(stderr, "failed to open %s\n", path.c_str());
        std::exit(2);
    }
    uint32_t pos = phys_addr(addr);
    char ch = 0;
    while (file.get(ch)) {
        mem[pos] = static_cast<uint8_t>(ch);
        pos = phys_addr(pos + 1u);
    }
}

struct PendingBus {
    bool valid = false;
    bool write = false;
    uint8_t size = 0;
    uint32_t addr = 0;
    uint32_t wdata = 0;
};

void tick(Vmips_core& dut) {
    dut.clk = 0;
    dut.eval();
    dut.clk = 1;
    dut.eval();
}

}  // namespace

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 2) {
        std::fprintf(stderr, "usage: %s <program.bin>\n", argv[0]);
        return 2;
    }

    std::vector<uint8_t> mem(kMemSize, 0);
    load_bin(mem, argv[1], kResetPc);

    Vmips_core dut;
    const char* trace_env = std::getenv("TRACE");
    bool trace = trace_env != nullptr && trace_env[0] != '\0' && std::string(trace_env) != "0";
    dut.clk = 0;
    dut.reset = 1;
    dut.bus_rdata = 0;
    dut.bus_ready = 0;
    dut.eval();

    PendingBus pending;
    bool ready_next = false;
    uint32_t rdata_next = 0;

    for (int i = 0; i < 5; ++i) {
        tick(dut);
    }
    dut.reset = 0;

    uint32_t last_wb_pc = 0xffffffffu;
    int same_pc_count = 0;

    for (uint64_t cycle = 0; cycle < 20000; ++cycle) {
        dut.bus_ready = ready_next ? 1 : 0;
        dut.bus_rdata = rdata_next;
        ready_next = false;

        tick(dut);

        if (trace && cycle < 90) {
            std::printf("cycle=%llu pcnext=%08x bus_v=%u bus_w=%u bus_a=%08x ready=%u\n",
                        static_cast<unsigned long long>(cycle),
                        dut.debug_pc,
                        dut.bus_valid,
                        dut.bus_write,
                        dut.bus_addr,
                        dut.bus_ready);
        }

        if (trace && dut.debug_wb_rf_wen == 0xf) {
            std::printf("cycle=%llu wb pc=%08x r%u=%08x\n",
                        static_cast<unsigned long long>(cycle),
                        dut.debug_wb_pc,
                        dut.debug_wb_rf_wnum,
                        dut.debug_wb_rf_wdata);
        }

        if (dut.debug_pc == last_wb_pc) {
            ++same_pc_count;
        } else {
            same_pc_count = 0;
            last_wb_pc = dut.debug_pc;
        }

        if (pending.valid) {
            if (pending.write) {
                if (pending.size == 0) {
                    store_byte(mem, pending.addr, pending.wdata);
                } else {
                    store_word(mem, pending.addr, pending.wdata);
                }
            }
            rdata_next = load_word(mem, pending.addr & ~3u);
            ready_next = true;
            pending.valid = false;
        } else if (dut.bus_valid) {
            pending.valid = true;
            pending.write = dut.bus_write;
            pending.size = dut.bus_size;
            pending.addr = dut.bus_addr;
            pending.wdata = dut.bus_wdata;
        }

        if (same_pc_count > 100) {
            break;
        }
    }

    std::string program(argv[1]);
    if (program.find("isa-directed") != std::string::npos) {
        uint32_t fail_count = load_word(mem, 0x80400100u);
        std::printf("isa-directed fail_count = %u\n", fail_count);
        if (fail_count != 0) {
            std::fprintf(stderr, "isa-directed check failed\n");
            return 1;
        }
        std::printf("isa-directed check passed\n");
        return 0;
    }

    const uint32_t expected[] = {2, 3, 5, 8, 13, 21, 34, 55};
    bool ok = true;
    for (unsigned i = 0; i < sizeof(expected) / sizeof(expected[0]); ++i) {
        uint32_t actual = load_word(mem, 0x80400000u + i * 4u);
        std::printf("mem[%08x] = %u\n", 0x80400000u + i * 4u, actual);
        if (actual != expected[i]) {
            ok = false;
        }
    }

    if (ok) {
        std::printf("sample fibonacci check passed\n");
        return 0;
    }

    std::fprintf(stderr, "sample fibonacci check failed\n");
    return 1;
}
