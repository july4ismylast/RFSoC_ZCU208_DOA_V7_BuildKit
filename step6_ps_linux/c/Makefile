# The A53 supervisor: host build for the test bench, cross build for the board.
#
#   make            host binary in build/step6/supervisor  (any g++/clang++)
#   make cross      aarch64 binary, needs aarch64-linux-gnu-g++ or the
#                   PetaLinux SDK's environment-setup script on PATH
#   make clean
ROOT := $(abspath ../..)
BUILD := $(ROOT)/build/step6
CXX ?= g++
CXXFLAGS ?= -std=c++17 -O2 -Wall -Wextra -pedantic
CROSS ?= aarch64-linux-gnu-g++

.PHONY: all host cross clean

all: host

host: $(BUILD)/supervisor

$(BUILD)/supervisor: supervisor.cpp
	@mkdir -p $(BUILD)
	$(CXX) $(CXXFLAGS) -o "$@" supervisor.cpp
	@echo "built $@"

# For the board: static, stripped, no runtime dependency beyond glibc/gcc.
cross: supervisor.cpp
	@mkdir -p $(BUILD)
	@command -v $(CROSS) >/dev/null 2>&1 || { \
	    echo "no $(CROSS) on PATH -- source the PetaLinux SDK first:"; \
	    echo "  source /opt/petalinux/2023.2/environment-setup-cortexa72-cortexa53-xilinx-linux"; \
	    exit 2; }
	$(CROSS) $(CXXFLAGS) -static -s -o $(BUILD)/supervisor_aarch64 supervisor.cpp
	file $(BUILD)/supervisor_aarch64 || true

clean:
	rm -rf $(BUILD)
