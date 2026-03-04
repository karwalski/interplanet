# InterPlanet LTX — OCaml Library

OCaml implementation of the LTX (Light-Time eXchange) protocol SDK.
Stdlib-only (requires the `unix` library from the OCaml standard distribution).
Requires OCaml 4.13+ and `ocamlfind`.

## Requirements

- OCaml 4.13 or later
- `ocamlfind` (`opam install ocamlfind`)
- No third-party packages — uses only `unix` from the standard library

## Build

```sh
make build
```

Compiles `lib/constants.ml`, `lib/models.ml`, and `lib/interplanet_ltx.ml`
into a native executable `interplanet_ltx`.

## Test

```sh
make test
```

Runs the unit test suite and reports `N passed  M failed`.

## Lint

```sh
make lint
```

Type-checks the library sources without producing an executable.

## Module Layout

```
lib/
  constants.ml        — VERSION, DEFAULT_QUANTUM, DEFAULT_API_BASE, DEFAULT_SEGMENTS
  models.ml           — ltx_node, ltx_plan, ltx_timed_segment, ltx_node_url, delay_matrix_entry
  interplanet_ltx.ml  — full SDK implementation
test/
  unit_test.ml        — 88+ assertions across 12 sections
```

## Public API

All functions are in the `Interplanet_ltx` module:

| Function | Description |
|---|---|
| `create_plan ?title ?start ?quantum ?mode ?host_name ?host_location ?remote_name ?remote_location ?delay ?nodes ?segments ()` | Create a new LTX plan |
| `upgrade_config plan` | Upgrade a v1 plan to v2 format |
| `compute_segments plan` | Expand segment templates into timed segments |
| `total_min plan` | Total meeting duration in minutes |
| `make_plan_id plan` | Generate a deterministic plan ID |
| `encode_hash plan` | Encode plan as a URL fragment (`#l=…`) |
| `decode_hash hash` | Decode a URL fragment back to a plan |
| `build_node_urls plan base_url` | Build per-node join URLs |
| `build_delay_matrix plan` | Build pairwise delay matrix |
| `generate_ics plan` | Generate an iCalendar (.ics) document |
| `format_hms sec` | Format seconds as `MM:SS` or `HH:MM:SS` |

## Quick Start

```ocaml
(* Compile: ocamlfind ocamlopt -package unix -linkpkg
            lib/constants.ml lib/models.ml lib/interplanet_ltx.ml main.ml -o main *)

let () =
  let plan = Interplanet_ltx.create_plan
    ~title:"Earth-Mars Session"
    ~start:"2040-01-15T14:00:00Z"
    ~remote_name:"Mars Hab-01"
    ~delay:1240
    () in
  let plan_id = Interplanet_ltx.make_plan_id plan in
  let total   = Interplanet_ltx.total_min plan in
  Printf.printf "Plan ID : %s\n" plan_id;
  Printf.printf "Duration: %d min\n" total
```

## Version

1.0.0
