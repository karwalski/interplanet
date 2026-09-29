/**
 * itx.hpp — C++ header-only wrapper for libitx
 * Story 33.3 — C LTX library · C++17
 *
 * Usage:
 *   #include "itx.hpp"
 *   itx::Plan plan = itx::createPlan("Q3 Review", "2026-03-15T14:00:00Z", 860);
 *   std::string hash = plan.encodeHash();
 *
 *   // Wire-format plans (JSON as received; see libitx.h "Wire-format plans"):
 *   std::string id = itx::makePlanIdJson(planJsonText);
 *   itx::PlanValidation r = itx::validatePlanJson(planJsonText);
 *   if (!r.valid) std::cerr << r.errors[0].code << " at " << r.errors[0].path;
 */

#ifndef ITX_HPP
#define ITX_HPP

#include "libitx.h"

#include <cstddef>
#include <cstdlib>
#include <memory>
#include <optional>
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

/* ── Wire-format plans (src/itx_plan_json.c) ─────────────────────────────── */
/*
 * Wrappers over the itx_*json* functions. They work on plans as received
 * (JSON text or a parsed tree that keeps key insertion order), reproduce
 * every vector in spec/golden/plan-ids.json and throw std::invalid_argument
 * where the C function reports invalid input.
 */

namespace detail {
/** Take ownership of a malloc'd C string and return it as std::string. */
inline std::string takeCString(char *s, const char *what) {
    if (!s) throw std::invalid_argument(std::string(what) + ": invalid JSON");
    std::string out(s);
    std::free(s);
    return out;
}
} /* namespace detail */

/** Non-owning view of a parsed JSON value (valid while its Json lives). */
class JsonRef {
public:
    JsonRef() = default;
    explicit JsonRef(const itx_json_t *v) : _v(v) {}

    const itx_json_t *raw() const { return _v; }
    explicit operator bool() const { return _v != nullptr; }

    itx_json_kind_t kind() const {
        if (!_v) throw std::logic_error("itx::JsonRef: empty");
        return itx_json_kind(_v);
    }
    bool isNull()   const { return _v && kind() == ITX_JSON_NULL; }
    bool isObject() const { return _v && kind() == ITX_JSON_OBJECT; }
    bool isArray()  const { return _v && kind() == ITX_JSON_ARRAY; }

    /** Object member by key; an empty JsonRef when absent. */
    JsonRef get(const std::string &key) const { return JsonRef(_v ? itx_json_get(_v, key.c_str()) : nullptr); }
    JsonRef operator[](const std::string &key) const { return get(key); }
    /** Array element or object member; an empty JsonRef when out of range. */
    JsonRef at(std::size_t i) const { return JsonRef(_v ? itx_json_at(_v, i) : nullptr); }
    std::size_t size() const { return _v ? itx_json_len(_v) : 0; }
    /** Key of an object member obtained with at(). */
    std::string key() const {
        const char *k = _v ? itx_json_key(_v) : nullptr;
        return k ? k : "";
    }

    std::optional<std::string> str() const {
        const char *s = _v ? itx_json_str(_v) : nullptr;
        if (!s) return std::nullopt;
        return std::string(s);
    }
    std::optional<double> num() const {
        double d = 0;
        if (_v && itx_json_num(_v, &d)) return d;
        return std::nullopt;
    }

    /** JSON.stringify (insertion order). */
    std::string stringify() const {
        if (!_v) throw std::logic_error("itx::JsonRef: empty");
        return detail::takeCString(itx_json_stringify(_v), "itx::stringify");
    }
    /** ltx-sdk.js canonicalJSON (sorted keys, JS number form). */
    std::string canonical() const {
        if (!_v) throw std::logic_error("itx::JsonRef: empty");
        return detail::takeCString(itx_json_canonical(_v), "itx::canonical");
    }

private:
    const itx_json_t *_v = nullptr;
};

/** Owning parsed JSON document (move-only). */
class Json {
public:
    /** JSON.parse. @throws std::invalid_argument on a syntax error. */
    static Json parse(const std::string &text) {
        itx_json_t *v = itx_json_parse(text.c_str());
        if (!v) throw std::invalid_argument("itx::Json::parse: invalid JSON");
        return Json(v);
    }

    JsonRef root() const { return JsonRef(_v.get()); }
    operator JsonRef() const { return root(); }
    JsonRef operator[](const std::string &key) const { return root().get(key); }
    std::string stringify() const { return root().stringify(); }
    std::string canonical() const { return root().canonical(); }

private:
    struct Deleter { void operator()(itx_json_t *v) const { itx_json_free(v); } };
    explicit Json(itx_json_t *v) : _v(v) {}
    std::unique_ptr<itx_json_t, Deleter> _v;
};

/** Canonical JSON of JSON text. @throws std::invalid_argument. */
inline std::string canonicalJson(const std::string &json) {
    return detail::takeCString(itx_canonical_json(json.c_str()), "itx::canonicalJson");
}

/** SHA-256 hex digest (lowercase) of arbitrary bytes. */
inline std::string sha256Hex(const std::string &data) {
    unsigned char dg[32];
    itx_sha256(data.data(), data.size(), dg);
    static const char hx[] = "0123456789abcdef";
    std::string out(64, '0');
    for (int i = 0; i < 32; i++) {
        out[2 * i]     = hx[dg[i] >> 4];
        out[2 * i + 1] = hx[dg[i] & 15];
    }
    return out;
}

/** Frozen v2 hash: imul(31, h) + charCodeAt(i) over UTF-16 code units. */
inline unsigned int imul31Utf16(const std::string &utf8) {
    return itx_imul31_utf16(utf8.c_str());
}

/**
 * makePlanId of a v2/v3 plan as received (v1 configs must be upgraded first).
 * @throws std::invalid_argument on invalid JSON, start or a v1 config.
 */
inline std::string makePlanIdJson(const std::string &plan_json) {
    char buf[ITX_PLAN_ID_LEN];
    if (itx_make_plan_id_json(plan_json.c_str(), buf) != 0)
        throw std::invalid_argument("itx::makePlanIdJson: invalid plan");
    return buf;
}
inline std::string makePlanId(JsonRef plan) {
    char buf[ITX_PLAN_ID_LEN];
    if (!plan || itx_make_plan_id_value(plan.raw(), buf) != 0)
        throw std::invalid_argument("itx::makePlanId: invalid plan");
    return buf;
}

/** planHash: SHA-256 hex of the canonical JSON. @throws std::invalid_argument. */
inline std::string planHashJson(const std::string &plan_json) {
    char hex[65];
    if (itx_plan_hash_json(plan_json.c_str(), hex) != 0)
        throw std::invalid_argument("itx::planHashJson: invalid JSON");
    return hex;
}
inline std::string planHash(JsonRef plan) {
    char hex[65];
    if (!plan || itx_plan_hash_value(plan.raw(), hex) != 0)
        throw std::invalid_argument("itx::planHash: invalid plan");
    return hex;
}

/** One validatePlan finding. */
struct PlanError {
    std::string code;
    std::string path;
    std::string message;
};

/** validatePlan result. */
struct PlanValidation {
    bool                   valid = false;
    bool                   truncated = false;  /**< more than ITX_MAX_PLAN_ERRORS */
    std::vector<PlanError> errors;

    bool hasCode(const std::string &code) const {
        for (const auto &e : errors)
            if (e.code == code) return true;
        return false;
    }
};

namespace detail {
inline PlanValidation toValidation(const itx_plan_validation_t &r) {
    PlanValidation out;
    out.valid = r.valid != 0;
    out.truncated = r.truncated != 0;
    out.errors.reserve(r.error_count);
    for (int i = 0; i < r.error_count; i++)
        out.errors.push_back({ r.errors[i].code, r.errors[i].path, r.errors[i].message });
    return out;
}
} /* namespace detail */

/** validatePlan of JSON text (invalid JSON reports not_an_object). */
inline PlanValidation validatePlanJson(const std::string &plan_json) {
    auto r = std::make_unique<itx_plan_validation_t>();  /* ~20 KB: keep off the stack */
    itx_validate_plan_json(plan_json.c_str(), r.get());
    return detail::toValidation(*r);
}
inline PlanValidation validatePlan(JsonRef plan) {
    auto r = std::make_unique<itx_plan_validation_t>();
    itx_validate_plan_value(plan.raw(), r.get());
    return detail::toValidation(*r);
}

/** First reserved-field violation ("reserved_streams" or
 *  "reserved_branching"), or std::nullopt. */
inline std::optional<std::string> reservedFieldCodeJson(const std::string &plan_json) {
    const char *c = itx_reserved_field_code(plan_json.c_str());
    if (!c) return std::nullopt;
    return std::string(c);
}
inline std::optional<std::string> reservedFieldCode(JsonRef plan) {
    const char *c = plan ? itx_reserved_field_code_value(plan.raw()) : nullptr;
    if (!c) return std::nullopt;
    return std::string(c);
}

/* ── Constants ───────────────────────────────────────────────────────────── */

constexpr const char *VERSION         = ITX_VERSION_STRING;
constexpr int         DEFAULT_QUANTUM = 5;
constexpr int         DEFAULT_SEG_COUNT = 7;

} /* namespace itx */

#endif /* ITX_HPP */
