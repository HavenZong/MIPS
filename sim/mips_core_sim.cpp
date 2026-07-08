#include "Vmips_core.h"
#include "verilated.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace {

const uint32_t kResetPc = 0x80000000u;
const uint32_t kMemSize = 8u * 1024u * 1024u;
const uint32_t kUartDataAddr = 0xbfd003f8u;
const uint32_t kUartStatusAddr = 0xbfd003fcu;
const uint32_t kUserBase = 0x80100000u;
const uint32_t kUserDataBase = 0x80400000u;
const uint32_t kMatrixOutBase = 0x80420000u;
const char kMatrixInPath[] = "/tmp/matrix.in";
const char kMatrixOutPath[] = "/tmp/matrix.out";
const char kMonitorWelcome[] = "MONITOR for MIPS32 - initialized.";

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

std::vector<uint8_t> read_file(const std::string& path) {
    std::ifstream file(path.c_str(), std::ios::binary);
    if (!file) {
        std::fprintf(stderr, "failed to open %s\n", path.c_str());
        std::exit(2);
    }
    return std::vector<uint8_t>((std::istreambuf_iterator<char>(file)),
                                std::istreambuf_iterator<char>());
}

std::vector<uint32_t> read_hex_words(const std::string& path) {
    std::ifstream file(path.c_str());
    if (!file) {
        std::fprintf(stderr, "failed to open %s\n", path.c_str());
        std::exit(2);
    }
    std::vector<uint32_t> words;
    std::string line;
    while (std::getline(file, line)) {
        if (line.empty()) {
            continue;
        }
        uint32_t value = 0;
        std::stringstream ss;
        ss << std::hex << line;
        ss >> value;
        if (!ss) {
            std::fprintf(stderr, "invalid hex word in %s: %s\n", path.c_str(), line.c_str());
            std::exit(2);
        }
        words.push_back(value);
    }
    return words;
}

void load_hex_words(std::vector<uint8_t>& mem, const std::string& path, uint32_t addr) {
    std::vector<uint32_t> words = read_hex_words(path);
    for (size_t i = 0; i < words.size(); ++i) {
        store_word(mem, addr + static_cast<uint32_t>(i * 4u), words[i]);
    }
}

void append_u32_le(std::deque<uint8_t>& data, uint32_t value) {
    data.push_back(value & 0xffu);
    data.push_back((value >> 8) & 0xffu);
    data.push_back((value >> 16) & 0xffu);
    data.push_back((value >> 24) & 0xffu);
}

uint32_t bytes_to_u32_le(const std::vector<uint8_t>& data, size_t offset) {
    return static_cast<uint32_t>(data[offset]) |
           (static_cast<uint32_t>(data[offset + 1]) << 8) |
           (static_cast<uint32_t>(data[offset + 2]) << 16) |
           (static_cast<uint32_t>(data[offset + 3]) << 24);
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
        std::fprintf(stderr, "usage: %s <program.bin> [c3-user.bin]\n", argv[0]);
        return 2;
    }

    bool kernel_c3_mode = argc >= 3;
    std::vector<uint8_t> c3_user;
    if (kernel_c3_mode) {
        c3_user = read_file(argv[2]);
        if (c3_user.empty() || (c3_user.size() % 4) != 0) {
            std::fprintf(stderr, "c3 user binary must be non-empty and word aligned\n");
            return 2;
        }
    }
    std::string c3_user_path = kernel_c3_mode ? std::string(argv[2]) : std::string();
    bool kernel_matrix_mode = kernel_c3_mode && c3_user_path.find("perf-matrix") != std::string::npos;

    std::vector<uint8_t> mem(kMemSize, 0);
    load_bin(mem, argv[1], kResetPc);
    std::string program(argv[1]);
    bool perf_matrix_mode = program.find("perf-matrix") != std::string::npos || kernel_matrix_mode;
    std::vector<uint32_t> matrix_expected;
    if (perf_matrix_mode) {
        load_hex_words(mem, kMatrixInPath, kUserDataBase);
        matrix_expected = read_hex_words(kMatrixOutPath);
    }

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
    std::deque<uint8_t> uart_rx;
    std::vector<uint8_t> uart_tx;
    std::vector<uint8_t> kernel_response;
    bool c3_script_loaded = false;
    bool c3_pass = false;
    bool matrix_pass = false;

    for (int i = 0; i < 5; ++i) {
        tick(dut);
    }
    dut.reset = 0;

    uint32_t last_wb_pc = 0xffffffffu;
    int same_pc_count = 0;

    uint64_t max_cycles = kernel_matrix_mode ? 200000000ull :
                          kernel_c3_mode ? 20000000ull :
                          perf_matrix_mode ? 100000000ull :
                          20000ull;
    for (uint64_t cycle = 0; cycle < max_cycles; ++cycle) {
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
            if (pending.addr == kUartStatusAddr) {
                rdata_next = 0x1u | (uart_rx.empty() ? 0x0u : 0x2u);
            } else if (pending.addr == kUartDataAddr) {
                if (pending.write) {
                    uart_tx.push_back(static_cast<uint8_t>(pending.wdata & 0xffu));
                    if (trace) {
                        std::printf("uart_tx[%zu] = %02x\n",
                                    uart_tx.size() - 1u,
                                    static_cast<unsigned>(uart_tx.back()));
                    }
                } else if (!uart_rx.empty()) {
                    rdata_next = uart_rx.front();
                    uart_rx.pop_front();
                } else {
                    rdata_next = 0;
                }
            } else if (pending.write) {
                if (pending.size == 0) {
                    store_byte(mem, pending.addr, pending.wdata);
                } else {
                    store_word(mem, pending.addr, pending.wdata);
                }
                rdata_next = load_word(mem, pending.addr & ~3u);
            } else {
                rdata_next = load_word(mem, pending.addr & ~3u);
            }
            ready_next = true;
            pending.valid = false;
        } else if (dut.bus_valid) {
            pending.valid = true;
            pending.write = dut.bus_write;
            pending.size = dut.bus_size;
            pending.addr = dut.bus_addr;
            pending.wdata = dut.bus_wdata;
        }

        if (kernel_c3_mode && !c3_script_loaded &&
            uart_tx.size() >= sizeof(kMonitorWelcome) - 1u) {
            std::string welcome(uart_tx.begin(), uart_tx.begin() + sizeof(kMonitorWelcome) - 1u);
            std::printf("kernel welcome: %s\n", welcome.c_str());
            if (welcome != kMonitorWelcome) {
                std::fprintf(stderr, "kernel welcome mismatch\n");
                return 1;
            }

            uart_rx.push_back('A');
            append_u32_le(uart_rx, kUserBase);
            append_u32_le(uart_rx, static_cast<uint32_t>(c3_user.size()));
            for (size_t i = 0; i < c3_user.size(); ++i) {
                uart_rx.push_back(c3_user[i]);
            }

            uart_rx.push_back('D');
            append_u32_le(uart_rx, kUserBase);
            append_u32_le(uart_rx, static_cast<uint32_t>(c3_user.size()));

            uart_rx.push_back('G');
            append_u32_le(uart_rx, kUserBase);

            if (kernel_matrix_mode) {
                uart_rx.push_back('D');
                append_u32_le(uart_rx, kMatrixOutBase);
                append_u32_le(uart_rx, 147456u);
            } else {
                uart_rx.push_back('R');

                uart_rx.push_back('D');
                append_u32_le(uart_rx, kUserDataBase);
                append_u32_le(uart_rx, 4);
            }

            c3_script_loaded = true;
        }

        if ((kernel_matrix_mode && c3_script_loaded) || (perf_matrix_mode && !kernel_c3_mode)) {
            bool bare_matrix_returned = perf_matrix_mode && !kernel_c3_mode && dut.debug_pc < kResetPc;
            if (!bare_matrix_returned && (cycle & 0xfffull) != 0 && cycle + 1u != max_cycles) {
                continue;
            }
            bool done = true;
            bool any_nonzero = false;
            bool ok = true;
            for (size_t i = 0; i < matrix_expected.size(); ++i) {
                uint32_t actual = load_word(mem, kMatrixOutBase + static_cast<uint32_t>(i * 4u));
                if (actual != 0) {
                    any_nonzero = true;
                }
                if (actual != matrix_expected[i]) {
                    done = false;
                    ok = false;
                    break;
                }
            }
            if (ok && any_nonzero) {
                std::printf("%s matrix memory check passed at cycle %llu\n",
                            kernel_matrix_mode ? "kernel-perf" : "perf-matrix",
                            static_cast<unsigned long long>(cycle));
                matrix_pass = true;
                break;
            }
            if (cycle + 1u == max_cycles && !done) {
                for (size_t i = 0; i < matrix_expected.size(); ++i) {
                    uint32_t actual = load_word(mem, kMatrixOutBase + static_cast<uint32_t>(i * 4u));
                    if (actual != matrix_expected[i]) {
                        std::fprintf(stderr,
                                     "%s matrix mismatch at word %zu addr=%08x actual=%08x expected=%08x\n",
                                     kernel_matrix_mode ? "kernel-perf" : "perf-matrix",
                                     i,
                                     kMatrixOutBase + static_cast<uint32_t>(i * 4u),
                                     actual,
                                     matrix_expected[i]);
                        break;
                    }
                }
            }
        } else if (kernel_c3_mode && c3_script_loaded) {
            size_t welcome_len = sizeof(kMonitorWelcome) - 1u;
            if (uart_tx.size() > welcome_len) {
                kernel_response.assign(uart_tx.begin() + welcome_len, uart_tx.end());
            }

            size_t expected_len = c3_user.size() + 2u + 120u + 4u;
            if (kernel_response.size() >= expected_len) {
                bool ok = true;
                for (size_t i = 0; i < c3_user.size(); ++i) {
                    if (kernel_response[i] != c3_user[i]) {
                        ok = false;
                        std::fprintf(stderr, "D command mismatch at byte %zu\n", i);
                        break;
                    }
                }
                size_t off = c3_user.size();
                if (kernel_response[off] != 0x06 || kernel_response[off + 1] != 0x07) {
                    std::fprintf(stderr, "G command markers mismatch: %02x %02x\n",
                                 kernel_response[off], kernel_response[off + 1]);
                    ok = false;
                }
                off += 2;
                uint32_t reg_v0 = bytes_to_u32_le(kernel_response, off + (2u - 1u) * 4u);
                if (reg_v0 != 0) {
                    std::fprintf(stderr, "R command v0 fail_count = %u\n", reg_v0);
                    ok = false;
                }
                off += 120;
                uint32_t mem_fail_count = bytes_to_u32_le(kernel_response, off);
                std::printf("kernel D/G/R checks: v0=%u mem_fail_count=%u\n", reg_v0, mem_fail_count);
                if (mem_fail_count != 0) {
                    ok = false;
                }
                if (!ok) {
                    return 1;
                }
                std::printf("kernel-c3 monitor check passed\n");
                c3_pass = true;
                break;
            }
        }

        if (!kernel_c3_mode && same_pc_count > 100) {
            break;
        }
    }

    if (kernel_c3_mode) {
        if (kernel_matrix_mode) {
            if (!matrix_pass) {
                std::fprintf(stderr, "kernel-perf matrix check timed out, tx=%zu pc=%08x\n",
                             uart_tx.size(), dut.debug_pc);
                return 1;
            }
            return 0;
        }
        if (!c3_pass) {
            std::fprintf(stderr, "kernel-c3 monitor check timed out, tx=%zu pc=%08x\n",
                         uart_tx.size(), dut.debug_pc);
            return 1;
        }
        return 0;
    }

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

    if (program.find("lab1") != std::string::npos) {
        uint32_t a = 1;
        uint32_t b = 1;
        bool ok = true;
        for (unsigned i = 0; i < 64; ++i) {
            uint32_t next = a + b;
            a = b;
            b = next;
            uint32_t actual = load_word(mem, 0x80400000u + i * 4u);
            if (i < 8 || i >= 60) {
                std::printf("lab1 mem[%08x] = %u expected %u\n",
                            0x80400000u + i * 4u, actual, b);
            }
            if (actual != b) {
                ok = false;
            }
        }
        if (ok) {
            std::printf("lab1 fibonacci64 check passed\n");
            return 0;
        }
        std::fprintf(stderr, "lab1 fibonacci64 check failed\n");
        return 1;
    }

    if (perf_matrix_mode) {
        if (matrix_pass) {
            return 0;
        }
        bool ok = true;
        for (size_t i = 0; i < matrix_expected.size(); ++i) {
            uint32_t actual = load_word(mem, kMatrixOutBase + static_cast<uint32_t>(i * 4u));
            if (actual != matrix_expected[i]) {
                std::fprintf(stderr,
                             "perf-matrix mismatch at word %zu addr=%08x actual=%08x expected=%08x\n",
                             i,
                             kMatrixOutBase + static_cast<uint32_t>(i * 4u),
                             actual,
                             matrix_expected[i]);
                ok = false;
                break;
            }
        }
        if (ok) {
            std::printf("perf-matrix data check passed\n");
            return 0;
        }
        return 1;
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
