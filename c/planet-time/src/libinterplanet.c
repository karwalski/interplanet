/**
 * libinterplanet.c — Interplanetary Time Library (C implementation)
 *
 * Direct port of planet-time.js v1.0.0.
 * All numeric constants are taken verbatim from the JavaScript source.
 *
 * No malloc, no file I/O, no threads.
 * Dependencies: <math.h>, <string.h>, <stdint.h>, <stdio.h>, <stdlib.h>
 */

#include "../include/libinterplanet.h"
#include <math.h>
#include <string.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

/* ── Section 1: Constants & data tables ───────────────────────────────────── */

const double  IPT_AU_KM        = 149597870.7;
const double  IPT_C_KMS        = 299792.458;
const double  IPT_AU_SECONDS   = 149597870.7 / 299792.458; /* ≈ 499.004 */
const double  IPT_J2000_JD     = 2451545.0;
const int64_t IPT_J2000_MS     = 946728000000LL;   /* 2000-01-01T12:00:00Z */
const int64_t IPT_MARS_SOL_MS  = 88775244LL;
const int64_t IPT_MARS_EPOCH_MS = -524069761536LL; /* 1953-05-24T09:03:58.464Z */

#define EARTH_DAY_MS 86400000LL
#define PI           3.14159265358979323846
#define TWO_PI       6.28318530717958647692
#define D2R          (PI / 180.0)

/* Planet indices (match ipt_planet_t, Moon handled by mapping to Earth) */
#define NPLANETS_REAL 8 /* Mercury..Neptune */

/* Planet data table (indices 0=Mercury .. 7=Neptune) */
typedef struct {
    double  solar_day_ms;      /* solar day in milliseconds */
    double  sidereal_yr_ms;    /* sidereal year in milliseconds */
    double  days_per_period;
    int     periods_per_week;
    int     work_periods_per_week;
    int     work_hours_start;
    int     work_hours_end;
    int     earth_clock_sched; /* 1 = use UTC weekday/hour (Mercury/Venus) */
    int64_t epoch_ms;          /* planet epoch as Unix ms */
    const char *name;
    const char *symbol;
} _planet_t;

static const _planet_t PDATA[NPLANETS_REAL] = {
    /* IPT_MERCURY (0) — Earth-clock scheduling (solar day >> circadian rhythm) */
    {
        175.9408 * 86400000.0,          /* solar_day_ms */
        87.9691  * 86400000.0,          /* sidereal_yr_ms */
        1.0, 7, 5, 9, 17,               /* work hours = UTC 09–17 (Earth-clock) */
        1,                               /* earth_clock_sched = 1 */
        946728000000LL,                  /* J2000_MS */
        "Mercury", "\xe2\x98\xbf"        /* ☿ utf-8 */
    },
    /* IPT_VENUS (1) — Earth-clock scheduling (solar day >> circadian rhythm) */
    {
        116.7500 * 86400000.0,
        224.701  * 86400000.0,
        1.0, 7, 5, 9, 17,               /* work hours = UTC 09–17 (Earth-clock) */
        1,                               /* earth_clock_sched = 1 */
        946728000000LL,
        "Venus", "\xe2\x99\x80"          /* ♀ */
    },
    /* IPT_EARTH (2) */
    {
        86400000.0,
        365.25636 * 86400000.0,
        1.0, 7, 5, 9, 17,
        0,                               /* earth_clock_sched = 0 */
        946728000000LL,
        "Earth", "\xe2\x99\x81"          /* ♁ */
    },
    /* IPT_MARS (3) */
    {
        88775244.0,
        686.9957 * 86400000.0,
        1.0, 7, 5, 9, 17,
        0,                               /* earth_clock_sched = 0 */
        -524069761536LL,                 /* MARS_EPOCH_MS = 1953-05-24T09:03:58.464Z */
        "Mars", "\xe2\x99\x82"           /* ♂ */
    },
    /* IPT_JUPITER (4) */
    {
        9.9250 * 3600000.0,
        4332.589 * 86400000.0,
        2.5, 7, 5, 8, 16,
        0,                               /* earth_clock_sched = 0 */
        946728000000LL,
        "Jupiter", "\xe2\x99\x83"        /* ♃ */
    },
    /* IPT_SATURN (5) — Mankovich, Marley, Fortney & Mozshovitz 2023 ring seismology refinement */
    {
        10.578 * 3600000.0,
        10759.22 * 86400000.0,
        2.25, 7, 5, 8, 16,
        0,                               /* earth_clock_sched = 0 */
        946728000000LL,
        "Saturn", "\xe2\x99\x84"         /* ♄ */
    },
    /* IPT_URANUS (6) */
    {
        17.2479 * 3600000.0,
        30688.5 * 86400000.0,
        1.0, 7, 5, 8, 16,
        0,                               /* earth_clock_sched = 0 */
        946728000000LL,
        "Uranus", "\xe2\x9b\xa2"         /* ⛢ */
    },
    /* IPT_NEPTUNE (7) */
    {
        16.1100 * 3600000.0,
        60195.0 * 86400000.0,
        1.0, 7, 5, 8, 16,
        0,                               /* earth_clock_sched = 0 */
        946728000000LL,
        "Neptune", "\xe2\x99\x86"        /* ♆ */
    },
};

/* Orbital elements (Meeus Table 31.a)
   Indexed 0=Mercury .. 7=Neptune (same as PDATA) */
typedef struct { double L0, dL, om0, e0, a; } _orbelem_t;

static const _orbelem_t ORBELEMS[NPLANETS_REAL] = {
    { 252.2507, 149474.0722,  77.4561, 0.20564, 0.38710 }, /* Mercury */
    { 181.9798,  58519.2130, 131.5637, 0.00677, 0.72333 }, /* Venus   */
    { 100.4664,  36000.7698, 102.9373, 0.01671, 1.00000 }, /* Earth   */
    { 355.4330,  19141.6964, 336.0600, 0.09341, 1.52366 }, /* Mars    */
    {  34.3515,   3036.3027,  14.3320, 0.04849, 5.20336 }, /* Jupiter */
    {  50.0775,   1223.5093,  93.0572, 0.05551, 9.53707 }, /* Saturn  */
    { 314.0550,    429.8633, 173.0052, 0.04630, 19.1912 }, /* Uranus  */
    { 304.3480,    219.8997,  48.1234, 0.00899, 30.0690 }, /* Neptune */
};

/* ── Section 2: Leap-second table ────────────────────────────────────────── */

/* [TAI−UTC (seconds), UTC onset as Unix ms] */
typedef struct { int tai_utc; int64_t utc_ms; } _leapsec_t;

static const _leapsec_t LEAPSECS[] = {
    { 10, 63072000000LL   }, /* 1972-01-01 */
    { 11, 78796800000LL   }, /* 1972-07-01 */
    { 12, 94694400000LL   }, /* 1973-01-01 */
    { 13, 126230400000LL  }, /* 1974-01-01 */
    { 14, 157766400000LL  }, /* 1975-01-01 */
    { 15, 189302400000LL  }, /* 1976-01-01 */
    { 16, 220924800000LL  }, /* 1977-01-01 */
    { 17, 252460800000LL  }, /* 1978-01-01 */
    { 18, 283996800000LL  }, /* 1979-01-01 */
    { 19, 315532800000LL  }, /* 1980-01-01 */
    { 20, 362793600000LL  }, /* 1981-07-01 */
    { 21, 394329600000LL  }, /* 1982-07-01 */
    { 22, 425865600000LL  }, /* 1983-07-01 */
    { 23, 489024000000LL  }, /* 1985-07-01 */
    { 24, 567993600000LL  }, /* 1988-01-01 */
    { 25, 631152000000LL  }, /* 1990-01-01 */
    { 26, 662688000000LL  }, /* 1991-01-01 */
    { 27, 709948800000LL  }, /* 1992-07-01 */
    { 28, 741484800000LL  }, /* 1993-07-01 */
    { 29, 773020800000LL  }, /* 1994-07-01 */
    { 30, 820454400000LL  }, /* 1996-01-01 */
    { 31, 867715200000LL  }, /* 1997-07-01 */
    { 32, 915148800000LL  }, /* 1999-01-01 */
    { 33, 1136073600000LL }, /* 2006-01-01 */
    { 34, 1230768000000LL }, /* 2009-01-01 */
    { 35, 1341100800000LL }, /* 2012-07-01 */
    { 36, 1435708800000LL }, /* 2015-07-01 */
    { 37, 1483228800000LL }, /* 2017-01-01 — current as of 2025 */
};
#define NLEAP ((int)(sizeof(LEAPSECS)/sizeof(LEAPSECS[0])))

/* Return TAI − UTC in seconds for a given UTC timestamp (ms). */
static int _tai_minus_utc(int64_t utc_ms) {
    int offset = 10;
    for (int i = 0; i < NLEAP; i++) {
        if (utc_ms >= LEAPSECS[i].utc_ms)
            offset = LEAPSECS[i].tai_utc;
        else
            break;
    }
    return offset;
}

/* ── Section 3: Julian Day ────────────────────────────────────────────────── */

/*
 * Convert a UTC timestamp (ms) to Terrestrial Time Julian Day Number.
 * TT = UTC + (TAI−UTC) + 32.184 s
 * JDE = 2440587.5 + ttMs / 86400000
 */
static double _jde(int64_t utc_ms) {
    double tt_ms = (double)utc_ms + (_tai_minus_utc(utc_ms) + 32.184) * 1000.0;
    return 2440587.5 + tt_ms / 86400000.0;
}

/* ── Section 4: Julian centuries ─────────────────────────────────────────── */

/* Julian centuries since J2000.0 */
static double _jc(int64_t utc_ms) {
    return (_jde(utc_ms) - IPT_J2000_JD) / 36525.0;
}

/* ── Section 5: Kepler solver ─────────────────────────────────────────────── */

/* Solve Kepler's equation M = E − e·sin(E) using Newton-Raphson. */
static double _kepler_E(double M, double e) {
    double E = M;
    for (int i = 0; i < 50; i++) {
        double dE = (M - E + e * sin(E)) / (1.0 - e * cos(E));
        E += dE;
        if (fabs(dE) < 1e-12) break;
    }
    return E;
}

/* ── Section 6: Heliocentric position ────────────────────────────────────── */

/* Map ipt_planet_t to an orbital elements index (Moon → Earth). */
static int _planet_idx(ipt_planet_t p) {
    if (p == IPT_MOON) return (int)IPT_EARTH;
    if ((int)p < 0 || (int)p >= NPLANETS_REAL) return -1;
    return (int)p;
}

int ipt_helio_pos(ipt_planet_t p, int64_t utc_ms, ipt_helio_t *out) {
    int idx = _planet_idx(p);
    if (idx < 0 || !out) return -1;

    const _orbelem_t *el = &ORBELEMS[idx];
    double T   = _jc(utc_ms);

    double L   = fmod(fmod((el->L0 + el->dL * T) * D2R, TWO_PI) + TWO_PI, TWO_PI);
    double om  = el->om0 * D2R;
    double M   = fmod(fmod(L - om, TWO_PI) + TWO_PI, TWO_PI);
    double e   = el->e0;
    double a   = el->a;

    double E   = _kepler_E(M, e);
    double v   = 2.0 * atan2(sqrt(1.0 + e) * sin(E / 2.0),
                              sqrt(1.0 - e) * cos(E / 2.0));
    double r   = a * (1.0 - e * cos(E));
    double lon = fmod(fmod(v + om, TWO_PI) + TWO_PI, TWO_PI);

    out->x   = r * cos(lon);
    out->y   = r * sin(lon);
    out->r   = r;
    out->lon = lon;
    return 0;
}

/* ── Section 7: Distance / light travel ──────────────────────────────────── */

double ipt_body_distance_au(ipt_planet_t a, ipt_planet_t b, int64_t utc_ms) {
    ipt_helio_t pA, pB;
    if (ipt_helio_pos(a, utc_ms, &pA) != 0) return -1.0;
    if (ipt_helio_pos(b, utc_ms, &pB) != 0) return -1.0;
    double dx = pA.x - pB.x, dy = pA.y - pB.y;
    return sqrt(dx * dx + dy * dy);
}

double ipt_light_travel_s(ipt_planet_t from, ipt_planet_t to, int64_t utc_ms) {
    double d = ipt_body_distance_au(from, to, utc_ms);
    if (d < 0.0) return -1.0;
    return d * IPT_AU_SECONDS;
}

/* ── Section 8: Line-of-sight ────────────────────────────────────────────── */

int ipt_check_los(ipt_planet_t a, ipt_planet_t b, int64_t utc_ms,
                   ipt_los_t *out) {
    if (!out) return -1;
    ipt_helio_t pA, pB;
    if (ipt_helio_pos(a, utc_ms, &pA) != 0) return -1;
    if (ipt_helio_pos(b, utc_ms, &pB) != 0) return -1;

    double dx = pB.x - pA.x, dy = pB.y - pA.y;
    double d2 = dx * dx + dy * dy;

    /* Guard: same heliocentric position (e.g. Moon maps to Earth orbit) */
    if (d2 < 1e-20) {
        /* Bodies co-located — LOS is trivially clear, use A's helio distance */
        out->closest_sun_au = pA.r;
        out->elong_deg      = 0.0;
        out->blocked        = 0;
        out->degraded       = 0;
        out->clear          = 1;
        return 0;
    }

    double dist = sqrt(d2);

    /* Closest approach of segment A→B to the Sun (origin) */
    double t_param = -(pA.x * dx + pA.y * dy) / d2;
    if (t_param < 0.0) t_param = 0.0;
    if (t_param > 1.0) t_param = 1.0;
    double cx = pA.x + t_param * dx, cy = pA.y + t_param * dy;
    double closest = sqrt(cx * cx + cy * cy);

    /* Solar elongation at A */
    double cos_el = (-pA.x * dx - pA.y * dy) / (pA.r * dist);
    if (cos_el < -1.0) cos_el = -1.0;
    if (cos_el >  1.0) cos_el =  1.0;
    double elong_deg = acos(cos_el) * 180.0 / PI;

    out->closest_sun_au = closest;
    out->elong_deg      = elong_deg;
    out->blocked        = (closest < 0.01) ? 1 : 0;
    out->degraded       = (!out->blocked && closest < 0.05) ? 1 : 0;
    out->clear          = (!out->blocked && !out->degraded) ? 1 : 0;
    return 0;
}

/* ── Section 9: Lower-quartile light time ────────────────────────────────── */

static int _cmp_double(const void *va, const void *vb) {
    double da = *(const double *)va, db = *(const double *)vb;
    if (da < db) return -1;
    if (da > db) return  1;
    return 0;
}

double ipt_lower_quartile_light_time(ipt_planet_t a, ipt_planet_t b,
                                      int64_t ref_ms) {
    if (_planet_idx(a) < 0 || _planet_idx(b) < 0) return -1.0;
    const int SAMPLES = 360;
    double times[360];
    double step = 365.25 * (double)EARTH_DAY_MS / SAMPLES;
    for (int i = 0; i < SAMPLES; i++) {
        int64_t t = ref_ms + (int64_t)(i * step);
        double lt = ipt_light_travel_s(a, b, t);
        times[i] = (lt < 0.0) ? 1e18 : lt;
    }
    qsort(times, SAMPLES, sizeof(double), _cmp_double);
    return times[(int)(SAMPLES * 0.25)]; /* index 90 */
}

/* ── Section 10: MTC & Mars time ─────────────────────────────────────────── */

int ipt_get_mtc(int64_t utc_ms, ipt_mtc_t *out) {
    if (!out) return -1;
    double total_sols = (double)(utc_ms - IPT_MARS_EPOCH_MS) / (double)IPT_MARS_SOL_MS;
    int32_t sol       = (int32_t)floor(total_sols);
    double  frac      = total_sols - floor(total_sols);
    int h = (int)floor(frac * 24.0);
    int m = (int)floor((frac * 24.0 - h) * 60.0);
    int s = (int)floor(((frac * 24.0 - h) * 60.0 - m) * 60.0);
    out->sol    = sol;
    out->hour   = h;
    out->minute = m;
    out->second = s;
    snprintf(out->mtc_str, sizeof(out->mtc_str), "%02d:%02d", h, m);
    return 0;
}

int ipt_get_mars_time_at_offset(int64_t utc_ms, int offset_h,
                                  ipt_planet_time_t *out) {
    if (!out) return -1;
    ipt_mtc_t mtc;
    ipt_get_mtc(utc_ms, &mtc);
    int h    = mtc.hour + offset_h;
    int sol_delta = 0;
    if (h >= 24) { h -= 24; sol_delta =  1; }
    if (h <   0) { h += 24; sol_delta = -1; }

    memset(out, 0, sizeof(*out));
    out->hour        = h;
    out->minute      = mtc.minute;
    out->second      = mtc.second;
    out->day_number  = mtc.sol + sol_delta;
    out->local_hour  = (double)h + mtc.minute / 60.0 + mtc.second / 3600.0;
    out->day_fraction = out->local_hour / 24.0;
    snprintf(out->time_str,      sizeof(out->time_str),      "%02d:%02d",    h, mtc.minute);
    snprintf(out->time_str_full, sizeof(out->time_str_full), "%02d:%02d:%02d", h, mtc.minute, mtc.second);
    return 0;
}

/* ── Section 11: Planet time ─────────────────────────────────────────────── */

int ipt_get_planet_time(ipt_planet_t p, int64_t utc_ms, int tz_h,
                         ipt_planet_time_t *out) {
    if (!out) return -1;
    /* Moon uses Earth's schedule (tidally locked) */
    ipt_planet_t key = (p == IPT_MOON) ? IPT_EARTH : p;
    int idx = _planet_idx(key);
    if (idx < 0) return -1;

    const _planet_t *pl = &PDATA[idx];

    /* elapsed ms from planet epoch, adjusted for timezone */
    double tz_adjust_ms = (double)tz_h / 24.0 * pl->solar_day_ms;
    double elapsed_ms   = (double)(utc_ms - pl->epoch_ms) + tz_adjust_ms;

    double total_days   = elapsed_ms / pl->solar_day_ms;
    int32_t day_number  = (int32_t)floor(total_days);
    double day_fraction = total_days - floor(total_days);

    double local_hour   = day_fraction * 24.0;
    int h = (int)floor(local_hour);
    int m = (int)floor((local_hour - h) * 60.0);
    int s = (int)floor(((local_hour - h) * 60.0 - m) * 60.0);

    /* Work period / week */
    int piw, is_work_period, is_work_hour;
    if (pl->earth_clock_sched) {
        /* Mercury/Venus: solar day >> circadian rhythm — use UTC weekday + UTC hour.
         * UTC day-of-week formula: ((floor(unix_ms / 86400000) % 7) + 3) % 7 → Mon=0..Sun=6 */
        int64_t utc_day = (int64_t)floor((double)utc_ms / (double)EARTH_DAY_MS);
        piw = (int)(((utc_day % 7) + 7 + 3) % 7);
        is_work_period = (piw < pl->work_periods_per_week) ? 1 : 0;
        /* UTC hour of day (fractional) */
        int64_t ms_in_day = ((utc_ms % EARTH_DAY_MS) + EARTH_DAY_MS) % EARTH_DAY_MS;
        double utc_hour = (double)ms_in_day / 3600000.0;
        is_work_hour = (is_work_period
                        && utc_hour >= pl->work_hours_start
                        && utc_hour < pl->work_hours_end) ? 1 : 0;
    } else {
        double total_periods = total_days / pl->days_per_period;
        int32_t period_int   = (int32_t)floor(total_periods);
        piw = (int)(((period_int % pl->periods_per_week) + pl->periods_per_week)
                        % pl->periods_per_week);
        is_work_period = (piw < pl->work_periods_per_week) ? 1 : 0;
        is_work_hour   = (is_work_period
                          && local_hour >= pl->work_hours_start
                          && local_hour < pl->work_hours_end) ? 1 : 0;
    }

    /* Year / day-in-year */
    double year_len_days = pl->sidereal_yr_ms / pl->solar_day_ms;
    int32_t year_number  = (int32_t)floor(total_days / year_len_days);
    double  day_in_year  = total_days - year_number * year_len_days;

    memset(out, 0, sizeof(*out));
    out->hour            = h;
    out->minute          = m;
    out->second          = s;
    out->local_hour      = local_hour;
    out->day_fraction    = day_fraction;
    out->day_number      = day_number;
    out->day_in_year     = (int32_t)floor(day_in_year);
    out->year_number     = year_number;
    out->period_in_week  = piw;
    out->is_work_period  = is_work_period;
    out->is_work_hour    = is_work_hour;
    snprintf(out->time_str,      sizeof(out->time_str),      "%02d:%02d",       h, m);
    snprintf(out->time_str_full, sizeof(out->time_str_full), "%02d:%02d:%02d",  h, m, s);

    /* Mars-specific sol info */
    if (key == IPT_MARS) {
        out->sol_in_year  = (int32_t)floor(day_in_year);
        out->sols_per_year = (int32_t)round(pl->sidereal_yr_ms / pl->solar_day_ms);
    }

    /* Zone ID — empty string for Earth; "PREFIX±N" for all other bodies */
    {
        const char *prefix = NULL;
        switch (p) {
            case IPT_MARS:    prefix = "AMT"; break;
            case IPT_MOON:    prefix = "LMT"; break;
            case IPT_MERCURY: prefix = "MMT"; break;
            case IPT_VENUS:   prefix = "VMT"; break;
            case IPT_JUPITER: prefix = "JMT"; break;
            case IPT_SATURN:  prefix = "SMT"; break;
            case IPT_URANUS:  prefix = "UMT"; break;
            case IPT_NEPTUNE: prefix = "NMT"; break;
            default:          prefix = NULL;  break; /* Earth */
        }
        if (prefix == NULL) {
            out->zone_id[0] = '\0';
        } else if (tz_h >= 0) {
            snprintf(out->zone_id, sizeof(out->zone_id), "%s+%d", prefix, tz_h);
        } else {
            snprintf(out->zone_id, sizeof(out->zone_id), "%s%d", prefix, tz_h);
        }
    }

    return 0;
}

/* ── Section 12: Meeting windows ─────────────────────────────────────────── */

int ipt_find_windows(ipt_planet_t a, ipt_planet_t b,
                      int64_t from_ms, int earth_days,
                      ipt_window_t *out, int max_out) {
    if (!out || max_out <= 0) return 0;
    if (_planet_idx(a) < 0 || _planet_idx(b) < 0) return 0;

    const int64_t STEP = 15LL * 60000LL; /* 15 minutes */
    int64_t end_ms = from_ms + (int64_t)earth_days * EARTH_DAY_MS;

    int count     = 0;
    int in_window = 0;
    int64_t win_start = 0;

    for (int64_t t = from_ms; t < end_ms && count < max_out; t += STEP) {
        ipt_planet_time_t ta, tb;
        ipt_get_planet_time(a, t, 0, &ta);
        ipt_get_planet_time(b, t, 0, &tb);
        int overlap = ta.is_work_hour && tb.is_work_hour;

        if (overlap && !in_window) {
            in_window = 1;
            win_start = t;
        } else if (!overlap && in_window) {
            in_window = 0;
            if (count < max_out) {
                out[count].start_ms    = win_start;
                out[count].end_ms      = t;
                out[count].duration_min = (int)((t - win_start) / 60000LL);
                count++;
            }
        }
    }
    /* Close any window still open at end */
    if (in_window && count < max_out) {
        out[count].start_ms    = win_start;
        out[count].end_ms      = end_ms;
        out[count].duration_min = (int)((end_ms - win_start) / 60000LL);
        count++;
    }
    return count;
}

/* ── Section 13: Formatting ──────────────────────────────────────────────── */

void ipt_format_light_time(double seconds, char *buf, int buf_len) {
    if (!buf || buf_len <= 0) return;
    if (seconds < 0.001) {
        snprintf(buf, buf_len, "<1ms");
    } else if (seconds < 1.0) {
        snprintf(buf, buf_len, "%.0fms", seconds * 1000.0);
    } else if (seconds < 60.0) {
        snprintf(buf, buf_len, "%.1fs", seconds);
    } else if (seconds < 3600.0) {
        snprintf(buf, buf_len, "%.1fmin", seconds / 60.0);
    } else {
        int h = (int)floor(seconds / 3600.0);
        int m = (int)round(fmod(seconds, 3600.0) / 60.0);
        snprintf(buf, buf_len, "%dh %dm", h, m);
    }
}

void ipt_format_planet_time(ipt_planet_t p, const ipt_planet_time_t *pt,
                              char *buf, int buf_len) {
    if (!buf || buf_len <= 0 || !pt) return;
    const char *name = "Unknown";
    if (p == IPT_MOON) {
        name = "Moon";
    } else if (_planet_idx(p) >= 0) {
        name = PDATA[_planet_idx(p)].name;
    }
    const char *status = pt->is_work_hour    ? "work"
                       : pt->is_work_period  ? "off-shift"
                       : "rest";
    if (p == IPT_MARS && pt->sols_per_year > 0) {
        snprintf(buf, buf_len, "%s  %s  Sol %d Yr %d  [%s]",
                 name, pt->time_str,
                 pt->sol_in_year, pt->year_number, status);
    } else {
        snprintf(buf, buf_len, "%s  %s  Day %d Yr %d  [%s]",
                 name, pt->time_str,
                 pt->day_in_year, pt->year_number, status);
    }
}
