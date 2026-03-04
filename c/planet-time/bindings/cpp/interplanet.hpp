/**
 * interplanet.hpp — Header-only C++17 wrapper for libinterplanet
 *
 * Wraps the C API in the `ipt::` namespace with idiomatic C++ types.
 * Link against libinterplanet (shared or static) when using this header.
 *
 * Example:
 *   #include "interplanet.hpp"
 *   auto pt = ipt::getPlanetTime(ipt::Planet::Mars, utc_ms, 0);
 *   std::cout << pt.timeStr << "\n";
 */

#pragma once

#include "../../include/libinterplanet.h"
#include <string>
#include <vector>
#include <stdexcept>
#include <cstdint>

namespace ipt {

/* ── Planet enum ─────────────────────────────────────────────────────────── */

enum class Planet : int {
    Mercury = IPT_MERCURY,
    Venus   = IPT_VENUS,
    Earth   = IPT_EARTH,
    Mars    = IPT_MARS,
    Jupiter = IPT_JUPITER,
    Saturn  = IPT_SATURN,
    Uranus  = IPT_URANUS,
    Neptune = IPT_NEPTUNE,
    Moon    = IPT_MOON,
};

/* ── Result types ─────────────────────────────────────────────────────────── */

struct HelioPos {
    double x, y, r, lon;
};

struct PlanetTime {
    int     hour, minute, second;
    double  localHour;
    double  dayFraction;
    int32_t dayNumber;
    int32_t dayInYear;
    int32_t yearNumber;
    int     periodInWeek;
    bool    isWorkPeriod;
    bool    isWorkHour;
    std::string timeStr;
    std::string timeStrFull;
    /* Mars only */
    int32_t solInYear;
    int32_t solsPerYear;
};

struct MTC {
    int32_t     sol;
    int         hour, minute, second;
    std::string mtcStr;
};

struct LineOfSight {
    bool   clear, blocked, degraded;
    double closestSunAU;
    double elongDeg;
};

struct MeetingWindow {
    int64_t startMs, endMs;
    int     durationMin;
};

/* ── Helper to convert enum to C type ─────────────────────────────────────── */

inline ipt_planet_t toCPlanet(Planet p) {
    return static_cast<ipt_planet_t>(static_cast<int>(p));
}

/* ── Wrapper functions ────────────────────────────────────────────────────── */

/**
 * Heliocentric position of a planet.
 * @throws std::invalid_argument if planet is invalid.
 */
inline HelioPos helioPos(Planet p, int64_t utc_ms) {
    ipt_helio_t raw;
    if (ipt_helio_pos(toCPlanet(p), utc_ms, &raw) != 0)
        throw std::invalid_argument("ipt::helioPos: invalid planet");
    return { raw.x, raw.y, raw.r, raw.lon };
}

/**
 * Distance in AU between two solar-system bodies.
 * @throws std::invalid_argument on bad input.
 */
inline double bodyDistanceAU(Planet a, Planet b, int64_t utc_ms) {
    double d = ipt_body_distance_au(toCPlanet(a), toCPlanet(b), utc_ms);
    if (d < 0.0) throw std::invalid_argument("ipt::bodyDistanceAU: invalid planet");
    return d;
}

/**
 * One-way light travel time in seconds between two bodies.
 */
inline double lightTravelSeconds(Planet from, Planet to, int64_t utc_ms) {
    double s = ipt_light_travel_s(toCPlanet(from), toCPlanet(to), utc_ms);
    if (s < 0.0) throw std::invalid_argument("ipt::lightTravelSeconds: invalid planet");
    return s;
}

/**
 * Local time on a planet.
 * @param p      Planet.
 * @param utc_ms UTC timestamp in milliseconds.
 * @param tz_h   Integer UTC offset in planet local hours (0 = prime meridian).
 */
inline PlanetTime getPlanetTime(Planet p, int64_t utc_ms, int tz_h = 0) {
    ipt_planet_time_t raw;
    if (ipt_get_planet_time(toCPlanet(p), utc_ms, tz_h, &raw) != 0)
        throw std::invalid_argument("ipt::getPlanetTime: invalid planet");
    PlanetTime out{};
    out.hour         = raw.hour;
    out.minute       = raw.minute;
    out.second       = raw.second;
    out.localHour    = raw.local_hour;
    out.dayFraction  = raw.day_fraction;
    out.dayNumber    = raw.day_number;
    out.dayInYear    = raw.day_in_year;
    out.yearNumber   = raw.year_number;
    out.periodInWeek = raw.period_in_week;
    out.isWorkPeriod = raw.is_work_period != 0;
    out.isWorkHour   = raw.is_work_hour   != 0;
    out.timeStr      = raw.time_str;
    out.timeStrFull  = raw.time_str_full;
    out.solInYear    = raw.sol_in_year;
    out.solsPerYear  = raw.sols_per_year;
    return out;
}

/**
 * Mars Coordinated Time (MTC).
 */
inline MTC getMTC(int64_t utc_ms) {
    ipt_mtc_t raw;
    ipt_get_mtc(utc_ms, &raw);
    return { raw.sol, raw.hour, raw.minute, raw.second, raw.mtc_str };
}

/**
 * Mars local time at a given AMT offset (integer Mars hours).
 */
inline PlanetTime getMarsTimeAtOffset(int64_t utc_ms, int offset_h) {
    ipt_planet_time_t raw;
    ipt_get_mars_time_at_offset(utc_ms, offset_h, &raw);
    PlanetTime out{};
    out.hour      = raw.hour;
    out.minute    = raw.minute;
    out.second    = raw.second;
    out.localHour = raw.local_hour;
    out.dayNumber = raw.day_number;
    out.timeStr   = raw.time_str;
    return out;
}

/**
 * Line-of-sight status between two bodies.
 */
inline LineOfSight checkLOS(Planet a, Planet b, int64_t utc_ms) {
    ipt_los_t raw;
    if (ipt_check_los(toCPlanet(a), toCPlanet(b), utc_ms, &raw) != 0)
        throw std::invalid_argument("ipt::checkLOS: invalid planet");
    return {
        raw.clear != 0,
        raw.blocked != 0,
        raw.degraded != 0,
        raw.closest_sun_au,
        raw.elong_deg
    };
}

/**
 * 25th-percentile light travel time over one Earth year (360 samples).
 */
inline double lowerQuartileLightTime(Planet a, Planet b, int64_t ref_ms) {
    double s = ipt_lower_quartile_light_time(toCPlanet(a), toCPlanet(b), ref_ms);
    if (s < 0.0) throw std::invalid_argument("ipt::lowerQuartileLightTime: invalid planet");
    return s;
}

/**
 * Find work-hour overlap windows between two planets.
 * @param earth_days  Number of Earth days to search.
 * @param max_windows Maximum windows to return.
 */
inline std::vector<MeetingWindow> findWindows(Planet a, Planet b,
                                               int64_t from_ms,
                                               int earth_days,
                                               int max_windows = 64) {
    std::vector<ipt_window_t> raw(max_windows);
    int n = ipt_find_windows(toCPlanet(a), toCPlanet(b), from_ms, earth_days,
                              raw.data(), max_windows);
    std::vector<MeetingWindow> out;
    out.reserve(n);
    for (int i = 0; i < n; i++)
        out.push_back({ raw[i].start_ms, raw[i].end_ms, raw[i].duration_min });
    return out;
}

/**
 * Format a light travel time as a human-readable string.
 */
inline std::string formatLightTime(double seconds) {
    char buf[64];
    ipt_format_light_time(seconds, buf, sizeof(buf));
    return buf;
}

/**
 * Format a PlanetTime as a human-readable string.
 * (Requires the original ipt_planet_time_t; use the C API directly or
 *  call ipt_format_planet_time with the C struct.)
 */
inline std::string formatPlanetTime(Planet p, const ipt_planet_time_t &pt) {
    char buf[128];
    ipt_format_planet_time(toCPlanet(p), &pt, buf, sizeof(buf));
    return buf;
}

/* ── Constants ────────────────────────────────────────────────────────────── */

inline double auKm()       { return IPT_AU_KM;        }
inline double cKms()       { return IPT_C_KMS;         }
inline double auSeconds()  { return IPT_AU_SECONDS;    }
inline double j2000JD()    { return IPT_J2000_JD;      }
inline int64_t j2000Ms()   { return IPT_J2000_MS;      }
inline int64_t marsSolMs() { return IPT_MARS_SOL_MS;   }
inline int64_t marsEpochMs(){ return IPT_MARS_EPOCH_MS; }

} /* namespace ipt */
