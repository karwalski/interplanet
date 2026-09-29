# interplanet — toke interplanetary time CLI

# This port is written in the pre-3.0 toke dialect (`=` compares, `_` excluded),
# so toke 3.0.0 (https://github.com/karwalski/toke) rejects it (E2002).
# Checked 2026-09-29 on x86_64 Linux: tkc at ad4301b emits wrong ABI
# types for cross-module f64 parameters (clang link error); tkc at c6d1c8a
# links, but `ltx` segfaults and `time` prints nothing. The committed LLVM IR
# (src/main.ll, src/interplanet/*) links and runs once its arm64-apple
# `target` lines are removed. Override the toolchain location with
#   make TOKE_ROOT=/path/to/toke
TOKE_ROOT   ?= /Users/matthew.watt/tk/toke
TKC         ?= $(TOKE_ROOT)/tkc
TOKE_STDLIB := $(TOKE_ROOT)/src/stdlib

BIN := interplanet
SRC := src
IFACE_DIR := $(SRC)/interplanet

# Stdlib C sources needed
STDLIB_SRCS := \
  $(TOKE_STDLIB)/str.c \
  $(TOKE_STDLIB)/args.c \
  $(TOKE_STDLIB)/log.c \
  $(TOKE_STDLIB)/tk_time.c \
  $(TOKE_STDLIB)/tk_runtime.c

GLUE_SRC := $(SRC)/glue.c

CFLAGS := -std=c99 -D_GNU_SOURCE -O1 -I$(TOKE_STDLIB) -Wno-pedantic
LIBS := -lm -lz

.PHONY: all clean

all: $(BIN)

$(IFACE_DIR):
	mkdir -p $(IFACE_DIR)

# Module: planettime
$(IFACE_DIR)/planettime.tki $(IFACE_DIR)/planettime: $(SRC)/planettime.tk | $(IFACE_DIR)
	cd $(SRC) && $(TKC) --emit-interface --emit-llvm --out interplanet/planettime planettime.tk

# Module: ltx (depends on planettime)
$(IFACE_DIR)/ltx.tki $(IFACE_DIR)/ltx: $(SRC)/ltx.tk $(IFACE_DIR)/planettime.tki | $(IFACE_DIR)
	cd $(SRC) && $(TKC) --emit-interface --emit-llvm --out interplanet/ltx ltx.tk

# main.ll (depends on both modules)
$(SRC)/main.ll: $(SRC)/main.tk $(IFACE_DIR)/planettime.tki $(IFACE_DIR)/ltx.tki
	cd $(SRC) && $(TKC) --emit-llvm --out main.ll main.tk

# Final binary
$(BIN): $(SRC)/main.ll $(IFACE_DIR)/planettime $(IFACE_DIR)/ltx $(GLUE_SRC)
	clang $(CFLAGS) -x ir $(SRC)/main.ll $(IFACE_DIR)/planettime $(IFACE_DIR)/ltx \
	  -x c $(STDLIB_SRCS) $(GLUE_SRC) \
	  -o $@ $(LIBS)

clean:
	rm -f $(BIN) $(SRC)/main.ll $(IFACE_DIR)/planettime $(IFACE_DIR)/planettime.tki \
	  $(IFACE_DIR)/ltx $(IFACE_DIR)/ltx.tki
	rmdir $(IFACE_DIR) 2>/dev/null || true
