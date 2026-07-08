# Makefile -- InterPlanet LTX OCaml library (Story 64.1 + Epic 29 + Story 72.5)

OCAMLFIND  ?= ocamlfind
OCAMLOPT   ?= ocamlopt
PKGS_FULL   = unix,str
SEC_SRCS    = lib/ed25519.ml lib/security.ml
V11_SRCS    = $(SEC_SRCS) lib/v11.ml
SEC_TEST    = test/security_test
V11_TEST    = test/v11_test
UNIT_SRCS   = lib/constants.ml lib/models.ml lib/interplanet_ltx.ml
UNIT_TEST   = test/unit_test

.PHONY: build test lint clean

build:
	$(OCAMLFIND) $(OCAMLOPT) -package $(PKGS_FULL) -linkpkg -I lib $(V11_SRCS) -o interplanet_ltx_sec

test: $(UNIT_TEST) $(SEC_TEST) $(V11_TEST)
	./$(UNIT_TEST)
	./$(SEC_TEST)
	./$(V11_TEST)

$(UNIT_TEST): $(UNIT_SRCS) test/unit_test.ml
	$(OCAMLFIND) $(OCAMLOPT) -package $(PKGS_FULL) -linkpkg -I lib $(UNIT_SRCS) test/unit_test.ml -o $(UNIT_TEST)

$(SEC_TEST): $(SEC_SRCS) test/security_test.ml
	$(OCAMLFIND) $(OCAMLOPT) -linkpkg -I lib $(SEC_SRCS) test/security_test.ml -o $(SEC_TEST)

$(V11_TEST): $(V11_SRCS) test/v11_test.ml
	$(OCAMLFIND) $(OCAMLOPT) -linkpkg -I lib $(V11_SRCS) test/v11_test.ml -o $(V11_TEST)

lint:
	$(OCAMLFIND) $(OCAMLOPT) -linkpkg -i -I lib $(V11_SRCS) > /dev/null

clean:
	rm -f *.cmi *.cmx *.o interplanet_ltx interplanet_ltx_sec
	rm -f lib/*.cmi lib/*.cmx lib/*.o
	rm -f test/*.cmi test/*.cmx test/*.o test/unit_test test/security_test test/v11_test
