defmodule InterplanetLtx.Constants do
  @moduledoc """
  Constants for the LTX (Light-Time eXchange) library.
  Pure Elixir port of ltx-sdk.js — Story 49.1.
  """

  @version "1.0.0"
  @default_quantum 3
  @default_api_base "https://interplanet.live/api/ltx.php"
  @default_segments [
    %{type: "PLAN_CONFIRM", q: 2},
    %{type: "TX",           q: 2},
    %{type: "RX",           q: 2},
    %{type: "CAUCUS",       q: 2},
    %{type: "TX",           q: 2},
    %{type: "RX",           q: 2},
    %{type: "BUFFER",       q: 1}
  ]

  @default_plan_lock_timeout_factor 2
  @delay_violation_warn_s 120
  @delay_violation_degraded_s 300
  @session_states ["INIT", "LOCKED", "RUNNING", "DEGRADED", "COMPLETE"]

  def version, do: @version
  def default_quantum, do: @default_quantum
  def default_api_base, do: @default_api_base
  def default_segments, do: @default_segments
  def default_plan_lock_timeout_factor, do: @default_plan_lock_timeout_factor
  def delay_violation_warn_s, do: @delay_violation_warn_s
  def delay_violation_degraded_s, do: @delay_violation_degraded_s
  def session_states, do: @session_states
end
