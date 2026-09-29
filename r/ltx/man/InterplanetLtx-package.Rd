\name{InterplanetLtx-package}
\alias{InterplanetLtx-package}
\alias{InterplanetLtx}
\alias{create_plan}
\alias{ltx_node}
\alias{ltx_segment_spec}
\alias{compute_segments}
\alias{total_min}
\alias{make_plan_id}
\alias{encode_hash}
\alias{decode_hash}
\alias{build_node_urls}
\alias{generate_ics}
\alias{build_delay_matrix}
\alias{pair_delay}
\alias{format_hms}
\alias{format_utc}
\alias{json_stringify}
\alias{canonical_json}
\alias{sha256_hex}
\alias{plan_hash}
\alias{imul31_hex}
\alias{b64url_encode}
\alias{b64url_decode}
\alias{validate_plan}
\alias{reserved_field_errors}
\alias{assert_no_reserved_fields}
\alias{upgrade_plan_to_v3}
\docType{package}
\title{LTX (Light-Time eXchange) Protocol SDK}
\description{
R port of the InterPlanet LTX SDK (\code{javascript/ltx/ltx-sdk.js}); see
\code{docs/LTX-SPECIFICATION.md} in the repository.

Plans and segments:
\itemize{
  \item \code{create_plan(...)}, \code{ltx_node(id, name, role, delay = 0, location = "earth")},
    \code{ltx_segment_spec(type, q, speaker = NULL, label = NULL)}: build a plan.
  \item \code{compute_segments(plan)}, \code{total_min(plan)}: segment timeline
    and total length.
  \item \code{upgrade_plan_to_v3(plan)}: v2 to v3 plan upgrade.
}
Identity and encoding:
\itemize{
  \item \code{make_plan_id(plan)}: the frozen v2 planId (reproduces
    \code{spec/golden/plan-ids.json} and \code{plan-id-prefixes.json}).
  \item \code{plan_hash(plan)}, \code{canonical_json(x)}, \code{json_stringify(x)},
    \code{sha256_hex(s)}, \code{imul31_hex(s)}: hashing and JSON serialisation.
  \item \code{encode_hash(plan)}, \code{decode_hash(hash_str)},
    \code{b64url_encode}, \code{b64url_decode}: URL hash form.
  \item \code{build_node_urls(plan, base_url = "")}: per-node links.
}
Validation: \code{validate_plan(plan)}, \code{reserved_field_errors(plan)},
\code{assert_no_reserved_fields(plan, fn_name)}.

Output and delays: \code{generate_ics(plan)}, \code{build_delay_matrix(plan)},
\code{pair_delay(plan, node_id_a, node_id_b)}, \code{format_hms(sec)},
\code{format_utc(dt)}.
}
\keyword{package}
