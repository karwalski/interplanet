# Makefile — libitx C LTX library
# Story 33.3 · C99 · No external dependencies

CC       = cc
CFLAGS   = -std=c99 -Wall -Wextra -O2
SRC      = src/libitx.c
INC      = -Iinclude
OBJ      = lib/libitx.o
LIB_A    = lib/libitx.a
LIB_SO   = lib/libitx.so
TEST_BIN = bin/test_libitx

.PHONY: all build shared test clean

all: build test

build: $(LIB_A)

$(OBJ): $(SRC) include/libitx.h
	@mkdir -p lib
	$(CC) $(CFLAGS) $(INC) -c $(SRC) -o $(OBJ)

$(LIB_A): $(OBJ)
	ar rcs $(LIB_A) $(OBJ)

shared: $(LIB_SO)

$(LIB_SO): $(SRC) include/libitx.h
	@mkdir -p lib
	$(CC) $(CFLAGS) $(INC) -fPIC -shared $(SRC) -o $(LIB_SO) -lm

test: $(LIB_A)
	@mkdir -p bin
	$(CC) $(CFLAGS) $(INC) tests/test_libitx.c $(LIB_A) -lm -o $(TEST_BIN)
	@echo ""
	@echo "── Running unit tests ──────────────────────────────────────────"
	./$(TEST_BIN)

clean:
	rm -rf lib/ bin/
