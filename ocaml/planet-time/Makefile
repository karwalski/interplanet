# Makefile — InterPlanet Time OCaml library (Story 18.18)

OCAMLOPT   ?= ocamlopt
LIB_SRCS    = lib/constants.ml lib/orbital.ml lib/time_calc.ml lib/interplanet_time.ml
TEST_BIN    = _build/unit_test

.PHONY: build test lint clean

build:
	$(OCAMLOPT) -I lib $(LIB_SRCS) -o interplanet_time

test: $(TEST_BIN)
	./$(TEST_BIN)

$(TEST_BIN): $(LIB_SRCS) test/unit_test.ml
	mkdir -p _build
	$(OCAMLOPT) -I lib \
		$(LIB_SRCS) test/unit_test.ml -o $(TEST_BIN)

lint:
	$(OCAMLOPT) -I lib $(LIB_SRCS) -o /tmp/ipt_ocaml_lint && rm -f /tmp/ipt_ocaml_lint lib/*.cmi lib/*.cmx lib/*.o

clean:
	rm -rf _build
	rm -f *.cmi *.cmx *.o interplanet_time
	rm -f lib/*.cmi lib/*.cmx lib/*.o
	rm -f test/*.cmi test/*.cmx test/*.o
