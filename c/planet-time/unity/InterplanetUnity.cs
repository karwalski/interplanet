/**
 * InterplanetUnity.cs — Unity MonoBehaviour helpers for libinterplanet
 *
 * Requires the Interplanet.cs P/Invoke layer to be included in the project,
 * and the native libinterplanet library placed in Assets/Plugins/.
 *
 * Usage:
 *   1. Attach InterplanetClock to any GameObject.
 *   2. Set Planet and TzOffsetHours in the Inspector.
 *   3. The LocalTime and IsWorkHour fields update at ~1 Hz.
 *
 * The library computes times in real-wall-clock UTC, so it works in Editor
 * and in builds without any additional setup.
 */

using System;
using UnityEngine;

namespace Interplanet.Unity
{
    /// <summary>
    /// Polls the local time on a chosen planet at ~1 Hz and exposes it
    /// as Inspector-readable fields. Attach to any GameObject.
    /// </summary>
    public class InterplanetClock : MonoBehaviour
    {
        [Header("Settings")]
        [Tooltip("Which planet to display time for.")]
        public Planet planet = Planet.Mars;

        [Tooltip("Integer UTC offset in planet local hours from prime meridian. " +
                 "For Mars: AMT+4 = 4, AMT-3 = -3.")]
        public int tzOffsetHours = 0;

        [Tooltip("Seconds between updates (default: 1).")]
        public float updateInterval = 1.0f;

        [Header("Read-only output")]
        [SerializeField, Tooltip("Local time string (HH:MM)")]
        private string _localTime = "--:--";

        [SerializeField, Tooltip("Full local time (HH:MM:SS)")]
        private string _localTimeFull = "--:--:--";

        [SerializeField]
        private bool _isWorkHour = false;

        [SerializeField]
        private bool _isWorkPeriod = false;

        [SerializeField]
        private int _dayNumber = 0;

        [SerializeField]
        private int _yearNumber = 0;

        [SerializeField]
        private double _localHour = 0.0;

        /* Public read-only properties */
        public string LocalTime      => _localTime;
        public string LocalTimeFull  => _localTimeFull;
        public bool   IsWorkHour     => _isWorkHour;
        public bool   IsWorkPeriod   => _isWorkPeriod;
        public int    DayNumber      => _dayNumber;
        public int    YearNumber     => _yearNumber;
        public double LocalHourValue => _localHour;

        /* Event fired after each update */
        public event Action<PlanetTime> OnPlanetTimeUpdated;

        private float _elapsed = float.MaxValue; /* force immediate first update */
        private PlanetTime _last;

        private void Update()
        {
            _elapsed += Time.unscaledDeltaTime;
            if (_elapsed < updateInterval) return;
            _elapsed = 0f;
            Refresh();
        }

        /// <summary>Force an immediate refresh (e.g. when settings change).</summary>
        public void Refresh()
        {
            try
            {
                long utcMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
                _last = Api.GetPlanetTime(planet, utcMs, tzOffsetHours);

                _localTime     = _last.TimeStr;
                _localTimeFull = _last.TimeStrFull;
                _isWorkHour    = _last.IsWorkHour;
                _isWorkPeriod  = _last.IsWorkPeriod;
                _dayNumber     = _last.DayNumber;
                _yearNumber    = _last.YearNumber;
                _localHour     = _last.LocalHour;

                OnPlanetTimeUpdated?.Invoke(_last);
            }
            catch (Exception ex)
            {
                Debug.LogWarning($"[InterplanetClock] {ex.Message}");
            }
        }

        private void OnValidate()
        {
            /* Refresh in the Editor when Inspector values change */
            if (Application.isEditor && !Application.isPlaying)
                Refresh();
        }
    }

    /// <summary>
    /// Displays the current Mars Coordinated Time (MTC) on a UI Text component.
    /// Attach alongside a UnityEngine.UI.Text component.
    /// </summary>
    [RequireComponent(typeof(UnityEngine.UI.Text))]
    public class MarsMTCDisplay : MonoBehaviour
    {
        [Tooltip("Seconds between updates.")]
        public float updateInterval = 1.0f;

        private UnityEngine.UI.Text _text;
        private float _elapsed = float.MaxValue;

        private void Awake() { _text = GetComponent<UnityEngine.UI.Text>(); }

        private void Update()
        {
            _elapsed += Time.unscaledDeltaTime;
            if (_elapsed < updateInterval) return;
            _elapsed = 0f;
            try
            {
                long utcMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
                var mtc = Api.GetMTC(utcMs);
                _text.text = $"MTC {mtc.MtcStr}  Sol {mtc.Sol}";
            }
            catch (Exception ex)
            {
                _text.text = "MTC --:--";
                Debug.LogWarning($"[MarsMTCDisplay] {ex.Message}");
            }
        }
    }

    /// <summary>
    /// Shows the current one-way light travel time from Earth to a chosen planet.
    /// </summary>
    public class LightTravelDisplay : MonoBehaviour
    {
        [Tooltip("Destination planet.")]
        public Planet destination = Planet.Mars;

        [Tooltip("Seconds between updates (light travel changes slowly).")]
        public float updateInterval = 60.0f;

        [SerializeField]
        private string _lightTimeStr = "...";

        public string LightTimeStr => _lightTimeStr;

        public event Action<double> OnLightTimeUpdated;

        private float _elapsed = float.MaxValue;

        private void Update()
        {
            _elapsed += Time.unscaledDeltaTime;
            if (_elapsed < updateInterval) return;
            _elapsed = 0f;
            try
            {
                long utcMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
                double secs = Api.LightTravelSeconds(Planet.Earth, destination, utcMs);
                _lightTimeStr = Api.FormatLightTime(secs);
                OnLightTimeUpdated?.Invoke(secs);
            }
            catch (Exception ex)
            {
                _lightTimeStr = "?";
                Debug.LogWarning($"[LightTravelDisplay] {ex.Message}");
            }
        }
    }
}
