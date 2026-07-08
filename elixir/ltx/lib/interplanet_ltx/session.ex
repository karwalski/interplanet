# session.ex — LTX v1.1 session state machine (Epic 72).
# Mirrors typescript/ltx/src/session.ts (Stories 68.1/68.2 —
# LTX-SPECIFICATION.md §5 plan lock, DEGRADED, quorum; §5.4 delay violations).
#
# Pure and time-injected: every event carries "nowMs", transition/2 never
# reads a clock, and all side-effects are returned as effect maps.

defmodule InterplanetLtx.Session do
  @moduledoc """
  Pure session state machine over string-keyed plan maps.

  States: DRAFT LOCKING LOCKED ACTIVE DEGRADED EMERGENCY_HOLD COMPLETE ABORTED.
  Events are string-keyed maps with a "type" key (matching the conformance
  vectors), e.g. `%{"type" => "START_LOCK", "nowMs" => 1000}`.
  """

  alias InterplanetLtx.Constants
  alias InterplanetLtx.Segments

  # ── Helpers ─────────────────────────────────────────────────────────────────

  defp participants(plan) do
    Enum.filter(plan["nodes"] || [], fn n -> n["role"] == "PARTICIPANT" end)
  end

  @doc "2 × one-way delay to the furthest node, in ms (LTX-SPECIFICATION.md §5.1)."
  def lock_timeout_ms(plan) do
    max_delay_s =
      Enum.reduce(plan["nodes"] || [], 0, fn n, m -> max(m, n["delay"] || 0) end)

    Constants.default_plan_lock_timeout_factor() * max_delay_s * 1000
  end

  defp quorum_count(plan, quorum) do
    total = length(participants(plan))

    cond do
      quorum in [:majority, "majority"] -> div(total, 2) + 1
      is_integer(quorum) -> quorum |> max(1) |> min(total)
      true -> total
    end
  end

  # Ascending-delay fallback ordering over confirmed participants (§5.3).
  defp confirmed_subset(ctx) do
    host = List.first(ctx.plan["nodes"])

    confirmed =
      participants(ctx.plan)
      |> Enum.filter(fn n -> ctx.confirmations[n["id"]] == ctx.plan_id end)
      |> Enum.sort_by(fn n -> n["delay"] || 0 end)
      |> Enum.map(fn n -> n["id"] end)

    [host["id"] | confirmed]
  end

  defp full_lock_reached(ctx) do
    Enum.all?(participants(ctx.plan), fn n ->
      ctx.confirmations[n["id"]] == ctx.plan_id
    end)
  end

  defp quorum_reached(ctx) do
    confirmed =
      participants(ctx.plan)
      |> Enum.count(fn n -> ctx.confirmations[n["id"]] == ctx.plan_id end)

    confirmed >= ctx.quorum_threshold
  end

  # Declared one-way delay for a node: v3 pair matrix HOST row, else node delay.
  defp declared_delay_s(plan, node_id) do
    node = Enum.find(plan["nodes"] || [], fn n -> n["id"] == node_id end)

    cond do
      is_nil(node) ->
        nil

      is_map(plan["delays"]) ->
        host_id = List.first(plan["nodes"])["id"]
        key = [host_id, node_id] |> Enum.sort() |> Enum.join("|")

        if is_number(plan["delays"][key]),
          do: plan["delays"][key],
          else: node["delay"] || 0

      true ->
        node["delay"] || 0
    end
  end

  # ── Session construction ────────────────────────────────────────────────────

  @doc """
  Create a session context in DRAFT state. `plan_id` is supplied by the
  caller (`Segments.make_plan_id/1`) so this module stays pure.
  Options: `quorum: :all | :majority | integer` (default `:all`).
  """
  def create_session(plan, plan_id, opts \\ []) do
    plan = Segments.plan_map(plan)

    %{
      state: "DRAFT",
      plan: plan,
      plan_id: plan_id,
      session_root_plan_id: plan_id,
      plan_version: plan["planVersion"] || 1,
      lock: nil,
      lock_started_at_ms: nil,
      lock_timeout_ms: lock_timeout_ms(plan),
      confirmations: %{},
      mismatched: [],
      quorum_threshold: quorum_count(plan, Keyword.get(opts, :quorum, :all)),
      subset: nil,
      degraded_reasons: [],
      resume_state: nil,
      pending_amendment: nil
    }
  end

  # ── Transition plumbing ─────────────────────────────────────────────────────

  defp moved(ctx, to, event, effects, detail \\ nil) do
    entry =
      %{
        type: "state_transition",
        from: ctx.state,
        to: to,
        event: event["type"],
        at_ms: event["nowMs"]
      }
      |> then(fn e -> if detail, do: Map.put(e, :detail, detail), else: e end)

    %{ctx: %{ctx | state: to}, effects: [%{kind: "audit", entry: entry} | effects]}
  end

  defp unchanged(ctx, effects \\ []), do: %{ctx: ctx, effects: effects}

  defp invalid(ctx, event) do
    %{kind: "notify", level: "warn", code: "INVALID_EVENT",
      detail: "#{event["type"]} ignored in state #{ctx.state}"}
  end

  defp degrade(ctx, event, reason, extra \\ []) do
    next = %{ctx | degraded_reasons: ctx.degraded_reasons ++ [reason]}

    effects =
      [
        %{kind: "notify", level: "warn", code: "DEGRADED", detail: reason},
        %{kind: "escalate", code: "DEGRADED", detail: reason}
      ] ++ extra

    if ctx.state == "DEGRADED" do
      unchanged(next, Enum.take(effects, 1))
    else
      moved(next, "DEGRADED", event, effects, reason)
    end
  end

  # ── Transition function ─────────────────────────────────────────────────────

  @doc """
  Advance the session state machine. Pure: same (ctx, event) always yields
  the same result. Returns `%{ctx: ctx, effects: effects}`.
  """
  def transition(ctx, %{"type" => "START_LOCK"} = event) do
    if ctx.state != "DRAFT" do
      unchanged(ctx, [invalid(ctx, event)])
    else
      host_id = List.first(ctx.plan["nodes"])["id"]

      next = %{ctx |
        lock_started_at_ms: event["nowMs"],
        confirmations: Map.put(ctx.confirmations, host_id, ctx.plan_id)
      }

      moved(next, "LOCKING", event, [])
    end
  end

  def transition(ctx, %{"type" => "PLAN_CONFIRM"} = event) do
    if ctx.state not in ["LOCKING", "DEGRADED"] do
      unchanged(ctx, [invalid(ctx, event)])
    else
      node_id = event["nodeId"]
      plan_id = event["planId"]
      next = %{ctx | confirmations: Map.put(ctx.confirmations, node_id, plan_id)}

      cond do
        plan_id != ctx.plan_id ->
          next = %{next | mismatched: Enum.reject(ctx.mismatched, &(&1 == node_id)) ++ [node_id]}

          unchanged(next, [%{
            kind: "notify", level: "warn", code: "PLANID_MISMATCH",
            detail: "#{node_id} confirmed #{plan_id}, expected #{ctx.plan_id} (resolve per §5.5)"
          }])

        true ->
          next = %{next | mismatched: Enum.reject(ctx.mismatched, &(&1 == node_id))}

          if full_lock_reached(next) do
            locked = %{next | lock: "FULL", subset: nil}
            # Late full confirmation recovers a DEGRADED quorum lock (§5.2).
            moved(locked, "LOCKED", event, [%{
              kind: "notify", level: "info", code: "LOCKED", detail: "full lock achieved"
            }])
          else
            unchanged(next)
          end
      end
    end
  end

  def transition(ctx, %{"type" => "TICK"} = event) do
    cond do
      ctx.state != "LOCKING" -> unchanged(ctx)
      is_nil(ctx.lock_started_at_ms) -> unchanged(ctx)
      event["nowMs"] - ctx.lock_started_at_ms < ctx.lock_timeout_ms -> unchanged(ctx)
      # Lock timeout expired (§5.1).
      quorum_reached(ctx) ->
        subset = confirmed_subset(ctx)
        next = %{ctx | lock: "QUORUM", subset: subset}

        missing =
          participants(ctx.plan)
          |> Enum.filter(fn n -> ctx.confirmations[n["id"]] != ctx.plan_id end)
          |> Enum.map(fn n -> n["id"] end)

        degrade(next, event,
          "quorum lock with subset [#{Enum.join(subset, ",")}]; unconfirmed: [#{Enum.join(missing, ",")}]")

      true ->
        degrade(ctx, event, "plan-lock timeout without quorum")
    end
  end

  def transition(ctx, %{"type" => "SESSION_START"} = event) do
    cond do
      ctx.state == "LOCKED" ->
        moved(ctx, "ACTIVE", event, [])

      ctx.state == "DEGRADED" and not is_nil(ctx.lock) ->
        # §5.2: escalation to HOST required before TX.
        unchanged(ctx, [%{
          kind: "escalate", code: "DEGRADED_START",
          detail: "session start requested while DEGRADED; HOST decision required"
        }])

      true ->
        unchanged(ctx, [invalid(ctx, event)])
    end
  end

  def transition(ctx, %{"type" => "DELAY_MEASURED"} = event) do
    if ctx.state not in ["ACTIVE", "LOCKED", "DEGRADED"] do
      unchanged(ctx)
    else
      declared = declared_delay_s(ctx.plan, event["nodeId"])
      measured = event["measuredDelayS"]

      cond do
        is_nil(declared) ->
          unchanged(ctx, [invalid(ctx, event)])

        abs(measured - declared) > Constants.delay_violation_degraded_s() ->
          degrade(ctx, event,
            "delay violation #{event["nodeId"]}: measured #{measured}s vs declared #{declared}s (>#{Constants.delay_violation_degraded_s()}s)")

        abs(measured - declared) > Constants.delay_violation_warn_s() ->
          unchanged(ctx, [%{
            kind: "notify", level: "warn", code: "DELAY_VIOLATION",
            detail: "#{event["nodeId"]}: measured #{measured}s vs declared #{declared}s"
          }])

        true ->
          unchanged(ctx)
      end
    end
  end

  def transition(ctx, %{"type" => "EOK_OVERRIDE"} = event) do
    cond do
      ctx.state in ["COMPLETE", "ABORTED"] ->
        unchanged(ctx)

      event["verified"] != true ->
        unchanged(ctx, [%{
          kind: "notify", level: "error", code: "OVERRIDE_REJECTED",
          detail: event["reason"] || "override failed verification"
        }])

      ctx.state == "EMERGENCY_HOLD" ->
        unchanged(ctx)

      true ->
        next = %{ctx | resume_state: ctx.state}

        moved(next, "EMERGENCY_HOLD", event, [%{
          kind: "notify", level: "error", code: "EMERGENCY_HOLD",
          detail: event["reason"] || "verified EOK override"
        }])
    end
  end

  def transition(ctx, %{"type" => "AMENDMENT_PROPOSED"} = event) do
    cond do
      ctx.state not in ["ACTIVE", "LOCKED", "DEGRADED"] ->
        unchanged(ctx, [invalid(ctx, event)])

      event["planVersion"] != ctx.plan_version + 1 ->
        unchanged(ctx, [%{
          kind: "notify", level: "error", code: "AMENDMENT_REJECTED",
          detail: "planVersion #{event["planVersion"]} != #{ctx.plan_version} + 1"
        }])

      true ->
        # Delta re-lock (§6.4): timeout scoped to the furthest affected node.
        affected_ids = event["affectedNodeIds"] || []

        max_delay_s =
          (ctx.plan["nodes"] || [])
          |> Enum.filter(fn n -> n["id"] in affected_ids end)
          |> Enum.reduce(0, fn n, m -> max(m, n["delay"] || 0) end)

        pending = %{
          plan_id: event["planId"],
          plan_version: event["planVersion"],
          affected_node_ids: affected_ids,
          confirmed: [],
          proposed_at_ms: event["nowMs"],
          timeout_ms: Constants.default_plan_lock_timeout_factor() * max_delay_s * 1000
        }

        unchanged(%{ctx | pending_amendment: pending}, [%{
          kind: "notify", level: "info", code: "AMENDMENT_PROPOSED",
          detail: "plan #{event["planId"]} v#{event["planVersion"]}; awaiting [#{Enum.join(affected_ids, ",")}]"
        }])
    end
  end

  def transition(ctx, %{"type" => "AMENDMENT_CONFIRMED"} = event) do
    pa = ctx.pending_amendment

    cond do
      is_nil(pa) or event["planId"] != pa.plan_id ->
        unchanged(ctx, [invalid(ctx, event)])

      event["nodeId"] not in pa.affected_node_ids ->
        unchanged(ctx)

      true ->
        confirmed =
          Enum.reject(pa.confirmed, &(&1 == event["nodeId"])) ++ [event["nodeId"]]

        if length(confirmed) < length(pa.affected_node_ids) do
          unchanged(%{ctx | pending_amendment: %{pa | confirmed: confirmed}})
        else
          # All affected nodes confirmed — the amendment applies. The caller
          # swaps ctx.plan for the verified successor plan.
          next = %{ctx |
            plan_id: pa.plan_id,
            plan_version: pa.plan_version,
            pending_amendment: nil
          }

          unchanged(next, [%{
            kind: "notify", level: "info", code: "AMENDMENT_APPLIED",
            detail: "plan #{pa.plan_id} v#{pa.plan_version} in effect (root #{ctx.session_root_plan_id})"
          }])
        end
    end
  end

  def transition(ctx, %{"type" => "HOST_DECISION"} = event) do
    cond do
      event["decision"] == "abort" ->
        if ctx.state in ["COMPLETE", "ABORTED"] do
          unchanged(ctx)
        else
          moved(ctx, "ABORTED", event, [])
        end

      event["decision"] == "resume" and ctx.state == "EMERGENCY_HOLD" ->
        back = ctx.resume_state || "ACTIVE"
        moved(%{ctx | resume_state: nil}, back, event, [])

      event["decision"] == "continue" and ctx.state == "DEGRADED" ->
        # §5.2: HOST elects to continue with the confirmed subset.
        moved(ctx, "ACTIVE", event, [%{
          kind: "notify", level: "warn", code: "CONTINUE_DEGRADED",
          detail:
            if(ctx.subset,
              do: "continuing with subset [#{Enum.join(ctx.subset, ",")}]",
              else: "continuing despite degraded condition")
        }])

      true ->
        unchanged(ctx, [invalid(ctx, event)])
    end
  end

  def transition(ctx, %{"type" => "SESSION_END"} = event) do
    if ctx.state in ["ACTIVE", "DEGRADED"] do
      moved(ctx, "COMPLETE", event, [])
    else
      unchanged(ctx, [invalid(ctx, event)])
    end
  end
end
