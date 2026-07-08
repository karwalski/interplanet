defmodule InterplanetLtx.Models do
  @moduledoc """
  Struct definitions for the LTX (Light-Time eXchange) library.
  Pure Elixir port of ltx-sdk.js — Story 49.1.
  """

  defmodule LtxNode do
    @moduledoc "Represents a node (participant) in an LTX session."
    @enforce_keys [:id, :name, :role, :delay, :location]
    defstruct [:id, :name, :role, :delay, :location]
  end

  defmodule LtxSegmentTemplate do
    @moduledoc """
    Segment template: type and quantum multiplier.
    `speaker`/`label` (Epic 71 conference mode, v1.1) are optional and nil for
    classic two-node plans, so pre-Epic-71 plans keep their frozen v2 planId.
    """
    @enforce_keys [:type, :q]
    defstruct [:type, :q, :speaker, :label]
  end

  defmodule LtxSegment do
    @moduledoc "Computed timed segment."
    defstruct [:type, :q, :start, :end, :dur_min, :start_ms, :end_ms]
  end

  defmodule LtxNodeUrl do
    @moduledoc "Perspective URL for a node in a plan."
    defstruct [:node_id, :name, :role, :url]
  end

  defmodule LtxPlan do
    @moduledoc "Full LTX session plan (v2)."
    @enforce_keys [:v, :title, :start, :quantum, :mode, :nodes, :segments]
    defstruct [:v, :title, :start, :quantum, :mode, :nodes, :segments]
  end
end
