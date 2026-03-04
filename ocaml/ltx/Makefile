# Makefile -- InterPlanet LTX OCaml library (Story 64.1 + Epic 29)

OCAMLFIND  ?= ocamlfind
OCAMLOPT   ?= ocamlopt
PKGS_FULL   = unix,str
SEC_SRCS    = lib/security.ml
SEC_TEST    = test/security_test

.PHONY: build test lint clean

build:
	$(OCAMLFIND) $(OCAMLOPT) -package $(PKGS_FULL) -linkpkg $(SEC_SRCS) -o interplanet_ltx_sec

test: $(SEC_TEST)
	./$(SEC_TEST)

$(SEC_TEST): $(SEC_SRCS) test/security_test.ml
	$(OCAMLFIND) $(OCAMLOPT) -linkpkg -I lib $(SEC_SRCS) test/security_test.ml -o $(SEC_TEST)

lint:
	$(OCAMLFIND) $(OCAMLOPT) -linkpkg -i $(SEC_SRCS) > /dev/null

clean:
	rm -f *.cmi *.cmx *.o interplanet_ltx interplanet_ltx_sec
	rm -f lib/*.cmi lib/*.cmx lib/*.o
	rm -f test/*.cmi test/*.cmx test/*.o test/unit_test test/security_test
