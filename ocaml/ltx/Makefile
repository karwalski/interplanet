# Makefile -- InterPlanet LTX OCaml library (Story 64.1 + Epic 29 + Story 72.5)

OCAMLFIND  ?= ocamlfind
OCAMLOPT   ?= ocamlopt
PKGS_FULL   = unix,str
SEC_SRCS    = lib/ed25519.ml lib/security.ml
UPPER_SRC   = lib/upper.ml
V11_ONLY    = lib/validate.ml lib/v11.ml
V11_SRCS    = $(SEC_SRCS) $(UPPER_SRC) $(V11_ONLY)
SEC_TEST    = test/security_test
V11_TEST    = test/v11_test
PARITY_TEST = test/parity_test
UNIT_SRCS   = lib/constants.ml lib/models.ml $(UPPER_SRC) lib/interplanet_ltx.ml
UNIT_TEST   = test/unit_test

.PHONY: build test lint clean

build:
	$(OCAMLFIND) $(OCAMLOPT) -package $(PKGS_FULL) -linkpkg -I lib $(V11_SRCS) -o interplanet_ltx_sec

test: $(UNIT_TEST) $(SEC_TEST) $(V11_TEST) $(PARITY_TEST)
	./$(UNIT_TEST)
	./$(SEC_TEST)
	./$(V11_TEST)
	./$(PARITY_TEST)

$(UNIT_TEST): $(UNIT_SRCS) test/unit_test.ml
	$(OCAMLFIND) $(OCAMLOPT) -package $(PKGS_FULL) -linkpkg -I lib $(UNIT_SRCS) test/unit_test.ml -o $(UNIT_TEST)

$(SEC_TEST): $(SEC_SRCS) test/security_test.ml
	$(OCAMLFIND) $(OCAMLOPT) -linkpkg -I lib $(SEC_SRCS) test/security_test.ml -o $(SEC_TEST)

$(V11_TEST): $(V11_SRCS) test/v11_test.ml
	$(OCAMLFIND) $(OCAMLOPT) -linkpkg -I lib $(V11_SRCS) test/v11_test.ml -o $(V11_TEST)

$(PARITY_TEST): $(V11_SRCS) $(UNIT_SRCS) test/parity_test.ml
	$(OCAMLFIND) $(OCAMLOPT) -package $(PKGS_FULL) -linkpkg -I lib $(UNIT_SRCS) $(SEC_SRCS) $(V11_ONLY) test/parity_test.ml -o $(PARITY_TEST)

lint:
	$(OCAMLFIND) $(OCAMLOPT) -linkpkg -i -I lib $(V11_SRCS) > /dev/null

clean:
	rm -f *.cmi *.cmx *.o interplanet_ltx interplanet_ltx_sec
	rm -f lib/*.cmi lib/*.cmx lib/*.o
	rm -f test/*.cmi test/*.cmx test/*.o test/unit_test test/security_test test/v11_test test/parity_test
