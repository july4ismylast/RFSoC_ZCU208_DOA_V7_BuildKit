# The R5F estimator as a shared library, so the python test bench can call the
# exact same C the board would run.  No Xilinx headers, no Vitis: plain gcc.
ROOT := $(abspath ../..)
BUILD := $(ROOT)/build/step3
LIB := $(BUILD)/libdoa_core.so
# -pedantic is left out on purpose: passing a `double(*)[2]` to a
# `const double(*)[2]` parameter is legal C23 and only pedantic-warned
# before it, and the R5 toolchain is fine with it.
CFLAGS ?= -std=c99 -O2 -Wall -Wextra

.PHONY: all clean check

all: $(LIB)

$(LIB): doa_core.c doa_core.h
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -shared -fPIC -o "$@" doa_core.c -lm
	@echo "built $@"

# The same file, compiled the way the R5 would see it: no shared object, 32-bit
# int, warnings fatal.  If your toolchain is armr5-none-eabi-gcc, use
#   make CC=armr5-none-eabi-gcc ABI=arm
check: doa_core.c doa_core.h
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) -Werror -c doa_core.c -o $(BUILD)/doa_core.o
	@echo "compiles clean with -Werror"

clean:
	rm -rf $(BUILD)
