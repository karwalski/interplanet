/**
 * libitx.h — LTX (Light-Time eXchange) C library
 * Story 33.3 — C LTX library
 *
 * Pure C99, no external dependencies.
 * Independent of libinterplanet (the interplanetary time library).
 */

#ifndef LIBITX_H
#define LIBITX_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ── Version ─────────────────────────────────────────────────────────────── */

#define ITX_VERSION_STRING  "1.0.0"

/* ── Limits ──────────────────────────────────────────────────────────────── */

#define ITX_MAX_NODES     8      /**< Max nodes per plan */
#define ITX_MAX_SEGMENTS  32     /**< Max segment templates per plan */
#define ITX_MAX_STR       256    /**< Max string field length */
#define ITX_PLAN_ID_LEN   128    /**< Plan ID buffer size (non-ASCII names take up to 3 bytes per UTF-16 unit) */
#define ITX_HASH_BUF      21856  /**< encodeHash output buffer size ("#l=" + base64 of ITX_JSON_BUF bytes) */
#define ITX_ICS_BUF       16384  /**< generateICS output buffer size (a full plan needs about 12.7 KB) */
#define ITX_URL_BUF       (ITX_HASH_BUF + 576) /**< Per-node URL buffer size: base URL (up to 511 bytes) + "?node=" + id + the whole hash */
#define ITX_JSON_BUF      16384  /**< Largest wire JSON encoded or decoded */

/* ── Structs ─────────────────────────────────────────────────────────────── */

/** A participant node in an LTX session. */
typedef struct {
    char id[32];            /**< e.g. "N0", "N1" */
    char name[ITX_MAX_STR]; /**< e.g. "Earth HQ" */
    char role[32];          /**< "HOST" or "PARTICIPANT" */
    int  delay;             /**< One-way signal delay in seconds */
    char location[32];      /**< "earth", "mars", "moon" */
} itx_node_t;

/**
 * A segment type+quantum entry in a plan's template list, with optional
 * attribution (LTX-SPECIFICATION.md 3.4.1). An empty speaker or label is
 * absent and is not serialised; set ones are written as
 * {type, q, speaker?, label?}, the ltx-sdk.js key order.
 */
typedef struct {
    char type[32];            /**< "PLAN_CONFIRM", "TX", "RX", "CAUCUS", "BUFFER", "MERGE" */
    int  q;                   /**< Duration in quanta */
    char speaker[32];         /**< Presenting node id, e.g. "N1" ("" = absent) */
    char label[ITX_MAX_STR];  /**< Agenda title (UTF-8, "" = absent) */
} itx_seg_tmpl_t;

/** A computed, timed segment with absolute UTC epoch milliseconds. */
typedef struct {
    char      type[32];
    int       q;
    long long start_ms; /**< UTC epoch milliseconds */
    long long end_ms;   /**< UTC epoch milliseconds */
    int       dur_min;  /**< Duration in minutes (q * quantum) */
} itx_segment_t;

/** An LTX session plan configuration (v2 schema). */
typedef struct {
    int             v;                              /**< Schema version (2) */
    char            title[ITX_MAX_STR];
    char            start[64];                      /**< ISO-8601 UTC start time */
    int             quantum;                        /**< Minutes per quantum */
    char            mode[32];                       /**< e.g. "LTX" */
    itx_node_t      nodes[ITX_MAX_NODES];
    int             node_count;
    itx_seg_tmpl_t  segments[ITX_MAX_SEGMENTS];
    int             seg_count;
} itx_plan_t;

/** A perspective URL for a specific node. */
typedef struct {
    char node_id[32];
    char name[ITX_MAX_STR];
    char role[32];
    char url[ITX_URL_BUF];
} itx_node_url_t;

/* ── Default constants (defined in libitx.c) ─────────────────────────────── */

extern const itx_seg_tmpl_t ITX_DEFAULT_SEGMENTS[7]; /**< Default 7-segment plan */
extern const int             ITX_DEFAULT_SEG_COUNT;   /**< 7 */
extern const int             ITX_DEFAULT_QUANTUM;     /**< 5 minutes per quantum */
extern const char            ITX_DEFAULT_API_BASE[];  /**< REST API base URL */

/* ── Plan creation ───────────────────────────────────────────────────────── */

/**
 * Initialise plan with default Earth HQ → Mars Hab-01 nodes and segments.
 *
 * @param plan       Output plan struct (caller allocates)
 * @param title      Session title (NULL → "LTX Session")
 * @param start_iso  ISO-8601 UTC start time string (NULL → "")
 * @param delay_sec  One-way light-travel delay for the remote node in seconds
 */
void itx_create_plan(itx_plan_t *plan, const char *title,
                     const char *start_iso, int delay_sec);

/* ── Segment computation ─────────────────────────────────────────────────── */

/**
 * Compute the timed segment array for a plan.
 *
 * @param plan      Input plan
 * @param segs      Output array (caller provides ITX_MAX_SEGMENTS slots)
 * @param seg_count Output: number of segments written
 */
void itx_compute_segments(const itx_plan_t *plan,
                          itx_segment_t *segs, int *seg_count);

/** Total session duration in minutes. */
int itx_total_min(const itx_plan_t *plan);

/* ── Plan ID ─────────────────────────────────────────────────────────────── */

/**
 * Compute the deterministic plan ID string.
 * Matches the ID generated by ltx-sdk.js and @interplanet/ltx.
 *
 * @param plan   Input plan
 * @param buf    Output buffer (at least ITX_PLAN_ID_LEN bytes)
 *
 * @example buf → "LTX-20260301-EARTHHQ-MARS-v2-a3b2c1d0"
 */
void itx_make_plan_id(const itx_plan_t *plan, char *buf);

/* ── Encoding ────────────────────────────────────────────────────────────── */

/**
 * Encode a plan to a URL-safe base64 hash fragment ("#l=…").
 * No padding characters (+, /, =).
 *
 * @param plan   Input plan
 * @param buf    Output buffer (at least ITX_HASH_BUF bytes)
 */
void itx_encode_hash(const itx_plan_t *plan, char *buf);

/**
 * Decode a plan from a URL hash fragment.
 * Accepts "#l=…", "l=…", or the raw base64 token.
 *
 * @param hash   Input hash string
 * @param plan   Output plan struct (caller allocates)
 * @return       0 on success, -1 on error
 */
int itx_decode_hash(const char *hash, itx_plan_t *plan);

/* ── Node URLs ────────────────────────────────────────────────────────────── */

/**
 * Build perspective URLs for all nodes in a plan.
 *
 * @param plan      Input plan
 * @param base_url  Base page URL (e.g. "https://interplanet.live/ltx.html")
 * @param urls      Output array (caller provides ITX_MAX_NODES slots)
 * @param url_count Output: number of URLs written
 */
void itx_build_node_urls(const itx_plan_t *plan, const char *base_url,
                         itx_node_url_t *urls, int *url_count);

/* ── ICS generation ──────────────────────────────────────────────────────── */

/**
 * Generate LTX-extended iCalendar (.ics) content for a plan.
 * Includes LTX-NODE, LTX-DELAY, LTX-LOCALTIME extension properties.
 *
 * @param plan   Input plan
 * @param buf    Output buffer (at least ITX_ICS_BUF bytes)
 */
void itx_generate_ics(const itx_plan_t *plan, char *buf);

/* ── Formatting ──────────────────────────────────────────────────────────── */

/**
 * Format a duration in seconds as "MM:SS" (< 1 hour) or "HH:MM:SS".
 *
 * @param seconds   Duration in seconds (negative clamped to 0)
 * @param buf       Output buffer (at least 12 bytes)
 */
void itx_format_hms(int seconds, char *buf);

/**
 * Format UTC epoch milliseconds as "HH:MM:SS UTC".
 *
 * @param epoch_ms  Epoch milliseconds
 * @param buf       Output buffer (at least 16 bytes)
 */
void itx_format_utc(long long epoch_ms, char *buf);

/* ── Wire-format plans (src/itx_plan_json.c) ─────────────────────────────── */
/*
 * These mirror javascript/ltx/ltx-sdk.js on plans as received (JSON text or a
 * parsed tree that keeps key insertion order, which the frozen v2 planId hash
 * depends on). Checked against spec/golden/plan-ids.json.
 */

/** JSON value kinds. */
typedef enum {
    ITX_JSON_NULL, ITX_JSON_BOOL, ITX_JSON_NUMBER, ITX_JSON_STRING, ITX_JSON_ARRAY, ITX_JSON_OBJECT
} itx_json_kind_t;

/** Parsed JSON value (opaque). Objects keep key insertion order. */
typedef struct itx_json itx_json_t;

/** JSON.parse. Returns NULL on a syntax error. Free with itx_json_free. */
itx_json_t *itx_json_parse(const char *text);
void itx_json_free(itx_json_t *v);
itx_json_kind_t itx_json_kind(const itx_json_t *v);
/** Object member by key (NULL if absent or v is not an object). */
const itx_json_t *itx_json_get(const itx_json_t *obj, const char *key);
/** Number of array elements or object members. */
size_t itx_json_len(const itx_json_t *v);
/** i-th array element or object member (NULL if out of range). */
const itx_json_t *itx_json_at(const itx_json_t *v, size_t i);
/** Key of an object member returned by itx_json_at. */
const char *itx_json_key(const itx_json_t *member);
/** String value (UTF-8), or NULL if v is not a string. */
const char *itx_json_str(const itx_json_t *v);
/** Number value into *out; returns 1 if v is a number, else 0. */
int itx_json_num(const itx_json_t *v, double *out);
/** JSON.stringify (insertion order). malloc'd; caller frees. */
char *itx_json_stringify(const itx_json_t *v);
/** ltx-sdk.js canonicalJSON: keys sorted by UTF-16 code units at every
 *  level (RFC 8785 order), JS number form. malloc'd; caller frees. */
char *itx_json_canonical(const itx_json_t *v);
/** Canonical JSON of JSON text. malloc'd; NULL on a parse error. */
char *itx_canonical_json(const char *json);

/**
 * JSON.stringify of a UTF-8 string: \b \t \n \f \r, other C0 controls as
 * \u00xx, a lone UTF-16 surrogate held as WTF-8 (ED A0..BF xx) as \udxxx.
 * malloc'd; caller frees. NULL on allocation failure.
 */
char *itx_json_quote(const char *utf8);

/**
 * makePlanId HOSTSTR and NODESTR from node names (names[0] is the HOST):
 * name.replace(/\s+/g, '').toUpperCase() with JavaScript's \s and the full
 * Unicode case mapping of JS toUpperCase (special casing included), and
 * slices counted in UTF-16 code units; a cut that splits a surrogate pair
 * keeps the high surrogate as WTF-8, as JS keeps it. host needs 32 bytes,
 * nodes 64.
 */
void itx_plan_id_name_strs(const char *const *names, size_t count, char *host, char *nodes);

/** SHA-256 (FIPS 180-4). */
void itx_sha256(const void *data, size_t len, unsigned char out[32]);
/** Frozen v2 hash: h = imul(31, h) + charCodeAt(i) over UTF-16 code units. */
unsigned int itx_imul31_utf16(const char *utf8);

/**
 * makePlanId over a v2/v3 plan as received: v2 hashes the insertion-order
 * JSON (UTF-16 code units), v3 is SHA-256 of the canonical JSON (first 8 hex
 * digits). Unlike itx_make_plan_id (fixed key order, v2 fields only) this
 * reproduces every golden vector. buf needs ITX_PLAN_ID_LEN bytes.
 * Returns 0, or -1 on invalid JSON / start / a v1 config (upgrade it first).
 */
int itx_make_plan_id_json(const char *plan_json, char *buf);
int itx_make_plan_id_value(const itx_json_t *plan, char *buf);

/** planHash: SHA-256 hex of the canonical JSON (prevPlanHash, §6.4).
 *  hex needs 65 bytes. Returns 0, or -1 on invalid JSON. */
int itx_plan_hash_json(const char *plan_json, char hex[65]);
int itx_plan_hash_value(const itx_json_t *plan, char hex[65]);

#define ITX_MAX_PLAN_ERRORS 64

/** One validatePlan finding. */
typedef struct {
    char code[24];     /**< e.g. "reserved_streams" */
    char path[96];     /**< e.g. "segments[0].branch" */
    char message[192];
} itx_plan_error_t;

/** validatePlan result. */
typedef struct {
    int              valid;        /**< 1 when there are no errors */
    int              error_count;
    int              truncated;    /**< 1 if more than ITX_MAX_PLAN_ERRORS */
    itx_plan_error_t errors[ITX_MAX_PLAN_ERRORS];
} itx_plan_validation_t;

/**
 * validatePlan (LTX-SPECIFICATION.md §3.5, §4, §7): wire-format checks of
 * spec/ltx-schema.json plus the reserved-field rules. Error codes:
 * not_an_object, invalid_version, missing_field, invalid_field,
 * invalid_quantum, invalid_mode, invalid_nodes, invalid_host,
 * duplicate_node_id, invalid_segment, unknown_speaker, v3_field_in_v2,
 * invalid_delays, reserved_streams (non-empty or non-array streams, segment
 * stream), reserved_branching (branches, branching, segment branch).
 * Returns out->valid. Invalid JSON reports not_an_object.
 */
int itx_validate_plan_json(const char *plan_json, itx_plan_validation_t *out);
int itx_validate_plan_value(const itx_json_t *plan, itx_plan_validation_t *out);
/** 1 if any error in r carries code. */
int itx_validation_has_code(const itx_plan_validation_t *r, const char *code);

/**
 * First reserved-field violation ("reserved_streams" or
 * "reserved_branching"), or NULL. The C port constructs no v3 plans,
 * amendments or sessions, so callers that do must refuse plans for which
 * this is non-NULL, as the reference SDKs do.
 */
const char *itx_reserved_field_code(const char *plan_json);
const char *itx_reserved_field_code_value(const itx_json_t *plan);

#ifdef __cplusplus
}
#endif

#endif /* LIBITX_H */
