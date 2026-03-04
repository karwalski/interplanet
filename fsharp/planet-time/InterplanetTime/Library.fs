// Library.fs — Interplanetary Time Library for F# (.NET 6)
// Port of planet-time.js v1.1.0 — Story 18.14
//
// Provides time, calendar, orbital mechanics, and light-speed calculations
// for every planet in the solar system.
//
// Module: InterplanetTime

module InterplanetTime

open System

// ── Planet discriminated union ────────────────────────────────────────────────

type Planet =
    | Mercury
    | Venus
    | Earth
    | Mars
    | Jupiter
    | Saturn
    | Uranus
    | Neptune
    | Moon

// ── Result record types ───────────────────────────────────────────────────────

type PlanetTime = {
    Hour         : int
    Minute       : int
    Second       : int
    LocalHour    : float
    DayFraction  : float
    DayNumber    : int64
    DayInYear    : int64
    YearNumber   : int64
    PeriodInWeek : int
    IsWorkPeriod : bool
    IsWorkHour   : bool
    TimeStr      : string
    TimeStrFull  : string
    SolInYear    : int option
    SolsPerYear  : int option
}

type MtcResult = {
    Sol    : int64
    Hour   : int
    Minute : int
    Second : int
    MtcStr : string
}

type HelioPos = {
    X   : float
    Y   : float
    R   : float
    Lon : float
}

// ── Internal planet data ──────────────────────────────────────────────────────

type private PlanetData = {
    SolarDayMs        : int64
    SiderealYrMs      : int64
    EpochMs           : int64
    WorkStart         : int
    WorkEnd           : int
    DaysPerPeriod     : float
    PeriodsPerWeek    : int
    WorkPeriodsPerWeek: int
    EarthClockSched   : bool
}

type private OrbElems = {
    L0  : float   // mean longitude at J2000 (deg)
    DL  : float   // rate (deg/Julian century)
    Om0 : float   // longitude of perihelion (deg)
    E0  : float   // eccentricity
    A   : float   // semi-major axis (AU)
}

// ── Constants ─────────────────────────────────────────────────────────────────

/// J2000.0 epoch as Unix timestamp (ms) — Date.UTC(2000,0,1,12,0,0)
let [<Literal>] J2000_MS : int64 = 946_728_000_000L

/// Julian Day number of J2000.0
let [<Literal>] J2000_JD : float = 2_451_545.0

/// Mars epoch (MY0) — Date.UTC(1953,4,24,9,3,58,464)
let [<Literal>] MARS_EPOCH_MS : int64 = -524_069_761_536L

/// Mars solar day in milliseconds (24h 39m 35.244s)
let [<Literal>] MARS_SOL_MS : int64 = 88_775_244L

/// 1 AU in kilometres (IAU 2012)
let [<Literal>] AU_KM : float = 149_597_870.7

/// Speed of light in km/s (SI definition)
let [<Literal>] C_KMS : float = 299_792.458

/// Light travel time for 1 AU in seconds
let AU_SECONDS : float = AU_KM / C_KMS  // ≈ 499.004 s

// ── IERS leap seconds (28 entries, last: 2017-01-01) ─────────────────────────
// [utcMs, taiMinusUtc]

let private LEAP_SECS : (int64 * int) array = [|
    (63_072_000_000L,   10); (78_796_800_000L,   11); (94_694_400_000L,   12)
    (126_230_400_000L,  13); (157_766_400_000L,  14); (189_302_400_000L,  15)
    (220_924_800_000L,  16); (252_460_800_000L,  17); (283_996_800_000L,  18)
    (315_532_800_000L,  19); (362_793_600_000L,  20); (394_329_600_000L,  21)
    (425_865_600_000L,  22); (489_024_000_000L,  23); (567_993_600_000L,  24)
    (631_152_000_000L,  25); (662_688_000_000L,  26); (709_948_800_000L,  27)
    (741_484_800_000L,  28); (773_020_800_000L,  29); (820_454_400_000L,  30)
    (867_715_200_000L,  31); (915_148_800_000L,  32); (1_136_073_600_000L, 33)
    (1_230_768_000_000L, 34); (1_341_100_800_000L, 35); (1_435_708_800_000L, 36)
    (1_483_228_800_000L, 37)
|]

// ── Orbital elements (Meeus Table 31.a) ──────────────────────────────────────

let private ORB_ELEMS : Map<string, OrbElems> =
    Map.ofList [
        "mercury", { L0 = 252.2507; DL = 149_474.0722; Om0 =  77.4561; E0 = 0.20564; A =  0.38710 }
        "venus",   { L0 = 181.9798; DL =  58_519.2130; Om0 = 131.5637; E0 = 0.00677; A =  0.72333 }
        "earth",   { L0 = 100.4664; DL =  36_000.7698; Om0 = 102.9373; E0 = 0.01671; A =  1.00000 }
        "mars",    { L0 = 355.4330; DL =  19_141.6964; Om0 = 336.0600; E0 = 0.09341; A =  1.52366 }
        "jupiter", { L0 =  34.3515; DL =   3_036.3027; Om0 =  14.3320; E0 = 0.04849; A =  5.20336 }
        "saturn",  { L0 =  50.0775; DL =   1_223.5093; Om0 =  93.0572; E0 = 0.05551; A =  9.53707 }
        "uranus",  { L0 = 314.0550; DL =     429.8633; Om0 = 173.0052; E0 = 0.04630; A = 19.19126 }
        "neptune", { L0 = 304.3480; DL =     219.8997; Om0 =  48.1234; E0 = 0.00899; A = 30.06900 }
        // Moon uses Earth's orbit for heliocentric position
        "moon",    { L0 = 100.4664; DL =  36_000.7698; Om0 = 102.9373; E0 = 0.01671; A =  1.00000 }
    ]

// ── Planet data table ─────────────────────────────────────────────────────────

let private EARTH_DAY_MS : int64 = 86_400_000L

let private PLANET_DATA : Map<string, PlanetData> =
    Map.ofList [
        "mercury", {
            SolarDayMs        = int64 (Math.Round(175.9408 * float EARTH_DAY_MS))
            SiderealYrMs      = int64 (Math.Round(87.9691  * float EARTH_DAY_MS))
            EpochMs           = J2000_MS
            WorkStart = 9; WorkEnd = 17
            DaysPerPeriod = 1.0; PeriodsPerWeek = 7; WorkPeriodsPerWeek = 5
            EarthClockSched = true
        }
        "venus", {
            SolarDayMs        = int64 (Math.Round(116.7500 * float EARTH_DAY_MS))
            SiderealYrMs      = int64 (Math.Round(224.701  * float EARTH_DAY_MS))
            EpochMs           = J2000_MS
            WorkStart = 9; WorkEnd = 17
            DaysPerPeriod = 1.0; PeriodsPerWeek = 7; WorkPeriodsPerWeek = 5
            EarthClockSched = true
        }
        "earth", {
            SolarDayMs        = EARTH_DAY_MS
            SiderealYrMs      = int64 (Math.Round(365.25636 * float EARTH_DAY_MS))
            EpochMs           = J2000_MS
            WorkStart = 9; WorkEnd = 17
            DaysPerPeriod = 1.0; PeriodsPerWeek = 7; WorkPeriodsPerWeek = 5
            EarthClockSched = false
        }
        "mars", {
            SolarDayMs        = MARS_SOL_MS
            SiderealYrMs      = int64 (Math.Round(686.9957 * float EARTH_DAY_MS))
            EpochMs           = MARS_EPOCH_MS
            WorkStart = 9; WorkEnd = 17
            DaysPerPeriod = 1.0; PeriodsPerWeek = 7; WorkPeriodsPerWeek = 5
            EarthClockSched = false
        }
        "jupiter", {
            SolarDayMs        = int64 (Math.Round(9.9250 * 3_600_000.0))
            SiderealYrMs      = int64 (Math.Round(4332.589 * float EARTH_DAY_MS))
            EpochMs           = J2000_MS
            WorkStart = 8; WorkEnd = 16
            DaysPerPeriod = 2.5; PeriodsPerWeek = 7; WorkPeriodsPerWeek = 5
            EarthClockSched = false
        }
        "saturn", {
            SolarDayMs        = int64 (Math.Round(10.578 * 3_600_000.0))
            SiderealYrMs      = int64 (Math.Round(10_759.22 * float EARTH_DAY_MS))
            EpochMs           = J2000_MS
            WorkStart = 8; WorkEnd = 16
            DaysPerPeriod = 2.25; PeriodsPerWeek = 7; WorkPeriodsPerWeek = 5
            EarthClockSched = false
        }
        "uranus", {
            SolarDayMs        = int64 (Math.Round(17.2479 * 3_600_000.0))
            SiderealYrMs      = int64 (Math.Round(30_688.5 * float EARTH_DAY_MS))
            EpochMs           = J2000_MS
            WorkStart = 8; WorkEnd = 16
            DaysPerPeriod = 1.0; PeriodsPerWeek = 7; WorkPeriodsPerWeek = 5
            EarthClockSched = false
        }
        "neptune", {
            SolarDayMs        = int64 (Math.Round(16.1100 * 3_600_000.0))
            SiderealYrMs      = int64 (Math.Round(60_195.0 * float EARTH_DAY_MS))
            EpochMs           = J2000_MS
            WorkStart = 8; WorkEnd = 16
            DaysPerPeriod = 1.0; PeriodsPerWeek = 7; WorkPeriodsPerWeek = 5
            EarthClockSched = false
        }
        "moon", {
            SolarDayMs        = EARTH_DAY_MS
            SiderealYrMs      = int64 (Math.Round(365.25636 * float EARTH_DAY_MS))
            EpochMs           = J2000_MS
            WorkStart = 9; WorkEnd = 17
            DaysPerPeriod = 1.0; PeriodsPerWeek = 7; WorkPeriodsPerWeek = 5
            EarthClockSched = false
        }
    ]

// ── TT / JDE helpers ──────────────────────────────────────────────────────────

let private getTAIminusUTC (utcMs: int64) : int =
    LEAP_SECS
    |> Array.fold (fun acc (tMs, delta) ->
        if utcMs >= tMs then delta else acc) 10

let private jde (utcMs: int64) : float =
    let ttMs = float utcMs + float (getTAIminusUTC utcMs) * 1000.0 + 32_184.0
    2_440_587.5 + ttMs / 86_400_000.0

let private julianCenturies (utcMs: int64) : float =
    (jde utcMs - J2000_JD) / 36_525.0

// ── Kepler solver ─────────────────────────────────────────────────────────────

let private keplerE (mRad: float) (e: float) : float =
    let mutable e_ = mRad
    let mutable i  = 0
    while i < 50 do
        let dE = (mRad - e_ + e * Math.Sin(e_)) / (1.0 - e * Math.Cos(e_))
        e_ <- e_ + dE
        if Math.Abs(dE) < 1e-12 then i <- 50   // break
        else i <- i + 1
    e_

// ── Heliocentric position ─────────────────────────────────────────────────────

let private getHelioXY (planet: string) (utcMs: int64) : HelioPos =
    let key = if planet = "moon" then "earth" else planet
    let el  = ORB_ELEMS |> Map.tryFind key |> Option.defaultWith (fun () -> ORB_ELEMS.["earth"])

    let t   = julianCenturies utcMs
    let d2r = Math.PI / 180.0
    let tau = 2.0 * Math.PI

    let l   = ((el.L0 + el.DL * t) * d2r % tau + tau) % tau
    let om  = el.Om0 * d2r
    let m   = ((l - om) % tau + tau) % tau
    let e   = el.E0
    let a   = el.A

    let ecc = keplerE m e
    let nu  = 2.0 * Math.Atan2(
                Math.Sqrt(1.0 + e) * Math.Sin(ecc / 2.0),
                Math.Sqrt(1.0 - e) * Math.Cos(ecc / 2.0))
    let r   = a * (1.0 - e * Math.Cos(ecc))
    let lon = ((nu + om) % tau + tau) % tau

    { X = r * Math.Cos(lon); Y = r * Math.Sin(lon); R = r; Lon = lon }

// ── Public API ────────────────────────────────────────────────────────────────

/// Get the heliocentric position of a planet at the given UTC milliseconds.
/// Moon uses Earth's orbital elements.
let helioPos (planet: string) (utcMs: int64) : HelioPos =
    getHelioXY planet utcMs

/// Distance in AU between two solar system bodies.
let bodyDistanceAu (a: string) (b: string) (utcMs: int64) : float =
    let pA = getHelioXY a utcMs
    let pB = getHelioXY b utcMs
    let dx = pA.X - pB.X
    let dy = pA.Y - pB.Y
    Math.Sqrt(dx * dx + dy * dy)

/// One-way light travel time between two bodies in seconds.
let lightTravelSeconds (from_: string) (to_: string) (utcMs: int64) : float =
    bodyDistanceAu from_ to_ utcMs * AU_SECONDS

/// Get Mars Coordinated Time (MTC) for the given UTC milliseconds.
let getMtc (utcMs: int64) : MtcResult =
    let ms   = float (utcMs - MARS_EPOCH_MS)
    let solD = ms / float MARS_SOL_MS
    let sol  = int64 (Math.Floor(solD))
    let frac = solD - Math.Floor(solD)

    let h   = int (frac * 24.0)
    let mf  = (frac * 24.0 - float h) * 60.0
    let m   = int mf
    let s   = int ((mf - float m) * 60.0)

    { Sol = sol; Hour = h; Minute = m; Second = s
      MtcStr = sprintf "%02d:%02d" h m }

/// Get the local time on a planet.
/// tzOffsetH is the optional zone offset in local hours from the planet prime meridian.
/// For Moon, uses Earth solar day and epoch (tidally locked).
let getPlanetTime (planet: string) (utcMs: int64) (tzOffsetH: float) : PlanetTime =
    let effective = if planet = "moon" then "earth" else planet
    let pd =
        match PLANET_DATA |> Map.tryFind effective with
        | Some d -> d
        | None   -> failwith (sprintf "Unknown planet: %s" planet)

    let solarDay = float pd.SolarDayMs

    // tz offset applied as fraction of solar day (matches JS exactly)
    let elapsedMs = float (utcMs - pd.EpochMs) + tzOffsetH / 24.0 * solarDay
    let totalDays = elapsedMs / solarDay
    let dayNumber = int64 (Math.Floor(totalDays))
    let dayFrac   = totalDays - float dayNumber

    let localHour = dayFrac * 24.0
    let h  = int localHour
    let mf = (localHour - float h) * 60.0
    let m  = int mf
    let s  = int ((mf - float m) * 60.0)

    // Work period (positive modulo so pre-epoch dates give valid range)
    let piw, isWorkPeriod, isWorkHour =
        if pd.EarthClockSched then
            // Mercury/Venus: solar day >> circadian rhythm; use UTC Earth-clock scheduling
            // UTC day-of-week: ((floor(utcMs / 86400000) % 7 + 10) % 7 → Mon=0..Sun=6
            // (+7 before +3 ensures positive result for pre-1970 timestamps)
            let utcDay = int64 (Math.Floor(float utcMs / 86_400_000.0))
            let p = int (((utcDay % 7L) + 10L) % 7L)
            let wp = p < pd.WorkPeriodsPerWeek
            // UTC hour within the day — positive modulo handles pre-1970 timestamps
            let msInDay = ((utcMs % 86_400_000L) + 86_400_000L) % 86_400_000L
            let utcHour = float msInDay / 3_600_000.0
            let wh = wp && utcHour >= float pd.WorkStart && utcHour < float pd.WorkEnd
            p, wp, wh
        else
            let totalPeriods = totalDays / pd.DaysPerPeriod
            let p = (int (Math.Floor(totalPeriods)) % pd.PeriodsPerWeek + pd.PeriodsPerWeek) % pd.PeriodsPerWeek
            let wp = p < pd.WorkPeriodsPerWeek
            let wh = wp && localHour >= float pd.WorkStart && localHour < float pd.WorkEnd
            p, wp, wh

    // Year / day-in-year
    let yearLenDays = float pd.SiderealYrMs / solarDay
    let yearNumber  = int64 (Math.Floor(totalDays / yearLenDays))
    let dayInYear   = int64 (Math.Floor(totalDays - float yearNumber * yearLenDays))

    let solInYear, solsPerYear =
        if effective = "mars" then
            Some (int dayInYear),
            Some (int (Math.Round(float pd.SiderealYrMs / solarDay)))
        else
            None, None

    { Hour         = h
      Minute       = m
      Second       = s
      LocalHour    = localHour
      DayFraction  = dayFrac
      DayNumber    = dayNumber
      DayInYear    = dayInYear
      YearNumber   = yearNumber
      PeriodInWeek = piw
      IsWorkPeriod = isWorkPeriod
      IsWorkHour   = isWorkHour
      TimeStr      = sprintf "%02d:%02d" h m
      TimeStrFull  = sprintf "%02d:%02d:%02d" h m s
      SolInYear    = solInYear
      SolsPerYear  = solsPerYear }

/// Format a light travel time (seconds) as a human-readable string.
/// Mirrors formatLightTime() in planet-time.js.
let formatLightTime (seconds: float) : string =
    if seconds < 0.001 then "<1ms"
    elif seconds < 1.0  then sprintf "%dms" (int (seconds * 1000.0))
    elif seconds < 60.0 then sprintf "%.1fs" seconds
    elif seconds < 3600.0 then sprintf "%.1fmin" (seconds / 60.0)
    else
        let hr = int (seconds / 3600.0)
        let mn = int (Math.Round((seconds % 3600.0) / 60.0))
        sprintf "%dh %dm" hr mn
