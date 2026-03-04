/**
 * Script Include: x_snc_ipt_PlanetTime
 * Scope: x_snc_ipt (Interplanet Time)
 *
 * Provides planetary time calculations including Mars Time (MTC),
 * light-travel delay between solar system bodies, and formatting helpers.
 *
 * ES5 compatible — no const, let, or arrow functions.
 */
var x_snc_ipt = x_snc_ipt || {};

x_snc_ipt.PlanetTime = Class.create();
x_snc_ipt.PlanetTime.prototype = {

    initialize: function () {
        // Mean distance from Sun in AU for each supported body.
        // Values are time-averaged (epoch J2000.0).
        this._distanceAu = {
            mercury:  0.387,
            venus:    0.723,
            earth:    1.000,
            mars:     1.524,
            ceres:    2.767,
            jupiter:  5.203,
            saturn:   9.537,
            uranus:  19.191,
            neptune: 30.069,
            pluto:   39.482
        };

        // Speed of light in AU per second
        this._lightSpeedAuPerSec = 499.004783836; // 1 AU / c  (seconds)
    },

    /**
     * Returns the current interplanetary time record for a given body.
     * @param {string} bodyKey - lowercase planet key, e.g. 'mars'
     * @param {GlideDateTime} [gdt] - optional reference time; defaults to now
     * @returns {Object} { bodyKey, utcISO, mtc, lightSecondsFromEarth, lightTimeFormatted }
     */
    getPlanetTime: function (bodyKey, gdt) {
        var now = gdt || new GlideDateTime();
        var utcISO = now.getValue();
        var bodyLower = (bodyKey || 'mars').toLowerCase();

        var ltSec = this.lightTravelSeconds('earth', bodyLower);
        var mtcStr = (bodyLower === 'mars') ? this.getMTC(now) : '';

        return {
            bodyKey: bodyLower,
            utcISO: utcISO,
            mtc: mtcStr,
            lightSecondsFromEarth: ltSec,
            lightTimeFormatted: this.formatLightTime(ltSec)
        };
    },

    /**
     * Calculates one-way light travel time in seconds between two bodies.
     * Uses the difference of mean heliocentric distances as a simple approximation.
     * @param {string} fromBody - source body key
     * @param {string} toBody   - destination body key
     * @returns {number} light travel seconds (positive)
     */
    lightTravelSeconds: function (fromBody, toBody) {
        var fromAu = this.bodyDistanceAu(fromBody);
        var toAu   = this.bodyDistanceAu(toBody);
        var deltaAu = Math.abs(toAu - fromAu);
        // Multiply by seconds-per-AU (1 AU / speed of light)
        return deltaAu * this._lightSpeedAuPerSec;
    },

    /**
     * Returns the mean heliocentric distance in AU for a body.
     * Falls back to Earth (1.0 AU) for unknown keys.
     * @param {string} bodyKey
     * @returns {number} distance in AU
     */
    bodyDistanceAu: function (bodyKey) {
        var key = (bodyKey || '').toLowerCase();
        if (this._distanceAu.hasOwnProperty(key)) {
            return this._distanceAu[key];
        }
        return 1.0; // default to Earth
    },

    /**
     * Computes Mars Coordinated Time (MTC) for a given GlideDateTime.
     * Based on the algorithm from the Mars24 sunclock by Michael Allison (NASA/GISS).
     * @param {GlideDateTime} gdt
     * @returns {string} MTC in "HH:MM:SS" format
     */
    getMTC: function (gdt) {
        var msEpoch = gdt.getNumericValue(); // ms since Unix epoch

        // Julian Date of Unix epoch is 2440587.5
        var jdUt = 2440587.5 + msEpoch / 86400000.0;

        // Julian Date of J2000 epoch
        var j2000 = jdUt - 2451545.0;

        // Mars mean anomaly (degrees)
        var mAnomDeg = (19.3870 + 0.52402075 * j2000) % 360.0;

        // Equation of center (degrees)
        var mAnomRad = mAnomDeg * Math.PI / 180.0;
        var eoc = (10.691 + 3.0e-7 * j2000) * Math.sin(mAnomRad)
                + 0.623 * Math.sin(2 * mAnomRad)
                + 0.050 * Math.sin(3 * mAnomRad)
                + 0.005 * Math.sin(4 * mAnomRad)
                + 0.0005 * Math.sin(5 * mAnomRad);

        // Fictional Mean Sun
        var fms = (270.3863 + 0.52403840 * j2000) % 360.0;

        // Areocentric solar longitude (Ls)
        var ls = (fms + eoc) % 360.0;

        // Equation of Time (degrees)
        var eot = 2.861 * Math.sin(2 * ls * Math.PI / 180.0)
                - 0.071 * Math.sin(4 * ls * Math.PI / 180.0)
                + 0.002 * Math.sin(6 * ls * Math.PI / 180.0)
                - eoc;

        // Mars Solar Date (MSD)
        var msd = (j2000 - 4.5) / 1.027491252 + 44796.0 - 0.00096;

        // Mars Coordinated Time (MTC) in hours
        var mtcHours = (24.0 * msd + eot / 15.0) % 24.0;
        if (mtcHours < 0) { mtcHours += 24.0; }

        var hh = Math.floor(mtcHours);
        var mm = Math.floor((mtcHours - hh) * 60);
        var ss = Math.floor(((mtcHours - hh) * 60 - mm) * 60);

        return this._pad2(hh) + ':' + this._pad2(mm) + ':' + this._pad2(ss);
    },

    /**
     * Formats a light-travel duration in seconds into a human-readable string.
     * e.g. 762 -> "12 min 42 sec"
     *      45  -> "45 sec"
     *      5400 -> "1 hr 30 min"
     * @param {number} seconds
     * @returns {string}
     */
    formatLightTime: function (seconds) {
        var s = Math.round(seconds);
        if (s < 60) {
            return s + ' sec';
        }
        var m = Math.floor(s / 60);
        var remS = s % 60;
        if (m < 60) {
            return m + ' min' + (remS > 0 ? ' ' + remS + ' sec' : '');
        }
        var h = Math.floor(m / 60);
        var remM = m % 60;
        return h + ' hr' + (remM > 0 ? ' ' + remM + ' min' : '');
    },

    // ---- private helpers ----

    _pad2: function (n) {
        return n < 10 ? '0' + n : '' + n;
    },

    type: 'PlanetTime'
};
