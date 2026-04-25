/*
 * glue.c — Minimal i64-ABI wrappers for the interplanet toke port.
 *
 * The toke compiler emits stdlib calls using the _w wrapper convention
 * where all arguments and return values are i64 (pointers as integers).
 * This file provides the wrappers actually needed by interplanet.
 */

#include "str.h"
#include "args.h"
#include "log.h"
#include "tk_time.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

/* ── str wrappers ──────────────────────────────────────────────────── */

int64_t tk_str_concat_w(int64_t a, int64_t b) {
    return (int64_t)(intptr_t)str_concat(
        (const char *)(intptr_t)a,
        (const char *)(intptr_t)b);
}

int64_t tk_str_len_w(int64_t s) {
    return (int64_t)str_len((const char *)(intptr_t)s);
}

int64_t tk_str_upper_w(int64_t s) {
    return (int64_t)(intptr_t)str_upper((const char *)(intptr_t)s);
}

int64_t tk_str_lower_w(int64_t s) {
    return (int64_t)(intptr_t)str_lower((const char *)(intptr_t)s);
}

int64_t tk_str_from_int(int64_t n) {
    return (int64_t)(intptr_t)str_from_int(n);
}

int64_t tk_str_split_w(int64_t s, int64_t sep) {
    if (!s || !sep) return 0;
    StrArray arr = str_split((const char *)(intptr_t)s, (const char *)(intptr_t)sep);
    int64_t *block = (int64_t *)malloc((arr.len + 1) * sizeof(int64_t));
    if (!block) return 0;
    block[0] = (int64_t)arr.len;
    for (size_t i = 0; i < arr.len; i++)
        block[i + 1] = (int64_t)(intptr_t)arr.data[i];
    return (int64_t)(intptr_t)(block + 1);
}

int64_t tk_str_slice_w(int64_t s, int64_t start, int64_t end_) {
    if (!s) return 0;
    StrSliceResult r = str_slice((const char *)(intptr_t)s, (uint64_t)start, (uint64_t)end_);
    return r.is_err ? 0 : (int64_t)(intptr_t)r.ok;
}

int64_t tk_str_toint_w(int64_t s) {
    const char *p = s ? (const char *)(intptr_t)s : "0";
    return (int64_t)strtoll(p, NULL, 10);
}

int64_t tk_str_bytes_w(int64_t s) {
    /* Return the string pointer itself — toke treats str as byte array */
    return s;
}

/* ── args wrappers ─────────────────────────────────────────────────── */

int64_t tk_args_count_w(void) {
    return (int64_t)args_count();
}

int64_t tk_args_get_w(int64_t n) {
    StrArgsResult r = args_get((uint64_t)n);
    return r.is_err ? 0 : (int64_t)(intptr_t)r.ok;
}

/* ── log wrappers ──────────────────────────────────────────────────── */

int64_t tk_log_info_w(int64_t msg, int64_t fields_map) {
    (void)fields_map;
    tk_log_info((const char *)(intptr_t)msg, NULL, 0);
    return 0;
}

int64_t tk_log_error_w(int64_t msg, int64_t fields_map) {
    (void)fields_map;
    tk_log_error((const char *)(intptr_t)msg, NULL, 0);
    return 0;
}

/* ── array wrappers ────────────────────────────────────────────────── */

int64_t tk_array_append_w(int64_t arr_i64, int64_t elem) {
    int64_t *ptr = (int64_t *)(intptr_t)arr_i64;
    int64_t len = ptr[-1];
    int64_t *block = (int64_t *)malloc((size_t)(len + 2) * sizeof(int64_t));
    if (!block) return arr_i64;
    block[0] = len + 1;
    memcpy(block + 1, ptr, (size_t)len * sizeof(int64_t));
    block[len + 1] = elem;
    return (int64_t)(intptr_t)(block + 1);
}

/* ── math wrappers ─────────────────────────────────────────────────── */

int64_t tk_math_floor_w(int64_t x) {
    /* x is an i64 — but toke might pass a double bitcast to i64 */
    return x;
}

int64_t tk_math_sqrt_w(int64_t x) {
    (void)x;
    return 0;
}

/* ── time wrappers ─────────────────────────────────────────────────── */

int64_t tk_time_now_w(void) {
    return (int64_t)tk_time_now();
}

int64_t tk_time_format_w(int64_t ts, int64_t fmt) {
    const char *result = tk_time_format((uint64_t)ts, (const char *)(intptr_t)fmt);
    return result ? (int64_t)(intptr_t)result : 0;
}

/*
 * tk_time_toparts_w — Convert ms timestamp to toke struct with fields:
 *   year, month, day, hour, min, sec
 * Returns i8* pointer to toke struct layout (array of i64, length prefix at [-1]).
 */
int64_t tk_time_toparts_w(int64_t ts) {
    TkTimeParts parts = tk_time_to_parts((uint64_t)ts);
    /* Toke structs: block[-1] = field count, block[0..n-1] = fields */
    int64_t *block = (int64_t *)malloc(7 * sizeof(int64_t));
    if (!block) return 0;
    block[0] = 6; /* field count */
    block[1] = (int64_t)parts.year;
    block[2] = (int64_t)parts.month;
    block[3] = (int64_t)parts.day;
    block[4] = (int64_t)parts.hour;
    block[5] = (int64_t)parts.min;
    block[6] = (int64_t)parts.sec;
    return (int64_t)(intptr_t)(block + 1);
}

int64_t tk_time_weekday_w(int64_t ts) {
    return (int64_t)tk_time_weekday((uint64_t)ts);
}
