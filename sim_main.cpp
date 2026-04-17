#include "verilated.h"

#ifndef TOP_HEADER
#error "TOP_HEADER must be defined by the build system."
#endif

#ifndef TOP_CLASS
#error "TOP_CLASS must be defined by the build system."
#endif

#include TOP_HEADER

#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <memory>

namespace {

constexpr std::uint64_t kDefaultMaxTicks = 100000;

std::uint64_t read_max_ticks() {
  if (const char *value = std::getenv("SIM_MAX_TICKS")) {
    const auto parsed = std::strtoull(value, nullptr, 10);
    if (parsed != 0) {
      return parsed;
    }
  }
  return kDefaultMaxTicks;
}

}  // namespace

int main(int argc, char **argv) {
  Verilated::commandArgs(argc, argv);

  std::unique_ptr<TOP_CLASS> top = std::make_unique<TOP_CLASS>();
  top->clk = 0;
  top->eval();

  const std::uint64_t max_ticks = read_max_ticks();

  for (std::uint64_t tick = 0; tick < max_ticks && !Verilated::gotFinish(); ++tick) {
    top->clk = !top->clk;
    top->eval();
    Verilated::timeInc(1);
  }

  top->final();

  if (Verilated::gotFinish()) {
    return 0;
  }

  std::cerr << "Simulation timed out after " << max_ticks
            << " ticks. Set SIM_MAX_TICKS to raise the limit." << std::endl;
  return 1;
}
