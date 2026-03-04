/**
 * itx.hpp — C++ header-only wrapper for libitx
 * Story 33.3 — C LTX library · C++17
 *
 * Usage:
 *   #include "itx.hpp"
 *   itx::Plan plan = itx::createPlan("Q3 Review", "2026-03-15T14:00:00Z", 860);
 *   std::string hash = plan.encodeHash();
 */

#ifndef ITX_HPP
#define ITX_HPP

#include "libitx.h"

#include <string>
#include <vector>
#include <stdexcept>

namespace itx {

/* ── Value types ─────────────────────────────────────────────────────────── */

struct Node {
    std::string id;
    std::string name;
    std::string role;
    int         delay;
    std::string location;
};

struct SegmentTemplate {
    std::string type;
    int         q;
};

struct Segment {
    std::string type;
    int         q;
    long long   start_ms;
    long long   end_ms;
    int         dur_min;
};

struct NodeUrl {
    std::string node_id;
    std::string name;
    std::string role;
    std::string url;
};

/* ── Plan ────────────────────────────────────────────────────────────────── */

class Plan {
public:
    Plan() { itx_create_plan(&_p, nullptr, nullptr, 0); }

    explicit Plan(const itx_plan_t &raw) : _p(raw) {}

    /** Access the underlying C struct (e.g. for passing to C functions). */
    const itx_plan_t &raw() const { return _p; }
    itx_plan_t       &raw()       { return _p; }

    /* ── Computed properties ──────────────────────────────────────────── */

    std::vector<Segment> computeSegments() const {
        itx_segment_t segs[ITX_MAX_SEGMENTS];
        int n = 0;
        itx_compute_segments(&_p, segs, &n);
        std::vector<Segment> out;
        out.reserve(n);
        for (int i = 0; i < n; i++) {
            out.push_back({ segs[i].type, segs[i].q,
                            segs[i].start_ms, segs[i].end_ms,
                            segs[i].dur_min });
        }
        return out;
    }

    int totalMin() const { return itx_total_min(&_p); }

    std::string makePlanId() const {
        char buf[ITX_PLAN_ID_LEN];
        itx_make_plan_id(&_p, buf);
        return buf;
    }

    std::string encodeHash() const {
        char buf[ITX_HASH_BUF];
        itx_encode_hash(&_p, buf);
        return buf;
    }

    std::vector<NodeUrl> buildNodeUrls(const std::string &base_url) const {
        itx_node_url_t urls[ITX_MAX_NODES];
        int n = 0;
        itx_build_node_urls(&_p, base_url.c_str(), urls, &n);
        std::vector<NodeUrl> out;
        out.reserve(n);
        for (int i = 0; i < n; i++) {
            out.push_back({ urls[i].node_id, urls[i].name,
                            urls[i].role,    urls[i].url });
        }
        return out;
    }

    std::string generateICS() const {
        char buf[ITX_ICS_BUF];
        itx_generate_ics(&_p, buf);
        return buf;
    }

    /* ── Accessors ─────────────────────────────────────────────────────── */

    int         v()          const { return _p.v; }
    std::string title()      const { return _p.title; }
    std::string start()      const { return _p.start; }
    int         quantum()    const { return _p.quantum; }
    std::string mode()       const { return _p.mode; }
    int         nodeCount()  const { return _p.node_count; }
    int         segCount()   const { return _p.seg_count; }

    Node node(int i) const {
        if (i < 0 || i >= _p.node_count) throw std::out_of_range("node index");
        const auto &n = _p.nodes[i];
        return { n.id, n.name, n.role, n.delay, n.location };
    }

    SegmentTemplate segTemplate(int i) const {
        if (i < 0 || i >= _p.seg_count) throw std::out_of_range("segment index");
        return { _p.segments[i].type, _p.segments[i].q };
    }

private:
    itx_plan_t _p{};
};

/* ── Factory functions ───────────────────────────────────────────────────── */

/**
 * Create a plan with default Earth HQ → Mars Hab-01 nodes.
 *
 * @param title      Session title (empty → "LTX Session")
 * @param start_iso  ISO-8601 UTC start time
 * @param delay_sec  One-way light-travel delay in seconds
 */
inline Plan createPlan(const std::string &title,
                       const std::string &start_iso,
                       int                delay_sec = 0) {
    itx_plan_t p;
    itx_create_plan(&p,
                    title.empty()     ? nullptr : title.c_str(),
                    start_iso.empty() ? nullptr : start_iso.c_str(),
                    delay_sec);
    return Plan(p);
}

/**
 * Decode a plan from a URL hash fragment ("#l=…" or "l=…").
 * @throws std::runtime_error on parse failure.
 */
inline Plan decodeHash(const std::string &hash) {
    itx_plan_t p;
    int rc = itx_decode_hash(hash.c_str(), &p);
    if (rc != 0) throw std::runtime_error("itx::decodeHash: invalid hash");
    return Plan(p);
}

/* ── Formatting helpers ──────────────────────────────────────────────────── */

inline std::string formatHMS(int seconds) {
    char buf[12];
    itx_format_hms(seconds, buf);
    return buf;
}

inline std::string formatUTC(long long epoch_ms) {
    char buf[16];
    itx_format_utc(epoch_ms, buf);
    return buf;
}

/* ── Constants ───────────────────────────────────────────────────────────── */

constexpr const char *VERSION         = ITX_VERSION_STRING;
constexpr int         DEFAULT_QUANTUM = 3;
constexpr int         DEFAULT_SEG_COUNT = 7;

} /* namespace itx */

#endif /* ITX_HPP */
