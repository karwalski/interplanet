/**
 * InterplanetLTX.cs — C# P/Invoke bindings for libitx
 * Story 33.3 — C LTX library · .NET 6+
 *
 * Build the native library first:
 *   make shared   (produces lib/libitx.so or lib/libitx.dylib)
 *
 * Then reference this file in your C# project and set:
 *   InterplanetLTX.LibPath = "/path/to/libitx.so";
 */

using System;
using System.Runtime.InteropServices;
using System.Text;

namespace InterPlanet;

/* ── Native structs (must match C layout exactly) ─────────────────────── */

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
internal unsafe struct NativeNode
{
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
    public string Id;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
    public string Name;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
    public string Role;
    public int Delay;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
    public string Location;
}

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
internal struct NativeSegTmpl
{
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
    public string Type;
    public int Q;
}

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
internal struct NativeSegment
{
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
    public string Type;
    public int Q;
    public long StartMs;
    public long EndMs;
    public int  DurMin;
}

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
internal unsafe struct NativePlan
{
    public int V;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
    public string Title;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]
    public string Start;
    public int Quantum;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
    public string Mode;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 8)]
    public NativeNode[] Nodes;
    public int NodeCount;
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 32)]
    public NativeSegTmpl[] Segments;
    public int SegCount;
}

[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
internal struct NativeNodeUrl
{
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
    public string NodeId;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
    public string Name;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
    public string Role;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 1024)]
    public string Url;
}

/* ── P/Invoke declarations ────────────────────────────────────────────── */

internal static class Native
{
    internal const string Lib = "libitx";

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern void itx_create_plan(
        ref NativePlan plan, string? title, string? startIso, int delaySec);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern void itx_compute_segments(
        ref NativePlan plan,
        [MarshalAs(UnmanagedType.LPArray, SizeConst = 32)] NativeSegment[] segs,
        ref int segCount);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int itx_total_min(ref NativePlan plan);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern void itx_make_plan_id(
        ref NativePlan plan,
        [MarshalAs(UnmanagedType.LPStr)] StringBuilder buf);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern void itx_encode_hash(
        ref NativePlan plan,
        [MarshalAs(UnmanagedType.LPStr)] StringBuilder buf);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern int itx_decode_hash(
        [MarshalAs(UnmanagedType.LPStr)] string hash,
        ref NativePlan plan);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern void itx_build_node_urls(
        ref NativePlan plan,
        [MarshalAs(UnmanagedType.LPStr)] string baseUrl,
        [MarshalAs(UnmanagedType.LPArray, SizeConst = 8)] NativeNodeUrl[] urls,
        ref int urlCount);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern void itx_generate_ics(
        ref NativePlan plan,
        [MarshalAs(UnmanagedType.LPStr)] StringBuilder buf);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern void itx_format_hms(
        int seconds,
        [MarshalAs(UnmanagedType.LPStr)] StringBuilder buf);

    [DllImport(Lib, CallingConvention = CallingConvention.Cdecl)]
    internal static extern void itx_format_utc(
        long epochMs,
        [MarshalAs(UnmanagedType.LPStr)] StringBuilder buf);
}

/* ── Public C# API ────────────────────────────────────────────────────── */

/// <summary>Managed view of an LTX participant node.</summary>
public record LtxNode(string Id, string Name, string Role, int Delay, string Location);

/// <summary>Managed view of a segment template entry.</summary>
public record LtxSegmentTemplate(string Type, int Q);

/// <summary>Managed view of a computed, timed segment.</summary>
public record LtxSegment(string Type, int Q, long StartMs, long EndMs, int DurMin);

/// <summary>Managed view of a per-node URL.</summary>
public record LtxNodeUrl(string NodeId, string Name, string Role, string Url);

/// <summary>
///   C# wrapper around the native libitx LTX session plan.
/// </summary>
public sealed class LtxPlan
{
    private NativePlan _native;

    /// <summary>Library version string (from compile-time constant).</summary>
    public const string Version = "1.0.0";

    private LtxPlan(NativePlan native) => _native = native;

    /// <summary>Schema version (2).</summary>
    public int    V       => _native.V;
    /// <summary>Session title.</summary>
    public string Title   => _native.Title;
    /// <summary>ISO-8601 UTC start time.</summary>
    public string Start   => _native.Start;
    /// <summary>Minutes per quantum.</summary>
    public int    Quantum => _native.Quantum;
    /// <summary>Mode string (e.g. "LTX").</summary>
    public string Mode    => _native.Mode;

    /// <summary>Nodes in this plan.</summary>
    public LtxNode[] Nodes
    {
        get
        {
            var out_ = new LtxNode[_native.NodeCount];
            for (int i = 0; i < _native.NodeCount; i++)
            {
                var n = _native.Nodes[i];
                out_[i] = new LtxNode(n.Id, n.Name, n.Role, n.Delay, n.Location);
            }
            return out_;
        }
    }

    /// <summary>Segment templates in this plan.</summary>
    public LtxSegmentTemplate[] SegmentTemplates
    {
        get
        {
            var out_ = new LtxSegmentTemplate[_native.SegCount];
            for (int i = 0; i < _native.SegCount; i++)
                out_[i] = new LtxSegmentTemplate(_native.Segments[i].Type, _native.Segments[i].Q);
            return out_;
        }
    }

    /// <summary>Compute timed segments for this plan.</summary>
    public LtxSegment[] ComputeSegments()
    {
        var raw = new NativeSegment[32];
        int n = 0;
        Native.itx_compute_segments(ref _native, raw, ref n);
        var out_ = new LtxSegment[n];
        for (int i = 0; i < n; i++)
            out_[i] = new LtxSegment(raw[i].Type, raw[i].Q, raw[i].StartMs, raw[i].EndMs, raw[i].DurMin);
        return out_;
    }

    /// <summary>Total session duration in minutes.</summary>
    public int TotalMin() => Native.itx_total_min(ref _native);

    /// <summary>Deterministic plan ID string (e.g. "LTX-20260315-EARTHHQ-MARS-v2-a3b2c1d0").</summary>
    public string MakePlanId()
    {
        var sb = new StringBuilder(80);
        Native.itx_make_plan_id(ref _native, sb);
        return sb.ToString();
    }

    /// <summary>Encode the plan as a URL hash fragment ("#l=…").</summary>
    public string EncodeHash()
    {
        var sb = new StringBuilder(4096);
        Native.itx_encode_hash(ref _native, sb);
        return sb.ToString();
    }

    /// <summary>Build perspective URLs for all nodes.</summary>
    public LtxNodeUrl[] BuildNodeUrls(string baseUrl)
    {
        var raw = new NativeNodeUrl[8];
        int n = 0;
        Native.itx_build_node_urls(ref _native, baseUrl, raw, ref n);
        var out_ = new LtxNodeUrl[n];
        for (int i = 0; i < n; i++)
            out_[i] = new LtxNodeUrl(raw[i].NodeId, raw[i].Name, raw[i].Role, raw[i].Url);
        return out_;
    }

    /// <summary>Generate LTX-extended iCalendar (.ics) content.</summary>
    public string GenerateICS()
    {
        var sb = new StringBuilder(8192);
        Native.itx_generate_ics(ref _native, sb);
        return sb.ToString();
    }

    /* ── Static factory methods ───────────────────────────────────────── */

    /// <summary>
    ///   Create a plan with default Earth HQ → Mars Hab-01 nodes.
    /// </summary>
    /// <param name="title">Session title (null → "LTX Session")</param>
    /// <param name="startIso">ISO-8601 UTC start time</param>
    /// <param name="delaySec">One-way light-travel delay in seconds</param>
    public static LtxPlan Create(string? title, string startIso, int delaySec = 0)
    {
        var native = new NativePlan
        {
            Nodes    = new NativeNode[8],
            Segments = new NativeSegTmpl[32],
        };
        Native.itx_create_plan(ref native, title, startIso, delaySec);
        return new LtxPlan(native);
    }

    /// <summary>
    ///   Decode a plan from a URL hash fragment ("#l=…" or "l=…").
    /// </summary>
    /// <exception cref="FormatException">Thrown if the hash is invalid.</exception>
    public static LtxPlan DecodeHash(string hash)
    {
        var native = new NativePlan
        {
            Nodes    = new NativeNode[8],
            Segments = new NativeSegTmpl[32],
        };
        int rc = Native.itx_decode_hash(hash, ref native);
        if (rc != 0) throw new FormatException($"InterplanetLTX: invalid hash: {hash}");
        return new LtxPlan(native);
    }

    /* ── Formatting helpers ───────────────────────────────────────────── */

    /// <summary>Format a duration in seconds as "MM:SS" or "HH:MM:SS".</summary>
    public static string FormatHMS(int seconds)
    {
        var sb = new StringBuilder(12);
        Native.itx_format_hms(seconds, sb);
        return sb.ToString();
    }

    /// <summary>Format UTC epoch milliseconds as "HH:MM:SS UTC".</summary>
    public static string FormatUTC(long epochMs)
    {
        var sb = new StringBuilder(16);
        Native.itx_format_utc(epochMs, sb);
        return sb.ToString();
    }
}
