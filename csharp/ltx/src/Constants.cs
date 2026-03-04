// Constants.cs — SDK constants
// C# port of ltx-sdk.js (Story 33.10)

namespace InterplanetLtx;

public static class Constants
{
    public const string VERSION = "1.0.0";

    public static readonly string[] SEG_TYPES =
    {
        "PLAN_CONFIRM", "TX", "RX", "CAUCUS", "BUFFER", "MERGE"
    };

    public const int DEFAULT_QUANTUM = 3;   // minutes per quantum

    public const string DEFAULT_API_BASE = "https://interplanet.live/api/ltx.php";

    /// <summary>Multiplier for plan-lock timeout: timeout = delay * factor * 1000 ms.</summary>
    public const int DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR = 2;

    /// <summary>Delay difference (seconds) above which a warning is issued.</summary>
    public const int DELAY_VIOLATION_WARN_S = 120;

    /// <summary>Delay difference (seconds) above which session moves to DEGRADED state.</summary>
    public const int DELAY_VIOLATION_DEGRADED_S = 300;

    public static readonly string[] SESSION_STATES =
    {
        "INIT", "LOCKED", "RUNNING", "DEGRADED", "COMPLETE"
    };

    public static readonly List<LtxSegmentTemplate> DEFAULT_SEGMENTS = new()
    {
        new LtxSegmentTemplate("PLAN_CONFIRM", 2),
        new LtxSegmentTemplate("TX",           2),
        new LtxSegmentTemplate("RX",           2),
        new LtxSegmentTemplate("CAUCUS",       2),
        new LtxSegmentTemplate("TX",           2),
        new LtxSegmentTemplate("RX",           2),
        new LtxSegmentTemplate("BUFFER",       1),
    };
}
