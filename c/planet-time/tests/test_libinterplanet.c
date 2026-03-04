/**
 * test_libinterplanet.c — C unit tests for libinterplanet
 *
 * No external framework. Mirrors the structure of test-planet-time.js.
 * Build and run:
 *   cd libinterplanet && make test
 *
 * Exit code: 0 if all tests pass, 1 if any fail.
 */

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <stdint.h>

#include "../include/libinterplanet.h"

/* ── Test harness ─────────────────────────────────────────────────────────── */

static int PASS = 0, FAIL = 0;

#define ASSERT_CLOSE(a, b, tol, msg) \
    do { \
        double _a = (double)(a), _b = (double)(b), _t = (double)(tol); \
        if (fabs(_a - _b) <= _t) { \
            PASS++; \
        } else { \
            FAIL++; \
            printf("FAIL  %-50s  got=%.8g  exp=%.8g  diff=%.6g\n", \
                   (msg), _a, _b, fabs(_a - _b)); \
        } \
    } while (0)

#define ASSERT_INT(a, b, msg) \
    do { \
        int _a = (int)(a), _b = (int)(b); \
        if (_a == _b) { \
            PASS++; \
        } else { \
            FAIL++; \
            printf("FAIL  %-50s  got=%d  exp=%d\n", (msg), _a, _b); \
        } \
    } while (0)

#define ASSERT_TRUE(cond, msg) \
    do { \
        if (cond) { PASS++; } \
        else { FAIL++; printf("FAIL  %s\n", (msg)); } \
    } while (0)

#define ASSERT_STR(a, b, msg) \
    do { \
        if (strcmp((a),(b)) == 0) { PASS++; } \
        else { FAIL++; printf("FAIL  %-50s  got=\"%s\"  exp=\"%s\"\n", (msg),(a),(b)); } \
    } while (0)

static void section(const char *name) {
    printf("\n── %s ──\n", name);
}

/* ── Known UTC timestamps ─────────────────────────────────────────────────── */

/* J2000.0: 2000-01-01T12:00:00Z */
static const int64_t T_J2000 = 946728000000LL;

/* Mars close approach 2003-08-27T09:51:00Z ≈ 1061977860000 ms
   (actual closest approach; light travel ~186 s) */
static const int64_t T_MARS_CLOSE_2003 = 1061977860000LL;

/* Mars opposition 2020-10-13T23:26:00Z ≈ 1602631560000 ms
   (light travel ~206 s) */
static const int64_t T_MARS_OPP_2020 = 1602631560000LL;

/* Jupiter opposition 2023-11-03T00:00:00Z */
static const int64_t T_JUP_OPP_2023 = 1698969600000LL;

/* 2025-01-01T00:00:00Z */
static const int64_t T_2025 = 1735689600000LL;

/* 2024-06-15T12:00:00Z */
static const int64_t T_2024_MID = 1718452800000LL;

/* ─────────────────────────────────────────────────────────────────────────── */

static void test_constants(void) {
    section("1. Constants");

    ASSERT_CLOSE(IPT_AU_KM,       149597870.7,      1.0,   "AU_KM");
    ASSERT_CLOSE(IPT_C_KMS,       299792.458,        0.001, "C_KMS");
    ASSERT_CLOSE(IPT_AU_SECONDS,  499.004,           0.001, "AU_SECONDS");
    ASSERT_CLOSE(IPT_J2000_JD,    2451545.0,         0.0,   "J2000_JD");
    ASSERT_INT  (IPT_J2000_MS,    946728000000LL,          "J2000_MS");
    ASSERT_INT  (IPT_MARS_SOL_MS, 88775244LL,              "MARS_SOL_MS");
    ASSERT_CLOSE((double)IPT_MARS_EPOCH_MS, -524069761536.0, 1.0, "MARS_EPOCH_MS");
}

static void test_jde(void) {
    section("2. JDE at J2000.0 epoch");

    /* ipt_helio_pos at J2000 with Earth — internally calls _jde() which should
       return approximately 2451545.0.  We verify this indirectly by checking that
       the orbital calculation produces a sensible distance for Earth (should be ~1 AU). */
    ipt_helio_t pos;
    int rc = ipt_helio_pos(IPT_EARTH, T_J2000, &pos);
    ASSERT_INT(rc, 0, "ipt_helio_pos Earth J2000 returns 0");
    ASSERT_CLOSE(pos.r, 1.0, 0.02, "Earth helio distance at J2000 ≈ 1 AU");

    /* Verify Jupiter's heliocentric distance at J2000.
       Jupiter is not at perihelion/aphelion at J2000; JS reference gives ≈4.97 AU.
       Semi-major axis is 5.20 AU; actual position depends on current orbital phase. */
    ipt_helio_t jup;
    ipt_helio_pos(IPT_JUPITER, T_J2000, &jup);
    ASSERT_CLOSE(jup.r, 4.968, 0.1, "Jupiter helio distance at J2000 ≈ 4.97 AU");
    ASSERT_TRUE(jup.r > 4.9 && jup.r < 5.5, "Jupiter helio distance in plausible range");
}

static void test_mtc(void) {
    section("3. MTC at J2000.0 (Allison & McEwen calibration)");

    ipt_mtc_t mtc;
    int rc = ipt_get_mtc(T_J2000, &mtc);
    ASSERT_INT(rc, 0, "ipt_get_mtc returns 0");

    /* At J2000.0, MTC hour should be close to 0 (within a few hours of the
       Allison & McEwen calibration point).  The exact sol count is large. */
    ASSERT_TRUE(mtc.hour >= 0 && mtc.hour <= 23, "MTC hour in [0,23]");
    ASSERT_TRUE(mtc.minute >= 0 && mtc.minute <= 59, "MTC minute in [0,59]");
    ASSERT_TRUE(mtc.sol > 0, "MTC sol > 0 at J2000");

    /* JS reference gives MTC ≈ 15:45 at J2000. Verify hour and minute are plausible.
       (The Allison & McEwen calibration anchors the epoch, not J2000 to midnight.) */
    ASSERT_TRUE(mtc.hour >= 0 && mtc.hour <= 23, "MTC hour at J2000 in valid range");
    ASSERT_CLOSE(mtc.hour + mtc.minute / 60.0, 15.75, 1.0, "MTC at J2000 ≈ 15:45");
}

static void test_light_travel(void) {
    section("4–6. Light travel time");

    /* 4. Earth–Mars 2003-08-27 (close approach, ~186 s) */
    double lt_em_2003 = ipt_light_travel_s(IPT_EARTH, IPT_MARS, T_MARS_CLOSE_2003);
    ASSERT_CLOSE(lt_em_2003, 185.97, 30.0, "E-M 2003-08-27 ≈ 186 s ±30");
    ASSERT_TRUE(lt_em_2003 > 150.0 && lt_em_2003 < 220.0, "E-M 2003 in plausible range");

    /* 5. Earth–Mars 2020-10-13 (opposition, ~207 s) */
    double lt_em_2020 = ipt_light_travel_s(IPT_EARTH, IPT_MARS, T_MARS_OPP_2020);
    ASSERT_CLOSE(lt_em_2020, 206.96, 30.0, "E-M 2020-10-13 ≈ 207 s ±30");

    /* 6. Earth–Jupiter 2023-11-03 (~2010 s) */
    double lt_ej_2023 = ipt_light_travel_s(IPT_EARTH, IPT_JUPITER, T_JUP_OPP_2023);
    ASSERT_CLOSE(lt_ej_2023, 2010.0, 200.0, "E-Jupiter 2023-11-03 ≈ 2010 s ±200");

    /* Symmetry: A→B == B→A */
    double lt_me_2003 = ipt_light_travel_s(IPT_MARS, IPT_EARTH, T_MARS_CLOSE_2003);
    ASSERT_CLOSE(lt_em_2003, lt_me_2003, 0.001, "Light travel is symmetric");
}

static void test_planet_time(void) {
    section("7. getPlanetTime — all 9 bodies at 3 reference dates");

    int64_t dates[3] = { T_J2000, T_MARS_CLOSE_2003, T_2025 };
    ipt_planet_t planets[9] = {
        IPT_MERCURY, IPT_VENUS, IPT_EARTH, IPT_MARS,
        IPT_JUPITER, IPT_SATURN, IPT_URANUS, IPT_NEPTUNE, IPT_MOON
    };
    const char *names[9] = {
        "Mercury","Venus","Earth","Mars",
        "Jupiter","Saturn","Uranus","Neptune","Moon"
    };

    for (int di = 0; di < 3; di++) {
        for (int pi = 0; pi < 9; pi++) {
            ipt_planet_time_t pt;
            char label[64];
            snprintf(label, sizeof(label), "%s at date[%d] rc==0", names[pi], di);
            int rc = ipt_get_planet_time(planets[pi], dates[di], 0, &pt);
            ASSERT_INT(rc, 0, label);

            snprintf(label, sizeof(label), "%s hour in [0,23]", names[pi]);
            ASSERT_TRUE(pt.hour >= 0 && pt.hour <= 23, label);

            snprintf(label, sizeof(label), "%s minute in [0,59]", names[pi]);
            ASSERT_TRUE(pt.minute >= 0 && pt.minute <= 59, label);

            snprintf(label, sizeof(label), "%s second in [0,59]", names[pi]);
            ASSERT_TRUE(pt.second >= 0 && pt.second <= 59, label);

            snprintf(label, sizeof(label), "%s day_fraction in [0,1)", names[pi]);
            ASSERT_TRUE(pt.day_fraction >= 0.0 && pt.day_fraction < 1.0, label);

            snprintf(label, sizeof(label), "%s time_str has colon", names[pi]);
            ASSERT_TRUE(pt.time_str[2] == ':', label);
        }
    }

    /* Mars sol info */
    ipt_planet_time_t mars_pt;
    ipt_get_planet_time(IPT_MARS, T_2025, 0, &mars_pt);
    ASSERT_TRUE(mars_pt.sols_per_year >= 668 && mars_pt.sols_per_year <= 669,
                "Mars sols_per_year ≈ 668–669");
    ASSERT_TRUE(mars_pt.sol_in_year >= 0 && mars_pt.sol_in_year < 669,
                "Mars sol_in_year in valid range");
}

static void test_work_hours(void) {
    section("8. Work hour / period logic");

    /* Earth: work period = Mon-Fri, work hours = 9-17.
       J2000.0 = 2000-01-01 Saturday 12:00 UTC.
       Earth epochMs = J2000_MS, so day 0 starts at J2000. */
    ipt_planet_time_t earth_pt;
    ipt_get_planet_time(IPT_EARTH, T_J2000, 0, &earth_pt);
    /* Earth epoch is J2000_MS, so at T_J2000 elapsed=0 → local_hour=0 (midnight).
       period_in_week=0 < 5 → is_work_period=1.
       local_hour=0 which is < 9 → is_work_hour=0 (outside work shift). */
    ASSERT_INT(earth_pt.is_work_period, 1, "Earth at J2000 is work period (period 0)");
    ASSERT_INT(earth_pt.is_work_hour, 0, "Earth at J2000 midnight is NOT work hour");

    /* Add 5 full Earth days to move into the weekend (period 5 or 6) */
    int64_t weekend_ms = T_J2000 + 5LL * 86400000LL + 12LL * 3600000LL; /* noon */
    ipt_planet_time_t wknd_pt;
    ipt_get_planet_time(IPT_EARTH, weekend_ms, 0, &wknd_pt);
    ASSERT_INT(wknd_pt.is_work_period, 0, "Earth after 5 days is rest period");
    ASSERT_INT(wknd_pt.is_work_hour, 0, "Earth weekend is not work hour");

    /* Before work hours: hour < 9 */
    int64_t early_ms = T_J2000 + 8LL * 3600000LL; /* 8:00 AM on day 0 */
    ipt_planet_time_t early_pt;
    ipt_get_planet_time(IPT_EARTH, early_ms, 0, &early_pt);
    ASSERT_INT(early_pt.is_work_hour, 0, "Earth 08:00 is not work hour");

    /* At exactly hour 9 — boundary: >= 9 and < 17 */
    int64_t work_start_ms = T_J2000 + 9LL * 3600000LL;
    ipt_planet_time_t ws_pt;
    ipt_get_planet_time(IPT_EARTH, work_start_ms, 0, &ws_pt);
    ASSERT_INT(ws_pt.is_work_hour, 1, "Earth 09:00 is work hour (boundary)");

    /* Period boundary: period 4 (last work period) vs period 5 (rest).
       With daysPerPeriod=1, periodsPerWeek=7, we need day 5. */
    int64_t day5_ms = T_J2000 + 5LL * 86400000LL + 10LL * 3600000LL;
    ipt_planet_time_t d5;
    ipt_get_planet_time(IPT_EARTH, day5_ms, 0, &d5);
    ASSERT_INT(d5.period_in_week, 5, "Earth day 5 has periodInWeek=5");
    ASSERT_INT(d5.is_work_period, 0, "Earth period 5 is not work period");
}

static void test_los(void) {
    section("9. Line-of-sight");

    /* During conjunction: Sun between Earth and Mars.
       When the planets are on the same side of the Sun, LOS is blocked.
       Approximate conjunction: 2002-08-10 (Earth-Mars solar conjunction). */
    int64_t t_conj = 1028880000000LL; /* 2002-08-10T00:00:00Z */
    ipt_los_t los_conj;
    int rc = ipt_check_los(IPT_EARTH, IPT_MARS, t_conj, &los_conj);
    ASSERT_INT(rc, 0, "ipt_check_los returns 0");
    /* We just check the struct is populated sensibly */
    ASSERT_TRUE(los_conj.closest_sun_au >= 0.0, "LOS closest_sun_au >= 0");
    ASSERT_TRUE(los_conj.elong_deg >= 0.0 && los_conj.elong_deg <= 180.0,
                "LOS elong_deg in [0, 180]");
    /* clear + blocked + degraded: at most one of blocked/degraded can be true */
    ASSERT_TRUE(!(los_conj.blocked && los_conj.degraded),
                "LOS: not both blocked and degraded");
    ASSERT_TRUE(los_conj.clear == (!los_conj.blocked && !los_conj.degraded),
                "LOS clear == !blocked && !degraded");

    /* At Mars close approach 2003-08-27, Mars is at opposition → LOS should be clear */
    ipt_los_t los_opp;
    ipt_check_los(IPT_EARTH, IPT_MARS, T_MARS_CLOSE_2003, &los_opp);
    ASSERT_INT(los_opp.clear, 1, "LOS clear at Mars 2003 opposition");
    ASSERT_INT(los_opp.blocked, 0, "LOS not blocked at Mars 2003 opposition");

    /* Moon uses Earth's orbital elements → same heliocentric position as Earth.
       The C code detects d2≈0 and returns clear=1, closest_sun_au=Earth's helio r ≈1 AU. */
    ipt_los_t los_moon;
    rc = ipt_check_los(IPT_EARTH, IPT_MOON, T_J2000, &los_moon);
    ASSERT_INT(rc, 0, "ipt_check_los Earth-Moon returns 0");
    ASSERT_INT(los_moon.clear, 1, "Earth-Moon LOS is clear (co-located bodies)");
    ASSERT_TRUE(los_moon.closest_sun_au > 0.9 && los_moon.closest_sun_au < 1.1,
                "Earth-Moon closest_sun_au ≈ 1 AU");
}

static void test_meeting_windows(void) {
    section("10. Meeting windows — Earth+0 vs Earth+0 always overlaps on weekday");

    /* Two Earth locations at UTC+0 should overlap during work hours (9-17).
       Search Monday 2025-01-06 to Friday 2025-01-10. */
    int64_t monday_ms = 1736121600000LL; /* 2025-01-06T00:00:00Z (Monday) */
    ipt_window_t wins[32];
    int n = ipt_find_windows(IPT_EARTH, IPT_EARTH, monday_ms, 5, wins, 32);

    ASSERT_TRUE(n > 0, "Earth+0 vs Earth+0 finds at least one window in 5 days");
    if (n > 0) {
        ASSERT_TRUE(wins[0].duration_min >= 60,
                    "First Earth-Earth window is at least 60 minutes");
        ASSERT_TRUE(wins[0].start_ms >= monday_ms, "Window starts after search start");
    }

    /* Earth vs Mars: Mars has a very long day, so search over 14 days */
    int n2 = ipt_find_windows(IPT_EARTH, IPT_MARS, T_2025, 14, wins, 32);
    ASSERT_TRUE(n2 >= 0, "ipt_find_windows Earth-Mars does not crash");

    /* Lower quartile light time — sanity check */
    double lq = ipt_lower_quartile_light_time(IPT_EARTH, IPT_MARS, T_2025);
    ASSERT_TRUE(lq > 100.0 && lq < 1500.0, "E-Mars lower-quartile in plausible range");
}

static void test_formatting(void) {
    section("11. Formatting");

    char buf[64];

    ipt_format_light_time(0.0005, buf, sizeof(buf));
    ASSERT_STR(buf, "<1ms", "format <1ms");

    ipt_format_light_time(0.5, buf, sizeof(buf));
    ASSERT_STR(buf, "500ms", "format 500ms");

    ipt_format_light_time(42.3, buf, sizeof(buf));
    ASSERT_STR(buf, "42.3s", "format 42.3s");

    ipt_format_light_time(186.0, buf, sizeof(buf));
    ASSERT_STR(buf, "3.1min", "format 3.1min");

    ipt_format_light_time(3661.0, buf, sizeof(buf));
    /* 3661 s = 1h 1m */
    ASSERT_STR(buf, "1h 1m", "format 1h 1m");

    /* format_planet_time smoke test */
    ipt_planet_time_t mars_pt;
    ipt_get_planet_time(IPT_MARS, T_2025, 0, &mars_pt);
    char fmt[128];
    ipt_format_planet_time(IPT_MARS, &mars_pt, fmt, sizeof(fmt));
    ASSERT_TRUE(strstr(fmt, "Mars") != NULL, "format_planet_time contains 'Mars'");
}

static void test_helio_sanity(void) {
    section("12. Heliocentric position sanity");

    const struct { ipt_planet_t p; double min_au, max_au; const char *name; } checks[] = {
        { IPT_MERCURY, 0.30, 0.47, "Mercury" },
        { IPT_VENUS,   0.71, 0.73, "Venus"   },
        { IPT_EARTH,   0.98, 1.02, "Earth"   },
        { IPT_MARS,    1.38, 1.67, "Mars"    },
        { IPT_JUPITER, 4.90, 5.46, "Jupiter" },
        { IPT_SATURN,  9.04, 10.07,"Saturn"  },
        { IPT_URANUS,  18.3, 20.1, "Uranus"  },
        { IPT_NEPTUNE, 29.8, 30.3, "Neptune" },
        { IPT_MOON,    0.98, 1.02, "Moon"    },
    };
    const int n = sizeof(checks) / sizeof(checks[0]);

    for (int i = 0; i < n; i++) {
        ipt_helio_t pos;
        char label[64];
        ipt_helio_pos(checks[i].p, T_2024_MID, &pos);
        snprintf(label, sizeof(label), "%s helio r in [%.2f, %.2f] AU", checks[i].name,
                 checks[i].min_au, checks[i].max_au);
        ASSERT_TRUE(pos.r >= checks[i].min_au && pos.r <= checks[i].max_au, label);
    }
}

/* ── Main ─────────────────────────────────────────────────────────────────── */

int main(void) {
    printf("libinterplanet C unit tests\n");
    printf("============================\n");

    test_constants();
    test_jde();
    test_mtc();
    test_light_travel();
    test_planet_time();
    test_work_hours();
    test_los();
    test_meeting_windows();
    test_formatting();
    test_helio_sanity();

    printf("\n============================\n");
    printf("Results: %d passed, %d failed\n", PASS, FAIL);

    return FAIL > 0 ? 1 : 0;
}
