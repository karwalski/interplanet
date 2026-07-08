# amend.ex — LTX v1.1 plan amendment chains (Epic 72).
# Mirrors typescript/ltx/src/amend.ts (Story 68.3 — LTX-SPECIFICATION.md §6.4,
# LTX-SECURITY.md §7.6).
#
# An amendment replaces a locked plan with a re-signed successor:
# planVersion + 1 and prevPlanHash = SHA-256(canonicalJSON(predecessor)).
# The canonical-JSON hash is order-insensitive and collision-resistant —
# never the legacy v2 polynomial planId hash.

defmodule InterplanetLtx.Amend do
  @moduledoc """
  Amendment-chain hashing and verification over signed plan envelopes
  (`%{"plan" => plan, "coseSign1" => cs}` maps as produced by
  `InterplanetLtx.Security.sign_plan/3`).
  """

  alias InterplanetLtx.Security

  @doc "SHA-256 hex of the canonical JSON of a plan."
  def plan_hash(plan) do
    :crypto.hash(:sha256, Security.canonical_json(plan))
    |> Base.encode16(case: :lower)
  end

  @doc """
  Create a signed amendment of `signed_plan` with `changes` merged in.
  The successor is always a v3 plan (LTX-SPECIFICATION.md §4.4); `v`,
  `planVersion` and `prevPlanHash` cannot be overridden via `changes`.
  """
  def create_amendment(signed_plan, changes, private_key_b64, pub_key_b64 \\ nil) do
    prev = signed_plan[:plan] || signed_plan["plan"]
    prev_version = prev["planVersion"] || 1

    successor =
      prev
      |> Map.merge(changes)
      |> Map.put("v", 3)
      |> Map.put("planVersion", prev_version + 1)
      |> Map.put("prevPlanHash", plan_hash(prev))

    Security.sign_plan(successor, private_key_b64, pub_key_b64)
  end

  @doc """
  Verify an amendment chain: `chain` is a list of signed plan envelopes,
  the first being the root plan, each later element a successive amendment.
  Checks, per link: HOST signature against `key_cache`, planVersion increment
  of exactly 1, and prevPlanHash equality with the recomputed predecessor
  hash (LTX-SECURITY.md §7.6). Returns `%{valid: bool, reason: string?}`.
  """
  def verify_amendment_chain(chain, key_cache) when is_list(chain) and chain != [] do
    sig_failure =
      chain
      |> Enum.with_index()
      |> Enum.find_value(fn {link, i} ->
        case Security.verify_plan(link, key_cache) do
          %{valid: true} -> nil
          %{valid: false, reason: reason} -> %{valid: false, reason: "link_#{i}_#{reason}"}
        end
      end)

    if sig_failure do
      sig_failure
    else
      root = plan_of(hd(chain))

      if root["prevPlanHash"] != nil do
        %{valid: false, reason: "root_has_prev_hash"}
      else
        verify_links(tl(chain), root, root["planVersion"] || 1, 1)
      end
    end
  end

  def verify_amendment_chain(_, _), do: %{valid: false, reason: "empty_chain"}

  defp verify_links([], _prev_plan, _prev_version, _i), do: %{valid: true}

  defp verify_links([link | rest], prev_plan, prev_version, i) do
    p = plan_of(link)

    cond do
      p["v"] != 3 ->
        %{valid: false, reason: "link_#{i}_not_v3"}

      (p["planVersion"] || 0) != prev_version + 1 ->
        %{valid: false, reason: "link_#{i}_version_gap"}

      p["prevPlanHash"] != plan_hash(prev_plan) ->
        %{valid: false, reason: "link_#{i}_prev_hash_mismatch"}

      true ->
        verify_links(rest, p, p["planVersion"], i + 1)
    end
  end

  defp plan_of(link), do: link[:plan] || link["plan"]
end
