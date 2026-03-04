/**
 * Script Include: x_snc_ipt_LightTimeExchange
 * Scope: x_snc_ipt (Interplanet Time)
 *
 * Builds and manages Light-Time Exchange (LTX) communication plans —
 * structured schedules that account for one-way signal delay between
 * solar system bodies when coordinating messages or meetings.
 *
 * ES5 compatible — no const, let, or arrow functions.
 */
var x_snc_ipt = x_snc_ipt || {};

x_snc_ipt.LightTimeExchange = Class.create();
x_snc_ipt.LightTimeExchange.prototype = {

    initialize: function () {
        this._planetTime = new x_snc_ipt.PlanetTime();
        // Round-trip tolerance window in seconds (replies arriving within this
        // window of the expected round-trip time are considered "on time").
        this.toleranceSec = 30;
    },

    /**
     * Creates a full communication plan between two bodies.
     * @param {string} fromPlanet - originating body key, e.g. 'earth'
     * @param {string} toPlanet   - destination body key, e.g. 'mars'
     * @param {GlideDateTime} sendTime - planned send time
     * @param {number} [meetingDurationMin] - optional meeting window in minutes (default 60)
     * @returns {Object} plan object with segments, totals, and plan ID
     */
    createPlan: function (fromPlanet, toPlanet, sendTime, meetingDurationMin) {
        var duration = meetingDurationMin || 60;
        var planId = this.makePlanId(fromPlanet, toPlanet, sendTime);
        var oneWaySec = this._planetTime.lightTravelSeconds(fromPlanet, toPlanet);
        var segments = this.computeSegments(fromPlanet, toPlanet, sendTime, oneWaySec);

        return {
            planId: planId,
            fromPlanet: fromPlanet,
            toPlanet: toPlanet,
            sendTime: sendTime.getValue(),
            oneWayLightSec: oneWaySec,
            oneWayLightFormatted: this._planetTime.formatLightTime(oneWaySec),
            roundTripLightSec: oneWaySec * 2,
            meetingDurationMin: duration,
            segments: segments,
            totalMin: this.totalMin(segments),
            createdAt: (new GlideDateTime()).getValue()
        };
    },

    /**
     * Computes the ordered time segments for a light-time exchange plan.
     * Segments represent: Outbound signal travel, Reply window, Return signal travel.
     * @param {string} fromPlanet
     * @param {string} toPlanet
     * @param {GlideDateTime} sendTime
     * @param {number} oneWaySec - pre-computed one-way light travel seconds
     * @returns {Array} array of segment objects
     */
    computeSegments: function (fromPlanet, toPlanet, sendTime, oneWaySec) {
        var segments = [];
        var oneWayMin = oneWaySec / 60.0;

        // Segment 1 — Outbound: signal leaves fromPlanet, arrives at toPlanet
        var outboundArrival = new GlideDateTime(sendTime);
        outboundArrival.addSeconds(Math.round(oneWaySec));

        segments.push({
            segmentIndex: 0,
            label: 'Outbound signal',
            type: 'transit',
            direction: 'outbound',
            origin: fromPlanet,
            destination: toPlanet,
            departureTime: sendTime.getValue(),
            arrivalTime: outboundArrival.getValue(),
            durationSec: Math.round(oneWaySec),
            durationMin: parseFloat(oneWayMin.toFixed(2))
        });

        // Segment 2 — Reply window at destination
        var replyWindowSec = Math.max(300, this.toleranceSec * 4); // at least 5 min
        var replyWindowEnd = new GlideDateTime(outboundArrival);
        replyWindowEnd.addSeconds(replyWindowSec);

        segments.push({
            segmentIndex: 1,
            label: 'Reply window at ' + toPlanet,
            type: 'window',
            direction: 'none',
            origin: toPlanet,
            destination: toPlanet,
            departureTime: outboundArrival.getValue(),
            arrivalTime: replyWindowEnd.getValue(),
            durationSec: replyWindowSec,
            durationMin: parseFloat((replyWindowSec / 60.0).toFixed(2))
        });

        // Segment 3 — Return: reply signal travels back to fromPlanet
        var returnArrival = new GlideDateTime(replyWindowEnd);
        returnArrival.addSeconds(Math.round(oneWaySec));

        segments.push({
            segmentIndex: 2,
            label: 'Return signal',
            type: 'transit',
            direction: 'return',
            origin: toPlanet,
            destination: fromPlanet,
            departureTime: replyWindowEnd.getValue(),
            arrivalTime: returnArrival.getValue(),
            durationSec: Math.round(oneWaySec),
            durationMin: parseFloat(oneWayMin.toFixed(2))
        });

        return segments;
    },

    /**
     * Generates a deterministic plan ID string from the plan parameters.
     * Format: "LTX-{FROM}-{TO}-{YYYYMMDDHHmm}"
     * @param {string} fromPlanet
     * @param {string} toPlanet
     * @param {GlideDateTime} sendTime
     * @returns {string}
     */
    makePlanId: function (fromPlanet, toPlanet, sendTime) {
        var datePart = sendTime.getValue().replace(/[-:T ]/g, '').substring(0, 12);
        return 'LTX-' + fromPlanet.toUpperCase()
             + '-' + toPlanet.toUpperCase()
             + '-' + datePart;
    },

    /**
     * Sums the total elapsed minutes across all segments in a plan.
     * @param {Array} segments - array of segment objects from computeSegments()
     * @returns {number} total minutes (rounded to 2 decimal places)
     */
    totalMin: function (segments) {
        var sum = 0;
        for (var i = 0; i < segments.length; i++) {
            sum += segments[i].durationMin;
        }
        return parseFloat(sum.toFixed(2));
    },

    /**
     * Serialises a plan object to a JSON string safe for storing in
     * a ServiceNow large-text field or attachment.
     * @param {Object} plan - plan object from createPlan()
     * @returns {string} JSON string
     */
    planToJson: function (plan) {
        // gs.log is available in server-side context
        try {
            return JSON.stringify(plan, null, 2);
        } catch (e) {
            gs.logError('x_snc_ipt.LightTimeExchange.planToJson: ' + e.message,
                        'LightTimeExchange');
            return '{}';
        }
    },

    /**
     * Saves a plan to the x_snc_ipt_ltx_plan table.
     * @param {Object} plan - plan object from createPlan()
     * @returns {string} sys_id of the created record, or '' on failure
     */
    savePlan: function (plan) {
        try {
            var gr = new GlideRecord('x_snc_ipt_ltx_plan');
            gr.initialize();
            gr.setValue('u_plan_id', plan.planId);
            gr.setValue('u_from_planet', plan.fromPlanet);
            gr.setValue('u_to_planet', plan.toPlanet);
            gr.setValue('u_send_time', plan.sendTime);
            gr.setValue('u_one_way_sec', plan.oneWayLightSec);
            gr.setValue('u_round_trip_sec', plan.roundTripLightSec);
            gr.setValue('u_total_min', plan.totalMin);
            gr.setValue('u_plan_json', this.planToJson(plan));
            return gr.insert();
        } catch (e) {
            gs.logError('x_snc_ipt.LightTimeExchange.savePlan: ' + e.message,
                        'LightTimeExchange');
            return '';
        }
    },

    type: 'LightTimeExchange'
};
