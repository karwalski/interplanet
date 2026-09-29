# Makefile — libitx C LTX library
# Story 33.3 · C99 · No external dependencies

CC       = cc
CFLAGS   = -std=c99 -Wall -Wextra -O2
SRC      = src/libitx.c src/itx_plan_json.c
INC      = -Iinclude
OBJ      = lib/libitx.o lib/itx_plan_json.o
LIB_A    = lib/libitx.a
LIB_SO   = lib/libitx.so
TEST_BIN = bin/test_libitx
PLAN_TEST_BIN = bin/test_plan_json

.PHONY: all build shared test clean

all: build test

build: $(LIB_A)

lib/%.o: src/%.c include/libitx.h
	@mkdir -p lib
	$(CC) $(CFLAGS) $(INC) -c $< -o $@

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
	$(CC) $(CFLAGS) $(INC) tests/test_plan_json.c $(LIB_A) -lm -o $(PLAN_TEST_BIN)
	@echo ""
	@echo "── Wire-format plans: golden planIds, validatePlan ─────────────"
	./$(PLAN_TEST_BIN) ../../spec/golden/plan-ids.json

clean:
	rm -rf lib/ bin/
