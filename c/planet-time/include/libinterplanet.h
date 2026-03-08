/**
 * libinterplanet.h — Public C API for the Interplanetary Time Library
 *
 * Port of planet-time.js v1.0.0 to native C.
 * All UTC timestamps are int64_t milliseconds since the Unix epoch
 * (identical to JS Date.getTime()).
 *
 * No dynamic memory allocation; all structs are stack-allocated by the caller.
 *
 * Build: see CMakeLists.txt or Makefile in the parent directory.
 * Usage examples: see README.md and bindings/cpp/interplanet.hpp.
 */

#ifndef LIBINTERPLANET_H
#define LIBINTERPLANET_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

/* ── Version ──────────────────────────────────────────────────────────────── */

#define IPT_VERSION_MAJOR 1
#define IPT_VERSION_MINOR 0
#define IPT_VERSION_PATCH 0
#define IPT_VERSION_STRING "1.0.0"

/* ── Planet identifiers ───────────────────────────────────────────────────── */

typedef enum {
    IPT_MERCURY = 0,
    IPT_VENUS   = 1,
    IPT_EARTH   = 2,
    IPT_MARS    = 3,
    IPT_JUPITER = 4,
    IPT_SATURN  = 5,
    IPT_URANUS  = 6,
    IPT_NEPTUNE = 7,
    IPT_MOON    = 8   /* treated as Earth for work-schedule purposes */
} ipt_planet_t;

/* ── Output structs ───────────────────────────────────────────────────────── */

/**
 * Heliocentric position in the ecliptic plane.
 * x, y in AU; r = heliocentric distance in AU; lon = ecliptic longitude (radians).
 */
typedef struct {
    double x;
    double y;
    double r;
    double lon;
} ipt_helio_t;

/**
 * Local time on a planet (or Moon).
 * All integer fields are zero-based where relevant.
 */
typedef struct {
    int     hour;           /**< 0–23 */
    int     minute;         /**< 0–59 */
    int     second;         /**< 0–59 */
    double  local_hour;     /**< fractional hour, 0.0–24.0 */
    double  day_fraction;   /**< position within current solar day, 0.0–1.0 */
    int32_t day_number;     /**< total solar days since planet epoch */
    int32_t day_in_year;    /**< day index within the current planet year (0-based) */
    int32_t year_number;    /**< years since planet epoch */
    int     period_in_week; /**< 0–(periodsPerWeek-1) */
    int     is_work_period; /**< boolean: 1 if this period is a work period */
    int     is_work_hour;   /**< boolean: 1 if currently within work hours */
    char    time_str[6];    /**< "HH:MM\0" */
    char    time_str_full[9]; /**< "HH:MM:SS\0" */
    /* Mars only — zero for other planets */
    int32_t sol_in_year;    /**< sol index within the current Mars year */
    int32_t sols_per_year;  /**< total sols in a Mars year (~668) */
    char    zone_id[12];    /**< interplanetary zone ID e.g. "AMT+4\0"; "" for Earth */
} ipt_planet_time_t;

/**
 * Mars Coordinated Time (MTC) — the Martian equivalent of UTC.
 * sol is the absolute sol number since the Mars epoch (May 24 1953).
 */
typedef struct {
    int32_t sol;
    int     hour;
    int     minute;
    int     second;
    char    mtc_str[6]; /**< "HH:MM\0" */
} ipt_mtc_t;

/**
 * Line-of-sight status between two solar-system bodies.
 * Blocked: closest approach to Sun < 0.01 AU.
 * Degraded: closest approach 0.01–0.05 AU.
 */
typedef struct {
    int    clear;           /**< boolean */
    int    blocked;         /**< boolean */
    int    degraded;        /**< boolean */
    double closest_sun_au;  /**< AU */
    double elong_deg;       /**< solar elongation at body A (degrees) */
} ipt_los_t;

/**
 * A single meeting window where all parties' work hours overlap.
 */
typedef struct {
    int64_t start_ms;       /**< UTC ms */
    int64_t end_ms;         /**< UTC ms */
    int     duration_min;   /**< minutes */
} ipt_window_t;

/* ── Constants (defined in libinterplanet.c) ──────────────────────────────── */

extern const double  IPT_AU_KM;       /**< 1 AU in km (IAU 2012 exact) */
extern const double  IPT_C_KMS;       /**< speed of light km/s (SI exact) */
extern const double  IPT_AU_SECONDS;  /**< light travel time for 1 AU in seconds */
extern const double  IPT_J2000_JD;    /**< Julian Day of J2000.0 epoch */
extern const int64_t IPT_J2000_MS;    /**< J2000.0 as Unix ms (946728000000) */
extern const int64_t IPT_MARS_SOL_MS; /**< Mars solar day in ms (88775244) */
extern const int64_t IPT_MARS_EPOCH_MS; /**< Mars MY0 epoch as Unix ms */

/* ── Core functions ───────────────────────────────────────────────────────── */

/**
 * Heliocentric (x, y) position of a planet.
 * @param p       Planet identifier. IPT_MOON uses Earth's orbit.
 * @param utc_ms  UTC timestamp in milliseconds.
 * @param out     Output struct (must be non-NULL).
 * @return 0 on success, -1 if p is invalid.
 */
int ipt_helio_pos(ipt_planet_t p, int64_t utc_ms, ipt_helio_t *out);

/**
 * Distance in AU between two solar-system bodies.
 * @return AU distance, or -1.0 on invalid input.
 */
double ipt_body_distance_au(ipt_planet_t a, ipt_planet_t b, int64_t utc_ms);

/**
 * One-way light travel time between two bodies.
 * @return seconds, or -1.0 on invalid input.
 */
double ipt_light_travel_s(ipt_planet_t from, ipt_planet_t to, int64_t utc_ms);

/**
 * Local time on a planet at a given UTC instant and timezone offset.
 * @param p      Planet identifier.
 * @param utc_ms UTC timestamp in milliseconds.
 * @param tz_h   Integer UTC offset in planet local hours from prime meridian.
 *               Use 0 for planet mean time (e.g. AMT for Mars, UTC for Earth).
 * @param out    Output struct (must be non-NULL).
 * @return 0 on success, -1 on invalid input.
 */
int ipt_get_planet_time(ipt_planet_t p, int64_t utc_ms, int tz_h,
                         ipt_planet_time_t *out);

/**
 * Mars Coordinated Time (MTC) at a UTC instant.
 * @param utc_ms UTC timestamp in milliseconds.
 * @param out    Output struct (must be non-NULL).
 * @return 0 on success.
 */
int ipt_get_mtc(int64_t utc_ms, ipt_mtc_t *out);

/**
 * Mars local time at a given offset from AMT (integer Mars-hour offset).
 * @param utc_ms   UTC timestamp in milliseconds.
 * @param offset_h Mars-hour offset from AMT (e.g. +4 for AMT+4).
 * @param out      Output struct (must be non-NULL).
 * @return 0 on success.
 */
int ipt_get_mars_time_at_offset(int64_t utc_ms, int offset_h,
                                  ipt_planet_time_t *out);

/**
 * Line-of-sight status between two bodies.
 * @param a, b   Planet identifiers.
 * @param utc_ms UTC timestamp in milliseconds.
 * @param out    Output struct (must be non-NULL).
 * @return 0 on success, -1 on invalid input.
 */
int ipt_check_los(ipt_planet_t a, ipt_planet_t b, int64_t utc_ms,
                   ipt_los_t *out);

/**
 * Sample light travel time over one Earth year and return the 25th-percentile.
 * Uses 360 evenly spaced samples.
 * @param a, b   Planet identifiers.
 * @param ref_ms UTC reference start timestamp.
 * @return seconds at p25, or -1.0 on invalid input.
 */
double ipt_lower_quartile_light_time(ipt_planet_t a, ipt_planet_t b,
                                      int64_t ref_ms);

/**
 * Find meeting windows where both planet A and planet B are in work hours.
 * Uses a 15-minute time step.
 *
 * @param a, b       Planet identifiers.
 * @param from_ms    UTC start of search window.
 * @param earth_days Number of Earth days to search.
 * @param out        Caller-allocated array to receive windows.
 * @param max_out    Maximum number of windows to write.
 * @return Number of windows found (may be less than max_out).
 */
int ipt_find_windows(ipt_planet_t a, ipt_planet_t b,
                      int64_t from_ms, int earth_days,
                      ipt_window_t *out, int max_out);

/* ── Formatting ───────────────────────────────────────────────────────────── */

/**
 * Format a light travel time as a human-readable string.
 * Examples: "186.0s", "3.1min", "1h 6m", "<1ms", "42ms".
 * @param seconds  Light travel time in seconds.
 * @param buf      Output buffer.
 * @param buf_len  Buffer size (recommend ≥ 32).
 */
void ipt_format_light_time(double seconds, char *buf, int buf_len);

/**
 * Format a planet time result as a short human-readable string.
 * Example: "Mars ♂  14:32  Wed  Sol 221  [work]"
 * @param p   Planet identifier (for planet name).
 * @param pt  Planet time result from ipt_get_planet_time().
 * @param buf Output buffer.
 * @param buf_len Buffer size (recommend ≥ 64).
 */
void ipt_format_planet_time(ipt_planet_t p, const ipt_planet_time_t *pt,
                              char *buf, int buf_len);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* LIBINTERPLANET_H */
