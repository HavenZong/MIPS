#include "Vsoc_system_tb.h"
#include "verilated.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace {

const char kWelcome[] = "MONITOR for MIPS32 - initialized.";
const uint32_t kUserBase = 0x80100000u;
const uint32_t kUserDataBase = 0x80400000u;
const uint32_t kMatrixOutBase = 0x80420000u;
#ifdef FAST_UART
const unsigned kTicksPerBit = 1;
#else
const unsigned kTicksPerBit = 50000000 / 9600;
#endif

std::vector<uint8_t> read_file(const char* path) {
    std::ifstream file(path, std::ios::binary);
    if (!file) {
        std::fprintf(stderr, "failed to open %s\n", path);
        std::exit(2);
    }
    return std::vector<uint8_t>((std::istreambuf_iterator<char>(file)),
                                std::istreambuf_iterator<char>());
}

std::vector<uint32_t> read_hex_words(const char* path) {
    std::ifstream file(path);
    if (!file) {
        std::fprintf(stderr, "failed to open %s\n", path);
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
        words.push_back(value);
    }
    return words;
}

void append_u32_le(std::vector<uint8_t>* data, uint32_t value) {
    data->push_back(value & 0xffu);
    data->push_back((value >> 8) & 0xffu);
    data->push_back((value >> 16) & 0xffu);
    data->push_back((value >> 24) & 0xffu);
}

uint32_t bytes_to_u32_le(const std::string& data, size_t offset) {
    return static_cast<uint32_t>(static_cast<uint8_t>(data[offset])) |
           (static_cast<uint32_t>(static_cast<uint8_t>(data[offset + 1])) << 8) |
           (static_cast<uint32_t>(static_cast<uint8_t>(data[offset + 2])) << 16) |
           (static_cast<uint32_t>(static_cast<uint8_t>(data[offset + 3])) << 24);
}

class UartTxDecoder {
public:
    UartTxDecoder() : trace_(std::getenv("UART_TRACE") != nullptr) {}

    void sample(int txd) {
        if (receiving_) {
            if (countdown_ != 0) {
                --countdown_;
            }
            if (countdown_ == 0) {
                if (bit_ < 8) {
                    if (txd) {
                        value_ |= (1u << bit_);
                    }
                    ++bit_;
                    countdown_ = kTicksPerBit;
                } else {
                    out.push_back(static_cast<char>(value_ & 0xffu));
                    if (trace_) {
                        std::printf("uart char %02x '%c'\n", value_ & 0xffu,
                                    (value_ >= 32 && value_ <= 126) ? static_cast<char>(value_) : '.');
                    }
                    receiving_ = false;
                }
            }
        } else if (prev_txd_ == 1 && txd == 0) {
            receiving_ = true;
            countdown_ = kTicksPerBit + kTicksPerBit / 2;
            bit_ = 0;
            value_ = 0;
        }
        prev_txd_ = txd;
    }

    std::string out;

private:
    bool trace_ = false;
    int prev_txd_ = 1;
    bool receiving_ = false;
    unsigned countdown_ = 0;
    unsigned bit_ = 0;
    unsigned value_ = 0;
};

void tick(Vsoc_system_tb* dut, UartTxDecoder* decoder) {
    dut->clk = 0;
    dut->eval();
    dut->clk = 1;
    dut->eval();
    if (decoder != nullptr) {
        decoder->sample(dut->txd);
    }
}

void wait_cycles(Vsoc_system_tb* dut, UartTxDecoder* decoder, unsigned cycles) {
    for (unsigned i = 0; i < cycles; ++i) {
        tick(dut, decoder);
    }
}

void send_uart_byte(Vsoc_system_tb* dut, UartTxDecoder* decoder, uint8_t value) {
    dut->rxd = 0;
    wait_cycles(dut, decoder, kTicksPerBit);
    for (unsigned bit = 0; bit < 8; ++bit) {
        dut->rxd = (value >> bit) & 1u;
        wait_cycles(dut, decoder, kTicksPerBit);
    }
    dut->rxd = 1;
    wait_cycles(dut, decoder, kTicksPerBit);
}

bool check_kernel_response(const std::string& response, const std::vector<uint8_t>& c3_user) {
    const size_t expected_len = c3_user.size() + 2u + 120u + 4u;
    if (response.size() < expected_len) {
        return false;
    }

    bool ok = true;
    for (size_t i = 0; i < c3_user.size(); ++i) {
        if (static_cast<uint8_t>(response[i]) != c3_user[i]) {
            std::fprintf(stderr, "D command mismatch at byte %zu\n", i);
            ok = false;
            break;
        }
    }

    size_t off = c3_user.size();
    if (static_cast<uint8_t>(response[off]) != 0x06 ||
        static_cast<uint8_t>(response[off + 1]) != 0x07) {
        std::fprintf(stderr, "G command markers mismatch: %02x %02x\n",
                     static_cast<uint8_t>(response[off]),
                     static_cast<uint8_t>(response[off + 1]));
        ok = false;
    }

    off += 2;
    uint32_t reg_v0 = bytes_to_u32_le(response, off + (2u - 1u) * 4u);
    if (reg_v0 != 0) {
        std::fprintf(stderr, "R command v0 fail_count = %u\n", reg_v0);
        ok = false;
    }

    off += 120;
    uint32_t mem_fail_count = bytes_to_u32_le(response, off);
    std::printf("kernel D/G/R checks: v0=%u mem_fail_count=%u\n", reg_v0, mem_fail_count);
    return ok && mem_fail_count == 0;
}

}  // namespace

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    Vsoc_system_tb* dut = new Vsoc_system_tb;
    dut->clk = 0;
    dut->reset = 1;
    dut->rxd = 1;
    dut->eval();

    UartTxDecoder decoder;
    for (int i = 0; i < 8; ++i) {
        tick(dut, &decoder);
    }
    dut->reset = 0;

    for (unsigned cycle = 0; cycle < 2000000 && decoder.out.size() < sizeof(kWelcome) - 1u; ++cycle) {
        tick(dut, &decoder);
    }

    std::string welcome = decoder.out.substr(0, sizeof(kWelcome) - 1u);
    std::printf("system welcome: %s\n", welcome.c_str());
    if (welcome != kWelcome) {
        std::fprintf(stderr, "system welcome mismatch, pc=%08x len=%zu\n", dut->debug_pc, decoder.out.size());
        return 1;
    }

    std::vector<uint8_t> c3_user = read_file(argc >= 2 ? argv[1] : "../asm/c3-user.bin");
    bool perf_matrix = argc >= 2 && std::string(argv[1]).find("perf-matrix") != std::string::npos;
    std::vector<uint8_t> script;
    script.push_back('A');
    append_u32_le(&script, kUserBase);
    append_u32_le(&script, static_cast<uint32_t>(c3_user.size()));
    script.insert(script.end(), c3_user.begin(), c3_user.end());
    script.push_back('D');
    append_u32_le(&script, kUserBase);
    append_u32_le(&script, static_cast<uint32_t>(c3_user.size()));
    script.push_back('G');
    append_u32_le(&script, kUserBase);

    if (!perf_matrix) {
        script.push_back('R');
    }
    script.push_back('D');
    append_u32_le(&script, perf_matrix ? kMatrixOutBase : kUserDataBase);
    append_u32_le(&script, perf_matrix ? 147456u : 4u);

    for (size_t i = 0; i < script.size(); ++i) {
        send_uart_byte(dut, &decoder, script[i]);
    }

    const size_t welcome_len = sizeof(kWelcome) - 1u;
    const size_t expected_response_len = c3_user.size() + 2u + (perf_matrix ? 0u : 120u) +
                                         (perf_matrix ? 147456u : 4u);
    for (unsigned cycle = 0;
         cycle < 200000000 && decoder.out.size() < welcome_len + expected_response_len;
         ++cycle) {
        tick(dut, &decoder);
    }

    std::string response = decoder.out.substr(welcome_len);
    if (perf_matrix) {
        if (response.size() < expected_response_len) {
            std::fprintf(stderr, "perf response too short, pc=%08x response_len=%zu expected=%zu\n",
                         dut->debug_pc, response.size(), expected_response_len);
            return 1;
        }
        std::vector<uint32_t> expected = read_hex_words("/tmp/matrix.out");
        for (size_t i = 0; i < c3_user.size(); ++i) {
            if (static_cast<uint8_t>(response[i]) != c3_user[i]) {
                std::fprintf(stderr, "perf D command mismatch at byte %zu actual=%02x expected=%02x\n",
                             i,
                             static_cast<uint8_t>(response[i]),
                             c3_user[i]);
                return 1;
            }
        }
        if (static_cast<uint8_t>(response[c3_user.size()]) != 0x06 ||
            static_cast<uint8_t>(response[c3_user.size() + 1u]) != 0x07) {
            std::fprintf(stderr, "perf G markers mismatch: %02x %02x\n",
                         static_cast<uint8_t>(response[c3_user.size()]),
                         static_cast<uint8_t>(response[c3_user.size() + 1u]));
            return 1;
        }
        size_t off = c3_user.size() + 2u;
        for (size_t i = 0; i < expected.size(); ++i) {
            uint32_t actual = bytes_to_u32_le(response, off + i * 4u);
            if (actual != expected[i]) {
                std::fprintf(stderr,
                             "soc-system-perf mismatch word %zu actual=%08x expected=%08x\n",
                             i, actual, expected[i]);
                return 1;
            }
        }
        std::printf("soc-system-perf matrix check passed\n");
    } else if (!check_kernel_response(response, c3_user)) {
        std::fprintf(stderr, "kernel response check failed, pc=%08x response_len=%zu\n",
                     dut->debug_pc, response.size());
        return 1;
    }

    std::printf("soc-system kernel welcome check passed\n");
    std::printf("soc-system real UART command check passed\n");
    delete dut;
    return 0;
}
