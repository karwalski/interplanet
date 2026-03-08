/* InterPlanet — sky.js v1.10.0 */
// ════════════════════════════════════════════════════════════════════════════
// i18n shorthand — t() / getDayAbbr() delegates to window.I18N
// Inline English fallbacks guard against a browser-cached i18n.js that
// predates newly added keys.
// ════════════════════════════════════════════════════════════════════════════
const _I18N_INLINE = {
  'toast.cities_added_n': '{n} cities added',
  'toast.label_no_match': "No match found for '{text}'",
  'toast.label_updated':  'Updated to: {name}, {country}',
};
const t = (key, vars) => {
  let str = window.I18N ? window.I18N.t(key, vars) : key;
  if (str === key && _I18N_INLINE[key]) {
    str = _I18N_INLINE[key].replace(/\{(\w+)\}/g, (_, k) => vars?.[k] != null ? vars[k] : `{${k}}`);
  }
  return str;
};

// ════════════════════════════════════════════════════════════════════════════
// URL HASH CONFIG — bookmarkable city state
// ════════════════════════════════════════════════════════════════════════════
function _toBase64url(str) {
  return btoa(unescape(encodeURIComponent(str)))
    .replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
}
function _fromBase64url(b64) {
  try { return decodeURIComponent(escape(atob(b64.replace(/-/g,'+').replace(/_/g,'/')))); }
  catch(_) { return null; }
}
function syncHash() {
  if (!STATE.cities.length) {
    if (location.hash) history.replaceState(null, '', location.pathname + location.search);
    return;
  }
  history.replaceState(null, '', '#c=' + _toBase64url(
    JSON.stringify({ version: 2, cities: getCompactCities() })
  ));
}
function loadFromHash() {
  const m = location.hash.match(/^#c=([A-Za-z0-9_\-]+)$/);
  if (!m) return false;
  const json = _fromBase64url(m[1]);
  if (!json) return false;
  try {
    const data = JSON.parse(json);
    if (!data || !data.cities) return false;
    if (data.version >= 2) {
      data.cities.forEach(loadCityFromCompact);   // new compact format
    } else {
      data.cities.forEach(d => addCityFromData(d)); // old v1 — cities only, settings ignored
    }
    return true;
  } catch(_) { return false; }
}

// ════════════════════════════════════════════════════════════════════════════
// CITY DATABASE
// ════════════════════════════════════════════════════════════════════════════
// workWeek: 'mon-fri' | 'sun-thu' | 'sat-thu' (Iran) | 'mon-sat' (rare)
// workStart / workEnd: local hours (24h)
// pop: approximate city population (for light pollution)

const CITY_DB = [
  // ── UTC-12
  { city:'Baker Island', country:'US Minor Islands', tz:'Etc/GMT+12', lat:0.19, lon:-176.47, pop:0, workWeek:'mon-fri' },
  // ── UTC-11
  { city:'Apia', country:'Samoa', tz:'Pacific/Apia', lat:-13.83, lon:-171.77, pop:40e3, workWeek:'mon-fri' },
  // ── UTC-10
  { city:'Honolulu', country:'USA', tz:'Pacific/Honolulu', lat:21.31, lon:-157.85, pop:350e3, workWeek:'mon-fri' },
  // ── UTC-9
  { city:'Anchorage', country:'USA', tz:'America/Anchorage', lat:61.22, lon:-149.90, pop:290e3, workWeek:'mon-fri' },
  // ── UTC-8
  { city:'Los Angeles', country:'USA', tz:'America/Los_Angeles', lat:34.05, lon:-118.24, pop:4e6, workWeek:'mon-fri' },
  { city:'San Francisco', country:'USA', tz:'America/Los_Angeles', lat:37.77, lon:-122.42, pop:870e3, workWeek:'mon-fri' },
  { city:'Vancouver', country:'Canada', tz:'America/Vancouver', lat:49.25, lon:-123.12, pop:700e3, workWeek:'mon-fri' },
  // ── UTC-7
  { city:'Denver', country:'USA', tz:'America/Denver', lat:39.74, lon:-104.98, pop:700e3, workWeek:'mon-fri' },
  { city:'Phoenix', country:'USA', tz:'America/Phoenix', lat:33.45, lon:-112.07, pop:1.6e6, workWeek:'mon-fri' },
  { city:'Calgary', country:'Canada', tz:'America/Edmonton', lat:51.05, lon:-114.07, pop:1.3e6, workWeek:'mon-fri' },
  // ── UTC-6
  { city:'Chicago', country:'USA', tz:'America/Chicago', lat:41.85, lon:-87.65, pop:2.7e6, workWeek:'mon-fri' },
  { city:'Houston', country:'USA', tz:'America/Chicago', lat:29.76, lon:-95.37, pop:2.3e6, workWeek:'mon-fri' },
  { city:'Mexico City', country:'Mexico', tz:'America/Mexico_City', lat:19.43, lon:-99.13, pop:9e6, workWeek:'mon-fri' },
  { city:'Winnipeg', country:'Canada', tz:'America/Winnipeg', lat:49.90, lon:-97.14, pop:750e3, workWeek:'mon-fri' },
  { city:'Guatemala City', country:'Guatemala', tz:'America/Guatemala', lat:14.64, lon:-90.51, pop:3e6, workWeek:'mon-fri' },
  // ── UTC-5
  { city:'New York', country:'USA', tz:'America/New_York', lat:40.71, lon:-74.01, pop:8.3e6, workWeek:'mon-fri' },
  { city:'Toronto', country:'Canada', tz:'America/Toronto', lat:43.65, lon:-79.38, pop:2.9e6, workWeek:'mon-fri' },
  { city:'Miami', country:'USA', tz:'America/New_York', lat:25.77, lon:-80.19, pop:470e3, workWeek:'mon-fri' },
  { city:'Lima', country:'Peru', tz:'America/Lima', lat:-12.05, lon:-77.04, pop:10e6, workWeek:'mon-fri' },
  { city:'Bogotá', country:'Colombia', tz:'America/Bogota', lat:4.71, lon:-74.07, pop:7.4e6, workWeek:'mon-fri' },
  { city:'Havana', country:'Cuba', tz:'America/Havana', lat:23.13, lon:-82.38, pop:2.1e6, workWeek:'mon-fri' },
  // ── UTC-4
  { city:'Santiago', country:'Chile', tz:'America/Santiago', lat:-33.45, lon:-70.67, pop:5.6e6, workWeek:'mon-fri' },
  { city:'Caracas', country:'Venezuela', tz:'America/Caracas', lat:10.48, lon:-66.88, pop:3e6, workWeek:'mon-fri' },
  { city:'Halifax', country:'Canada', tz:'America/Halifax', lat:44.65, lon:-63.58, pop:430e3, workWeek:'mon-fri' },
  // ── UTC-3
  { city:'São Paulo', country:'Brazil', tz:'America/Sao_Paulo', lat:-23.55, lon:-46.63, pop:12e6, workWeek:'mon-fri' },
  { city:'Buenos Aires', country:'Argentina', tz:'America/Argentina/Buenos_Aires', lat:-34.60, lon:-58.38, pop:3e6, workWeek:'mon-fri' },
  { city:'Rio de Janeiro', country:'Brazil', tz:'America/Sao_Paulo', lat:-22.91, lon:-43.17, pop:6.7e6, workWeek:'mon-fri' },
  { city:'Montevideo', country:'Uruguay', tz:'America/Montevideo', lat:-34.90, lon:-56.19, pop:1.4e6, workWeek:'mon-fri' },
  // ── UTC-1
  { city:'Ponta Delgada', country:'Portugal (Azores)', tz:'Atlantic/Azores', lat:37.74, lon:-25.67, pop:68e3, workWeek:'mon-fri' },
  // ── UTC+0
  { city:'London', country:'UK', tz:'Europe/London', lat:51.51, lon:-0.13, pop:9e6, workWeek:'mon-fri' },
  { city:'Dublin', country:'Ireland', tz:'Europe/Dublin', lat:53.33, lon:-6.25, pop:1.2e6, workWeek:'mon-fri' },
  { city:'Lisbon', country:'Portugal', tz:'Europe/Lisbon', lat:38.72, lon:-9.14, pop:550e3, workWeek:'mon-fri' },
  { city:'Reykjavik', country:'Iceland', tz:'Atlantic/Reykjavik', lat:64.15, lon:-21.95, pop:130e3, workWeek:'mon-fri' },
  { city:'Accra', country:'Ghana', tz:'Africa/Accra', lat:5.56, lon:-0.20, pop:2.3e6, workWeek:'mon-fri' },
  { city:'Dakar', country:'Senegal', tz:'Africa/Dakar', lat:14.69, lon:-17.44, pop:3.1e6, workWeek:'mon-fri' },
  { city:'Casablanca', country:'Morocco', tz:'Africa/Casablanca', lat:33.59, lon:-7.62, pop:3.7e6, workWeek:'mon-fri' },
  // ── UTC+1
  { city:'Paris', country:'France', tz:'Europe/Paris', lat:48.85, lon:2.35, pop:2.2e6, workWeek:'mon-fri' },
  { city:'Berlin', country:'Germany', tz:'Europe/Berlin', lat:52.52, lon:13.40, pop:3.7e6, workWeek:'mon-fri' },
  { city:'Madrid', country:'Spain', tz:'Europe/Madrid', lat:40.42, lon:-3.70, pop:3.3e6, workWeek:'mon-fri' },
  { city:'Rome', country:'Italy', tz:'Europe/Rome', lat:41.90, lon:12.50, pop:2.9e6, workWeek:'mon-fri' },
  { city:'Amsterdam', country:'Netherlands', tz:'Europe/Amsterdam', lat:52.37, lon:4.89, pop:870e3, workWeek:'mon-fri' },
  { city:'Lagos', country:'Nigeria', tz:'Africa/Lagos', lat:6.45, lon:3.40, pop:15e6, workWeek:'mon-fri' },
  { city:'Kinshasa', country:'DR Congo', tz:'Africa/Kinshasa', lat:-4.32, lon:15.32, pop:15e6, workWeek:'mon-fri' },
  { city:'Warsaw', country:'Poland', tz:'Europe/Warsaw', lat:52.23, lon:21.01, pop:1.8e6, workWeek:'mon-fri' },
  { city:'Stockholm', country:'Sweden', tz:'Europe/Stockholm', lat:59.33, lon:18.07, pop:980e3, workWeek:'mon-fri' },
  // ── UTC+2
  { city:'Cairo', country:'Egypt', tz:'Africa/Cairo', lat:30.06, lon:31.25, pop:10e6, workWeek:'sun-thu' },
  { city:'Athens', country:'Greece', tz:'Europe/Athens', lat:37.97, lon:23.72, pop:800e3, workWeek:'mon-fri' },
  { city:'Helsinki', country:'Finland', tz:'Europe/Helsinki', lat:60.17, lon:24.94, pop:650e3, workWeek:'mon-fri' },
  { city:'Kyiv', country:'Ukraine', tz:'Europe/Kyiv', lat:50.45, lon:30.52, pop:2.8e6, workWeek:'mon-fri' },
  { city:'Bucharest', country:'Romania', tz:'Europe/Bucharest', lat:44.43, lon:26.10, pop:1.8e6, workWeek:'mon-fri' },
  { city:'Johannesburg', country:'South Africa', tz:'Africa/Johannesburg', lat:-26.20, lon:28.04, pop:5.8e6, workWeek:'mon-fri' },
  { city:'Cape Town', country:'South Africa', tz:'Africa/Johannesburg', lat:-33.93, lon:18.42, pop:4.6e6, workWeek:'mon-fri' },
  { city:'Harare', country:'Zimbabwe', tz:'Africa/Harare', lat:-17.82, lon:31.05, pop:1.5e6, workWeek:'mon-fri' },
  { city:'Jerusalem', country:'Israel', tz:'Asia/Jerusalem', lat:31.77, lon:35.21, pop:970e3, workWeek:'sun-thu' },
  { city:'Amman', country:'Jordan', tz:'Asia/Amman', lat:31.95, lon:35.93, pop:4.0e6, workWeek:'sun-thu' },
  { city:'Khartoum', country:'Sudan', tz:'Africa/Khartoum', lat:15.55, lon:32.53, pop:5.6e6, workWeek:'sun-thu' },
  // ── UTC+3
  { city:'Moscow', country:'Russia', tz:'Europe/Moscow', lat:55.75, lon:37.62, pop:12e6, workWeek:'mon-fri' },
  { city:'Istanbul', country:'Turkey', tz:'Europe/Istanbul', lat:41.01, lon:28.95, pop:15e6, workWeek:'mon-fri' },
  { city:'Riyadh', country:'Saudi Arabia', tz:'Asia/Riyadh', lat:24.69, lon:46.72, pop:7.7e6, workWeek:'sun-thu' },
  { city:'Nairobi', country:'Kenya', tz:'Africa/Nairobi', lat:-1.29, lon:36.82, pop:4.4e6, workWeek:'mon-fri' },
  { city:'Baghdad', country:'Iraq', tz:'Asia/Baghdad', lat:33.34, lon:44.40, pop:7.6e6, workWeek:'sun-thu' },
  { city:'Doha', country:'Qatar', tz:'Asia/Qatar', lat:25.29, lon:51.53, pop:635e3, workWeek:'sun-thu' },
  { city:'Kuwait City', country:'Kuwait', tz:'Asia/Kuwait', lat:29.37, lon:47.98, pop:2.4e6, workWeek:'sun-thu' },
  { city:'Addis Ababa', country:'Ethiopia', tz:'Africa/Addis_Ababa', lat:9.03, lon:38.74, pop:3.4e6, workWeek:'mon-fri' },
  { city:'Sanaa', country:'Yemen', tz:'Asia/Aden', lat:15.35, lon:44.21, pop:3.0e6, workWeek:'sun-thu' },
  { city:'Damascus', country:'Syria', tz:'Asia/Damascus', lat:33.51, lon:36.29, pop:2.5e6, workWeek:'sun-thu' },
  // ── UTC+3.5
  { city:'Tehran', country:'Iran', tz:'Asia/Tehran', lat:35.69, lon:51.42, pop:9e6, workWeek:'sat-thu' },
  // ── UTC+4
  { city:'Dubai', country:'UAE', tz:'Asia/Dubai', lat:25.20, lon:55.27, pop:3.3e6, workWeek:'mon-fri' },
  { city:'Abu Dhabi', country:'UAE', tz:'Asia/Dubai', lat:24.47, lon:54.37, pop:1.5e6, workWeek:'mon-fri' },
  { city:'Baku', country:'Azerbaijan', tz:'Asia/Baku', lat:40.41, lon:49.87, pop:2.3e6, workWeek:'mon-fri' },
  { city:'Muscat', country:'Oman', tz:'Asia/Muscat', lat:23.61, lon:58.59, pop:800e3, workWeek:'sun-thu' },
  { city:'Manama', country:'Bahrain', tz:'Asia/Bahrain', lat:26.22, lon:50.59, pop:200e3, workWeek:'sun-thu' },
  // ── UTC+4.5
  { city:'Kabul', country:'Afghanistan', tz:'Asia/Kabul', lat:34.53, lon:69.17, pop:4.1e6, workWeek:'sun-thu' },
  // ── UTC+5
  { city:'Karachi', country:'Pakistan', tz:'Asia/Karachi', lat:24.86, lon:67.01, pop:14e6, workWeek:'mon-fri' },
  { city:'Tashkent', country:'Uzbekistan', tz:'Asia/Tashkent', lat:41.30, lon:69.27, pop:2.7e6, workWeek:'mon-fri' },
  // ── UTC+5.5
  { city:'Mumbai', country:'India', tz:'Asia/Kolkata', lat:19.08, lon:72.88, pop:12e6, workWeek:'mon-fri' },
  { city:'New Delhi', country:'India', tz:'Asia/Kolkata', lat:28.61, lon:77.21, pop:11e6, workWeek:'mon-fri' },
  { city:'Bengaluru', country:'India', tz:'Asia/Kolkata', lat:12.97, lon:77.59, pop:11e6, workWeek:'mon-fri' },
  { city:'Colombo', country:'Sri Lanka', tz:'Asia/Colombo', lat:6.93, lon:79.86, pop:750e3, workWeek:'mon-fri' },
  // ── UTC+5.75
  { city:'Kathmandu', country:'Nepal', tz:'Asia/Kathmandu', lat:27.71, lon:85.32, pop:1e6, workWeek:'sun-fri' },
  // ── UTC+6
  { city:'Dhaka', country:'Bangladesh', tz:'Asia/Dhaka', lat:23.72, lon:90.41, pop:8.9e6, workWeek:'sun-thu' },
  { city:'Almaty', country:'Kazakhstan', tz:'Asia/Almaty', lat:43.25, lon:76.95, pop:1.8e6, workWeek:'mon-fri' },
  // ── UTC+6.5
  { city:'Yangon', country:'Myanmar', tz:'Asia/Yangon', lat:16.87, lon:96.17, pop:5.4e6, workWeek:'mon-fri' },
  // ── UTC+7
  { city:'Bangkok', country:'Thailand', tz:'Asia/Bangkok', lat:13.75, lon:100.52, pop:10e6, workWeek:'mon-fri' },
  { city:'Jakarta', country:'Indonesia', tz:'Asia/Jakarta', lat:-6.21, lon:106.85, pop:10e6, workWeek:'mon-fri' },
  { city:'Ho Chi Minh City', country:'Vietnam', tz:'Asia/Ho_Chi_Minh', lat:10.78, lon:106.70, pop:8.9e6, workWeek:'mon-fri' },
  { city:'Hanoi', country:'Vietnam', tz:'Asia/Ho_Chi_Minh', lat:21.03, lon:105.85, pop:7.6e6, workWeek:'mon-fri' },
  // ── UTC+8
  { city:'Beijing', country:'China', tz:'Asia/Shanghai', lat:39.91, lon:116.39, pop:21e6, workWeek:'mon-fri' },
  { city:'Shanghai', country:'China', tz:'Asia/Shanghai', lat:31.23, lon:121.47, pop:24e6, workWeek:'mon-fri' },
  { city:'Singapore', country:'Singapore', tz:'Asia/Singapore', lat:1.35, lon:103.82, pop:5.9e6, workWeek:'mon-fri' },
  { city:'Hong Kong', country:'China', tz:'Asia/Hong_Kong', lat:22.33, lon:114.17, pop:7.5e6, workWeek:'mon-fri' },
  { city:'Taipei', country:'Taiwan', tz:'Asia/Taipei', lat:25.05, lon:121.57, pop:2.7e6, workWeek:'mon-fri' },
  { city:'Kuala Lumpur', country:'Malaysia', tz:'Asia/Kuala_Lumpur', lat:3.14, lon:101.69, pop:1.8e6, workWeek:'mon-fri' },
  { city:'Perth', country:'Australia', tz:'Australia/Perth', lat:-31.95, lon:115.86, pop:2.1e6, workWeek:'mon-fri' },
  { city:'Manila', country:'Philippines', tz:'Asia/Manila', lat:14.60, lon:120.98, pop:14e6, workWeek:'mon-fri' },
  // ── UTC+9
  { city:'Tokyo', country:'Japan', tz:'Asia/Tokyo', lat:35.69, lon:139.69, pop:14e6, workWeek:'mon-fri' },
  { city:'Seoul', country:'South Korea', tz:'Asia/Seoul', lat:37.57, lon:126.98, pop:10e6, workWeek:'mon-fri' },
  { city:'Osaka', country:'Japan', tz:'Asia/Tokyo', lat:34.69, lon:135.50, pop:2.7e6, workWeek:'mon-fri' },
  { city:'Pyongyang', country:'N. Korea', tz:'Asia/Pyongyang', lat:39.02, lon:125.75, pop:2.9e6, workWeek:'mon-fri' },
  // ── UTC+9.5
  { city:'Adelaide', country:'Australia', tz:'Australia/Adelaide', lat:-34.93, lon:138.60, pop:1.4e6, workWeek:'mon-fri' },
  { city:'Darwin', country:'Australia', tz:'Australia/Darwin', lat:-12.47, lon:130.85, pop:150e3, workWeek:'mon-fri' },
  // ── UTC+10
  { city:'Sydney', country:'Australia', tz:'Australia/Sydney', lat:-33.87, lon:151.21, pop:5.3e6, workWeek:'mon-fri' },
  { city:'Melbourne', country:'Australia', tz:'Australia/Melbourne', lat:-37.81, lon:144.96, pop:5.1e6, workWeek:'mon-fri' },
  { city:'Brisbane', country:'Australia', tz:'Australia/Brisbane', lat:-27.47, lon:153.03, pop:2.5e6, workWeek:'mon-fri' },
  // ── UTC+12
  { city:'Auckland', country:'New Zealand', tz:'Pacific/Auckland', lat:-36.87, lon:174.77, pop:1.7e6, workWeek:'mon-fri' },
  { city:'Wellington', country:'New Zealand', tz:'Pacific/Auckland', lat:-41.29, lon:174.78, pop:215e3, workWeek:'mon-fri' },
  { city:'Suva', country:'Fiji', tz:'Pacific/Fiji', lat:-18.14, lon:178.44, pop:88e3, workWeek:'mon-fri' },
];

// Work week schedules: [workStart, workEnd, workDays (0=Sun … 6=Sat)]
const WORK_SCHEDULES = {
  'mon-fri': { workDays:[1,2,3,4,5], workStart:9, workEnd:18 },
  'sun-thu': { workDays:[0,1,2,3,4], workStart:9, workEnd:18 },
  'sat-thu': { workDays:[6,0,1,2,3], workStart:8, workEnd:17 }, // Iran (Sat-Wed full + Thu half; approx)
  'sun-fri': { workDays:[0,1,2,3,4,5], workStart:9, workEnd:17 }, // Nepal (6-day)
};

// ════════════════════════════════════════════════════════════════════════════
// PUBLIC HOLIDAYS (fixed-date; key = 'MM-DD', value = {country: holidayName})
// Excludes floating holidays (Easter, Thanksgiving, Eid etc.).
// ════════════════════════════════════════════════════════════════════════════
const PUBLIC_HOLIDAYS = {
  '01-01': {
    'USA':'New Year\'s Day','Canada':'New Year\'s Day','UK':'New Year\'s Day',
    'Ireland':'New Year\'s Day','Australia':'New Year\'s Day','New Zealand':'New Year\'s Day',
    'France':'New Year\'s Day','Germany':'New Year\'s Day','Spain':'New Year\'s Day',
    'Italy':'New Year\'s Day','Netherlands':'New Year\'s Day','Poland':'New Year\'s Day',
    'Sweden':'New Year\'s Day','Finland':'New Year\'s Day','Norway':'New Year\'s Day',
    'Greece':'New Year\'s Day','Portugal':'New Year\'s Day',
    'Russia':'New Year\'s Day','Ukraine':'New Year\'s Day','Romania':'New Year\'s Day',
    'Turkey':'New Year\'s Day','Egypt':'New Year\'s Day',
    'South Africa':'New Year\'s Day','Kenya':'New Year\'s Day',
    'Nigeria':'New Year\'s Day','Ghana':'New Year\'s Day','Senegal':'New Year\'s Day',
    'Ethiopia':'New Year\'s Day',
    'Mexico':'New Year\'s Day','Brazil':'New Year\'s Day','Argentina':'New Year\'s Day',
    'Chile':'New Year\'s Day','Colombia':'New Year\'s Day','Uruguay':'New Year\'s Day',
    'Peru':'New Year\'s Day','Cuba':'New Year\'s Day',
    'China':'New Year\'s Day','Japan':'New Year\'s Day','South Korea':'New Year\'s Day',
    'India':'New Year\'s Day','Singapore':'New Year\'s Day','Malaysia':'New Year\'s Day',
    'Philippines':'New Year\'s Day','Indonesia':'New Year\'s Day',
    'Thailand':'New Year\'s Day','Vietnam':'New Year\'s Day',
    'Pakistan':'New Year\'s Day','Bangladesh':'New Year\'s Day',
    'UAE':'New Year\'s Day','Qatar':'New Year\'s Day','Kuwait':'New Year\'s Day',
    'Bahrain':'New Year\'s Day','Oman':'New Year\'s Day','Jordan':'New Year\'s Day',
    'Israel':'New Year\'s Day (Gregorian)','Azerbaijan':'New Year\'s Day',
    'Kazakhstan':'New Year\'s Day','Uzbekistan':'New Year\'s Day',
    'Taiwan':'New Year\'s Day','Hong Kong':'New Year\'s Day',
    'Iceland':'New Year\'s Day','Morocco':'New Year\'s Day',
  },
  '01-06': { 'Spain':'Epiphany','Italy':'Epiphany','Greece':'Epiphany','Poland':'Epiphany','Germany':'Epiphany (some states)' },
  '01-26': { 'India':'Republic Day','Australia':'Australia Day' },
  '02-11': { 'Japan':'National Foundation Day','Iran':'Islamic Revolution Day' },
  '02-23': { 'Japan':'Emperor\'s Birthday' },
  '03-08': {
    'Russia':'International Women\'s Day','Ukraine':'International Women\'s Day',
    'Belarus':'International Women\'s Day','Kazakhstan':'International Women\'s Day',
    'Uzbekistan':'International Women\'s Day','Kyrgyzstan':'International Women\'s Day',
    'Tajikistan':'International Women\'s Day','Turkmenistan':'International Women\'s Day',
    'Armenia':'International Women\'s Day','Azerbaijan':'International Women\'s Day',
    'Georgia':'International Women\'s Day','Moldova':'International Women\'s Day',
    'Mongolia':'International Women\'s Day','Vietnam':'International Women\'s Day',
    'China':'International Women\'s Day (half-day)','Cuba':'International Women\'s Day',
    'North Korea':'International Women\'s Day','Nepal':'International Women\'s Day',
    'Angola':'International Women\'s Day','Uganda':'International Women\'s Day',
    'Zambia':'International Women\'s Day','Madagascar':'International Women\'s Day',
    'Cameroon':'International Women\'s Day','Laos':'International Women\'s Day',
    'Eritrea':'International Women\'s Day','Guinea-Bissau':'International Women\'s Day',
    'Burkina Faso':'International Women\'s Day',
  },
  '03-17': { 'Ireland':'St Patrick\'s Day' },
  '03-25': { 'Greece':'Independence Day' },
  '04-01': { 'Iran':'Islamic Republic Day' },
  '04-17': { 'Syria':'Independence Day' },
  '04-18': { 'Zimbabwe':'Independence Day' },
  '04-23': { 'Turkey':'National Sovereignty and Children\'s Day' },
  '04-25': { 'Australia':'ANZAC Day','New Zealand':'ANZAC Day','Portugal':'Freedom Day' },
  '04-27': { 'South Africa':'Freedom Day' },
  '05-01': {
    'France':'Labour Day','Germany':'Labour Day','Italy':'Labour Day',
    'Spain':'Labour Day','Netherlands':'Labour Day','Poland':'Labour Day',
    'Sweden':'Labour Day','Finland':'Labour Day','Greece':'Labour Day',
    'Russia':'Spring and Labour Day','Ukraine':'Labour Day',
    'Turkey':'Labour Day','China':'Labour Day','South Korea':'Labour Day',
    'India':'May Day','Brazil':'Labour Day','Cuba':'Labour Day',
    'Chile':'Labour Day','Mexico':'Labour Day','Argentina':'Labour Day',
    'Philippines':'Labour Day','Indonesia':'Labour Day','Malaysia':'Labour Day',
    'South Africa':'Workers Day','Kenya':'Labour Day','Nigeria':'Workers Day',
    'Egypt':'Labour Day','Morocco':'Labour Day',
    'Ghana':'May Day','Senegal':'Labour Day','Ethiopia':'Labour Day',
  },
  '05-05': { 'Japan':'Children\'s Day','South Korea':'Children\'s Day' },
  '05-09': { 'Russia':'Victory Day','Ukraine':'Victory Day (historical)' },
  '05-29': { 'Turkey':'Commemoration of Atatürk' },
  '06-02': { 'Italy':'Republic Day' },
  '06-10': { 'Portugal':'Portugal Day' },
  '06-12': { 'Russia':'Russia Day','Philippines':'Independence Day' },
  '06-16': { 'South Africa':'Youth Day' },
  '06-17': { 'Iceland':'National Day' },
  '06-19': { 'USA':'Juneteenth' },
  '06-25': { 'Mozambique':'Independence Day' },
  '07-01': { 'Canada':'Canada Day','Hong Kong':'Hong Kong SAR Establishment Day' },
  '07-04': { 'USA':'Independence Day' },
  '07-14': { 'France':'Bastille Day' },
  '07-21': { 'Belgium':'National Day' },
  '08-01': { 'Switzerland':'National Day' },
  '08-06': { 'Jamaica':'Independence Day' },
  '08-09': { 'Singapore':'National Day' },
  '08-11': { 'Japan':'Mountain Day' },
  '08-14': { 'Pakistan':'Independence Day' },
  '08-15': { 'India':'Independence Day','South Korea':'Liberation Day','France':'Assumption','Italy':'Assumption','Spain':'Assumption' },
  '08-17': { 'Indonesia':'Independence Day' },
  '09-01': { 'Libya':'Revolution Day' },
  '09-02': { 'Vietnam':'National Day' },
  '09-16': { 'Mexico':'Independence Day' },
  '10-01': { 'China':'National Day','Nigeria':'Independence Day' },
  '10-02': { 'India':'Gandhi Jayanti' },
  '10-03': { 'Germany':'German Unity Day','South Korea':'National Foundation Day' },
  '10-09': { 'South Korea':'Hangul Day' },
  '10-10': { 'Taiwan':'National Day' },
  '10-12': { 'Spain':'National Day' },
  '10-26': { 'Austria':'National Day' },
  '10-28': { 'Czech Republic':'Independence Day' },
  '10-29': { 'Turkey':'Republic Day' },
  '11-01': { 'France':'All Saints Day','Spain':'All Saints Day','Italy':'All Saints Day','Poland':'All Saints Day' },
  '11-02': { 'Mexico':'Day of the Dead' },
  '11-03': { 'Japan':'Culture Day' },
  '11-11': { 'USA':'Veterans Day','Canada':'Remembrance Day','France':'Armistice Day','Belgium':'Armistice Day','Poland':'Independence Day','UK':'Remembrance Day (observed)' },
  '11-15': { 'Brazil':'Proclamation of the Republic' },
  '11-23': { 'Japan':'Labour Thanksgiving Day' },
  '12-01': { 'Romania':'National Day' },
  '12-09': { 'Tanzania':'Independence Day' },
  '12-10': { 'Thailand':'Constitution Day' },
  '12-12': { 'Kenya':'Jamhuri Day' },
  '12-16': { 'South Africa':'Day of Reconciliation' },
  '12-25': {
    'USA':'Christmas Day','Canada':'Christmas Day','UK':'Christmas Day',
    'Ireland':'Christmas Day','Australia':'Christmas Day','New Zealand':'Christmas Day',
    'France':'Christmas Day','Germany':'Christmas Day','Spain':'Christmas Day',
    'Italy':'Christmas Day','Netherlands':'Christmas Day','Poland':'Christmas Day',
    'Sweden':'Christmas Day','Finland':'Christmas Day','Greece':'Christmas Day',
    'Portugal':'Christmas Day','Romania':'Christmas Day','Ukraine':'Christmas Day',
    'Russia':'Christmas Day','Brazil':'Christmas Day','Argentina':'Christmas Day',
    'Chile':'Christmas Day','Colombia':'Christmas Day','Mexico':'Christmas Day',
    'Philippines':'Christmas Day','South Korea':'Christmas Day',
    'South Africa':'Christmas Day','Kenya':'Christmas Day','Nigeria':'Christmas Day',
    'Ghana':'Christmas Day','Ethiopia':'Christmas Day (Julian — Jan 7)',
    'Singapore':'Christmas Day','Hong Kong':'Christmas Day','Taiwan':'Christmas Day',
    'Malaysia':'Christmas Day',
  },
  '12-26': {
    'UK':'Boxing Day','Canada':'Boxing Day','Australia':'Boxing Day',
    'New Zealand':'Boxing Day','South Africa':'Day of Goodwill',
    'Ireland':'St Stephen\'s Day',
  },
  '12-27': { 'North Korea':'Constitution Day' },
  '12-31': { 'Japan':'Ōmisoka (New Year\'s Eve)' },
};

// ════════════════════════════════════════════════════════════════════════════
// LOCAL PLANETS — additional bodies not exported by planet-time.js
// ════════════════════════════════════════════════════════════════════════════
const LOCAL_PLANETS = {
  moon: {
    name: 'Moon', symbol: '🌕', color: '#b8b8b8',
    solarDayMs: 29.53058867 * 86400000, // synodic month (day/night cycle from Earth perspective)
    workHoursStart: 9, workHoursEnd: 17,
    notes: 'Earth\'s natural satellite. Tidally locked; 1 lunar day ≈ 29.5 Earth days. ' +
           'Surface: −173°C (night) to +127°C (day). No formal work schedule.',
  },
};

// ── Local-body addon helpers ──────────────────────────────────────────────────
// Used by _addPluto() and any future body addons. NOT in planet-time.js.

/**
 * Build 24 timezone zones for a LOCAL_PLANETS body.
 * Same logic as planet-time.js _makeZones but self-contained so addons don't
 * need to touch the core library.
 * names[0]=prefix+0 … names[12]=prefix±12; names[13]=prefix-11 … names[23]=prefix-1.
 */
function _makeBodyZones(prefix, names) {
  const out = [];
  for (let h = 0; h <= 12; h++)
    out.push({ id: h===0?`${prefix}+0`:h===12?`${prefix}±12`:`${prefix}+${h}`,
               name: names[h] || `${prefix} Zone +${h}`, offsetHours: h });
  for (let h = 11; h >= 1; h--)
    out.push({ id: `${prefix}-${h}`,
               name: names[24-h] || `${prefix} Zone -${h}`, offsetHours: -h });
  return out;
}

/**
 * Keplerian r(M) approximation for a LOCAL_PLANETS body.
 * lp must have: orbitA (AU), orbitE (eccentricity), perihelionEpoch (ms), orbitalPeriodYears.
 * Returns heliocentric distance in AU. Earth is at ~1 AU, so result ≈ Earth distance.
 */
function _localBodyDistAU(lp, nowMs) {
  const periodMs = lp.orbitalPeriodYears * 365.25 * 86400000;
  const M = (((nowMs - lp.perihelionEpoch) % periodMs) + periodMs) % periodMs
            / periodMs * 2 * Math.PI;
  return lp.orbitA * (1 - lp.orbitE * lp.orbitE) / (1 + lp.orbitE * Math.cos(M));
}

/**
 * Compute year-number and sol-in-year for a LOCAL_PLANETS body with orbital data.
 * Returns { yearNumber, solInYear, solsPerYear }.
 */
function _localBodySolInfo(lp, nowMs) {
  const periodMs = lp.orbitalPeriodYears * 365.25 * 86400000;
  const elapsed  = ((nowMs - lp.perihelionEpoch) % periodMs + periodMs) % periodMs;
  const yearNumber = Math.floor((nowMs - lp.perihelionEpoch) / periodMs) + 1;
  const solInYear  = Math.floor(elapsed / lp.solarDayMs) + 1;
  const solsPerYear = Math.round(periodMs / lp.solarDayMs);
  return { yearNumber, solInYear, solsPerYear };
}

function getTodayHoliday(country, tz, date) {
  try {
    const parts = new Intl.DateTimeFormat('en-US',{timeZone:tz,month:'2-digit',day:'2-digit'}).formatToParts(date);
    const mm = parts.find(p=>p.type==='month').value;
    const dd = parts.find(p=>p.type==='day').value;
    return PUBLIC_HOLIDAYS[`${mm}-${dd}`]?.[country] || null;
  } catch { return null; }
}

// ════════════════════════════════════════════════════════════════════════════
// SOLAR POSITION
// ════════════════════════════════════════════════════════════════════════════
function sunAlt(lat, lon, date) {
  const R = Math.PI / 180, D = 180 / Math.PI;
  const n = date.getTime() / 86400000 + 2440587.5 - 2451545.0;
  const L = ((280.460 + 0.9856474 * n) % 360 + 360) % 360;
  const g = (((357.528 + 0.9856003 * n) % 360 + 360) % 360) * R;
  const lam = (L + 1.915 * Math.sin(g) + 0.020 * Math.sin(2 * g)) * R;
  const eps = (23.439 - 4e-7 * n) * R;
  const dec = Math.asin(Math.sin(eps) * Math.sin(lam));
  const RA  = Math.atan2(Math.cos(eps) * Math.sin(lam), Math.cos(lam));
  const UTh = date.getUTCHours() + date.getUTCMinutes()/60 + date.getUTCSeconds()/3600;
  const GMST = (6.697375 + 0.0657098242 * n + UTh) * 15 * R;
  const LHA  = GMST + lon * R - RA;
  const latR = lat * R;
  const sinA = Math.sin(latR)*Math.sin(dec) + Math.cos(latR)*Math.cos(dec)*Math.cos(LHA);
  return Math.asin(Math.max(-1, Math.min(1, sinA))) * D;
}

// ════════════════════════════════════════════════════════════════════════════
// MOON PHASE
// ════════════════════════════════════════════════════════════════════════════
function moonPhase(date) {
  // Returns 0–1 (0=new, 0.5=full) using corrected double-modulo formula
  const knownNew = new Date('2000-01-06T18:14:00Z').getTime();
  const synodicMs = 29.53058867 * 86400000;
  return (((date.getTime() - knownNew) % synodicMs) + synodicMs) % synodicMs / synodicMs;
}
function moonIllum(phase) { return (1 - Math.cos(phase * 2 * Math.PI)) / 2; }
function moonEmoji(phase) {
  return ['🌑','🌒','🌓','🌔','🌕','🌖','🌗','🌘'][Math.round(phase * 8) % 8];
}

// ════════════════════════════════════════════════════════════════════════════
// SUNRISE / SUNSET (5-min scan, cached per city-date)
// ════════════════════════════════════════════════════════════════════════════
const _srCache = new Map();
function getSunriseSunset(lat, lon, date) {
  const key = `${lat.toFixed(2)},${lon.toFixed(2)},${date.toISOString().slice(0,10)}`;
  if (_srCache.has(key)) return _srCache.get(key);

  const STEP = 5 * 60000;
  // Start from 6h before UTC midnight to cover all timezones
  const start = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()) - 6 * 3600000);
  let rise = null, set = null, prev = sunAlt(lat, lon, start);

  for (let i = 1; i <= 360; i++) {          // 360 × 5min = 30h
    const t = new Date(start.getTime() + i * STEP);
    const alt = sunAlt(lat, lon, t);
    if (!rise && prev < 0 && alt >= 0)         rise = t;
    if (rise && !set && prev >= 0 && alt < 0)  set  = t;
    prev = alt;
    if (rise && set) break;
  }

  const result = { rise, set };
  _srCache.set(key, result);
  if (_srCache.size > 200) _srCache.delete(_srCache.keys().next().value); // cap cache
  return result;
}

// ════════════════════════════════════════════════════════════════════════════
// LIGHT-SPEED PING HELPERS
// ════════════════════════════════════════════════════════════════════════════
// C_KMS already declared globally by planet-time.js (299792.458 km/s)
const EARTH_RADIUS_KM = 6371;
function haversineKm(lat1, lon1, lat2, lon2) {
  const R = Math.PI / 180;
  const dLat = (lat2 - lat1) * R, dLon = (lon2 - lon1) * R;
  const a = Math.sin(dLat/2)**2 + Math.cos(lat1*R) * Math.cos(lat2*R) * Math.sin(dLon/2)**2;
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(a));
}
function formatPingSec(seconds) {
  if (seconds < 0.001)   return '<1ms';
  if (seconds < 1)       return `${(seconds*1000).toFixed(0)}ms`;
  if (seconds < 60)      return `${seconds.toFixed(2)}s`;
  if (seconds < 3600)    return `${(seconds/60).toFixed(1)}min`;
  const h = Math.floor(seconds/3600), m = Math.round((seconds%3600)/60);
  return `${h}h ${m}m`;
}

// ════════════════════════════════════════════════════════════════════════════
// PLANET TEMPERATURE ESTIMATOR (Stefan-Boltzmann equilibrium + corrections)
// ════════════════════════════════════════════════════════════════════════════
const ALBEDOS     = { mercury:0.088,venus:0.900,earth:0.306,moon:0.120,
                      mars:0.250,jupiter:0.503,saturn:0.342,uranus:0.300,neptune:0.290 };
const GREENHOUSE  = { venus:450, earth:33 };  // K added by atmosphere
const DAYNIGHTSWING = { mercury:300, moon:150, mars:50 }; // ±K from mean due to diurnal cycle

function estimatePlanetTemp(planetKey, date) {
  let dAU = 1.0;
  try {
    const pos = PlanetTime.planetHelioXY(planetKey, date);
    dAU = pos.r;
  } catch(_) {
    const lp = LOCAL_PLANETS[planetKey];
    if (lp?.orbitA && lp.perihelionEpoch && lp.orbitalPeriodYears)
      dAU = _localBodyDistAU(lp, date.getTime());
    else if (lp?.orbitA) dAU = lp.orbitA;
  }
  const albedo  = ALBEDOS[planetKey] ?? LOCAL_PLANETS[planetKey]?.albedo ?? 0.3;
  const Teq     = 278.5 * Math.pow((1 - albedo) / (dAU * dAU), 0.25); // K
  const Tsurf   = Teq + (GREENHOUSE[planetKey] || 0);
  const meanC   = Math.round(Tsurf - 273.15);

  const swing   = DAYNIGHTSWING[planetKey];
  if (swing) {
    const ptKey = (planetKey === 'moon') ? 'earth' : planetKey;
    const pt = PlanetTime.getPlanetTime(ptKey, date);
    const hourAngle = Math.abs(((pt.localHour - 12 + 12) % 24) - 12); // 0=noon,12=midnight
    const dayFactor = Math.cos(hourAngle * Math.PI / 12);
    return { mean: meanC, current: Math.round(meanC + dayFactor * swing / 2), dynamic: true };
  }
  return { mean: meanC, current: meanC, dynamic: false };
}

// ════════════════════════════════════════════════════════════════════════════
// SVG OUTLINE ICONS — simple inline SVGs for weather/info rows
// ════════════════════════════════════════════════════════════════════════════
const _svgAttrs = (s) => `width="${s}" height="${s}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"`;
const svgTherm  = (s=11) => `<svg ${_svgAttrs(s)}><path d="M14 14.76V3.5a2.5 2.5 0 0 0-5 0v11.26a4.5 4.5 0 1 0 5 0z"/></svg>`;
const svgDrop   = (s=11) => `<svg ${_svgAttrs(s)}><path d="M12 2.69l5.66 5.66a8 8 0 1 1-11.31 0z"/></svg>`;
const svgRain   = (s=11) => `<svg ${_svgAttrs(s)}><line x1="16" y1="13" x2="16" y2="21"/><line x1="8" y1="13" x2="8" y2="21"/><line x1="12" y1="15" x2="12" y2="23"/><path d="M20 16.58A5 5 0 0 0 18 7h-1.26A8 8 0 1 0 4 15.25"/></svg>`;
const svgSunrise= (s=11) => `<svg ${_svgAttrs(s)}><path d="M17 18a5 5 0 0 0-10 0"/><line x1="12" y1="2" x2="12" y2="9"/><line x1="4.22" y1="10.22" x2="5.64" y2="11.64"/><line x1="1" y1="18" x2="3" y2="18"/><line x1="21" y1="18" x2="23" y2="18"/><line x1="18.36" y1="11.64" x2="19.78" y2="10.22"/><line x1="23" y1="22" x2="1" y2="22"/><polyline points="8 6 12 2 16 6"/></svg>`;
const svgSunset = (s=11) => `<svg ${_svgAttrs(s)}><path d="M17 18a5 5 0 0 0-10 0"/><line x1="12" y1="9" x2="12" y2="2"/><line x1="4.22" y1="10.22" x2="5.64" y2="11.64"/><line x1="1" y1="18" x2="3" y2="18"/><line x1="21" y1="18" x2="23" y2="18"/><line x1="18.36" y1="11.64" x2="19.78" y2="10.22"/><line x1="23" y1="22" x2="1" y2="22"/><polyline points="16 5 12 9 8 5"/></svg>`;
const svgMoonIco= (s=11) => `<svg ${_svgAttrs(s)}><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>`;
const svgCalendar=(s=11) => `<svg ${_svgAttrs(s)}><rect x="3" y="4" width="18" height="18" rx="2" ry="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>`;

// ════════════════════════════════════════════════════════════════════════════
// AURORA POTENTIAL (latitude-based heuristic, clear night only)
// ════════════════════════════════════════════════════════════════════════════
function auroraPotential(lat, alt, cloud) {
  if (alt > -3 || cloud > 40) return 0;
  const absLat = Math.abs(lat);
  if (absLat < 50) return 0;
  if (absLat < 55) return 0.05;
  if (absLat < 60) return 0.2;
  if (absLat < 65) return 0.5;
  if (absLat < 72) return 0.85;
  return 0.6; // polar cap — less frequent
}

// Light pollution floor (lifts darkness for cities)
function lightPolFloor(pop) {
  if (pop > 5e6)  return 0.18; // major city: never truly dark
  if (pop > 1e6)  return 0.12;
  if (pop > 200e3) return 0.07;
  if (pop > 50e3)  return 0.03;
  return 0;
}

// ════════════════════════════════════════════════════════════════════════════
// SKY COLOUR ENGINE
// ════════════════════════════════════════════════════════════════════════════
const mix = (a, b, t) => {
  t = Math.max(0, Math.min(1, t));
  return { r: a.r+(b.r-a.r)*t|0, g: a.g+(b.g-a.g)*t|0, b: a.b+(b.b-a.b)*t|0 };
};
const hex3 = c => '#' + [c.r,c.g,c.b].map(v => v.toString(16).padStart(2,'0')).join('');
const lum  = c => (0.299*c.r + 0.587*c.g + 0.114*c.b) / 255;
const liftBrightness = (c, floor) => {
  const l = lum(c); if (l >= floor) return c;
  const t = (floor - l) / (1 - l);
  return mix(c, {r:200,g:190,b:210}, t); // warm city-light tint
};

function skyGradient(alt, cloud, code, lat, pop, date) {
  const cf = (cloud || 0) / 100;
  const moon = moonIllum(moonPhase(date));
  const aurora = auroraPotential(lat, alt, cloud);
  const lpFloor = lightPolFloor(pop);

  // Palette
  const P = {
    night:     {r:6,  g:8,  b:32},
    deepTwil:  {r:18, g:14, b:58},
    nautTwil:  {r:38, g:28, b:90},
    civilTwil: {r:75, g:45, b:115},
    horizGlow: {r:255,g:115,b:45},
    golden:    {r:255,g:165,b:55},
    blueHour:  {r:65, g:115,b:200},
    clearDay:  {r:28, g:138,b:248},
    zenithDay: {r:10, g:90, b:200},
    hazyDay:   {r:120,g:170,b:228},
    overcast:  {r:148,g:158,b:168},
    partCloud: {r:90, g:155,b:235},
    rain:      {r:78, g:88, b:102},
    heavyRain: {r:52, g:57, b:68},
    storm:     {r:33, g:38, b:46},
    stormGrn:  {r:46, g:52, b:38},
    fog:       {r:192,g:197,b:202},
    snowSky:   {r:178,g:190,b:200},
    auroraGrn: {r:30, g:180,b:80},
    auroraPnk: {r:180,g:60, b:160},
    moonlit:   {r:40, g:50, b:80},
    fullMoon:  {r:55, g:65, b:100},
  };

  function baseHorizon(a) {
    if (a <= -18) return P.night;
    if (a <= -12) return mix(P.night,     P.deepTwil,  (a+18)/6);
    if (a <=  -6) return mix(P.deepTwil,  P.nautTwil,  (a+12)/6);
    if (a <=   0) return mix(P.nautTwil,  P.civilTwil, (a+ 6)/6);
    if (a <=   2) return mix(P.civilTwil, P.horizGlow,  a    /2);
    if (a <=   6) return mix(P.horizGlow, P.golden,    (a- 2)/4);
    if (a <=  12) return mix(P.golden,    P.blueHour,  (a- 6)/6);
    if (a <=  20) return mix(P.blueHour,  P.clearDay,  (a-12)/8);
    return P.clearDay;
  }

  function baseZenith(a) {
    if (a <= 0)  return mix(baseHorizon(a), P.night, 0.25);
    if (a <= 12) return mix(P.deepTwil, P.zenithDay, a/12);
    return P.zenithDay;
  }

  let h = baseHorizon(alt);
  let z = baseZenith(alt);
  const isDay = alt > -6;

  // ── Weather effects ──
  if (code >= 95) {
    const s = mix(P.storm, P.stormGrn, 0.2);
    h = isDay ? mix(h, s, 0.88) : mix(h, s, 0.5);
    z = mix(z, P.storm, isDay ? 0.85 : 0.45);
  } else if ((code>=71&&code<=77)||code===85||code===86) {
    if (isDay) { h = mix(h, P.snowSky, 0.55+cf*0.3); z = mix(z, P.overcast, 0.5+cf*0.3); }
  } else if ((code>=51&&code<=67)||(code>=80&&code<=82)) {
    const str = code>=63||code>=80 ? 0.65 : 0.45;
    if (isDay) { h = mix(h, P.rain, str); z = mix(z, P.heavyRain, str*0.8); }
    else       { h = mix(h, P.rain, 0.3); z = mix(z, P.heavyRain, 0.25); }
  } else if (code===45||code===48) {
    if (isDay) { h = mix(h, P.fog, 0.75); z = mix(z, P.overcast, 0.5); }
    else       { h = mix(h, P.fog, 0.3); }
  } else if (isDay && cf > 0) {
    // Two-tone cloudy gradient: horizon leans to white/grey, zenith stays bluer
    if (cf < 0.3) {
      h = mix(h, P.partCloud, cf*0.25); z = mix(z, P.zenithDay, 1-cf*0.15);
    } else if (cf < 0.7) {
      const t = (cf-0.3)/0.4;
      h = mix(h, mix(P.partCloud, P.overcast, t*0.6), cf*0.5);
      z = mix(z, P.hazyDay, cf*0.35);
    } else {
      h = mix(h, P.overcast, (cf-0.5)*1.5);
      z = mix(z, P.overcast, (cf-0.4)*1.2);
    }
  } else if (!isDay && cf > 0) {
    h = mix(h, {r:28,g:22,b:42}, cf*0.45);
  }

  // ── Moonlight ──
  if (!isDay && moon > 0.1) {
    const moonStr = moon * (alt > -18 ? 0.5 : 0.35) * (1 - cf*0.8);
    const moonCol = moon > 0.8 ? P.fullMoon : P.moonlit;
    h = mix(h, moonCol, moonStr);
    z = mix(z, moonCol, moonStr * 0.7);
  }

  // ── Aurora ──
  if (aurora > 0 && cf < 0.5) {
    const aStr = aurora * (1 - cf*1.5);
    const aCol = mix(P.auroraGrn, P.auroraPnk, 0.25);
    h = mix(h, aCol, aStr * 0.45);
    z = mix(z, P.auroraGrn, aStr * 0.7);
  }

  // ── Light pollution floor ──
  if (lpFloor > 0) {
    h = liftBrightness(h, lpFloor);
    z = liftBrightness(z, lpFloor * 0.6);
  }

  return { horizon: h, zenith: z };
}

function skyDescription(alt, cloud, code, localHour) {
  const cc = cloud||0;
  if (code>=95)             return t('sky.thunderstorm');
  if (code===85||code===86) return t('sky.snow_showers');
  if (code>=71&&code<=77)   return alt>0 ? t('sky.snowing') : t('sky.snow');
  if (code>=80&&code<=82)   return t('sky.rain_showers');
  if (code>=61&&code<=67)   return t('sky.rainy');
  if (code>=51&&code<=55)   return t('sky.drizzle');
  if (code===45||code===48) return t('sky.foggy');
  if (alt<=-18) return t('sky.clear_night');
  if (alt<=-12) return t('sky.astro_twilight');
  if (alt<=-6)  return t('sky.nautical_twilight');
  if (alt<=0)   return cc>60 ? t('sky.cloudy_twilight') : t('sky.twilight');
  if (alt<=10)  return (localHour ?? new Date().getUTCHours()) < 12 ? t('sky.sunrise') : t('sky.sunset');
  if (cc<20)    return t('sky.clear_sky');
  if (cc<50)    return t('sky.partly_cloudy');
  if (cc<80)    return t('sky.mostly_cloudy');
  return t('sky.overcast');
}

// ════════════════════════════════════════════════════════════════════════════
// PLANET SKY GRADIENT
// Day/night cycle based on local solar hour.
// Airless bodies (Moon, Mercury): black zenith at all times, surface colour at horizon.
// Atmospheric bodies: colour-accurate sky for each planet.
// Gas giants: what you'd see inside the cloud deck at "ground level".
// ════════════════════════════════════════════════════════════════════════════
function planetSkyGradient(planetKey, localHour) {
  // Sun elevation in degrees: 0° at hour 6/18, +90° at noon, -90° at midnight
  const altDeg = Math.sin((localHour - 6) / 12 * Math.PI) * 90;

  // Per-planet palettes: night / terminator / day-horizon / day-zenith
  // Gas giant palettes represent the cloud-deck interior (thick atmosphere = horizon IS the sky)
  const PA = {
    moon:    { n:{r:10,g:10,b:14},  tw:{r:95,g:60,b:35},   dH:{r:198,g:183,b:170}, dZ:{r:6,g:6,b:10},    airless:true, twRange:6  },
    mercury: { n:{r:8,g:7,b:9},     tw:{r:130,g:75,b:28},   dH:{r:215,g:175,b:140}, dZ:{r:6,g:6,b:9},     airless:true, twRange:5  },
    venus:   { n:{r:20,g:10,b:5},   tw:{r:80,g:50,b:10},    dH:{r:180,g:120,b:30},  dZ:{r:150,g:100,b:20}, airless:false, twRange:30 },
    earth:   { n:{r:0,g:0,b:10},    tw:{r:255,g:140,b:60},  dH:{r:135,g:180,b:230}, dZ:{r:30,g:90,b:200},  airless:false, twRange:18 },
    mars:    { n:{r:10,g:6,b:4},    tw:{r:60,g:90,b:120},   dH:{r:210,g:160,b:90},  dZ:{r:180,g:130,b:70}, airless:false, twRange:25 },
    // Gas giants — at "ground level" inside the cloud deck, the sky IS the clouds
    jupiter: { n:{r:15,g:10,b:8},   tw:{r:160,g:130,b:80},  dH:{r:220,g:200,b:150}, dZ:{r:240,g:220,b:170},airless:false, twRange:20 },
    saturn:  { n:{r:12,g:10,b:6},   tw:{r:140,g:120,b:70},  dH:{r:210,g:190,b:130}, dZ:{r:225,g:205,b:145},airless:false, twRange:22 },
    uranus:  { n:{r:0,g:15,b:20},   tw:{r:20,g:80,b:90},    dH:{r:80,g:180,b:190},  dZ:{r:50,g:160,b:175}, airless:false, twRange:15 },
    neptune: { n:{r:0,g:5,b:20},    tw:{r:10,g:40,b:100},   dH:{r:30,g:80,b:180},   dZ:{r:20,g:60,b:160},  airless:false, twRange:15 },
  };

  const p = PA[planetKey] || LOCAL_PLANETS[planetKey]?.skyPalette || PA.mars;
  let h, z;

  if (altDeg >= p.twRange) {
    // Full day
    h = p.dH;
    z = p.airless ? p.dZ : mix(p.dH, p.dZ, 0.65);
  } else if (altDeg >= 0) {
    // Golden hour / terminator
    const t = altDeg / p.twRange;
    h = mix(p.tw, p.dH, t);
    z = p.airless ? mix(p.n, p.dZ, t * 0.4) : mix(p.tw, p.dZ, t * 0.55);
  } else if (altDeg >= -p.twRange) {
    // Twilight
    const t = (altDeg + p.twRange) / p.twRange;
    h = mix(p.n, p.tw, t);
    z = p.airless ? mix(p.n, p.n, 0) : mix(p.n, p.tw, t * 0.25);
  } else {
    // Night
    h = p.n;
    z = p.airless ? {r:3,g:3,b:6} : p.n;
  }

  return { horizon: h, zenith: z };
}

function planetSkyDesc(localHour) {
  const h = ((localHour % 24) + 24) % 24;
  if (h < 0.5 || h >= 23.5) return t('sky.midnight');
  if (h < 5.5)  return t('sky.night');
  if (h < 6.5)  return t('sky.sunrise');
  if (h < 11.5) return t('sky.morning');
  if (h < 12.5) return t('sky.noon');
  if (h < 17.5) return t('sky.afternoon');
  if (h < 18.5) return t('sky.sunset');
  return t('sky.night');
}

// ════════════════════════════════════════════════════════════════════════════
// WORK HOURS HELPER
// ════════════════════════════════════════════════════════════════════════════
// Returns 'work' | 'marginal' | 'rest'
function workStatus(tz, workWeekKey, dateOverride) {
  const date = dateOverride || new Date();
  const sched = WORK_SCHEDULES[workWeekKey] || WORK_SCHEDULES['mon-fri'];
  // Get local parts in city's timezone
  const fmt = f => +new Intl.DateTimeFormat('en-US',{timeZone:tz,...f}).format(date);
  const dow   = fmt({weekday:'short'}) ; // won't work this way — use numeric
  // Use toLocaleString trick for numeric weekday
  const dayNum = +(new Intl.DateTimeFormat('en-US',{timeZone:tz,weekday:'long'})
    .format(date) === 'Sunday' ? 0
    : new Intl.DateTimeFormat('en-US',{timeZone:tz,weekday:'long'})
      .format(date) === 'Monday' ? 1
    : ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday']
      .indexOf(new Intl.DateTimeFormat('en-US',{timeZone:tz,weekday:'long'}).format(date)));

  const hourFrac = getLocalHourFrac(tz, date);
  const localHour = hourFrac * 24;

  if (!sched.workDays.includes(dayNum)) return 'rest';
  if (localHour >= sched.workEnd || localHour < sched.workStart) return 'rest';
  if (localHour < sched.workStart + 1 || localHour >= sched.workEnd - 1) return 'marginal';
  return 'work';
}

// Returns fraction 0-1 of day in a given timezone
function getLocalHourFrac(tz, date = new Date()) {
  const parts = new Intl.DateTimeFormat('en-US',{
    timeZone: tz, hour:'2-digit', minute:'2-digit', second:'2-digit', hour12: false
  }).formatToParts(date);
  const get = t => +(parts.find(p=>p.type===t)?.value||0);
  return (get('hour')*3600 + get('minute')*60 + get('second')) / 86400;
}

function getLocalDow(tz, date = new Date()) {
  return ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday']
    .indexOf(new Intl.DateTimeFormat('en-US',{timeZone:tz,weekday:'long'}).format(date));
}

function getLocalHour(tz, date = new Date()) {
  return +new Intl.DateTimeFormat('en-US',{timeZone:tz,hour:'numeric',hour12:false}).format(date);
}

// ════════════════════════════════════════════════════════════════════════════
// API
// ════════════════════════════════════════════════════════════════════════════
async function fetchWeather(lat, lon) {
  const base = STATE.settings.weatherApiUrl;
  if (!base) return null; // disabled when URL is empty
  try {
    const r = await fetch(
      `${base}/forecast?latitude=${lat}&longitude=${lon}` +
      `&current=temperature_2m,weather_code,cloud_cover,precipitation,wind_speed_10m,relative_humidity_2m` +
      `&hourly=temperature_2m,weather_code,cloud_cover,precipitation,precipitation_probability` +
      `&past_days=1&forecast_days=2&timezone=UTC`
    );
    if (!r.ok) { console.error(`Weather API ${r.status} for ${lat},${lon}`); return null; }
    return r.json();
  } catch(e) { console.error('Weather API unreachable:', e.message); return null; }
}

async function geocodeCity(name) {
  try {
    const r = await fetch(
      `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(name)}&count=5&language=en&format=json`
    );
    if (!r.ok) return null;
    const d = await r.json();
    return d.results?.[0] || null;
  } catch(e) { console.error('Geocode error', e); return null; }
}

async function geocodeCityMulti(name) {
  try {
    const r = await fetch(
      `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(name)}&count=8&language=en&format=json`
    );
    if (!r.ok) return [];
    const d = await r.json();
    return d.results || [];
  } catch(e) { console.error('Geocode error', e); return []; }
}

async function reverseGeocode(lat, lon) {
  try {
    const r = await fetch(
      `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lon}&format=json`,
      { headers: {'Accept-Language':'en'} }
    );
    if (!r.ok) return null;
    const d = await r.json();
    const a = d.address;
    return a.city||a.town||a.village||a.county||a.state||null;
  } catch { return null; }
}

function getTZAbbr(tz) {
  return new Intl.DateTimeFormat('en-US',{timeZone:tz,timeZoneName:'short'})
    .formatToParts(new Date()).find(p=>p.type==='timeZoneName')?.value??tz;
}

function getUTCOffsetMin(tz) {
  const d = new Date();
  const utcStr = d.toLocaleString('en-US',{timeZone:'UTC'});
  const tzStr  = d.toLocaleString('en-US',{timeZone:tz});
  return Math.round((new Date(tzStr)-new Date(utcStr))/60000);
}

function _use12h() { return STATE.settings.timeFormat === '12h'; }

function formatLocalTime(tz, date) {
  return new Intl.DateTimeFormat('en-US',{timeZone:tz,hour:'2-digit',minute:'2-digit',hour12:_use12h()}).format(date || getNow());
}

function fmtCityLocalTime(ms, city) {
  const d = new Date(ms);
  if (city.type === 'planet') {
    try {
      const pt = PlanetTime.getPlanetTime(city.planet, d, city.tzOffset || 0);
      const name = city.customName || city.zoneName || city.planet;
      const h12 = _use12h();
      let tStr;
      if (h12) {
        const h = pt.hour % 12 || 12;
        const ampm = pt.hour < 12 ? ' AM' : ' PM';
        tStr = `${String(h).padStart(2,'0')}:${String(pt.minute).padStart(2,'0')}${ampm}`;
      } else {
        tStr = pt.timeString;
      }
      return `${tStr} ${name}`;
    } catch(_) { return ''; }
  }
  const tz = city.tz || city.zoneId || 'UTC';
  const fmt = new Intl.DateTimeFormat('en-US', {
    hour: '2-digit', minute: '2-digit', hour12: _use12h(), timeZone: tz
  }).format(d);
  return `${fmt} ${city.customName || city.city || tz}`;
}

function fmtAllCityTimes(ms) {
  return STATE.cities.map(c => fmtCityLocalTime(ms, c)).filter(Boolean).join(' · ');
}

// ════════════════════════════════════════════════════════════════════════════
// ── Focus trap utility ────────────────────────────────────────────────────────
// Traps keyboard Tab/Shift+Tab within a container while a modal is open.
// Restores focus to the calling element when releaseTrap() is called.
let _trapHandler = null, _trapReturn = null;

function trapFocus(container) {
  releaseTrap();
  _trapReturn = document.activeElement;

  const focusable = () => [
    ...container.querySelectorAll(
      'a[href],button:not([disabled]),input:not([disabled]),select:not([disabled]),textarea:not([disabled]),[tabindex]:not([tabindex="-1"])'
    )
  ].filter(el => el.offsetParent !== null && getComputedStyle(el).display !== 'none');

  _trapHandler = (e) => {
    if (e.key !== 'Tab') return;
    const items = focusable();
    if (!items.length) { e.preventDefault(); return; }
    const first = items[0], last = items[items.length - 1];
    if (e.shiftKey) {
      if (document.activeElement === first) { e.preventDefault(); last.focus(); }
    } else {
      if (document.activeElement === last) { e.preventDefault(); first.focus(); }
    }
  };
  document.addEventListener('keydown', _trapHandler);

  // Move focus into the container
  const items = focusable();
  if (items.length) items[0].focus();
}

function releaseTrap() {
  if (_trapHandler) document.removeEventListener('keydown', _trapHandler);
  _trapHandler = null;
  if (_trapReturn && _trapReturn.focus) { _trapReturn.focus(); }
  _trapReturn = null;
}

function srAnnounce(text) {
  const el = document.getElementById('sr-status');
  if (el) { el.textContent = ''; requestAnimationFrame(() => { el.textContent = text; }); }
}

// STATE
// ════════════════════════════════════════════════════════════════════════════
let STATE = {
  cities: [],          // [{id, type:'earth'|'planet', ...}]
  settings: {
    showTime:true, showTZ:true, showCity:true, showCountry:true,
    showLabel:true, showHourly:true, showWork:true, horiz:false,
    showWeather:true, showSunMoon:true, showPing:true, compact:false,
    reduceMotion: false,
    simpleMode: true,    // 58.8 — simple view hides advanced display toggles
    hdtnApiUrl: 'https://dtn.interplanet.live/',
    llmApiUrl: 'https://slm.interplanet.live/',
    weatherApiUrl: 'https://api.open-meteo.com/v1',
    theme: 'system',
    timeFormat: '24h',   // '24h' | '12h'
    manualOrder: false,  // true after user drags to reorder — disables auto sort
  },
  timeTravelMs: 0,     // ms offset from real time; 0 = live mode
  cookieConsent: null,  // null|true|false
  userLat: null, userLon: null,
  userBody: 'earth',   // IAU body name lowercase: 'earth'|'mars'|'moon'|'transit'|etc.
  userLocation: null,  // Parsed manual location JSON object or null
};
// Expose on window for E2E test access
window.STATE = STATE;
window.LOCAL_PLANETS = LOCAL_PLANETS;

/** Returns a Date for "now" — offset by STATE.timeTravelMs when Time Travel is active. */
function getNow() { return new Date(Date.now() + STATE.timeTravelMs); }
window.getNow = getNow;

// LLM provider registry lives in assets/llm-providers.js (window.LLM_PROVIDERS)
// Kept separate so model lists / endpoints can be updated without touching app logic.

function loadLlmProviderCfg() {
  try { return JSON.parse(localStorage.getItem('llm_provider_cfg') || 'null'); } catch(_) { return null; }
}
function saveLlmProviderCfg(cfg) {
  try {
    if (cfg) localStorage.setItem('llm_provider_cfg', JSON.stringify(cfg));
    else localStorage.removeItem('llm_provider_cfg');
  } catch(_) {}
}

let _idSeq = 1;
const newId = () => _idSeq++;

// ── Cookie helpers ──────────────────────────────────────────────────────────
function getCookie(name) {
  const m = document.cookie.match('(?:^|; )'+name.replace(/([$?*|{}()[\]/+^])/g,'\\$1')+'=([^;]*)');
  return m ? decodeURIComponent(m[1]) : null;
}
function setCookie(name, val, days=365) {
  const exp = new Date(Date.now()+days*86400000).toUTCString();
  document.cookie = `${name}=${encodeURIComponent(val)};expires=${exp};path=/;SameSite=Lax`;
}
function delCookie(name) { document.cookie = name+'=;expires=Thu,01 Jan 1970 00:00:00 UTC;path=/'; }

function saveSettings() {
  try { localStorage.setItem('sky_settings', JSON.stringify(STATE.settings)); } catch(_) {}
}
function saveLocation(lat, lon, label) {
  try { localStorage.setItem('sky_location', JSON.stringify({ lat, lon, label: label || null })); } catch(_) {}
}
function loadLocation() {
  try {
    const raw = localStorage.getItem('sky_location');
    if (!raw) return;
    const { lat, lon, label } = JSON.parse(raw);
    if (typeof lat !== 'number' || typeof lon !== 'number') return;
    STATE.userLat = lat; STATE.userLon = lon;
    const locStatus = document.getElementById('loc-status');
    const reqBtn    = document.getElementById('req-loc-btn');
    if (locStatus) locStatus.innerHTML = `<i class="fa-solid fa-location-dot" aria-hidden="true"></i> ${label ? label + ' · ' : ''}${lat.toFixed(2)}, ${lon.toFixed(2)}`;
    if (reqBtn)    reqBtn.innerHTML    = `<i class="fa-solid fa-location-crosshairs" aria-hidden="true"></i> <span>${t('settings.update_location')}</span>`;
  } catch(_) {}
}
function loadSettings() {
  try {
    const s = localStorage.getItem('sky_settings');
    if (s) Object.assign(STATE.settings, JSON.parse(s));
  } catch(_) {}
}

function saveState() {
  saveSettings();                     // always — no consent needed for UI prefs
  if (!STATE.cookieConsent) return;
  setCookie('sky_cities', JSON.stringify(STATE.cities.map(c => ({
    type:c.type, tz:c.tz, city:c.city, country:c.country, lat:c.lat, lon:c.lon,
    pop:c.pop||0, workWeek:c.workWeek, customName:c.customName, planet:c.planet,
    tzOffset:c.tzOffset||0, zoneId:c.zoneId, zoneName:c.zoneName,
  }))));
  // sky_settings cookie removed — settings now live in localStorage
}

function loadState() {
  // Read consent from cookie with localStorage fallback (file:// protocol doesn't support cookies)
  const cookieVal = getCookie('sky_consent');
  const lsVal = (() => { try { return localStorage.getItem('sky_consent'); } catch(_) { return null; } })();
  const raw = cookieVal !== null ? cookieVal : lsVal;
  STATE.cookieConsent = raw === '1' ? true : raw === '0' ? false : null;

  if (STATE.cookieConsent) {
    try {
      const c = getCookie('sky_cities');
      if (c) JSON.parse(c).forEach(d => addCityFromData(d));
      // One-time migration: sky_settings cookie → localStorage (runs once, then LS takes over)
      const oldSettings = getCookie('sky_settings');
      if (oldSettings && !localStorage.getItem('sky_settings')) {
        try { Object.assign(STATE.settings, JSON.parse(oldSettings)); saveSettings(); } catch(_) {}
      }
    } catch(e) { console.warn('State load failed', e); }
  }
}

// ════════════════════════════════════════════════════════════════════════════
// SERVICE STATUS DASHBOARD (Story 16.3)
// ════════════════════════════════════════════════════════════════════════════

const _svcState = { dtn: null, slm: null };  // null | { ok, latencyMs, warm?, ts }
let _svcStatusTimer = null;

async function _pingEndpoint(url, timeoutMs) {
  const t0 = Date.now();
  try {
    const r = await fetch(url, { method:'HEAD', signal: AbortSignal.timeout(timeoutMs) });
    return { ok: r.ok || r.status < 500, latencyMs: Date.now() - t0 };
  } catch(_) {
    return { ok: false, latencyMs: Date.now() - t0 };
  }
}

async function refreshSvcStatus() {
  const dtnUrl = STATE.settings.hdtnApiUrl;
  const slmUrl = STATE.settings.llmApiUrl;

  const [dtnRes, slmRes] = await Promise.all([
    dtnUrl ? _pingEndpoint(dtnUrl, 6000) : Promise.resolve(null),
    slmUrl ? _pingEndpoint(slmUrl, 10000) : Promise.resolve(null),
  ]);

  if (dtnRes) _svcState.dtn = { ...dtnRes, ts: new Date() };
  if (slmRes) _svcState.slm = { ...slmRes, warm: slmRes.latencyMs < 5000, ts: new Date() };

  renderSvcStatus();
}

function renderSvcStatus() {
  const el = document.getElementById('mp-svc-status');
  if (!el) return;
  const items = [];

  if (_svcState.dtn) {
    const s = _svcState.dtn;
    const cls = s.ok ? 'svc-ok' : 'svc-err';
    const tip = s.ok ? `DTN ${s.latencyMs} ms` : 'DTN unreachable';
    items.push(`<span class="mp-svc-item ${cls}" title="${tip}"><span class="mp-svc-dot" aria-hidden="true"></span>DTN</span>`);
  }
  if (_svcState.slm) {
    const s = _svcState.slm;
    const cls = !s.ok ? 'svc-err' : s.warm ? 'svc-ok' : 'svc-warn';
    const status = !s.ok ? 'offline' : s.warm ? `warm · ${s.latencyMs} ms` : `cold · ${s.latencyMs} ms`;
    const extra  = s.ok && !s.warm ? ' ❄' : '';
    items.push(`<span class="mp-svc-item ${cls}" title="SLM ${status}"><span class="mp-svc-dot" aria-hidden="true"></span>SLM${extra}</span>`);
  }

  if (!items.length) { el.hidden = true; return; }
  el.hidden = false;
  el.innerHTML =
    `<div class="mp-svc-bar" role="status" aria-label="Service status">` +
    items.join('') +
    `<button class="mp-svc-refresh" id="mp-svc-refresh-btn" aria-label="Refresh service status" title="Refresh">` +
    `<i class="fa-solid fa-arrows-rotate" aria-hidden="true"></i></button></div>`;
  document.getElementById('mp-svc-refresh-btn')?.addEventListener('click', refreshSvcStatus);
}

// ════════════════════════════════════════════════════════════════════════════
// HDTN ML FORECAST API
// ════════════════════════════════════════════════════════════════════════════
const _hdtnCache = {};           // { "mars": { ts: Number, predictions: [] } }
const HDTN_TTL_MS = 30 * 60000; // 30-minute TTL

async function fetchHdtnForecast(planet) {
  const url = STATE.settings.hdtnApiUrl;
  if (!url) return null;
  const cached = _hdtnCache[planet];
  if (cached && Date.now() - cached.ts < HDTN_TTL_MS) return cached.predictions;
  try {
    const r = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ body: planet,
        start_iso: new Date().toISOString(), horizon_hours: 168 }),
    });
    if (!r.ok) { console.error(`HDTN API ${r.status} for ${planet}`); return null; }
    const d = await r.json();
    _hdtnCache[planet] = { ts: Date.now(), predictions: d.predictions };
    return d.predictions;
  } catch(e) { console.error('HDTN API unreachable:', e.message); return null; }
}

function updateHdtnDisplay(city, predictions) {
  const el = document.getElementById(`hdtn-${city.id}`);
  if (!el) return;
  const s = STATE.settings;
  if (!s.showPing) { el.style.display = 'none'; return; }
  if (!predictions || predictions.length < 2) { el.style.display = 'none'; return; }

  const nowKa  = predictions[0].ka_blackout_prob;
  const nowOpt = predictions[0].opt_blackout_prob;
  const first  = predictions[0].delay_min;
  const last   = predictions[predictions.length - 1].delay_min;
  const hoursSpan = (predictions.length - 1) * 6;
  const trendSlope = hoursSpan > 0 ? (last - first) / hoursSpan * 168 : 0;
  const arrowIcon = trendSlope > 0.5
    ? '<i class="fa-solid fa-arrow-trend-up" aria-hidden="true"></i>'
    : trendSlope < -0.5
    ? '<i class="fa-solid fa-arrow-trend-down" aria-hidden="true"></i>'
    : '<i class="fa-solid fa-arrow-right" aria-hidden="true"></i>';
  const slopeStr = (trendSlope >= 0 ? '+' : '') + trendSlope.toFixed(1);

  const kaDotClass = nowKa < 0.10 ? 'hdtn-safe' : nowKa < 0.50 ? 'hdtn-warn' : 'hdtn-danger';
  const optDotClass = nowOpt < 0.10 ? 'hdtn-safe' : nowOpt < 0.50 ? 'hdtn-warn' : 'hdtn-danger';

  // Story 9.2 — find optimal low-risk scheduling window in next 168h (ML forecast)
  const bestSlot = predictions.reduce((best, p, i) => {
    const risk = (p.ka_blackout_prob + p.opt_blackout_prob) / 2;
    return (!best || risk < best.risk) ? { risk, slot: p, index: i } : best;
  }, null);
  let bestTimeStr = '';
  if (bestSlot && bestSlot.slot.utc) {
    const bDate = new Date(bestSlot.slot.utc);
    const pad = n => String(n).padStart(2,'0');
    bestTimeStr = ` &nbsp;<span class="hdtn-best-slot" title="ML-optimal scheduling window (lowest Ka+Opt risk)">` +
      `<i class="fa-solid fa-chart-line" aria-hidden="true"></i> Best: ` +
      `${bDate.getUTCMonth()+1}/${bDate.getUTCDate()} ${pad(bDate.getUTCHours())}:${pad(bDate.getUTCMinutes())} UTC` +
      `</span>`;
  }

  el.innerHTML =
    `${arrowIcon} ${slopeStr} min/wk &nbsp;` +
    `<span class="${kaDotClass}">● Ka: ${Math.round(nowKa * 100)}%</span> &nbsp;` +
    `<span class="${optDotClass}">● Opt: ${Math.round(nowOpt * 100)}%</span>` +
    bestTimeStr;
  el.style.display = '';
}

async function refreshAllHdtn() {
  if (!STATE.settings.hdtnApiUrl) return;
  for (const city of STATE.cities) {
    if (city.type !== 'planet') continue;
    const p = await fetchHdtnForecast(city.planet);
    if (p) updateHdtnDisplay(city, p);
  }
}

// ════════════════════════════════════════════════════════════════════════════
// CITY MANAGEMENT
// ════════════════════════════════════════════════════════════════════════════
function addCityFromData(d) {
  const id = newId();
  const city = { id, ...d, weather: null, hourly: null, refreshTimer: null };
  STATE.cities.push(city);
  renderCity(city);
  sortCities();
  fetchAndUpdateCity(city);
}

function addEarthCity(dbEntry, opts = {}) {
  const id = newId();
  const city = {
    id, type:'earth',
    tz: dbEntry.tz,
    city: dbEntry.city, country: dbEntry.country,
    lat: dbEntry.lat, lon: dbEntry.lon,
    pop: dbEntry.pop||0,
    workWeek: dbEntry.workWeek||'mon-fri',
    customName: dbEntry.customName||null,
    weather: null, hourly: null,
  };
  STATE.cities.push(city);
  renderCity(city);
  sortCities();
  saveState(); syncHash();
  if (!opts.silent) showToast(t('toast.city_added', { name: city.customName || city.city }));
  fetchAndUpdateCity(city);
  updatePlaceholder();
  updateManageBtn();
  if (typeof updateMyLocButton === 'function') updateMyLocButton();
  return city;
}

function addPlanet(planetKey, tzOffsetHours = 0, zoneId = null, zoneName = null, opts = {}) {
  const P = PlanetTime.PLANETS[planetKey] || LOCAL_PLANETS[planetKey];
  if (!P) return;
  const id = newId();
  const city = {
    id, type:'planet', planet: planetKey,
    city: P.name, country: 'Solar System',
    tz: null, lat: 0, lon: 0, pop: 0, workWeek: null,
    tzOffset: tzOffsetHours, zoneId, zoneName,
    customName: null, weather: null, hourly: null,
  };
  STATE.cities.push(city);
  renderCity(city);
  saveState(); syncHash();
  if (!opts.silent) showToast(t('toast.city_added', { name: P.name || planetKey }));
  updatePlaceholder();
  updateManageBtn();
  startPlanetClock(city);
  refreshAllHdtn();
}

function removeCity(id) {
  const idx = STATE.cities.findIndex(c => c.id === id);
  if (idx < 0) return;
  const city = STATE.cities[idx];
  if (city.refreshTimer) clearInterval(city.refreshTimer);
  STATE.cities.splice(idx, 1);
  const el = document.getElementById(`city-${id}`);
  if (el) el.remove();
  saveState(); syncHash();
  updatePlaceholder();
  updateManageBtn();
  if (typeof updateMyLocButton === 'function') updateMyLocButton();
}

function updateManageBtn() {
  const btn = document.getElementById('manage-btn');
  if (!btn) return;
  btn.classList.toggle('visible', STATE.cities.length > 0);
  // Keep more-menu Manage item in sync
  const mmManage = document.getElementById('mm-manage');
  if (mmManage) mmManage.classList.toggle('visible', STATE.cities.length > 0);
}

function toggleManageMode() {
  const wrap = document.getElementById('cities-wrap');
  const bar  = document.getElementById('manage-bar');
  const btn  = document.getElementById('manage-btn');
  const on   = !wrap.classList.contains('manage-mode');
  wrap.classList.toggle('manage-mode', on);
  bar.classList.toggle('on', on);
  if (btn) { btn.classList.toggle('active', on); btn.setAttribute('aria-pressed', on); }
  if (on) _dragInit(); else _dragTeardown();
}

function exitManageMode() {
  const wrap = document.getElementById('cities-wrap');
  const bar  = document.getElementById('manage-bar');
  const btn  = document.getElementById('manage-btn');
  wrap.classList.remove('manage-mode');
  bar.classList.remove('on');
  if (btn) { btn.classList.remove('active'); btn.setAttribute('aria-pressed', 'false'); }
  _dragTeardown();
}

function clearAllCities() {
  STATE.cities.forEach(c => { if (c.refreshTimer) clearInterval(c.refreshTimer); });
  STATE.cities = [];
  document.querySelectorAll('.city-col').forEach(el => el.remove());
  saveState(); syncHash();
  updatePlaceholder();
  exitManageMode();
  updateManageBtn();
  if (typeof updateMyLocButton === 'function') updateMyLocButton();
}

function sortCities() {
  // If user has manually reordered, preserve their order (just sync DOM)
  if (STATE.settings.manualOrder) {
    const wrap = document.getElementById('cities-wrap');
    const addBtn = document.getElementById('add-col');
    STATE.cities.forEach(c => {
      const el = document.getElementById(`city-${c.id}`);
      if (el) wrap.insertBefore(el, addBtn);
    });
    return;
  }
  // Sort by UTC offset ascending (west → east), planets go last
  const wrap = document.getElementById('cities-wrap');
  const addBtn = document.getElementById('add-col');
  STATE.cities.sort((a, b) => {
    if (a.type==='planet' && b.type!=='planet') return 1;
    if (b.type==='planet' && a.type!=='planet') return -1;
    if (a.type==='planet' && b.type==='planet') return 0;
    return getUTCOffsetMin(a.tz) - getUTCOffsetMin(b.tz);
  });
  STATE.cities.forEach(c => {
    const el = document.getElementById(`city-${c.id}`);
    if (el) wrap.insertBefore(el, addBtn);
  });
}

// ════════════════════════════════════════════════════════════════════════════
// RENDER A CITY COLUMN
// ════════════════════════════════════════════════════════════════════════════
function renderCity(city) {
  const wrap = document.getElementById('cities-wrap');
  const addBtn = document.getElementById('add-col');

  const col = document.createElement('div');
  col.className = city.type === 'earth' ? 'city-col weather-loading' : 'city-col';
  col.id = `city-${city.id}`;
  col.tabIndex = 0;
  col.setAttribute('role', 'region');
  col.setAttribute('aria-label', 'Loading…');

  const P = city.type === 'planet' ? (PlanetTime.PLANETS[city.planet] || LOCAL_PLANETS[city.planet]) : null;
  col.innerHTML = `
    <div class="city-sky" id="sky-${city.id}">
      <div class="city-time-block" id="tb-${city.id}">
        <div class="city-time-row">
          <span class="city-time" id="time-${city.id}">--:--</span>
          <span class="city-dow"  id="dow-${city.id}"></span>
        </div>
      </div>
      <div class="sky-label" id="slabel-${city.id}"></div>
    </div>
    <div class="city-info" id="info-${city.id}">
      <div class="city-tz" id="tz-${city.id}"></div>
      <div class="city-name-wrap">
        ${city.type==='planet'
          ? `<span class="planet-badge" id="badge-${city.id}">${P.symbol} ${P.name}</span>`
          : `<input class="city-name-input" id="name-${city.id}" value="${(city.customName||city.city).replace(/"/g,'&quot;')}" aria-label="${(city.customName||city.city).replace(/"/g,'&quot;')} — type to search a different location" title="Type to search a different location">`
        }
        <span class="city-country" id="cty-${city.id}">${city.country}</span>
      </div>
      ${city.type==='planet' && city.zoneId ? `<div class="planet-zone" id="zone-${city.id}">${city.zoneId} · ${city.zoneName||''}</div>` : ''}
      ${city.type==='planet' ? `<div class="city-sky-desc" id="pdesc-${city.id}"></div>` : ''}
      <div class="holiday-badge" id="holiday-${city.id}" style="display:none"></div>
      ${city.type!=='planet' ? `<div class="work-indicator" id="work-${city.id}"><div class="work-dot rest"></div><span>${t('city.loading')}</span></div>` : ''}
      ${city.type!=='planet' ? `<div class="city-weather" id="wx-${city.id}" style="display:none"></div>` : ''}
      <div class="city-sun"  id="sun-${city.id}"  style="display:none"></div>
      ${city.type!=='planet' ? `<div class="city-moon" id="moon-${city.id}" style="display:none"></div>` : ''}
      <div class="city-temp-est" id="temp-${city.id}" style="display:none"></div>
      <div class="city-ping" id="ping-${city.id}" style="display:none"></div>
      ${city.type==='planet' ? `<div class="los-warn" id="los-${city.id}" style="display:none"></div>` : ''}
      ${city.type==='planet' ? `<div class="hdtn-forecast" id="hdtn-${city.id}" style="display:none" aria-live="polite"></div>` : ''}
    </div>
    <div class="hourly-wrap" id="hw-${city.id}">
      <div class="hourly-bar" id="hbar-${city.id}"></div>
      <div class="hourly-labels" id="hlbl-${city.id}"></div>
    </div>
    <div class="city-confirm" id="confirm-${city.id}"></div>
    <div class="city-a11y-details" id="a11y-${city.id}" tabindex="-1"></div>
    <button class="remove-btn" aria-label="${t('city.remove_aria',{name:(city.customName||city.city||city.planet||'location')}).replace(/"/g,'&quot;')}" onclick="removeCity(${city.id})"><i class="fa-solid fa-xmark" aria-hidden="true"></i></button>
    <div class="drag-handle" aria-hidden="true" title="Drag to reorder"><i class="fa-solid fa-grip-vertical"></i></div>
  `;

  wrap.insertBefore(col, addBtn);

  // City name edit (Earth only)
  if (city.type === 'earth') {
    const inp = document.getElementById(`name-${city.id}`);
    let debounce;
    inp.addEventListener('input', () => {
      clearTimeout(debounce);
      debounce = setTimeout(() => relocateCity(city, inp.value), 900);
    });
  }

  applySettings();
}

async function relocateCity(city, nameText) {
  nameText = nameText.trim();
  if (!nameText) return;

  // Close any pending confirmation from a previous search
  closeCityConfirm(city.id);

  // Search CITY_DB directly (exact + starts-with, case-insensitive)
  const query = nameText.toLowerCase();
  const dbMatches = CITY_DB.filter(c =>
    c.city.toLowerCase() === query || c.city.toLowerCase().startsWith(query)
  ).slice(0, 6);

  // Geocode for rich results including admin1 (state/region)
  const geoResults = await geocodeCityMulti(nameText);

  // Stale guard: if the user kept typing while we were waiting, discard
  const inp = document.getElementById(`name-${city.id}`);
  if (inp && inp.value.trim() !== nameText) return;

  // Build a unified, deduplicated candidate list (keyed by timezone)
  const seen = new Set();
  const candidates = [];

  // Geocode results first (they carry admin1 for richer labels)
  geoResults.forEach(r => {
    const tz = r.timezone || '';
    if (!tz || seen.has(tz)) return;
    seen.add(tz);
    const dbEntry = CITY_DB.find(c => c.tz === tz);
    candidates.push({
      name:     r.name,
      admin1:   r.admin1 || '',
      country:  r.country || '',
      tz,
      lat:      r.latitude,
      lon:      r.longitude,
      pop:      r.population || (dbEntry ? dbEntry.pop : 0),
      workWeek: dbEntry ? dbEntry.workWeek : 'mon-fri',
    });
  });

  // Fill in any CITY_DB matches not yet covered by geocode
  dbMatches.forEach(c => {
    if (!seen.has(c.tz)) {
      seen.add(c.tz);
      candidates.push({
        name: c.city, admin1: '', country: c.country,
        tz: c.tz, lat: c.lat, lon: c.lon,
        pop: c.pop, workWeek: c.workWeek,
      });
    }
  });

  if (candidates.length === 0) {
    // No results — treat as a label-only rename, keep current coords
    city.customName = nameText;
    showToast(t('toast.label_no_match', { text: nameText }));
    await fetchAndUpdateCity(city);
    saveState();
    return;
  }

  const diffTz = candidates.filter(c => c.tz !== city.tz);
  if (diffTz.length === 0) {
    // All candidates share the current timezone — silent update
    city.customName = nameText;
    city.lat = candidates[0].lat;
    city.lon = candidates[0].lon;
    showToast(t('toast.label_updated', { name: candidates[0].name, country: candidates[0].country }));
    await fetchAndUpdateCity(city);
    saveState();
    return;
  }

  // One or more candidates are in a different timezone — ask the user
  showCityConfirm(city, nameText, candidates);
}

function showCityConfirm(city, nameText, candidates) {
  const panel = document.getElementById(`confirm-${city.id}`);
  if (!panel) return;
  const inp = document.getElementById(`name-${city.id}`);

  const diffTz = candidates.filter(c => c.tz !== city.tz);
  const sameTz = candidates.filter(c => c.tz === city.tz);

  const fmtOffset = tz => {
    try {
      const off = getUTCOffsetMin(tz);
      const sign = off >= 0 ? '+' : '';
      const h = Math.floor(Math.abs(off)/60), m = Math.abs(off)%60;
      return `UTC${sign}${h}${m ? ':'+String(m).padStart(2,'0') : ''}`;
    } catch(e) { return 'UTC?'; }
  };
  const fmtAbbr = tz => { try { return getTZAbbr(tz); } catch(e) { return ''; } };
  const fmtLoc  = c => [c.admin1, c.country].filter(Boolean).join(', ');

  let html = `<div class="cc-title">`;
  html += diffTz.length === 1
    ? t('city.confirm_title_single', {name: nameText})
    : t('city.confirm_title_multi', {name: nameText});
  html += `</div>`;

  diffTz.forEach((c, i) => {
    const loc = fmtLoc(c);
    const abbr = fmtAbbr(c.tz);
    const utc  = fmtOffset(c.tz);
    html += `<div class="cc-candidate">
      <div class="cc-cand-info">
        <div class="cc-cand-name">${c.name}${loc ? ', ' + loc : ''}</div>
        <div class="cc-cand-tz">${abbr ? abbr + '  ' : ''}${utc}</div>
      </div>
      <button class="cc-btn cc-btn-change" data-idx="${i}">${t('city.confirm_change')}</button>
    </div>`;
  });

  html += `<div class="cc-actions">`;
  if (sameTz.length > 0) {
    const renameTitle = t('city.confirm_rename_with_tz',{abbr:fmtAbbr(city.tz),utc:fmtOffset(city.tz),name:nameText});
    html += `<button class="cc-btn cc-btn-rename" title="${renameTitle}">${t('city.confirm_rename')}</button>`;
  } else {
    html += `<button class="cc-btn cc-btn-rename">${t('city.confirm_rename_only')}</button>`;
  }
  html += `<button class="cc-btn cc-btn-cancel">${t('city.confirm_cancel')}</button></div>`;

  panel.innerHTML = html;
  panel.classList.add('on');

  // "Change timezone" buttons
  panel.querySelectorAll('.cc-btn-change').forEach(btn => {
    btn.addEventListener('click', async () => {
      const cand = diffTz[+btn.dataset.idx];
      city.customName = nameText;
      city.city       = cand.name;
      city.country    = cand.country;
      city.tz         = cand.tz;
      city.lat        = cand.lat;
      city.lon        = cand.lon;
      city.workWeek   = cand.workWeek;
      closeCityConfirm(city.id);
      if (inp) inp.value = nameText;
      showToast(t('toast.label_updated', { name: cand.name, country: cand.country }));
      await fetchAndUpdateCity(city);
      saveState();
      sortCities();
    });
  });

  // "Rename only" button — keep timezone, update label + use same-tz coords if available
  panel.querySelector('.cc-btn-rename').addEventListener('click', async () => {
    city.customName = nameText;
    if (sameTz.length > 0) { city.lat = sameTz[0].lat; city.lon = sameTz[0].lon; }
    closeCityConfirm(city.id);
    if (inp) inp.value = nameText;
    showToast(t('toast.label_updated', { name: nameText, country: city.country }));
    await fetchAndUpdateCity(city);
    saveState();
  });

  // "Cancel" button — revert the input
  panel.querySelector('.cc-btn-cancel').addEventListener('click', () => {
    closeCityConfirm(city.id);
    if (inp) inp.value = city.customName || city.city;
  });
}

function closeCityConfirm(cityId) {
  const panel = document.getElementById(`confirm-${cityId}`);
  if (panel) { panel.classList.remove('on'); panel.innerHTML = ''; }
}

// ════════════════════════════════════════════════════════════════════════════
// UTC PLACEHOLDER — shown when no cities are on screen
// Uses London sky colours but no city name / weather / info.
// ════════════════════════════════════════════════════════════════════════════
function updatePlaceholder() {
  const ph = document.getElementById('utc-placeholder');
  if (!ph) return;
  const hasCities = STATE.cities.length > 0;
  ph.classList.toggle('hidden', hasCities);
  if (hasCities) return;
  const now = getNow();
  // UTC clock
  const timeEl = document.getElementById('ph-utc-time');
  const dowEl  = document.getElementById('ph-utc-dow');
  if (timeEl) timeEl.textContent =
    `${String(now.getUTCHours()).padStart(2,'0')}:${String(now.getUTCMinutes()).padStart(2,'0')}`;
  if (dowEl) dowEl.textContent =
    new Intl.DateTimeFormat('en-US', {timeZone:'UTC', weekday:'short'}).format(now);
  // London sky gradient — lat 51.51, lon −0.13, no weather overlay (code 1 = mainly clear)
  const alt = sunAlt(51.51, -0.13, now);
  const { horizon, zenith } = skyGradient(alt, 20, 1, 51.51, 9e6, now);
  ph.style.background = `linear-gradient(to bottom, ${hex3(zenith)} 0%, ${hex3(horizon)} 100%)`;
}

// ════════════════════════════════════════════════════════════════════════════
// UPDATE CITY DISPLAY
// ════════════════════════════════════════════════════════════════════════════
function updateCityDisplay(city) {
  const now = getNow();
  const s = STATE.settings;

  if (city.type === 'planet') {
    updatePlanetDisplay(city, now);
    return;
  }

  // ── Earth city ──
  const alt = sunAlt(city.lat, city.lon, now);
  const wx  = city.weather;
  const cloud = wx?.cloud_cover ?? 50;
  const code  = wx?.weather_code ?? 1;
  const temp  = wx?.temperature_2m;
  const wind  = wx?.wind_speed_10m;

  const { horizon, zenith } = skyGradient(alt, cloud, code, city.lat, city.pop, now);
  const localHour = parseInt(new Intl.DateTimeFormat('en-US',{timeZone:city.tz,hour:'2-digit',hour12:false}).format(now));
  const desc = skyDescription(alt, cloud, code, localHour);
  const isLight = lum(horizon) > 0.42;
  // Text colour: strongly contrasting against horizon colour
  const textCol = isLight ? 'rgba(0,0,0,0.88)' : 'rgba(255,255,255,0.95)';
  // 58.11 — 3-way panel overlay based on solar altitude
  let panelOverlay;
  if (isLight) {
    panelOverlay = alt > 30 ? 'rgba(255,200,100,0.04)' : 'rgba(255,255,255,0.18)';
  } else {
    panelOverlay = alt < -6 ? 'rgba(0,0,40,0.15)' : 'rgba(50,20,60,0.12)';
  }

  const colEl   = document.getElementById(`city-${city.id}`);
  const skyEl   = document.getElementById(`sky-${city.id}`);
  const infoEl  = document.getElementById(`info-${city.id}`);
  const slabel  = document.getElementById(`slabel-${city.id}`);
  const timeEl  = document.getElementById(`time-${city.id}`);
  const tzEl    = document.getElementById(`tz-${city.id}`);
  const workEl  = document.getElementById(`work-${city.id}`);

  if (!skyEl) return;

  // Column background = horizon colour (fills info-panel area below sky)
  const gradStr = `linear-gradient(to bottom, ${hex3(zenith)} 0%, ${hex3(horizon)} 100%)`;
  if (colEl) colEl.style.background = hex3(horizon);
  skyEl.style.background  = gradStr;
  infoEl.style.background = panelOverlay; // subtle overlay over the horizon colour
  infoEl.style.color      = textCol;
  infoEl.style.borderTop  = `1px solid ${isLight ? 'rgba(0,0,0,0.1)' : 'rgba(255,255,255,0.1)'}`;

  if (slabel) { slabel.textContent = s.showLabel ? desc : ''; }
  const tbEl = document.getElementById(`tb-${city.id}`);
  if (tbEl) tbEl.style.display = s.showTime ? '' : 'none';
  if (timeEl) { timeEl.textContent = s.showTime ? formatLocalTime(city.tz) : ''; }

  // Day of week
  const dowEl = document.getElementById(`dow-${city.id}`);
  if (dowEl) {
    const locale = window.I18N ? window.I18N.getLocale() : 'en-US';
    const weekday = new Intl.DateTimeFormat(locale,{timeZone:city.tz,weekday:'short'}).format(now);
    dowEl.textContent = s.showTime ? weekday : '';
  }

  if (tzEl)   {
    const abbr = getTZAbbr(city.tz);
    const offsetMin = getUTCOffsetMin(city.tz);
    const sign = offsetMin >= 0 ? '+' : '-';
    const h = Math.floor(Math.abs(offsetMin)/60), m = Math.abs(offsetMin)%60;
    const utcStr = `UTC${sign}${h}${m?':'+String(m).padStart(2,'0'):''}`;
    const hasNamedAbbr = abbr && !/^(GMT|UTC)[+-]/.test(abbr);
    tzEl.textContent = s.showTZ ? (hasNamedAbbr ? `${abbr}  ${utcStr}` : utcStr) : '';
    tzEl.style.display = s.showTZ ? '' : 'none';
  }

  // Work indicator
  if (workEl && s.showWork) {
    const ws = workStatus(city.tz, city.workWeek);
    const dotClass = ws === 'work' ? 'work' : ws === 'marginal' ? 'marginal' : 'rest';
    const dotColor = ws === 'work' ? '#4caf50' : ws === 'marginal' ? '#ff9800' : '#f44336';
    const label = ws === 'work' ? t('work.status_work') : ws === 'marginal' ? t('work.status_marginal') : t('work.status_rest');
    workEl.innerHTML = `<div class="work-dot ${dotClass}" style="background:${dotColor}"></div><span>${label}</span>`;
    workEl.style.display = '';
  } else if (workEl) {
    workEl.style.display = 'none';
  }

  // Holiday badge
  const holidayEl = document.getElementById(`holiday-${city.id}`);
  if (holidayEl) {
    const h = getTodayHoliday(city.country, city.tz, now);
    if (h) { holidayEl.innerHTML = `${svgCalendar(10)} ${h}`; holidayEl.style.display = ''; }
    else    { holidayEl.style.display = 'none'; }
  }

  // Weather details
  const wxEl = document.getElementById(`wx-${city.id}`);
  if (wxEl) {
    if (s.showWeather && wx) {
      const t = wx.temperature_2m != null ? `${Math.round(wx.temperature_2m)}°C` : '';
      const hu = wx.relative_humidity_2m != null ? `${Math.round(wx.relative_humidity_2m)}%` : '';

      // Rain probability from current hour index
      let rainPct = '';
      if (city.hourly?.precipProb) {
        const nowIdx = city.hourly.times.findIndex((t2, i) => {
          const ms = new Date(t2 + 'Z').getTime();
          return ms <= now.getTime() && (i === city.hourly.times.length-1 || new Date(city.hourly.times[i+1] + 'Z').getTime() > now.getTime());
        });
        if (nowIdx >= 0) rainPct = `☂${city.hourly.precipProb[nowIdx] ?? '—'}%`;
      }

      const wmoDesc = (window.I18N ? window.I18N.tWmo(code) : null) || WMO[code] || desc;
      wxEl.innerHTML =
        `<span class="wx-chip">${wmoDesc}</span>` +
        (t  ? `<span class="wx-chip">${svgTherm(10)} ${t}</span>` : '') +
        (hu ? `<span class="wx-chip">${svgDrop(10)} ${hu}</span>` : '') +
        (rainPct ? `<span class="wx-chip">${svgRain(10)} ${rainPct.replace('☂','').trim()}</span>` : '');
      wxEl.style.display = '';
    } else { wxEl.style.display = 'none'; }
  }

  // Sunrise/Sunset
  const sunEl = document.getElementById(`sun-${city.id}`);
  if (sunEl) {
    if (s.showSunMoon) {
      const sr = getSunriseSunset(city.lat, city.lon, now);
      const fmtTime = d => d ? new Intl.DateTimeFormat('en-US',{timeZone:city.tz,hour:'2-digit',minute:'2-digit',hour12:_use12h()}).format(d) : '—';
      sunEl.innerHTML =
        `<span class="wx-chip">${svgSunrise(10)} ${fmtTime(sr.rise)}</span>` +
        `<span class="wx-chip">${svgSunset(10)} ${fmtTime(sr.set)}</span>`;
      sunEl.style.display = '';
    } else { sunEl.style.display = 'none'; }
  }

  // Moon phase
  const moonEl = document.getElementById(`moon-${city.id}`);
  if (moonEl) {
    if (s.showSunMoon) {
      const phase = moonPhase(now);
      const illum = moonIllum(phase);
      moonEl.innerHTML =
        `<span class="wx-chip">${svgMoonIco(10)} ${moonEmoji(phase)} ${Math.round(illum*100)}%</span>`;
      moonEl.style.display = '';
    } else { moonEl.style.display = 'none'; }
  }

  // Temperature estimate (Earth city — complement to weather temp)
  const tempEstEl = document.getElementById(`temp-${city.id}`);
  if (tempEstEl) tempEstEl.style.display = 'none'; // Earth gets real temp from weather

  // Round-trip propagation delay to this city — only shown when browser location is shared
  const pingEl = document.getElementById(`ping-${city.id}`);
  if (pingEl) {
    if (s.showPing && STATE.userLat !== null) {
      const distKm = haversineKm(city.lat, city.lon, STATE.userLat, STATE.userLon);
      const ltSec = distKm / C_KMS;
      pingEl.innerHTML = `<i class="fa-solid fa-bolt" aria-hidden="true"></i> ${formatPingSec(ltSec)} one-way from your location`;
      pingEl.style.display = '';
    } else { pingEl.style.display = 'none'; }
  }

  // Show/hide elements
  const nameInp = document.getElementById(`name-${city.id}`);
  const ctyEl   = document.getElementById(`cty-${city.id}`);
  if (nameInp) nameInp.style.display = s.showCity  ? '' : 'none';
  if (ctyEl)   ctyEl.style.display   = s.showCountry ? '' : 'none';

  // Hourly bar
  const hwEl = document.getElementById(`hw-${city.id}`);
  if (hwEl) hwEl.style.display = s.showHourly ? '' : 'none';

  if (s.showHourly && city.hourly) renderHourlyBar(city);

  // ── Accessibility: aria-label (summary) + a11y details div (expanded) ──
  if (colEl) {
    const timeStr = formatLocalTime(city.tz);
    const locale = window.I18N ? window.I18N.getLocale() : 'en';
    const weekday = new Intl.DateTimeFormat(locale,{timeZone:city.tz,weekday:'long'}).format(now);
    colEl.setAttribute('aria-label',
      `${city.customName||city.city}, ${city.country}. ${weekday}, ${timeStr}. Sky: ${desc}.`);
    city._skyDesc = desc; // cache for live tick updates
  }
  const a11yEl = document.getElementById(`a11y-${city.id}`);
  if (a11yEl) {
    const parts = [];
    const ws = workStatus(city.tz, city.workWeek);
    parts.push(ws === 'work' ? 'Work hours.' : ws === 'marginal' ? 'Marginal hours.' : 'Outside work hours.');
    if (wx) {
      if (wx.temperature_2m != null) parts.push(`Temperature: ${Math.round(wx.temperature_2m)} degrees Celsius.`);
      if (wx.relative_humidity_2m != null) parts.push(`Humidity: ${Math.round(wx.relative_humidity_2m)} percent.`);
    }
    const todayH = getTodayHoliday(city.country, city.tz, now);
    if (todayH) parts.push(`Public holiday: ${todayH}.`);
    const sr = getSunriseSunset(city.lat, city.lon, now);
    const fmtT = d => d ? new Intl.DateTimeFormat('en-US',{timeZone:city.tz,hour:'2-digit',minute:'2-digit',hour12:_use12h()}).format(d) : null;
    if (sr.rise) parts.push(`Sunrise: ${fmtT(sr.rise)}.`);
    if (sr.set) parts.push(`Sunset: ${fmtT(sr.set)}.`);
    if (s.showPing && STATE.userLat !== null) {
      const distKm = haversineKm(city.lat, city.lon, STATE.userLat, STATE.userLon);
      const rtSec = distKm / C_KMS * 2;
      parts.push(`Round-trip signal delay from your location: ${formatPingSec(rtSec)}.`);
    }
    a11yEl.textContent = parts.join(' ');
  }
}

function updatePlanetDisplay(city, now) {
  const P = PlanetTime.PLANETS[city.planet] || LOCAL_PLANETS[city.planet];
  if (!P) return;
  const isLocal = !PlanetTime.PLANETS[city.planet]; // true for moon, pluto, etc.
  const isMoon  = city.planet === 'moon';           // Moon-specific display
  const tzOff = city.tzOffset || 0;
  // getPlanetTime maps 'moon' → 'earth' internally; use earth for local bodies
  const ptKey = isLocal ? 'earth' : city.planet;
  const pt = PlanetTime.getPlanetTime(ptKey, now, tzOff);
  const s = STATE.settings;

  // Sky gradient based on local solar time
  const { horizon, zenith } = planetSkyGradient(city.planet, pt.localHour);
  const gradStr = `linear-gradient(to bottom, ${hex3(zenith)} 0%, ${hex3(horizon)} 100%)`;

  const colEl  = document.getElementById(`city-${city.id}`);
  const skyEl  = document.getElementById(`sky-${city.id}`);
  const infoEl = document.getElementById(`info-${city.id}`);
  const slabelEl = document.getElementById(`slabel-${city.id}`);
  const timeEl = document.getElementById(`time-${city.id}`);
  const dowEl  = document.getElementById(`dow-${city.id}`);
  const tzEl   = document.getElementById(`tz-${city.id}`);
  const pdesc  = document.getElementById(`pdesc-${city.id}`);
  const pingEl = document.getElementById(`ping-${city.id}`);
  const losEl  = document.getElementById(`los-${city.id}`);
  const tempEl = document.getElementById(`temp-${city.id}`);
  const sunEl  = document.getElementById(`sun-${city.id}`);
  const holidayEl = document.getElementById(`holiday-${city.id}`);

  if (!skyEl) return;

  const isLight = lum(horizon) > 0.42;
  const textCol = isLight ? 'rgba(0,0,0,0.85)' : 'rgba(255,255,255,0.95)';
  // 58.11 — 3-way panel overlay using solar hour angle as proxy for alt
  const hourAngle = pt.localHour - 12; // -12..+12; 0 = noon
  let panelOverlay;
  if (isLight) {
    panelOverlay = Math.abs(hourAngle) < 3 ? 'rgba(255,200,100,0.04)' : 'rgba(255,255,255,0.18)';
  } else {
    panelOverlay = Math.abs(hourAngle) > 8 ? 'rgba(0,0,40,0.15)' : 'rgba(50,20,60,0.12)';
  }

  // Column background = horizon colour (fills info area below sky)
  if (colEl) colEl.style.background = hex3(horizon);
  skyEl.style.background  = gradStr;
  infoEl.style.background = panelOverlay;
  infoEl.style.color      = textCol;
  infoEl.style.borderTop  = `1px solid ${isLight ? 'rgba(0,0,0,0.1)' : 'rgba(255,255,255,0.1)'}`;

  // Sky description label in the sky area
  if (slabelEl && s.showLabel) slabelEl.textContent = planetSkyDesc(pt.localHour);

  const tbElP = document.getElementById(`tb-${city.id}`);
  if (tbElP) tbElP.style.display = s.showTime ? '' : 'none';
  if (timeEl && s.showTime) {
    if (_use12h()) {
      const h = pt.hour % 12 || 12;
      const ampm = pt.hour < 12 ? ' AM' : ' PM';
      timeEl.textContent = `${String(h).padStart(2,'0')}:${String(pt.minute).padStart(2,'0')}${ampm}`;
    } else {
      timeEl.textContent = pt.timeString;
    }
  }
  if (dowEl) dowEl.textContent = s.showTime ? pt.dowShort : '';

  if (tzEl && s.showTZ) {
    let yearLabel;
    if (isLocal && P.orbitalPeriodYears && P.solarDayMs && P.perihelionEpoch) {
      // Local body with orbital data (e.g. Pluto) — show year + sol
      const si = _localBodySolInfo(P, now.getTime());
      yearLabel = `Year ${si.yearNumber}  Sol ${si.solInYear}`;
    } else if (isMoon) {
      yearLabel = t('planet.tidally_locked');
    } else if (pt.planet === 'Mars' && pt.solInfo) {
      yearLabel = `Year ${pt.yearNumber}  Sol ${pt.solInfo.solInYear}`;
    } else {
      yearLabel = `Year ${pt.yearNumber}  Day ${pt.dayInYear}`;
    }
    tzEl.textContent = yearLabel;
    tzEl.style.display = '';
  }

  if (pdesc) {
    if (isMoon) {
      const phase = moonPhase(now);
      pdesc.textContent = `${moonEmoji(phase)} ${Math.round(moonIllum(phase)*100)}% illuminated`;
    } else {
      const workLabel = pt.isWorkHour ? t('work.planet_work') : pt.isWorkPeriod ? t('work.planet_offshift') : t('work.planet_rest');
      pdesc.textContent = workLabel;
    }
  }

  // Temperature estimate
  if (tempEl) {
    const t = estimatePlanetTemp(city.planet, now);
    const tStr = t.dynamic
      ? `${svgTherm(10)} ~${t.current}°C (mean ${t.mean}°C)`
      : `${svgTherm(10)} ~${t.mean}°C (cloud tops / surface)`;
    tempEl.innerHTML = tStr;
    tempEl.style.display = '';
  }

  // Planet sunrise / sunset (simplified: rise at 06:00 local, set at 18:00 local)
  if (sunEl) {
    if (s.showSunMoon) {
      // Format hour respecting 12h/24h setting
      const fmtPlanetHour = h => {
        if (_use12h()) {
          const ampm = h < 12 ? 'AM' : 'PM';
          const h12  = h % 12 || 12;
          return `${h12}:00 ${ampm}`;
        }
        return String(h).padStart(2, '0') + ':00';
      };
      const riseH = 6, setH = 18;
      sunEl.innerHTML =
        `<span class="wx-chip">${svgSunrise(10)} ${fmtPlanetHour(riseH)}</span>` +
        `<span class="wx-chip">${svgSunset(10)} ${fmtPlanetHour(setH)}</span>`;
      sunEl.style.display = '';
    } else { sunEl.style.display = 'none'; }
  }

  // Holiday (always hidden for planets)
  if (holidayEl) holidayEl.style.display = 'none';

  // Light-speed ping from Earth
  if (pingEl) {
    if (s.showPing) {
      if (isMoon) {
        // Moon: ~384,400 km from Earth = ~1.28 s one-way (constant)
        pingEl.innerHTML = `<i class="fa-solid fa-bolt" aria-hidden="true"></i> ${formatPingSec(1.282)} one-way to Moon`;
      } else if (isLocal && P.orbitA && P.perihelionEpoch && P.orbitalPeriodYears) {
        // Local body with orbital data — compute Keplerian Earth distance
        const dAU  = _localBodyDistAU(P, now.getTime());
        const ltSec = dAU * PlanetTime.AU_SECONDS;
        const rttSec = ltSec * 2;
        const rttStr = rttSec < 7200 ? `${Math.round(rttSec)} s` : `${(rttSec / 3600).toFixed(1)} h`;
        pingEl.innerHTML = `<i class="fa-solid fa-bolt" aria-hidden="true"></i> ${PlanetTime.formatLightTime(ltSec)} · ↩ ${rttStr} RTT`;
      } else if (!isLocal) {
        const ltSec = PlanetTime.lightTravelSeconds('earth', city.planet, now);
        const rttSec = ltSec * 2;
        const rttStr = rttSec < 120 ? `${Math.round(rttSec)} s` : `${(rttSec / 60).toFixed(1)} min`;
        pingEl.innerHTML = `<i class="fa-solid fa-bolt" aria-hidden="true"></i> ${PlanetTime.formatLightTime(ltSec)} · ↩ ${rttStr} RTT`;
      } else {
        pingEl.style.display = 'none';
      }
      if (pingEl.style.display !== 'none') pingEl.style.display = '';
    } else { pingEl.style.display = 'none'; }
  }

  // Line-of-sight check (not applicable to Moon — always clear)
  if (losEl) {
    if (s.showPing && !isLocal) {
      const los = PlanetTime.checkLineOfSight('earth', city.planet, now);
      if (los.blocked) {
        losEl.innerHTML = '<i class="fa-solid fa-triangle-exclamation" aria-hidden="true"></i> Signal blocked (solar conjunction)';
        losEl.style.display = '';
      } else if (los.degraded) {
        losEl.innerHTML = `<i class="fa-solid fa-triangle-exclamation" aria-hidden="true"></i> Degraded (${los.closestSunAU.toFixed(3)} AU from Sun)`;
        losEl.style.display = '';
      } else {
        const conjDays = getNextConjunctionDays(city.planet, now);
        if (conjDays !== null && conjDays <= 120) {
          // Story 7.2 — include blackout calendar download link in conjunction countdown
          const blkLabel = t('meeting.blackout_cal_aria');
          losEl.innerHTML = `<span style="opacity:.45;font-size:.7rem">Next conjunction in ${conjDays} d</span>` +
            ` <button class="blackout-cal-btn" onclick="downloadBlackoutCalendar('${city.planet}')" ` +
            `title="${blkLabel}" aria-label="${blkLabel}" style="background:none;border:none;` +
            `cursor:pointer;padding:0 .25rem;font-size:.6rem;opacity:.5;color:inherit">` +
            `<i class="fa-solid fa-calendar-xmark" aria-hidden="true"></i></button>`;
          losEl.style.display = '';
        } else {
          losEl.style.display = 'none';
        }
      }
    } else { losEl.style.display = 'none'; }
  }

  // ── Accessibility: aria-label (summary) + a11y details div (expanded) ──
  if (colEl) {
    const skyDescStr = planetSkyDesc(pt.localHour);
    const zonePart = city.zoneId ? ` ${city.zoneId}.` : '';
    colEl.setAttribute('aria-label',
      `${P.name}.${zonePart} ${pt.timeString} ${pt.dowShort}. Sky: ${skyDescStr}.`);
  }
  const pa11yEl = document.getElementById(`a11y-${city.id}`);
  if (pa11yEl) {
    const pparts = [];
    if (isLocal && P.orbitalPeriodYears && P.solarDayMs && P.perihelionEpoch) {
      const si = _localBodySolInfo(P, now.getTime());
      pparts.push(`Year ${si.yearNumber}, Sol ${si.solInYear} of ${si.solsPerYear}.`);
      const workLabel = pt.isWorkHour ? 'Work hours.' : pt.isWorkPeriod ? 'Off-shift.' : 'Rest period.';
      pparts.push(workLabel);
      if (P.orbitA) {
        const dAU = _localBodyDistAU(P, now.getTime());
        pparts.push(`Signal propagation delay from Earth: ${PlanetTime.formatLightTime(dAU * PlanetTime.AU_SECONDS)} one-way.`);
      }
    } else if (!isLocal && pt.solInfo) {
      pparts.push(`Year ${pt.yearNumber}, Sol ${pt.solInfo.solInYear}.`);
    } else if (!isLocal) {
      pparts.push(`Year ${pt.yearNumber}, Day ${pt.dayInYear}.`);
    }
    if (!isLocal) {
      const workLabel = pt.isWorkHour ? 'Work hours.' : pt.isWorkPeriod ? 'Off-shift.' : 'Rest period.';
      pparts.push(workLabel);
      const ltSec = PlanetTime.lightTravelSeconds('earth', city.planet, now);
      pparts.push(`Signal propagation delay from Earth: ${PlanetTime.formatLightTime(ltSec)} one-way.`);
      const los = PlanetTime.checkLineOfSight('earth', city.planet, now);
      if (los.blocked) pparts.push('Warning: signal blocked by solar conjunction.');
      else if (los.degraded) pparts.push(`Warning: signal degraded, ${los.closestSunAU.toFixed(2)} AU from Sun.`);
    } else if (isMoon) {
      const phase = moonPhase(now);
      pparts.push(`Moon: ${Math.round(moonIllum(phase)*100)} percent illuminated.`);
    }
    pa11yEl.textContent = pparts.join(' ');
  }

  // Planet hourly schedule bar
  const hw = document.getElementById(`hw-${city.id}`);
  if (hw) {
    hw.style.display = s.showHourly ? '' : 'none';
    if (s.showHourly) renderPlanetHourlyBar(city, pt);
  }
}

function hexToRgb(h) {
  const r = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(h);
  return r ? {r:parseInt(r[1],16),g:parseInt(r[2],16),b:parseInt(r[3],16)} : {r:128,g:128,b:128};
}

// ════════════════════════════════════════════════════════════════════════════
// HOURLY BARS
// ════════════════════════════════════════════════════════════════════════════
const WMO = {0:'Clear',1:'Mainly clear',2:'Part cloud',3:'Overcast',
  45:'Fog',48:'Icy fog',51:'Lt drizzle',53:'Drizzle',55:'Hvy drizzle',
  61:'Lt rain',63:'Rain',65:'Hvy rain',71:'Lt snow',73:'Snow',75:'Hvy snow',
  77:'Snow grains',80:'Showers',81:'Showers',82:'Hvy showers',
  85:'Snow shower',86:'Hvy snow',95:'Thunderstorm',96:'T-storm+hail',99:'T-storm+hail'};

function renderHourlyBar(city) {
  const bar  = document.getElementById(`hbar-${city.id}`);
  const lbls = document.getElementById(`hlbl-${city.id}`);
  if (!bar || !city.hourly) return;

  const h = city.hourly;
  const now = getNow();
  const nowMs = now.getTime();

  // Find index of "now" in the hourly data (times are UTC strings from &timezone=UTC)
  const nowIdx = h.times.findIndex((t, i) => {
    const ms = new Date(t + 'Z').getTime();
    return ms <= nowMs && (i===h.times.length-1 || new Date(h.times[i+1] + 'Z').getTime() > nowMs);
  });
  const startIdx = Math.max(0, nowIdx - 24);
  const endIdx   = Math.min(h.times.length - 1, nowIdx + 24);
  const slice    = h.times.slice(startIdx, endIdx+1);

  bar.innerHTML = '';

  slice.forEach((tStr, i) => {
    const realIdx = startIdx + i;
    const tMs = new Date(tStr + 'Z').getTime();
    const cloud = h.clouds[realIdx] ?? 50;
    const code  = h.codes[realIdx]  ?? 1;
    const temp  = h.temps[realIdx];
    const dt = new Date(tMs);
    const alt = sunAlt(city.lat, city.lon, dt);
    const { horizon } = skyGradient(alt, cloud, code, city.lat, city.pop, dt);
    const ws = workStatusAt(city.tz, city.workWeek, dt);

    const cell = document.createElement('div');
    cell.className = 'hour-cell';
    cell.style.background = hex3(horizon);

    // Work hours: top border (horizontal bar) or left border (vertical bar)
    const _isVertBar = document.getElementById('cities-wrap').classList.contains('horiz');
    if (ws === 'work')
      cell.style.boxShadow = _isVertBar ? 'inset 2px 0 0 rgba(76,175,80,0.7)' : 'inset 0 2px 0 rgba(76,175,80,0.7)';
    else if (ws==='marginal')
      cell.style.boxShadow = _isVertBar ? 'inset 2px 0 0 rgba(255,152,0,0.6)' : 'inset 0 2px 0 rgba(255,152,0,0.6)';

    const _popData = {
      time: new Intl.DateTimeFormat('en-US',{timeZone:city.tz,hour:'2-digit',minute:'2-digit',hour12:_use12h()}).format(dt),
      date: new Intl.DateTimeFormat('en-US',{timeZone:city.tz,weekday:'short',month:'short',day:'numeric'}).format(dt),
      desc: skyDescription(alt, cloud, code, parseInt(new Intl.DateTimeFormat('en-US',{timeZone:city.tz,hour:'2-digit',hour12:false}).format(dt))),
      code: WMO[code]||`Code ${code}`,
      cloud, temp, ws, color: hex3(horizon)
    };
    cell.addEventListener('mouseenter', e => showHourPopup(e, _popData));
    cell.addEventListener('mouseleave', hideHourPopup);
    cell.addEventListener('mousemove', moveHourPopup);
    cell.addEventListener('click', e => { e.stopPropagation(); _popPinned = true; showHourPopup(e, _popData); });

    bar.appendChild(cell);
  });

  // Now-line — use top in vertical bar mode, left otherwise
  if (nowIdx >= startIdx && nowIdx <= endIdx) {
    const pct = ((nowIdx - startIdx) / slice.length * 100).toFixed(2);
    const line = document.createElement('div');
    line.className = 'now-line';
    const _vert = document.getElementById('cities-wrap').classList.contains('horiz');
    if (_vert) line.style.top = pct + '%'; else line.style.left = pct + '%';
    bar.appendChild(line);
  }

  // Labels: -24h, now, +24h
  if (lbls) {
    const fmtH = t => new Intl.DateTimeFormat('en-US',{timeZone:city.tz,hour:'numeric',hour12:_use12h()}).format(new Date(t));
    lbls.textContent = '';
    lbls.innerHTML = `<span>-24h</span><span>${fmtH(nowMs)}</span><span>+24h</span>`;
  }
}

function renderPlanetHourlyBar(city, currentPt) {
  const bar = document.getElementById(`hbar-${city.id}`);
  if (!bar) return;
  const P = PlanetTime.PLANETS[city.planet];
  if (!P) { bar.innerHTML = ''; return; } // LOCAL_PLANETS (Moon etc.) — no hourly schedule
  bar.innerHTML = '';

  // Show ±24 Earth hours centered on now — mirrors the Earth hourly bar layout
  // so the now-line is always at 50% and the time span is the same across all cards.
  const now = getNow();
  const EARTH_HOUR_MS = 3600000;
  const SLOTS = 48;
  const startMs = now.getTime() - 24 * EARTH_HOUR_MS;
  const pColor = hexToRgb(P.color);

  for (let i = 0; i < SLOTS; i++) {
    const dt = new Date(startMs + i * EARTH_HOUR_MS);
    const pt = PlanetTime.getPlanetTime(city.planet, dt, city.tzOffset || 0);
    const factor = pt.isWorkHour ? 1.0 : 0.35;
    const c = { r: pColor.r * factor | 0, g: pColor.g * factor | 0, b: pColor.b * factor | 0 };

    const cell = document.createElement('div');
    cell.className = 'hour-cell';
    cell.style.background = hex3(c);
    if (pt.isWorkHour) cell.style.boxShadow = 'inset 0 2px 0 rgba(76,175,80,0.7)';

    // Capture pt for closure
    const _pt = pt, _dt = dt, _c = { ...c };
    const _pPopData = {
      time: `${_pt.timeString} (${P.name} local)`,
      date: _dt.toUTCString().replace(' GMT', ' UTC'),
      desc: _pt.isWorkHour ? t('hourly.planet_work') : t('hourly.planet_rest'),
      code: '',
      ws: _pt.isWorkHour ? 'work' : 'rest',
      color: hex3(_c)
    };
    cell.addEventListener('mouseenter', e => showHourPopup(e, _pPopData));
    cell.addEventListener('mouseleave', hideHourPopup);
    cell.addEventListener('mousemove', moveHourPopup);
    cell.addEventListener('click', e => { e.stopPropagation(); _popPinned = true; showHourPopup(e, _pPopData); });
    bar.appendChild(cell);
  }

  // Now-line always centered — the bar spans ±24 Earth hours around now
  const nowLine = document.createElement('div');
  nowLine.className = 'now-line';
  const _pVertBar = document.getElementById('cities-wrap').classList.contains('horiz');
  if (_pVertBar) nowLine.style.top = '50%'; else nowLine.style.left = '50%';
  bar.appendChild(nowLine);
}

// workStatusAt: same as workStatus but for a specific date
function workStatusAt(tz, workWeekKey, date) {
  const sched = WORK_SCHEDULES[workWeekKey] || WORK_SCHEDULES['mon-fri'];
  const dow   = getLocalDow(tz, date);
  const hour  = getLocalHour(tz, date);
  if (!sched.workDays.includes(dow)) return 'rest';
  if (hour < sched.workStart || hour >= sched.workEnd) return 'rest';
  if (hour < sched.workStart+1 || hour >= sched.workEnd-1) return 'marginal';
  return 'work';
}

// ════════════════════════════════════════════════════════════════════════════
// HOUR POPUP
// ════════════════════════════════════════════════════════════════════════════
let _popX = 0, _popY = 0, _popPinned = false;
function showHourPopup(e, data) {
  const p = document.getElementById('hpop');
  _popX = e.clientX; _popY = e.clientY;
  const ws = data.ws === 'work' ? t('hourly.popup_work') : data.ws === 'marginal' ? t('hourly.popup_marginal') : t('hourly.popup_rest');
  p.innerHTML = `
    <div class="hpop-time">${data.time}</div>
    <div style="opacity:.5;font-size:.68rem;margin-bottom:.3rem">${data.date}</div>
    <div class="hpop-row"><span>${data.desc}</span><span>${ws}</span></div>
    ${data.code ? `<div class="hpop-row"><span>${data.code}</span>${data.cloud!=null?`<span><i class="fa-solid fa-cloud" aria-hidden="true"></i> ${data.cloud}%</span>`:''}</div>` : ''}
    ${data.temp!=null ? `<div class="hpop-row"><span><i class="fa-solid fa-temperature-half" aria-hidden="true"></i> ${Math.round(data.temp)}°</span></div>` : ''}
  `;
  positionPopup(_popX, _popY);
  p.classList.add('on');
}
function moveHourPopup(e) { if (!_popPinned) positionPopup(e.clientX, e.clientY); }
function hideHourPopup()  { if (_popPinned) return; document.getElementById('hpop').classList.remove('on'); }
function positionPopup(x, y) {
  const p = document.getElementById('hpop');
  const pw = p.offsetWidth||160, ph = p.offsetHeight||80;
  let px = x+12, py = y-ph-8;
  if (px+pw > window.innerWidth-8) px = x-pw-12;
  if (py < 8) py = y+12;
  p.style.left = px+'px'; p.style.top = py+'px';
}

// ════════════════════════════════════════════════════════════════════════════
// FETCH & UPDATE
// ════════════════════════════════════════════════════════════════════════════
const WEATHER_CACHE_MS = 10 * 60 * 1000; // 10-minute cache — respects Open-Meteo free tier

function _wxCacheKey(lat, lon) {
  return `wx_${parseFloat(lat).toFixed(3)}_${parseFloat(lon).toFixed(3)}`;
}
function _wxCacheGet(lat, lon) {
  try {
    const raw = localStorage.getItem(_wxCacheKey(lat, lon));
    if (!raw) return null;
    const { d, ts } = JSON.parse(raw);
    return (Date.now() - ts < WEATHER_CACHE_MS) ? d : null;
  } catch(_) { return null; }
}
function _wxCacheSet(lat, lon, data) {
  try { localStorage.setItem(_wxCacheKey(lat, lon), JSON.stringify({ d: data, ts: Date.now() })); } catch(_) {}
}
function _wxCacheClear(lat, lon) {
  try { localStorage.removeItem(_wxCacheKey(lat, lon)); } catch(_) {}
}

async function fetchAndUpdateCity(city, { forceRefresh = false } = {}) {
  if (city.type === 'planet') return;

  let data = forceRefresh ? null : _wxCacheGet(city.lat, city.lon);
  if (!data) {
    data = await fetchWeather(city.lat, city.lon);
    if (data) _wxCacheSet(city.lat, city.lon, data);
  }

  if (data) {
    city.weather = data.current;
    const h = data.hourly;
    city.hourly = {
      times:      h.time,
      clouds:     h.cloud_cover,
      codes:      h.weather_code,
      temps:      h.temperature_2m,
      precipProb: h.precipitation_probability,
    };
  }
  // Remove shimmer and render (success or failure)
  const colEl = document.getElementById(`city-${city.id}`);
  if (colEl) colEl.classList.remove('weather-loading');
  updateCityDisplay(city);
  // Refresh every 10 min
  if (city.refreshTimer) clearInterval(city.refreshTimer);
  city.refreshTimer = setInterval(() => fetchAndUpdateCity(city), WEATHER_CACHE_MS);
}

function startPlanetClock(city) {
  updateCityDisplay(city);
  city.refreshTimer = setInterval(() => updateCityDisplay(city), 30000);
}

// ════════════════════════════════════════════════════════════════════════════
// CONJUNCTION COUNTDOWN
// ════════════════════════════════════════════════════════════════════════════
const _conjunctionCache = {};

function getNextConjunctionDays(planet, now) {
  const MS_PER_DAY = 86400000;
  const cached = _conjunctionCache[planet];
  if (cached && now.getTime() - cached.computedAt < 6 * 3600000) return cached.days;
  let days = null;
  for (let d = 1; d <= 730; d++) {
    const future = new Date(now.getTime() + d * MS_PER_DAY);
    try {
      if (PlanetTime.checkLineOfSight('earth', planet, future).blocked) { days = d; break; }
    } catch (_) { break; }
  }
  _conjunctionCache[planet] = { days, computedAt: now.getTime() };
  return days;
}

// ── Conjunction blackout calendar export (Story 7.2) ─────────────────────
// Finds all conjunction periods for `planet` in the next 2 years and
// generates a VFREEBUSY/VEVENT-based ICS "blackout calendar" for schedulers.

function buildConjunctionPeriods(planet, fromDate, horizonDays) {
  const MS_PER_DAY = 86400000;
  const STEP       = 6 * 3600000;   // 6-hour step for accuracy
  const to         = fromDate.getTime() + horizonDays * MS_PER_DAY;

  const periods = [];
  let inConj    = false;
  let conjStart = null;

  for (let t = fromDate.getTime(); t < to; t += STEP) {
    const d = new Date(t);
    let blocked = false;
    try { blocked = PlanetTime.checkLineOfSight('earth', planet, d).blocked; } catch(_) { break; }
    if (blocked && !inConj) {
      inConj    = true;
      conjStart = d;
    } else if (!blocked && inConj) {
      inConj = false;
      periods.push({ start: conjStart, end: d });
    }
  }
  if (inConj && conjStart) periods.push({ start: conjStart, end: new Date(to) });
  return periods;
}

function downloadBlackoutCalendar(planet) {
  const planetName = planet.charAt(0).toUpperCase() + planet.slice(1);
  const pad = n => String(n).padStart(2, '0');
  const fmt = d =>
    `${d.getUTCFullYear()}${pad(d.getUTCMonth()+1)}${pad(d.getUTCDate())}` +
    `T${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}00Z`;

  const periods = buildConjunctionPeriods(planet, new Date(), 730);
  if (periods.length === 0) {
    showToast(`No conjunctions found for ${planetName} in the next 2 years.`);
    return;
  }

  const lines = [
    'BEGIN:VCALENDAR', 'VERSION:2.0',
    `PRODID:-//InterPlanet//Conjunction Blackout ${planetName}//EN`,
    'CALSCALE:GREGORIAN', 'METHOD:PUBLISH',
    `X-WR-CALNAME:${planetName} Signal Blackout Periods`,
    `X-WR-CALDESC:Solar conjunction blackout periods for Earth–${planetName} link (generated by interplanet.live)`,
  ];

  periods.forEach((p, i) => {
    const uid = `${p.start.getTime()}-blackout-${planet}-${i}@interplanet.live`;
    lines.push(
      'BEGIN:VEVENT',
      `UID:${uid}`,
      `DTSTAMP:${fmt(new Date())}`,
      `DTSTART:${fmt(p.start)}`,
      `DTEND:${fmt(p.end)}`,
      `SUMMARY:${planetName} Solar Conjunction — Signal Blackout`,
      `DESCRIPTION:Earth–${planetName} communications blocked by solar conjunction.\\nSignal quality severely degraded or lost entirely.\\nSchedule no time-critical sessions during this period.\\n\\nGenerated by interplanet.live`,
      'TRANSP:OPAQUE',
      'STATUS:CONFIRMED',
      `CATEGORIES:CONJUNCTION,BLACKOUT,${planet.toUpperCase()}`,
      'END:VEVENT',
    );
  });

  lines.push('END:VCALENDAR');

  const ics  = lines.join('\r\n');
  const blob = new Blob([ics], { type: 'text/calendar;charset=utf-8' });
  const url  = URL.createObjectURL(blob);
  const a    = document.createElement('a');
  a.href = url;
  a.download = `${planet}-conjunction-blackout.ics`;
  a.click();
  URL.revokeObjectURL(url);
}

// ════════════════════════════════════════════════════════════════════════════
// LTX MEETING — open ltx.html pre-filled from current meeting state
// ════════════════════════════════════════════════════════════════════════════

/**
 * Build a minimal LTX config from the current meeting context and open ltx.html.
 * Called from "Open LTX" button rendered in the meeting panel slot results.
 * @param {number}  startMs   — meeting start (Unix ms)
 * @param {number}  delayMin  — one-way signal delay in minutes
 * @param {Array}   cities    — STATE.cities array
 */
function openLtxMeeting(startMs, delayMin, cities) {
  // Build nodes array (v2 schema): host = first Earth city, participants = planets + other earths
  const earthCities  = cities.filter(c => c.type !== 'planet');
  const planetCities = cities.filter(c => c.type === 'planet');
  const host = earthCities[0];
  const hostName = host ? (host.customName || host.city) : 'Earth';

  const nodes = [{ id:'N0', name:hostName, role:'HOST', delay:0, location:'earth' }];
  planetCities.forEach((p, i) => {
    const pName = p.customName || (p.planet.charAt(0).toUpperCase() + p.planet.slice(1)) + ' Node';
    nodes.push({ id:`N${nodes.length}`, name:pName, role:'PARTICIPANT',
      delay:Math.round((delayMin || 0) * 60), location:p.planet });
  });
  earthCities.slice(1).forEach(c => {
    const cName = c.customName || c.city;
    nodes.push({ id:`N${nodes.length}`, name:cName, role:'PARTICIPANT', delay:0, location:'earth' });
  });

  const participantStr = nodes.slice(1).map(n => n.name).join(' + ') || 'Remote';
  const cfg = {
    v:        2,
    title:    hostName + ' ↔ ' + participantStr + ' — LTX',
    start:    new Date(startMs).toISOString(),
    quantum:  5,
    mode:     'LTX-LIVE',
    nodes,
    segments: [
      { type:'PLAN_CONFIRM', q:2 },
      { type:'TX',           q:3 },
      { type:'RX',           q:3 },
      { type:'CAUCUS',       q:2 },
      { type:'TX',           q:3 },
      { type:'RX',           q:3 },
      { type:'MERGE',        q:2 },
      { type:'BUFFER',       q:1 },
    ],
  };
  const hash = '#l=' + _toBase64url(JSON.stringify(cfg));
  window.open('ltx.html' + hash, '_blank', 'noopener');
}

// ════════════════════════════════════════════════════════════════════════════
// ICS CALENDAR EXPORT (LTX-extended, RFC 5545 compatible)
// ════════════════════════════════════════════════════════════════════════════

// Builds LTX-* property lines from city list for inclusion in a VEVENT.
// Unknown properties are silently ignored by standard calendar clients
// (RFC 5545 §3.8.8.2), so the file remains fully compatible.
function _makeMeetingLtxLines(startDate, durationMin, cities) {
  if (!cities || !cities.length) return [];
  const hasPlanet = cities.some(c => c.type === 'planet');
  const mode = hasPlanet ? 'RELAY' : 'LIVE';
  // Deterministic plan ID
  const dateStr = startDate.toISOString().slice(0, 10).replace(/-/g, '');
  const hostId  = (cities[0].customName || cities[0].city || cities[0].planet || 'HOST')
    .replace(/\s+/g, '').toUpperCase().slice(0, 8);
  const destPart = cities.slice(1)
    .map(c => (c.customName || c.city || c.planet || 'NODE').replace(/\s+/g, '').toUpperCase().slice(0, 4))
    .join('-').slice(0, 16) || 'NODE';
  let h = 0;
  const raw = dateStr + hostId + destPart + durationMin;
  for (let i = 0; i < raw.length; i++) h = (Math.imul(31, h) + raw.charCodeAt(i)) >>> 0;
  const planId = `LTX-${dateStr}-${hostId}-${destPart}-${h.toString(16).padStart(8, '0')}`;
  const lines = [
    'LTX:1',
    `LTX-PLANID:${planId}`,
    'LTX-QUANTUM:PT15M',
    `LTX-MODE:${mode}`,
    'LTX-SEGMENT-TEMPLATE:A-W-R',
  ];
  cities.forEach((c, i) => {
    const nodeId = (c.customName || c.city || c.planet || 'NODE').replace(/\s+/g, '-').toUpperCase();
    lines.push(`LTX-NODE:ID=${nodeId};ROLE=${i === 0 ? 'HOST' : 'NODE'}`);
    if (c.type === 'planet') {
      const oneWaySec = PlanetTime.lightTravelSeconds('earth', c.planet);
      const assumed   = (oneWaySec / 60).toFixed(1);
      const max       = (oneWaySec / 60 + 2).toFixed(1);
      lines.push(`LTX-DELAY;NODEID=${nodeId}:ONEWAY-MIN=${assumed};ONEWAY-MAX=${max};ONEWAY-ASSUMED=${assumed}`);
    }
  });
  return lines;
}

function generateICS(startDate, durationMinutes, title, description, ltxLines) {
  const pad = n => String(n).padStart(2, '0');
  const fmt = d =>
    `${d.getUTCFullYear()}${pad(d.getUTCMonth()+1)}${pad(d.getUTCDate())}` +
    `T${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}00Z`;
  const endDate     = new Date(startDate.getTime() + durationMinutes * 60000);
  const uid         = `${startDate.getTime()}-ip@interplanet.live`;
  const safeDesc    = (description || '').replace(/\n/g, '\\n').replace(/,/g, '\\,');
  const safeSummary = (title || '').replace(/,/g, '\\,');
  const lines = [
    'BEGIN:VCALENDAR', 'VERSION:2.0',
    'PRODID:-//InterPlanet//LTX v1.1//EN',
    'CALSCALE:GREGORIAN', 'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    `UID:${uid}`,
    `DTSTAMP:${fmt(new Date())}`,
    `DTSTART:${fmt(startDate)}`,
    `DTEND:${fmt(endDate)}`,
    `SUMMARY:${safeSummary}`,
    `DESCRIPTION:${safeDesc}`,
  ];
  if (ltxLines && ltxLines.length) lines.push(...ltxLines);
  lines.push('END:VEVENT', 'END:VCALENDAR');
  return lines.join('\r\n');
}

function downloadICS(startDate, durationMinutes, cities) {
  const list      = cities || STATE.cities;
  const cityNames = list.map(c => c.customName || c.city || c.planet).join(', ');
  const title     = `Meeting — ${cityNames}`;
  const planets   = list.filter(c => c.type === 'planet');
  const delayNote = planets.length
    ? '\\nSignal delays: ' + planets.map(c => {
        const s = PlanetTime.lightTravelSeconds('earth', c.planet);
        return (c.customName || c.planet) + ' ' + Math.round(s / 60) + ' min one-way';
      }).join(', ')
    : '';
  const desc  = `InterPlanet scheduled meeting across: ${cityNames}.${delayNote}\\nScheduled via interplanet.live`;
  const ltxLines = _makeMeetingLtxLines(startDate, durationMinutes, list);
  const ics   = generateICS(startDate, durationMinutes, title, desc, ltxLines);
  const blob  = new Blob([ics], { type: 'text/calendar;charset=utf-8' });
  const url   = URL.createObjectURL(blob);
  const a     = document.createElement('a');
  a.href = url;
  a.download = `ltx-meeting-${startDate.toISOString().slice(0, 10)}.ics`;
  a.click();
  URL.revokeObjectURL(url);
}

// ── Recurring ICS series export (Story 2.3) ──────────────────────────────
// Generates a multi-VEVENT ICS file (one entry per date in `dates` array).
// Optionally includes RRULE if all gaps are the same interval (pure weekly/monthly series).

function downloadRecurringICS(dates, durMin, cities) {
  if (!dates || dates.length === 0) return;
  const pad = n => String(n).padStart(2, '0');
  const fmt = d =>
    `${d.getUTCFullYear()}${pad(d.getUTCMonth()+1)}${pad(d.getUTCDate())}` +
    `T${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}00Z`;

  const cityNames = (cities || STATE.cities).map(c => c.customName || c.city || c.planet).join(', ');
  const title     = `Meeting — ${cityNames}`;
  const safeTitle = title.replace(/,/g, '\\,');
  const safeDesc  = `Recurring InterPlanet meeting: ${cityNames}\\nScheduled via interplanet.live`.replace(/\n/g, '\\n');
  const durationMs = (durMin || 60) * 60000;

  const lines = [
    'BEGIN:VCALENDAR', 'VERSION:2.0',
    'PRODID:-//InterPlanet//Interplanetary Time Scheduler//EN',
    'CALSCALE:GREGORIAN', 'METHOD:PUBLISH',
  ];

  dates.forEach((startDate, i) => {
    const endDate = new Date(startDate.getTime() + durationMs);
    const uid = `${startDate.getTime()}-series${i}-ip@interplanet.live`;
    lines.push(
      'BEGIN:VEVENT',
      `UID:${uid}`,
      `DTSTAMP:${fmt(new Date())}`,
      `DTSTART:${fmt(startDate)}`,
      `DTEND:${fmt(endDate)}`,
      `SUMMARY:${safeTitle} (${i + 1}/${dates.length})`,
      `DESCRIPTION:${safeDesc}`,
      'SEQUENCE:' + i,
      'END:VEVENT',
    );
  });

  lines.push('END:VCALENDAR');

  const ics  = lines.join('\r\n');
  const blob = new Blob([ics], { type: 'text/calendar;charset=utf-8' });
  const url  = URL.createObjectURL(blob);
  const a    = document.createElement('a');
  a.href = url;
  a.download = `interplanet-series-${dates[0].toISOString().slice(0, 10)}.ics`;
  a.click();
  URL.revokeObjectURL(url);
}

// ── Calendar quick-add URL builders (Story 2.2) ───────────────────────────

function _calTitle(cities) {
  const names = (cities || STATE.cities).map(c => c.customName || c.city || c.planet).join(', ');
  return `Meeting — ${names}`;
}

function _gcalUrl(startMs, durMin) {
  const start = new Date(startMs);
  const end   = new Date(startMs + durMin * 60000);
  const fmt   = d => d.toISOString().replace(/[-:]/g, '').replace('.000', '');
  const title = encodeURIComponent(_calTitle());
  const desc  = encodeURIComponent('Scheduled via interplanet.live');
  return `https://calendar.google.com/calendar/render?action=TEMPLATE` +
    `&text=${title}&dates=${fmt(start)}/${fmt(end)}&details=${desc}`;
}

function _outlookUrl(startMs, durMin) {
  const start = new Date(startMs);
  const end   = new Date(startMs + durMin * 60000);
  const title = encodeURIComponent(_calTitle());
  const desc  = encodeURIComponent('Scheduled via interplanet.live');
  return `https://outlook.live.com/calendar/0/deeplink/compose?path=%2Fcalendar%2Faction%2Fcompose` +
    `&rru=addevent&subject=${title}&startdt=${start.toISOString()}&enddt=${end.toISOString()}&body=${desc}`;
}

// ════════════════════════════════════════════════════════════════════════════
// MEETING SCHEDULER
// ════════════════════════════════════════════════════════════════════════════
function findNextOverlap(cities, fromDate) {
  const STEP = 30 * 60000;
  const MAX  = fromDate.getTime() + 14 * 24 * 3600000;
  for (let t = fromDate.getTime(); t < MAX; t += STEP) {
    const d = new Date(t);
    const allWork = cities.every(c => {
      if (c.type === 'planet') return PlanetTime.getPlanetTime(c.planet, d, c.tzOffset||0).isWorkHour;
      return workStatusAt(c.tz, c.workWeek, d) === 'work';
    });
    if (allWork) return new Date(t);
  }
  return null;
}

// ── Rotation preview (Story 1.3) ─────────────────────────────────────────────
// Build a 4-week recurring-meeting preview: find the next overlap each week,
// track per-city work-status, and flag which cities are disadvantaged most often.

function _cityWorkAt(c, d) {
  if (c.type === 'planet') return PlanetTime.getPlanetTime(c.planet, d, c.tzOffset||0).isWorkHour;
  return workStatusAt(c.tz, c.workWeek, d) === 'work';
}

function buildRotationPreview(cities, firstDate, weeks) {
  weeks = weeks || 4;
  const rows = [];
  let cur = firstDate;
  for (let i = 0; i < weeks; i++) {
    const work = cities.map(c => _cityWorkAt(c, cur));
    rows.push({ date: cur, work });
    const nextFrom = new Date(cur.getTime() + 6 * 24 * 3600000);
    const next = findNextOverlap(cities, nextFrom);
    if (!next) break;
    cur = next;
  }
  return rows;
}

function renderRotationPreview(cities, firstDate, container) {
  if (cities.length < 2) return;
  const rows = buildRotationPreview(cities, firstDate, 4);
  if (rows.length < 2) return; // only show if we found 2+ occurrences

  const locale = window.I18N ? window.I18N.getLocale() : 'en-US';
  const fmtDate = d => new Intl.DateTimeFormat(locale, {
    weekday:'short', month:'short', day:'numeric',
    hour:'2-digit', minute:'2-digit', hour12:false, timeZone:'UTC',
  }).format(d);

  // Count how many times each city is in rest hours (disadvantaged)
  const restCounts = cities.map(() => 0);
  rows.forEach(r => r.work.forEach((w, i) => { if (!w) restCounts[i]++; }));
  const maxRest = Math.max(...restCounts);
  const disadvantaged = cities
    .map((c, i) => ({ name: c.customName || c.city || c.planet, pct: Math.round(100 * restCounts[i] / rows.length) }))
    .filter(x => x.pct >= 50);

  const abbr = c => c.customName || c.city || c.planet || '';

  let html = `<div class="mp-rotation">`;
  html += `<div class="mp-rotation-hdr">${t('meeting.rotation_preview')}</div>`;
  html += `<table class="mp-rotation-tbl"><thead><tr>`;
  html += `<th>${t('meeting.rotation_date')}</th>`;
  cities.forEach(c => { html += `<th title="${c.customName||c.city||c.planet}">${abbr(c)}</th>`; });
  html += `</tr></thead><tbody>`;
  rows.forEach(r => {
    html += `<tr><td>${fmtDate(r.date)}</td>`;
    r.work.forEach(w => {
      html += `<td class="${w ? 'rot-work' : 'rot-rest'}">${w ? '●' : '○'}</td>`;
    });
    html += `</tr>`;
  });
  html += `</tbody></table>`;
  if (disadvantaged.length) {
    const names = disadvantaged.map(x => `${x.name} (${x.pct}% rest)`).join(', ');
    html += `<div class="mp-rotation-note">${t('meeting.rotation_note', { names })}</div>`;
  }

  // Story 2.3 — "Series .ics" download button (stored as data-attr; wired below)
  const datesJson = JSON.stringify(rows.map(r => r.date.toISOString()));
  html += `<button class="mp-series-ics-btn" data-dates='${datesJson.replace(/'/g,"&#39;")}' ` +
    `title="${t('meeting.series_ics')}" aria-label="${t('meeting.series_ics')}">` +
    `<i class="fa-solid fa-calendar-days" aria-hidden="true"></i> ${t('meeting.series_ics')}</button>`;

  html += `</div>`;

  const div = document.createElement('div');
  div.innerHTML = html;
  // Wire series ICS button
  const seriesBtn = div.querySelector('.mp-series-ics-btn');
  if (seriesBtn) {
    seriesBtn.addEventListener('click', () => {
      const dates = JSON.parse(seriesBtn.dataset.dates).map(s => new Date(s));
      downloadRecurringICS(dates, 60);
    });
  }
  container.appendChild(div);
}

let _mpDays = 1; // 1 / 3 / 7

function _mpDateStr(d) {
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth()+1).padStart(2,'0')}-${String(d.getUTCDate()).padStart(2,'0')}`;
}

function _mpShiftDate(delta) {
  const dateInput = document.getElementById('mp-date');
  const cur = dateInput.value ? new Date(dateInput.value + 'T00:00:00Z') : new Date();
  cur.setUTCDate(cur.getUTCDate() + delta);
  dateInput.value = _mpDateStr(cur);
  renderMeetingScheduler();
}

function renderMeetingScheduler() {
  const content = document.getElementById('mp-content');
  const earthCities = STATE.cities.filter(c => c.type === 'earth');
  const planetCities = STATE.cities.filter(c => c.type === 'planet');

  if (STATE.cities.length === 0) {
    content.innerHTML = `<div style="padding:1.2rem;opacity:.5;font-size:.85rem">${t('meeting.no_cities')}</div>`;
    return;
  }

  // Date picker — start from midnight UTC of selected date
  const dateInput = document.getElementById('mp-date');
  let startDate = new Date();
  startDate.setUTCHours(0, 0, 0, 0);
  if (dateInput && dateInput.value) {
    const [y,m,d] = dateInput.value.split('-').map(Number);
    startDate = new Date(Date.UTC(y, m-1, d, 0, 0, 0));
  }

  const now = new Date();
  const STEP_MS = 30 * 60000;
  const SLOTS_PER_DAY = 48; // 30-min slots × 48 = 24h
  const TOTAL_SLOTS = _mpDays * SLOTS_PER_DAY;
  const startMs = startDate.getTime();

  const allCols = [...earthCities, ...planetCities];
  const colCount = allCols.length;

  // Ka-band data for planet columns (ephemeral cache lookup)
  const planetKaData = {};
  if (STATE.settings.hdtnApiUrl) {
    planetCities.forEach(c => {
      const cached = _hdtnCache[c.planet];
      if (cached && Date.now() - cached.ts < HDTN_TTL_MS) planetKaData[c.id] = cached.predictions;
    });
  }

  const gridCols = `80px ${allCols.map(c =>
    (c.type === 'planet' && planetKaData[c.id]) ? '1fr 28px' : '1fr'
  ).join(' ')}`;

  let html = `<div style="display:grid;grid-template-columns:${gridCols};min-width:0">`;

  // ── Sticky column headers ─────────────────────────────────────────────────
  html += `<div class="mp-header-cell time-col"></div>`;
  allCols.forEach(c => {
    let sub = '';
    if (c.type === 'planet') {
      try {
        const ltSec = PlanetTime.lightTravelSeconds('earth', c.planet, now);
        sub = `<div style="font-size:.58rem;opacity:.4;font-weight:400"><i class="fa-solid fa-bolt" aria-hidden="true"></i> ${PlanetTime.formatLightTime(ltSec)} one-way</div>`;
      } catch(e) {}
    }
    const pDef = c.type==='planet' ? (PlanetTime.PLANETS[c.planet] || LOCAL_PLANETS[c.planet]) : null;
    html += `<div class="mp-header-cell" style="min-width:70px">${c.customName||c.city}${pDef?` ${pDef.symbol}`:''}${sub}</div>`;
    if (c.type === 'planet' && planetKaData[c.id]) {
      html += `<div class="mp-ka-hdr">Ka</div>`;
    }
  });

  // ── Slot rows ─────────────────────────────────────────────────────────────
  let lastUTCDay = -1;
  for (let i = 0; i < TOTAL_SLOTS; i++) {
    const slotMs   = startMs + i * STEP_MS;
    const slotDate = new Date(slotMs);
    const isNow    = Math.abs(slotMs - now.getTime()) < STEP_MS;

    // UTC day change — show compact date badge in time column
    const utcDay = slotDate.getUTCDate();
    const dayTurned = utcDay !== lastUTCDay;
    if (dayTurned) lastUTCDay = utcDay;
    const utcDateBadge = dayTurned
      ? `<span style="font-size:.55rem;opacity:.45;line-height:1.2;display:block;text-align:right">${
          slotDate.toLocaleDateString('en-GB',{weekday:'short',day:'numeric',month:'short',timeZone:'UTC'})
        }</span>`
      : '';

    html += `<div class="mp-cell time-col${isNow?' highlight':''}" style="flex-direction:column;align-items:flex-end;gap:0;padding-right:8px;min-width:80px">${
      utcDateBadge
    }<span>${slotDate.toISOString().slice(11,16)}</span></div>`;

    // Each city / planet — show local day name + time in every cell
    let allWork = true;
    const cellData = allCols.map(c => {
      if (c.type === 'planet') {
        const pt  = PlanetTime.getPlanetTime(c.planet, slotDate, c.tzOffset||0);
        const isW = pt.isWorkHour;
        if (!isW) allWork = false;
        const h = String(pt.hour).padStart(2,'0');
        const m = String(pt.minute).padStart(2,'0');
        const dayAbbr = pt.dayName ? pt.dayName.slice(0,3) : '';
        return { cls: isW?'work':'rest', day: dayAbbr, time: `${h}:${m}` };
      } else {
        const ws = workStatusAt(c.tz, c.workWeek, slotDate);
        if (ws !== 'work') allWork = false;
        const _loc = window.I18N ? window.I18N.getLocale() : 'en-US';
        const parts = new Intl.DateTimeFormat(_loc,{
          timeZone: c.tz, weekday:'short', hour:'2-digit', minute:'2-digit', hour12: false
        }).formatToParts(slotDate);
        const get = k => (parts.find(p=>p.type===k)||{}).value||'';
        return { cls: ws, day: get('weekday'), time: `${get('hour')}:${get('minute')}` };
      }
    });

    const overlapCls = allWork && colCount > 1 ? ' highlight' : '';
    cellData.forEach((cd, ci) => {
      const col = allCols[ci];
      html += `<div class="mp-cell ${cd.cls}${overlapCls}" style="min-width:70px;flex-direction:column;align-items:flex-start;gap:0;padding:2px 6px">` +
        `<span style="font-size:.58rem;opacity:.5;line-height:1.2">${cd.day}</span>` +
        `<span>${cd.time}</span>` +
        `</div>`;
      if (col.type === 'planet' && planetKaData[col.id]) {
        const preds = planetKaData[col.id];
        const t0 = new Date(preds[0].timestamp).getTime();
        const nearestIdx = Math.max(0, Math.min(preds.length - 1,
          Math.round((slotMs - t0) / (6 * 3600000))));
        const ka = preds[nearestIdx].ka_blackout_prob;
        const kaBg = ka < 0.10 ? 'rgba(76,175,80,0.25)' :
                     ka < 0.50 ? 'rgba(255,160,0,0.30)' : 'rgba(240,60,60,0.35)';
        html += `<div class="mp-ka-cell" style="background:${kaBg}"></div>`;
      }
    });
  }

  html += '</div>';
  content.innerHTML = html;

  // Scroll to current time if viewing today
  if (_mpDays === 1 || now.getTime() >= startMs && now.getTime() < startMs + _mpDays * 86400000) {
    const nowOffset = now.getTime() - startMs;
    const slotIndex = Math.floor(nowOffset / STEP_MS);
    // Each slot = roughly 20px high; day headers are ~22px
    const approxScrollY = slotIndex * 22;
    content.scrollTop = Math.max(0, approxScrollY - 80);
  }
}

// ════════════════════════════════════════════════════════════════════════════
// BEST WINDOWS (ML forecast)
// ════════════════════════════════════════════════════════════════════════════
function findBestWindows() {
  const resultEl = document.getElementById('mp-signal-result');
  if (!resultEl) return;

  const planetCities = STATE.cities.filter(c => c.type === 'planet');
  if (STATE.cities.length === 0) {
    resultEl.innerHTML = `<div class="mp-signal-result" style="opacity:.6">${t('meeting.no_cities')}</div>`;
    return;
  }
  if (planetCities.length === 0) {
    resultEl.innerHTML = `<div class="mp-signal-result" style="opacity:.6">${t('meeting.no_planets_for_dtn')}</div>`;
    return;
  }

  if (!STATE.settings.hdtnApiUrl) {
    // No DTN URL — use findNextMeetingSlot as fallback
    _findBestWindowsNoDtn(resultEl);
    return;
  }

  // Gather cached predictions for all planets
  const planetPreds = {};
  let hasPreds = false;
  planetCities.forEach(c => {
    const cached = _hdtnCache[c.planet];
    if (cached && Date.now() - cached.ts < HDTN_TTL_MS) {
      planetPreds[c.id] = cached.predictions;
      hasPreds = true;
    }
  });

  if (!hasPreds) {
    resultEl.innerHTML = `<div class="mp-signal-result" style="opacity:.6">${t('meeting.no_hdtn')}</div>`;
    return;
  }

  // Use first planet's predictions as 6-hour time anchors
  const firstId = Object.keys(planetPreds)[0];
  const anchorPreds = planetPreds[firstId];
  const now = new Date();
  const candidates = [];

  anchorPreds.forEach(pred => {
    const slotTime = new Date(pred.timestamp);
    if (slotTime <= now) return;

    // Work-overlap score across all cities
    const allWork = STATE.cities.every(c => {
      if (c.type === 'planet') {
        return PlanetTime.getPlanetTime(c.planet, slotTime, c.tzOffset || 0).isWorkHour;
      }
      return workStatusAt(c.tz, c.workWeek, slotTime) === 'work';
    });

    // Max Ka risk across all planets with data
    let maxKa = 0;
    planetCities.forEach(c => {
      const cpreds = planetPreds[c.id];
      if (!cpreds) return;
      const match = cpreds.find(p => p.timestamp === pred.timestamp);
      if (match) maxKa = Math.max(maxKa, match.ka_blackout_prob);
    });

    const overlapScore = allWork ? 1 : 0.3;
    const combinedScore = overlapScore * (1 - maxKa);
    candidates.push({ time: slotTime, maxKa, delayMin: pred.delay_min, allWork, combinedScore });
  });

  candidates.sort((a, b) => b.combinedScore - a.combinedScore);

  // Pick top 3 non-adjacent windows (>= 12h apart)
  const windows = [];
  for (const cand of candidates) {
    if (windows.length >= 3) break;
    if (!windows.some(w => Math.abs(w.time - cand.time) < 12 * 3600000)) {
      windows.push(cand);
    }
  }

  if (windows.length === 0) {
    resultEl.innerHTML = `<div class="mp-signal-result" style="opacity:.6">${t('meeting.no_hdtn')}</div>`;
    return;
  }

  const rankSymbols = ['①', '②', '③'];
  let html = `<div class="mp-signal-result">`;
  html += `<div style="font-size:.68rem;opacity:.5;padding:.15rem 0 .35rem;font-weight:600">${t('meeting.best_windows')} — 7-day ML forecast</div>`;

  windows.forEach((w, i) => {
    const dateStr = w.time.toLocaleDateString('en-US',
      { weekday:'short', day:'numeric', month:'short', timeZone:'UTC' });
    const timeUtc = new Intl.DateTimeFormat('en-US',{
      hour:'2-digit', minute:'2-digit', hour12:_use12h(), timeZone:'UTC'
    }).format(w.time);
    const timeStr = dateStr + '  ' + timeUtc + ' UTC';
    const kaDotClass = w.maxKa < 0.10 ? 'hdtn-safe' : w.maxKa < 0.50 ? 'hdtn-warn' : 'hdtn-danger';
    const kaEmoji = w.maxKa < 0.10 ? '●' : w.maxKa < 0.50 ? '⬡' : '■';
    const allStr = w.allWork ? ' <span style="color:rgba(76,175,80,.9)"><i class="fa-solid fa-check" aria-hidden="true"></i> all</span>' : '';
    const ms = w.time.getTime();
    const localTimesStr = `<div class="mp-local-times">${fmtAllCityTimes(ms)}</div>`;
    html += `<div class="mp-window-item" onclick="navigateToWindow(${ms})">` +
      `<span class="mp-window-rank">${rankSymbols[i]}</span>` +
      `<span class="mp-window-time">${timeStr}${localTimesStr}</span>` +
      `<span class="mp-window-meta">` +
        `<span class="${kaDotClass}">${kaEmoji} Ka: ${Math.round(w.maxKa * 100)}%</span>` +
        ` <i class="fa-solid fa-arrow-right" aria-hidden="true"></i> ${w.delayMin.toFixed(1)} min${allStr}` +
      `</span>` +
      `<span class="mp-window-actions">` +
        `<button class="mp-cal-btn" title="${t('meeting.cal_ics')}" aria-label="${t('meeting.cal_ics')}" onclick="event.stopPropagation();downloadICS(new Date(${ms}),60)"><i class="fa-solid fa-calendar-arrow-down" aria-hidden="true"></i> ICS</button>` +
        `<button class="mp-cal-btn" title="${t('meeting.cal_google')}" aria-label="${t('meeting.cal_google')}" onclick="event.stopPropagation();window.open(_gcalUrl(${ms},60),'_blank')">G Cal</button>` +
        `<button class="mp-cal-btn" title="${t('meeting.cal_outlook')}" aria-label="${t('meeting.cal_outlook')}" onclick="event.stopPropagation();window.open(_outlookUrl(${ms},60),'_blank')">Outlook</button>` +
      `</span>` +
      `</div>`;
  });

  html += '</div>';
  resultEl.innerHTML = html;

  // SLM plain-language recommendation (fires async; no-ops if llmApiUrl empty)
  callSlmAssistant(windows, planetCities);
}

function _findBestWindowsNoDtn(resultEl) {
  const allLocs = STATE.cities.map(c => {
    if (c.type === 'planet') {
      return { type:'planet', planet: c.planet, tzOffset: c.tzOffset || 0,
               label: c.customName || c.zoneName || (c.planet.charAt(0).toUpperCase() + c.planet.slice(1)) };
    }
    return { type:'earth', tz: c.tz || c.zoneId || 'UTC',
             workWeek: c.workWeek, label: c.customName || c.city || c.zoneId || 'Earth' };
  });
  const result = PlanetTime.findNextMeetingSlot(allLocs, { from: new Date(), maxDays: 7, maxOptions: 3 });
  if (!result.found || !result.slots.length) {
    resultEl.innerHTML = `<div class="mp-signal-result" style="opacity:.6">${t('meeting.no_overlap',{count:STATE.cities.length})}</div>`;
    return;
  }
  let html = `<div class="mp-signal-result">`;
  html += `<div style="font-size:.68rem;opacity:.5;padding:.15rem 0 .35rem;font-weight:600">${t('meeting.windows_no_dtn')}</div>`;
  const rankSymbols = ['①', '②', '③'];
  result.slots.forEach((slot, i) => {
    const ms = slot.startMs + Math.min(30 * 60000, Math.floor((slot.endMs - slot.startMs) / 2));
    const d = new Date(ms);
    const dateStr = d.toLocaleDateString('en-US',{ weekday:'short', day:'numeric', month:'short', timeZone:'UTC' });
    const timeUtc = new Intl.DateTimeFormat('en-US',{
      hour:'2-digit', minute:'2-digit', hour12:_use12h(), timeZone:'UTC'
    }).format(d);
    const timeStr = dateStr + '  ' + timeUtc + ' UTC';
    const allWork = slot.localTimes?.every(lt => lt.isWorkHour !== false) ?? true;
    const allStr = allWork ? ` <span style="color:rgba(76,175,80,.9)"><i class="fa-solid fa-check" aria-hidden="true"></i> ${t('meeting.windows_all_work')}</span>` : '';
    const localTimesStr = `<div class="mp-local-times">${fmtAllCityTimes(ms)}</div>`;
    html += `<div class="mp-window-item" onclick="navigateToWindow(${ms})">` +
      `<span class="mp-window-rank">${rankSymbols[i] || ''}</span>` +
      `<span class="mp-window-time">${timeStr}${localTimesStr}</span>` +
      `<span class="mp-window-meta">${allStr}</span>` +
      `<span class="mp-window-actions">` +
        `<button class="mp-cal-btn" title="${t('meeting.cal_ics')}" aria-label="${t('meeting.cal_ics')}" onclick="event.stopPropagation();downloadICS(new Date(${ms}),60)"><i class="fa-solid fa-calendar-arrow-down" aria-hidden="true"></i> ICS</button>` +
        `<button class="mp-cal-btn" title="${t('meeting.cal_google')}" aria-label="${t('meeting.cal_google')}" onclick="event.stopPropagation();window.open(_gcalUrl(${ms},60),'_blank')">G Cal</button>` +
      `</span>` +
      `</div>`;
  });
  html += '</div>';
  resultEl.innerHTML = html;
}

// ════════════════════════════════════════════════════════════════════════════
// EXTERNAL LLM PROVIDER (Story 16.2)
// Streaming OpenAI-compatible + Anthropic adapter
// ════════════════════════════════════════════════════════════════════════════

/**
 * Build a rich system+user prompt for the meeting assistant.
 */
function _buildLlmPrompt(windows, planetCities, currentDelayMin, conjunctionInDays) {
  const earthCities = STATE.cities.filter(c => c.type !== 'planet');
  const locations   = [
    ...planetCities.map(c => {
      const name = c.planet.charAt(0).toUpperCase() + c.planet.slice(1);
      return `${name} (${c.zoneName || c.zoneId || 'AMT'})`;
    }),
    ...earthCities.map(c => `${c.city}, ${c.country}`),
  ];

  const windowLines = windows.map((w, i) => {
    const dt  = w.time.toISOString().replace('T',' ').slice(0,16) + ' UTC';
    const ka  = (w.maxKa * 100).toFixed(0) + '%';
    const wrk = w.allWork ? ' — all locations in work hours' : '';
    return `  ${i+1}. ${dt} · Ka-band risk ${ka} · delay ${w.delayMin.toFixed(1)} min one-way${wrk}`;
  }).join('\n');

  const svcDtn = _svcState.dtn ? (_svcState.dtn.ok ? `reachable (${_svcState.dtn.latencyMs} ms)` : 'unreachable') : 'not checked';
  const svcSlm = _svcState.slm ? (_svcState.slm.ok ? (_svcState.slm.warm ? 'warm' : 'cold-start') : 'unreachable') : 'not checked';

  const systemMsg = `You are an interplanetary meeting assistant for InterPlanet. ` +
    `Provide concise, practical meeting window recommendations based on signal delay conditions ` +
    `and work-hour overlap. Respond in 2–3 short paragraphs. Be specific about timing and reasons. ` +
    `Do not repeat data already shown — synthesise and advise.`;

  const userMsg =
    `Locations: ${locations.join(', ')}\n` +
    `Current one-way signal delay: ${currentDelayMin.toFixed(1)} min\n` +
    `Days until next conjunction: ~${conjunctionInDays}\n` +
    `DTN service: ${svcDtn} · SLM service: ${svcSlm}\n` +
    `\nTop meeting windows (7-day ML forecast):\n${windowLines}\n` +
    `\nRecommend the best window and explain the tradeoffs. Flag any conjunction risk or service issues.`;

  return { systemMsg, userMsg };
}

/**
 * Call an OpenAI-compatible endpoint with streaming.
 * Returns an async generator yielding text chunks.
 */
async function* _streamOpenAiCompat(baseUrl, apiKey, model, messages, auth) {
  const headers = { 'Content-Type': 'application/json' };
  if (auth === 'bearer')  headers['Authorization'] = `Bearer ${apiKey}`;
  if (auth === 'api-key') headers['api-key'] = apiKey;

  const r = await fetch(`${baseUrl}/chat/completions`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ model, messages, stream: true, max_tokens: 512 }),
    signal: AbortSignal.timeout(60000),
  });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);

  const reader = r.body.getReader();
  const dec    = new TextDecoder();
  let buf = '';
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buf += dec.decode(value, { stream: true });
    const lines = buf.split('\n');
    buf = lines.pop();
    for (const line of lines) {
      if (!line.startsWith('data: ')) continue;
      const data = line.slice(6).trim();
      if (data === '[DONE]') return;
      try {
        const delta = JSON.parse(data).choices?.[0]?.delta?.content;
        if (delta) yield delta;
      } catch(_) {}
    }
  }
}

/**
 * Call Anthropic Messages API with streaming.
 */
async function* _streamAnthropic(apiKey, model, systemMsg, userMsg) {
  const r = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model, max_tokens: 512, stream: true,
      system: systemMsg,
      messages: [{ role: 'user', content: userMsg }],
    }),
    signal: AbortSignal.timeout(60000),
  });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);

  const reader = r.body.getReader();
  const dec    = new TextDecoder();
  let buf = '';
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buf += dec.decode(value, { stream: true });
    const lines = buf.split('\n');
    buf = lines.pop();
    for (const line of lines) {
      if (!line.startsWith('data: ')) continue;
      try {
        const ev = JSON.parse(line.slice(6));
        if (ev.type === 'content_block_delta') yield ev.delta?.text || '';
      } catch(_) {}
    }
  }
}

/**
 * Gemini uses a different completions endpoint and request format.
 * Adapter to OpenAI-style: sends non-streaming request and returns full text.
 */
async function* _streamGemini(apiKey, model, systemMsg, userMsg) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`;
  const r = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      system_instruction: { parts: [{ text: systemMsg }] },
      contents: [{ role: 'user', parts: [{ text: userMsg }] }],
      generationConfig: { maxOutputTokens: 512 },
    }),
    signal: AbortSignal.timeout(60000),
  });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  const data = await r.json();
  const text = data.candidates?.[0]?.content?.parts?.[0]?.text || '';
  yield text;
}

/**
 * Route to the right provider adapter and stream into resultEl.
 */
async function callExternalLlm(windows, planetCities, resultEl, currentDelayMin, conjunctionInDays) {
  const provCfg = loadLlmProviderCfg();
  if (!provCfg?.provider || !provCfg?.apiKey) return false;  // no provider configured

  const provDef = window.LLM_PROVIDERS[provCfg.provider];
  if (!provDef) return false;

  const baseUrl = provCfg.baseUrl || provDef.baseUrl;
  const model   = provCfg.model   || provDef.models[0] || 'gpt-4o-mini';
  const { systemMsg, userMsg } = _buildLlmPrompt(windows, planetCities, currentDelayMin, conjunctionInDays);

  // Show streaming container
  const textId  = 'mp-llm-stream-' + Date.now();
  resultEl.innerHTML =
    `<div class="mp-llm-result">` +
    `<div class="mp-llm-icon"><i class="fa-solid fa-robot" aria-hidden="true"></i> ${provDef.name}</div>` +
    `<div class="mp-llm-stream" id="${textId}"></div>` +
    `<div class="mp-llm-reasoning" id="mp-llm-reasoning-wrap" hidden>` +
    `<button class="mp-llm-reasoning-toggle" id="mp-llm-reasoning-toggle" aria-expanded="false">` +
    `<i class="fa-solid fa-chevron-right" aria-hidden="true"></i> Show reasoning</button>` +
    `<div class="mp-llm-reasoning-body" id="mp-llm-reasoning-body" hidden></div>` +
    `</div></div>`;

  const textEl = document.getElementById(textId);
  const reasonWrap = document.getElementById('mp-llm-reasoning-wrap');
  const reasonToggle = document.getElementById('mp-llm-reasoning-toggle');
  const reasonBody  = document.getElementById('mp-llm-reasoning-body');

  // Wire up "Explain reasoning" toggle
  const promptFull = `[System]\n${systemMsg}\n\n[User]\n${userMsg}`;
  reasonWrap.hidden = false;
  reasonToggle.addEventListener('click', () => {
    const open = reasonBody.hidden;
    reasonBody.hidden = !open;
    reasonToggle.setAttribute('aria-expanded', String(open));
    reasonToggle.querySelector('i').className = open ? 'fa-solid fa-chevron-down' : 'fa-solid fa-chevron-right';
    if (open && !reasonBody.textContent) reasonBody.textContent = promptFull;
  });

  try {
    let gen;
    if (provCfg.provider === 'anthropic') {
      gen = _streamAnthropic(provCfg.apiKey, model, systemMsg, userMsg);
    } else if (provCfg.provider === 'gemini') {
      gen = _streamGemini(provCfg.apiKey, model, systemMsg, userMsg);
    } else {
      const messages = [
        { role: 'system', content: systemMsg },
        { role: 'user',   content: userMsg   },
      ];
      gen = _streamOpenAiCompat(baseUrl, provCfg.apiKey, model, messages, provDef.auth);
    }

    for await (const chunk of gen) {
      if (textEl) {
        textEl.textContent += chunk;
      }
    }
    return true;
  } catch(e) {
    const msg = e.name === 'TimeoutError' ? 'Request timed out.' : `Error: ${e.message}`;
    if (textEl) textEl.textContent = msg;
    return true;  // handled (don't fall through to SLM)
  }
}

// ════════════════════════════════════════════════════════════════════════════
// SLM AI ASSISTANT (hosted Lambda fallback)
// ════════════════════════════════════════════════════════════════════════════

/**
 * Send scheduled windows to the SLM endpoint and display a plain-language
 * recommendation below the ranked list. No-ops if llmApiUrl is not set.
 *
 * @param {Array} windows  — from findBestWindows() local `windows` array
 * @param {Array} planetCities — STATE.cities filtered to type==='planet'
 */
async function callSlmAssistant(windows, planetCities) {
  const resultEl = document.getElementById('mp-llm-result');
  if (!resultEl || windows.length === 0) { if (resultEl) resultEl.innerHTML = ''; return; }

  // Derive current one-way delay from HDTN cache or PlanetTime library
  let currentDelayMin = 0;
  if (planetCities.length > 0) {
    const p = planetCities[0];
    const cached = _hdtnCache[p.planet];
    if (cached && cached.predictions && cached.predictions.length > 0) {
      currentDelayMin = cached.predictions[0].delay_min;
    } else {
      try {
        currentDelayMin = PlanetTime.lightTravelSeconds('earth', p.planet, new Date()) / 60;
      } catch(_) {}
    }
  }

  // Rough conjunction estimate from current delay
  // At ~22 min delay the planet is near superior conjunction; at ~3 min it's near opposition
  const conjunctionInDays = currentDelayMin > 18
    ? Math.round(Math.max(5, (22 - currentDelayMin) * 15))
    : currentDelayMin < 6
      ? 380
      : 180;

  // Try external LLM provider first (Story 16.2); fall back to hosted SLM if not configured
  const usedExternal = await callExternalLlm(windows, planetCities, resultEl, currentDelayMin, conjunctionInDays);
  if (usedExternal) return;

  // Hosted SLM path — check URL is set
  const url = STATE.settings.llmApiUrl;
  if (!url) { resultEl.innerHTML = ''; return; }

  // Derive max Ka risk across all windows
  const kaRiskMax = windows.reduce((m, w) => Math.max(m, w.maxKa), 0);

  // Build bodies list — SLM supports exactly 2 bodies; prefer first planet + first Earth city
  const earthCities = STATE.cities.filter(c => c.type === 'earth');
  const allBodies = [
    ...planetCities.map(c => {
      const name = c.planet.charAt(0).toUpperCase() + c.planet.slice(1);
      return `${name}/${c.zoneName || c.zoneId || 'AMT'}`;
    }),
    ...earthCities.map(c => `Earth/${c.city}`),
  ];
  if (allBodies.length < 2) allBodies.push('Earth/UTC');
  const bodies = allBodies.slice(0, 2);  // limit to exactly 2

  // Per-window delay trend from HDTN forecast (first planet only)
  let globalTrendStr = '+0.0 min/wk';
  if (planetCities.length > 0) {
    const cached = _hdtnCache[planetCities[0].planet];
    if (cached && cached.predictions && cached.predictions.length >= 2) {
      const preds = cached.predictions;
      const slope = (preds[preds.length-1].delay_min - preds[0].delay_min) /
                    ((preds.length - 1) * 6 / 168);  // per week
      globalTrendStr = (slope >= 0 ? '+' : '') + slope.toFixed(1) + ' min/wk';
    }
  }

  const windowsPayload = windows.map((w, i) => ({
    rank: i + 1,
    start_utc: w.time.toISOString(),
    duration_hours: 6,  // HDTN slots are 6h
    overlap_score: parseFloat(w.combinedScore.toFixed(3)),
    ka_risk: parseFloat(w.maxKa.toFixed(3)),
    delay_trend: globalTrendStr,
  }));

  let locale = 'en';
  try { locale = (window.I18N && window.I18N.getLocale()) || 'en'; } catch(_) {}

  const payload = {
    query_locale: locale,
    bodies,
    current_delay_min: parseFloat(currentDelayMin.toFixed(2)),
    conjunction_in_days: conjunctionInDays,
    ka_risk_max: parseFloat(kaRiskMax.toFixed(3)),
    windows: windowsPayload,
  };

  // Show loading — cold-start can take up to 2 minutes on first request
  resultEl.innerHTML =
    `<div class="mp-llm-loading"><i class="fa-solid fa-robot" aria-hidden="true"></i> Generating recommendation… <span class="mp-llm-loading-hint">(first request may take up to 2 min)</span></div>`;

  try {
    const ctrl = new AbortController();
    const tid = setTimeout(() => ctrl.abort(), 120000);
    const r = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Accept-Language': locale,  // Story 9.1 — locale hint for SLM response language
      },
      body: JSON.stringify(payload),
      signal: ctrl.signal,
    });
    clearTimeout(tid);
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    const data = await r.json();
    // Accept both 'recommendation' (SLM v1) and 'message'/'response' (OpenAI-compatible)
    const recommendation = data.recommendation || data.message || data.response || '';
    if (!recommendation) throw new Error('empty response');
    data.recommendation = recommendation;

    const sessionId = Date.now().toString(36) + Math.random().toString(36).slice(2,6);
    const safe = data.recommendation.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
    resultEl.innerHTML =
      `<div class="mp-llm-result">` +
        `<div class="mp-llm-icon"><i class="fa-solid fa-robot" aria-hidden="true"></i></div>` +
        `<div class="mp-llm-text">${safe}</div>` +
        `<div class="mp-llm-feedback" data-session="${sessionId}">` +
          `<button class="mp-llm-thumb" data-rating="1" aria-label="Helpful">👍</button>` +
          `<button class="mp-llm-thumb" data-rating="-1" aria-label="Not helpful">👎</button>` +
        `</div>` +
      `</div>`;
    resultEl.querySelectorAll('.mp-llm-thumb').forEach(btn => {
      btn.addEventListener('click', () =>
        _sendLlmFeedback(url, sessionId, payload, data.recommendation,
                         parseInt(btn.dataset.rating), resultEl));
    });
  } catch(e) {
    const msg = e.name === 'AbortError' ? 'Assistant timed out — the model may be cold-starting. Please try again.' : 'Assistant unavailable.';
    resultEl.innerHTML =
      `<div class="mp-llm-error"><i class="fa-solid fa-triangle-exclamation" aria-hidden="true"></i> ${msg}</div>`;
  }
}

async function _sendLlmFeedback(url, sessionId, payload, recommendation, rating, resultEl) {
  const fb = resultEl.querySelector('.mp-llm-feedback');
  if (fb) { fb.innerHTML = `<span class="mp-llm-feedback-done">${rating > 0 ? '✓ Thanks!' : '✓ Noted.'}</span>`; }
  try {
    await fetch(url + '/feedback', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ session_id: sessionId, rating, payload, recommendation }),
    });
  } catch(_) {}
}

function navigateToWindow(timeMs) {
  const d = new Date(timeMs);
  const dateInput = document.getElementById('mp-date');
  if (dateInput) {
    dateInput.value = `${d.getUTCFullYear()}-${String(d.getUTCMonth()+1).padStart(2,'0')}-${String(d.getUTCDate()).padStart(2,'0')}`;
    renderMeetingScheduler();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// SEARCH
// ════════════════════════════════════════════════════════════════════════════
let _expandedPlanet = null; // which planet's timezone list is expanded

function openSearch() {
  _expandedPlanet = null;
  const modal = document.getElementById('search-modal');
  modal.classList.add('on');
  document.getElementById('search-input').value = '';
  renderSearchResults('');
  trapFocus(modal);
}

function closeSearch() {
  _expandedPlanet = null;
  document.getElementById('search-modal').classList.remove('on');
  releaseTrap();
}

function renderSearchResults(q) {
  const el = document.getElementById('search-results');
  q = q.toLowerCase().trim();

  // ── Earth cities ──────────────────────────────────────────────────────────
  const cities = q
    ? CITY_DB.filter(c => c.city.toLowerCase().includes(q) || c.country.toLowerCase().includes(q) || c.tz.toLowerCase().includes(q))
    : CITY_DB;

  let html = '';
  cities.slice(0, 50).forEach(c => {
    const offset = getUTCOffsetMin(c.tz);
    const sign = offset >= 0 ? '+' : '';
    const utcStr = `UTC${sign}${(offset/60).toFixed(1).replace('.0','')}`;
    const getDayAbbr = window.I18N ? window.I18N.getDayAbbr.bind(window.I18N) : (i) => ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'][i];
    const sched = WORK_SCHEDULES[c.workWeek] || WORK_SCHEDULES['mon-fri'];
    const wkLabel = `${getDayAbbr(sched.workDays[0])}–${getDayAbbr(sched.workDays[sched.workDays.length-1])}`;
    html += `<div class="sr-item" role="option" aria-selected="false" data-idx="${CITY_DB.indexOf(c)}">
      <div>
        <div class="sr-name">${c.city}</div>
        <div class="sr-sub">${c.country} · ${wkLabel} ${sched.workStart}:00–${sched.workEnd}:00</div>
      </div>
      <div class="sr-tz">${utcStr}</div>
    </div>`;
  });

  // ── Natural satellites (Moon + custom) — with accordion zone picker ─────────
  const localEntries = Object.entries(LOCAL_PLANETS).filter(([k,p]) =>
    !q || p.name.toLowerCase().includes(q) || k.includes(q)
  );
  if (localEntries.length) {
    html += `<div class="sr-section-header" role="presentation">${t('search.satellites_header')}</div>`;
    localEntries.forEach(([k,p]) => {
      const zones = PlanetTime.PLANET_ZONES[k] || p.zones || null;
      const hasZones = !!zones;
      const isExp = _expandedPlanet === k;
      const filteredZones = zones ? zones.filter(z =>
        !q || z.id.toLowerCase().includes(q) || z.name.toLowerCase().includes(q) ||
        p.name.toLowerCase().includes(q) || k.includes(q)
      ) : [];
      const zoneMatch = zones && filteredZones.length > 0;

      html += `<div class="sr-item sr-planet-row" role="option" aria-selected="false" data-planet="${k}">
        <div>
          <div class="sr-name">${p.symbol} ${p.name}</div>
          <div class="sr-sub">${p.notes.split('.')[0]}.</div>
        </div>
        <div class="sr-planet-controls">
          ${hasZones ? `<span class="sr-zones-toggle${isExp?' open':''}" data-toggle="${k}">${isExp?'▾':'▸'} ${t('search.zones')}</span>` : ''}
          <span class="sr-add-btn" data-add-planet="${k}" data-add-offset="0">${t('search.add')}</span>
        </div>
      </div>`;

      if (isExp || (q && zoneMatch)) {
        filteredZones.forEach(z => {
          html += `<div class="sr-item sr-zone" role="option" aria-selected="false" data-planet="${k}" data-offset="${z.offsetHours}" data-zoneid="${z.id}" data-zonename="${z.name}">
            <div>
              <div class="sr-name">${z.id}</div>
              <div class="sr-sub">${z.name}</div>
            </div>
            <div class="sr-tz">${z.offsetHours >= 0 ? '+' : ''}${z.offsetHours}h</div>
          </div>`;
        });
      }
    });
  }

  // ── Planets with accordion zone picker ───────────────────────────────────
  const planets = Object.entries(PlanetTime.PLANETS).filter(([k,p]) =>
    !q || p.name.toLowerCase().includes(q) || k.includes(q)
  );
  if (planets.length) {
    html += `<div class="sr-section-header" role="presentation">${t('search.planets_header')}</div>`;
    planets.forEach(([k, p]) => {
      const zones = (k === 'mars') ? PlanetTime.MARS_ZONES : (PlanetTime.PLANET_ZONES[k] || null);
      const hasZones = !!zones;
      const isExp = _expandedPlanet === k;

      // Filter zones by query if any
      const filteredZones = zones ? zones.filter(z =>
        !q || z.id.toLowerCase().includes(q) || z.name.toLowerCase().includes(q) ||
        p.name.toLowerCase().includes(q) || k.includes(q)
      ) : [];

      // If query matches zones but not planet name, still show planet header
      const planetMatch = !q || p.name.toLowerCase().includes(q) || k.includes(q);
      const zoneMatch   = zones && filteredZones.length > 0;
      if (!planetMatch && !zoneMatch) return;

      html += `<div class="sr-item sr-planet-row" role="option" aria-selected="false" data-planet="${k}">
        <div>
          <div class="sr-name">${p.symbol} ${p.name}</div>
          <div class="sr-sub">${p.notes.split('.')[0]}.</div>
        </div>
        <div class="sr-planet-controls">
          ${hasZones ? `<span class="sr-zones-toggle${isExp?' open':''}" data-toggle="${k}">${isExp?'▾':'▸'} ${t('search.zones')}</span>` : ''}
          <span class="sr-add-btn" data-add-planet="${k}" data-add-offset="0">${t('search.add')}</span>
        </div>
      </div>`;

      // Expanded zone list (or auto-expanded when query hits a zone)
      if (isExp || (q && zoneMatch && !planetMatch)) {
        filteredZones.forEach(z => {
          html += `<div class="sr-item sr-zone" role="option" aria-selected="false" data-planet="${k}" data-offset="${z.offsetHours}" data-zoneid="${z.id}" data-zonename="${z.name}">
            <div>
              <div class="sr-name">${z.id}</div>
              <div class="sr-sub">${z.name}</div>
            </div>
            <div class="sr-tz">${z.offsetHours >= 0 ? '+' : ''}${z.offsetHours}h</div>
          </div>`;
        });
      }
    });
  }

  el.innerHTML = html || `<div style="padding:1rem;opacity:.4;text-align:center;font-size:.85rem">${t('search.no_results')}</div>`;

  // Earth city clicks
  el.querySelectorAll('.sr-item[data-idx]').forEach(item => {
    item.addEventListener('click', () => {
      const dbEntry = CITY_DB[+item.dataset.idx];
      const already = STATE.cities.some(c => c.type==='earth' && c.tz===dbEntry.tz && c.city===dbEntry.city);
      if (!already) addEarthCity(dbEntry);
      closeSearch();
    });
  });

  // Zone toggle buttons — expand/collapse in-place
  el.querySelectorAll('[data-toggle]').forEach(btn => {
    btn.addEventListener('click', e => {
      e.stopPropagation();
      const k = btn.dataset.toggle;
      _expandedPlanet = (_expandedPlanet === k) ? null : k;
      renderSearchResults(document.getElementById('search-input').value);
    });
  });

  // "Add" buttons (planet at prime meridian, or local body)
  el.querySelectorAll('[data-add-planet]').forEach(btn => {
    btn.addEventListener('click', e => {
      e.stopPropagation();
      const k = btn.dataset.addPlanet;
      const off = parseFloat(btn.dataset.addOffset) || 0;
      const already = STATE.cities.some(c => c.type==='planet' && c.planet===k && !c.zoneId);
      if (!already) addPlanet(k, off, null, null);
      closeSearch();
    });
  });

  // Zone item clicks — add with that specific zone
  el.querySelectorAll('.sr-item.sr-zone').forEach(item => {
    item.addEventListener('click', () => {
      const k = item.dataset.planet;
      const off = parseFloat(item.dataset.offset) || 0;
      const zoneId = item.dataset.zoneid || null;
      const zoneName = item.dataset.zonename || null;
      const already = STATE.cities.some(c => c.type==='planet' && c.planet===k && c.zoneId===zoneId);
      if (!already) addPlanet(k, off, zoneId, zoneName);
      closeSearch();
    });
  });
}

// ════════════════════════════════════════════════════════════════════════════
// SETTINGS
// ════════════════════════════════════════════════════════════════════════════
function openSettings() {
  const panel = document.getElementById('settings-panel');
  panel.classList.add('on');
  document.getElementById('settings-ctl').setAttribute('aria-expanded', 'true');
  syncSettingsUI();
  updateNotifDot();
  trapFocus(panel);
}

// ════════════════════════════════════════════════════════════════════════════
// ADVANCED CITY SEARCH (extended WorldCityLocations database)
// ════════════════════════════════════════════════════════════════════════════
(function initAdvancedCitySearch() {
  const toggle       = document.getElementById('adv-city-toggle');
  const panel        = document.getElementById('adv-city-panel');
  const countrySelect= document.getElementById('adv-country-select');
  const cityInput    = document.getElementById('adv-city-input');
  const cityResults  = document.getElementById('adv-city-results');

  if (!toggle || !panel) return;

  // Inlined to avoid CORS block on file:// protocol
  const _COUNTRY_INDEX_INLINE = {"AF":"Afghanistan","AL":"Albania","DZ":"Algeria","AD":"Andorra","AO":"Angola","AR":"Argentina","AM":"Armenia","AU":"Australia","AT":"Austria","AZ":"Azerbaijan","BH":"Bahrain","BD":"Bangladesh","BB":"Barbados","BY":"Belarus","BE":"Belgium","BZ":"Belize","BJ":"Benin","BT":"Bhutan","BO":"Bolivia","BA":"Bosnia and Herzegovina","BR":"Brazil","BN":"Brunei","BG":"Bulgaria","KH":"Cambodia","CM":"Cameroon","CA":"Canada","CV":"Cape Verde","CF":"Central African Republic","TD":"Chad","CL":"Chile","CN":"China","CO":"Colombia","KM":"Comoros","CR":"Costa Rica","HR":"Croatia","CU":"Cuba","CY":"Cyprus","CZ":"Czech Republic","DK":"Denmark","DJ":"Djibouti","EC":"Ecuador","SV":"El Salvador","GQ":"Equatorial Guinea","ER":"Eritrea","EE":"Estonia","ET":"Ethiopia","FJ":"Fiji","FI":"Finland","FR":"France","GA":"Gabon","GM":"Gambia, The","GE":"Georgia","DE":"Germany","GH":"Ghana","GR":"Greece","GD":"Grenada","GT":"Guatemala","GY":"Guyana","HT":"Haiti","HN":"Honduras","HU":"Hungary","IS":"Iceland","IN":"India","ID":"Indonesia","IR":"Iran","IQ":"Iraq","IE":"Ireland","IL":"Israel","IT":"Italy","JM":"Jamaica","JP":"Japan","JO":"Jordan","KZ":"Kazakhstan","KE":"Kenya","KI":"Kiribati","KR":"Korea, South","KW":"Kuwait","LV":"Latvia","LB":"Lebanon","LR":"Liberia","LY":"Libya","LI":"Liechtenstein","LT":"Lithuania","LU":"Luxembourg","MK":"Macedonia","MW":"Malawi","MY":"Malaysia","MV":"Maldives","ML":"Mali","MT":"Malta","MH":"Marshall Islands","MR":"Mauritania","MU":"Mauritius","MX":"Mexico","FM":"Micronesia","MD":"Moldova","MC":"Monaco","MA":"Morocco","MZ":"Mozambique","MM":"Myanmar","NP":"Nepal","NL":"Netherlands","NZ":"New Zealand","NI":"Nicaragua","NE":"Niger","NG":"Nigeria","NO":"Norway","OM":"Oman","PK":"Pakistan","PW":"Palau","PA":"Panama","PG":"Papua New Guinea","PY":"Paraguay","PE":"Peru","PH":"Philippines","PL":"Poland","PT":"Portugal","QA":"Qatar","RO":"Romania","RU":"Russia","KN":"Saint Kitts and Nevis","WS":"Samoa","ST":"Sao Tome and Principe","SN":"Senegal","SC":"Seychelles","SI":"Slovenia","SB":"Solomon Islands","SO":"Somalia","ZA":"South Africa","ES":"Spain","LK":"Sri Lanka","SD":"Sudan","SR":"Suriname","SZ":"Swaziland","SE":"Sweden","CH":"Switzerland","SY":"Syria","TJ":"Tajikistan","TZ":"Tanzania","TH":"Thailand","TG":"Togo","TO":"Tonga","TN":"Tunisia","TR":"Turkey","TV":"Tuvalu","UG":"Uganda","UA":"Ukraine","GB":"United Kingdom","US":"United States","UY":"Uruguay","VE":"Venezuela","VN":"Vietnam","YE":"Yemen","ZM":"Zambia","ZW":"Zimbabwe"};

  let _countryCache = null;   // { ISO2: "Country Name" }
  let _cityCache    = {};     // { ISO2: [{n,la,lo,z}] }

  // Populate country list from inline data (no fetch needed — avoids CORS on file://)
  function ensureCountryIndex() {
    if (_countryCache) return;
    _countryCache = _COUNTRY_INDEX_INLINE;
    Object.entries(_countryCache)
      .sort((a, b) => a[1].localeCompare(b[1]))
      .forEach(([iso2, name]) => {
        const opt = document.createElement('option');
        opt.value = iso2;
        opt.textContent = name;
        countrySelect.appendChild(opt);
      });
  }

  toggle.addEventListener('click', async () => {
    const open = toggle.getAttribute('aria-expanded') === 'true';
    toggle.setAttribute('aria-expanded', String(!open));
    panel.hidden = open;
    if (!open) ensureCountryIndex();
  });

  countrySelect.addEventListener('change', async () => {
    const iso2 = countrySelect.value;
    cityInput.value = '';
    cityResults.innerHTML = '';
    cityInput.disabled = !iso2;
    if (!iso2) return;

    // Load country city file (cached)
    if (!_cityCache[iso2]) {
      cityInput.disabled = true;
      try {
        const r = await fetch(`assets/cities/${iso2}.json`);
        _cityCache[iso2] = await r.json();
      } catch(e) {
        cityResults.innerHTML = `<div style="padding:.5rem;opacity:.5;font-size:.78rem">Failed to load city list.</div>`;
        return;
      }
    }
    cityInput.disabled = false;
    cityInput.focus();
    renderAdvCities('');
  });

  cityInput.addEventListener('input', () => renderAdvCities(cityInput.value));

  function renderAdvCities(q) {
    const iso2 = countrySelect.value;
    const cities = _cityCache[iso2] || [];
    const lq = q.toLowerCase().trim();
    const matches = lq
      ? cities.filter(c => c.n.toLowerCase().includes(lq)).slice(0, 40)
      : cities.slice(0, 40);

    if (!matches.length) {
      cityResults.innerHTML = `<div style="padding:.5rem;opacity:.4;font-size:.78rem">No cities found.</div>`;
      return;
    }
    cityResults.innerHTML = matches.map((c, i) =>
      `<div class="adv-city-item" data-adv="${i}" role="option" aria-selected="false">
        <span>${c.n}</span>
        <span class="adv-city-tz">${c.z || ''}</span>
      </div>`
    ).join('');
    cityResults.querySelectorAll('.adv-city-item').forEach((el, i) => {
      el.addEventListener('click', () => {
        const city = matches[i];
        // Find nearest CITY_DB entry for fallback tz if missing
        let tz = city.z;
        if (!tz) {
          const nearest = CITY_DB.reduce((best, c) => {
            const d = Math.hypot(c.lat - city.la, c.lon - city.lo);
            return d < best.d ? { c, d } : best;
          }, { c: CITY_DB[0], d: Infinity }).c;
          tz = nearest.tz;
        }
        const countryName = (_countryCache && _countryCache[countrySelect.value]) || '';
        addCityFromData({
          type: 'earth', city: city.n, country: countryName,
          tz, lat: city.la, lon: city.lo, pop: 0, workWeek: 'mon-fri',
        });
        closeSearch();
      });
    });
  }
})();

function updateNotifDot() {
  // Show orange dot on settings button when cookie consent not yet decided
  const btn = document.getElementById('settings-ctl');
  if (STATE.cookieConsent === null) {
    btn.classList.add('has-notif');
    document.getElementById('cookie-inline').style.display = 'block';
  } else {
    btn.classList.remove('has-notif');
    document.getElementById('cookie-inline').style.display = 'none';
  }
}

function closeSettings() {
  document.getElementById('settings-panel').classList.remove('on');
  document.getElementById('settings-ctl').setAttribute('aria-expanded', 'false');
  releaseTrap();
}

// ── Keyboard shortcuts panel ───────────────────────────────────────────────

function openKbd() {
  const panel = document.getElementById('kbd-panel');
  if (!panel) return;
  panel.classList.add('on');
  document.getElementById('kbd-btn').setAttribute('aria-expanded', 'true');
  document.getElementById('kbd-btn').classList.add('active');
  const closeBtn = document.getElementById('kbd-close');
  if (closeBtn) closeBtn.focus();
}

function closeKbd() {
  const panel = document.getElementById('kbd-panel');
  if (!panel || !panel.classList.contains('on')) return;
  panel.classList.remove('on');
  document.getElementById('kbd-btn').setAttribute('aria-expanded', 'false');
  document.getElementById('kbd-btn').classList.remove('active');
}

function toggleKbd() {
  const panel = document.getElementById('kbd-panel');
  if (panel && panel.classList.contains('on')) { closeKbd(); } else { openKbd(); }
}

function syncSettingsUI() {
  const s = STATE.settings;
  document.getElementById('s-time').checked    = s.showTime;
  document.getElementById('s-tz').checked      = s.showTZ;
  document.getElementById('s-city').checked    = s.showCity;
  document.getElementById('s-country').checked = s.showCountry;
  document.getElementById('s-label').checked   = s.showLabel;
  document.getElementById('s-hourly').checked  = s.showHourly;
  document.getElementById('s-work').checked    = s.showWork;
  document.getElementById('s-weather').checked = s.showWeather;
  document.getElementById('s-sunmoon').checked = s.showSunMoon;
  document.getElementById('s-ping').checked    = s.showPing;
  document.getElementById('s-horiz').checked   = s.horiz;
  const compactEl = document.getElementById('s-compact');
  if (compactEl) compactEl.checked = s.compact || false;
  const reduceEl = document.getElementById('s-reduce-motion');
  if (reduceEl) reduceEl.checked = s.reduceMotion || false;

  const ckStatus = document.getElementById('ck-status');
  if (ckStatus) ckStatus.textContent =
    STATE.cookieConsent === true ? t('settings.cookie_accepted') :
    STATE.cookieConsent === false ? t('settings.cookie_declined') : t('settings.cookie_not_set');

  const hdtnUrlEl = document.getElementById('hdtn-api-url');
  if (hdtnUrlEl) hdtnUrlEl.value = s.hdtnApiUrl || '';

  const llmUrlEl = document.getElementById('llm-api-url');
  if (llmUrlEl) llmUrlEl.value = s.llmApiUrl || '';

  const weatherUrlEl = document.getElementById('weather-api-url');
  if (weatherUrlEl) weatherUrlEl.value = s.weatherApiUrl || '';

  const themeEl = document.getElementById('s-theme');
  if (themeEl) themeEl.value = s.theme || 'system';

  const verEl = document.getElementById('sp-lib-version');
  if (verEl) verEl.textContent = `planet-time.js v${PlanetTime.VERSION}`;

  // Time format segmented control
  const tfVal = s.timeFormat || '24h';
  document.querySelectorAll('#time-format-seg .sp-seg-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.val === tfVal);
  });

  // AI Provider — restore saved provider selection
  _syncProviderUI();

  // 58.8 — simple/advanced mode toggle
  const sp = document.getElementById('settings-panel');
  if (sp) sp.classList.toggle('settings-simple', !!s.simpleMode);
  const simpleModeVal = s.simpleMode ? 'simple' : 'advanced';
  document.querySelectorAll('#detail-mode-seg .sp-seg-btn').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.val === simpleModeVal);
  });
}

let _mqlTheme = null;
let _onMqlTheme = null;
function applyTheme(theme) {
  if (_mqlTheme && _onMqlTheme) {
    _mqlTheme.removeEventListener('change', _onMqlTheme);
    _mqlTheme = null; _onMqlTheme = null;
  }
  if (theme === 'light') {
    document.documentElement.classList.add('light-mode');
  } else if (theme === 'dark') {
    document.documentElement.classList.remove('light-mode');
  } else { // 'system'
    _mqlTheme = window.matchMedia('(prefers-color-scheme: light)');
    _onMqlTheme = () =>
      document.documentElement.classList.toggle('light-mode', _mqlTheme.matches);
    _onMqlTheme(); // apply immediately
    _mqlTheme.addEventListener('change', _onMqlTheme);
  }
}

function applySettings() {
  applyTheme(STATE.settings.theme || 'system');
  document.documentElement.classList.toggle('reduce-motion', !!STATE.settings.reduceMotion);
  const s = STATE.settings;
  const wrap = document.getElementById('cities-wrap');
  if (s.horiz) {
    wrap.classList.add('horiz');
    wrap.classList.remove('vert-forced');
  } else {
    wrap.classList.remove('horiz');
    wrap.classList.add('vert-forced');
  }
  if (s.compact) wrap.classList.add('compact');
  else wrap.classList.remove('compact');
  // Update layout icon and aria-pressed
  const layoutBtn = document.getElementById('layout-ctl');
  layoutBtn.innerHTML = s.horiz
    ? '<i class="fa-solid fa-arrows-left-right" aria-hidden="true"></i>'
    : '<i class="fa-solid fa-arrows-up-down" aria-hidden="true"></i>';
  layoutBtn.setAttribute('aria-pressed', String(s.horiz));
  STATE.cities.forEach(c => updateCityDisplay(c));
  // HDTN forecast visibility (compact handled by CSS; showPing toggles manually)
  STATE.cities.forEach(city => {
    if (city.type !== 'planet') return;
    const el = document.getElementById(`hdtn-${city.id}`);
    if (!el) return;
    if (!s.showPing) el.style.display = 'none';
    else if (el.textContent) el.style.display = '';
  });
  equalizeInfoHeights();
}

function bindSettingsToggles() {
  const map = {
    's-time':'showTime','s-tz':'showTZ','s-city':'showCity','s-country':'showCountry',
    's-label':'showLabel','s-hourly':'showHourly','s-work':'showWork',
    's-weather':'showWeather','s-sunmoon':'showSunMoon','s-ping':'showPing',
    's-compact':'compact','s-reduce-motion':'reduceMotion',
  };
  Object.entries(map).forEach(([id,key]) => {
    document.getElementById(id).addEventListener('change', e => {
      STATE.settings[key] = e.target.checked;
      applySettings(); saveState(); syncHash();
    });
  });
  document.getElementById('s-horiz').addEventListener('change', e => {
    STATE.settings.horiz = e.target.checked;
    applySettings(); saveState(); syncHash();
  });
  document.getElementById('s-theme').addEventListener('change', e => {
    STATE.settings.theme = e.target.value;
    applySettings(); saveState(); syncHash();
  });

  // 58.8 — detail level segmented control
  document.querySelectorAll('#detail-mode-seg .sp-seg-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      STATE.settings.simpleMode = btn.dataset.val === 'simple';
      syncSettingsUI(); saveState();
    });
  });
}

// ════════════════════════════════════════════════════════════════════════════
// CONFIG EXPORT / IMPORT / SHARE
// ════════════════════════════════════════════════════════════════════════════
function getCompactCities() {
  return STATE.cities.map(c => {
    if (c.type === 'planet') {
      const e = { type: 'planet', planet: c.planet };
      if (c.tzOffset) e.tzOffset = c.tzOffset;
      if (c.zoneId)   e.zoneId = c.zoneId;
      if (c.zoneName) e.zoneName = c.zoneName;
      return e;
    }
    // Earth — drop everything CITY_DB provides on load
    const e = { type: 'earth', city: c.city };
    if (c.customName) e.customName = c.customName;
    const inDb = CITY_DB.find(d => d.city === c.city && d.tz === c.tz);
    if (!inDb) {
      // Non-CITY_DB city (GPS / manual) — must store coords
      e.tz = c.tz; e.lat = c.lat; e.lon = c.lon;
      e.country = c.country; e.workWeek = c.workWeek || 'mon-fri';
    }
    return e;
  });
}

function loadCityFromCompact(entry) {
  if (!entry || typeof entry !== 'object') return;
  if (entry.type === 'planet') {
    addPlanet(entry.planet, entry.tzOffset || 0, entry.zoneId || null,
              entry.zoneName || null, { silent: true });
    return;
  }
  const db = CITY_DB.find(d => d.city === entry.city);
  if (db) {
    addCityFromData({ type: 'earth', city: db.city, country: db.country,
      tz: db.tz, lat: db.lat, lon: db.lon, pop: db.pop || 0,
      workWeek: db.workWeek, customName: entry.customName || null });
  } else if (entry.tz) {
    addCityFromData({ type: 'earth', city: entry.city, country: entry.country || '',
      tz: entry.tz, lat: entry.lat || 0, lon: entry.lon || 0,
      workWeek: entry.workWeek || 'mon-fri', customName: entry.customName || null });
  }
}

function getConfigJSON() {
  return {
    version: 1,
    cities: STATE.cities.map(c => ({
      type: c.type, tz: c.tz, city: c.city, country: c.country,
      lat: c.lat, lon: c.lon, pop: c.pop||0, workWeek: c.workWeek,
      customName: c.customName, planet: c.planet,
      tzOffset: c.tzOffset||0, zoneId: c.zoneId, zoneName: c.zoneName,
    })),
    settings: { ...STATE.settings },
  };
}

function applyConfig(cfg) {
  if (!cfg || !cfg.cities) { return; }
  // Remove existing cities
  STATE.cities.forEach(c => { if (c.refreshTimer) clearInterval(c.refreshTimer); });
  STATE.cities = [];
  document.querySelectorAll('.city-col').forEach(el => el.remove());
  // Apply settings
  if (cfg.settings) Object.assign(STATE.settings, cfg.settings);
  // Restore cities
  cfg.cities.forEach(d => addCityFromData(d));
  syncSettingsUI(); applySettings(); syncHash();
}

function showConfirm(onOk) {
  const el = document.getElementById('modal-confirm');
  if (window.I18N) window.I18N.applyTranslations();
  el.style.display = 'flex';
  trapFocus(el);
  document.getElementById('mc-ok').onclick = () => { hideConfirm(); onOk(); };
  document.getElementById('mc-cancel').onclick = hideConfirm;
}
function hideConfirm() {
  document.getElementById('modal-confirm').style.display = 'none';
  releaseTrap();
}

function showToast(msg) {
  const el = document.getElementById('share-toast');
  el.textContent = msg;
  el.style.opacity = '1';
  el.style.transform = 'translateX(-50%) translateY(0)';
  setTimeout(() => {
    el.style.opacity = '0';
    el.style.transform = 'translateX(-50%) translateY(20px)';
  }, 3500);
}

// ════════════════════════════════════════════════════════════════════════════
// EVENTS
// ════════════════════════════════════════════════════════════════════════════
document.getElementById('add-col').addEventListener('click', openSearch);
document.getElementById('search-close').addEventListener('click', closeSearch);
document.getElementById('search-modal').addEventListener('click', e => {
  if (e.target === document.getElementById('search-modal')) closeSearch();
});
document.getElementById('search-input').addEventListener('input', e => {
  renderSearchResults(e.target.value);
});

document.getElementById('layout-ctl').addEventListener('click', () => {
  STATE.settings.horiz = !STATE.settings.horiz;
  STATE._manualLayoutOverride = true;
  document.getElementById('s-horiz').checked = STATE.settings.horiz;
  applySettings(); saveState(); syncHash();
});
document.getElementById('settings-ctl').addEventListener('click', () => {
  document.getElementById('settings-panel').classList.contains('on') ? closeSettings() : openSettings();
});
document.getElementById('sp-close').addEventListener('click', closeSettings);
document.getElementById('kbd-btn').addEventListener('click', toggleKbd);
document.getElementById('kbd-close').addEventListener('click', closeKbd);

function openMeetingPanel() {
  if (window.innerWidth < 768) {
    document.body.classList.add('scheduler-fullscreen');
    history.pushState({ schedulerOpen: true }, '', location.href); // 58.5
  }
  const panel = document.getElementById('meeting-panel');
  const dateInput = document.getElementById('mp-date');
  if (dateInput && !dateInput.value) {
    const now = new Date();
    dateInput.value = `${now.getUTCFullYear()}-${String(now.getUTCMonth()+1).padStart(2,'0')}-${String(now.getUTCDate()).padStart(2,'0')}`;
  }
  renderMeetingScheduler();
  panel.classList.add('on');
  // Warm-up ping: trigger Lambda container before user clicks Best Windows
  const _slmUrl = STATE.settings.llmApiUrl;
  if (_slmUrl) fetch(_slmUrl, { method: 'HEAD' }).catch(() => {});
  document.getElementById('meeting-btn').setAttribute('aria-expanded', 'true');
  // Keep fullscreen link pointing to the current config hash
  const fsl = document.getElementById('mp-fullscreen-link');
  if (fsl) fsl.href = '?schedule=fullscreen' + location.hash;
  // Back button: strip ?schedule=fullscreen, keep city hash
  const backBtn = document.getElementById('mp-back-btn');
  if (backBtn) backBtn.href = location.hash || './';
  // Auto-refresh HDTN if cache is stale when panel opens
  if (STATE.settings.hdtnApiUrl && STATE.cities.some(c => c.type === 'planet')) {
    refreshAllHdtn();
  }
  trapFocus(panel);
  // Start service status polling (Story 16.3)
  if (_svcStatusTimer) clearInterval(_svcStatusTimer);
  refreshSvcStatus();  // immediate check
  _svcStatusTimer = setInterval(refreshSvcStatus, 60000);
}
function closeMeetingPanel() {
  document.body.classList.remove('scheduler-fullscreen');
  document.getElementById('meeting-panel').classList.remove('on');
  document.getElementById('meeting-btn').setAttribute('aria-expanded', 'false');
  releaseTrap();
  // Stop status polling
  if (_svcStatusTimer) { clearInterval(_svcStatusTimer); _svcStatusTimer = null; }
}

document.getElementById('meeting-btn').addEventListener('click', () => {
  const isOpen = document.getElementById('meeting-panel').classList.contains('on');
  if (isOpen) closeMeetingPanel(); else openMeetingPanel();
});

document.getElementById('mp-date').addEventListener('change', () => {
  renderMeetingScheduler();
});

document.getElementById('mp-prev').addEventListener('click', () => _mpShiftDate(-1));
document.getElementById('mp-next').addEventListener('click', () => _mpShiftDate(1));

document.querySelectorAll('.mp-days-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.mp-days-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    _mpDays = parseInt(btn.dataset.days, 10);
    renderMeetingScheduler();
  });
});

document.getElementById('mp-overlap-btn').addEventListener('click', () => {
  const resultEl = document.getElementById('mp-overlap-result');
  const cities = STATE.cities;
  if (cities.length < 2) {
    resultEl.innerHTML = `<span class="mp-overlap-none">${t('meeting.min_cities')}</span>`;
    return;
  }
  resultEl.innerHTML = `<span style="opacity:.5">${t('meeting.scanning')}</span>`;
  // Scan asynchronously so the UI updates
  setTimeout(() => {
    const from = new Date();
    const next = findNextOverlap(cities, from);
    if (next) {
      const _loc = window.I18N ? window.I18N.getLocale() : 'en-US';
      const fmt = new Intl.DateTimeFormat(_loc,{
        weekday:'short', month:'short', day:'numeric',
        hour:'2-digit', minute:'2-digit', hour12:_use12h(), timeZone:'UTC'
      }).format(next);

      // Fairness: how many participants are in work hours at this time
      const inWork = cities.map(c =>
        c.type === 'planet'
          ? PlanetTime.getPlanetTime(c.planet, next, c.tzOffset || 0).isWorkHour
          : workStatusAt(c.tz, c.workWeek, next) === 'work'
      );
      const inWorkCount = inWork.filter(Boolean).length;
      const fairnessPct = Math.round(100 * inWorkCount / cities.length);
      const fairnessIcon = fairnessPct >= 80 ? '🟢' : fairnessPct >= 50 ? '🟡' : '🔴';

      const nextMs = next.getTime();
      const _pc = cities.filter(c => c.type === 'planet');
      const _delayMinSnap = _pc.length
        ? PlanetTime.lightTravelSeconds('earth', _pc[0].planet, next) / 60 : 0;
      const localTimesHtml = `<div class="mp-local-times">${fmtAllCityTimes(nextMs)}</div>`;
      resultEl.innerHTML =
        `<div class="mp-overlap-header">` +
        `<span class="mp-overlap-found">${t('meeting.overlap_found',{fmt})}</span>` +
        `<span class="mp-fairness-badge" style="font-size:.7rem;opacity:.75;margin-left:.5rem">${fairnessIcon} ${inWorkCount}/${cities.length} in work hours</span>` +
        `</div>` +
        localTimesHtml +
        `<div class="mp-action-btns">` +
        `<button class="mp-action-btn mp-ics-btn" onclick="downloadICS(new Date(${nextMs}),60)"><i class="fa-solid fa-calendar-arrow-down" aria-hidden="true"></i> .ics</button>` +
        `<button class="mp-action-btn mp-ltx-btn" onclick="openLtxMeeting(${nextMs},${_delayMinSnap},STATE.cities)" title="Open LTX structured meeting runner"><i class="fa-solid fa-satellite-dish" aria-hidden="true"></i> LTX</button>` +
        `</div>`;

      // Rotation preview: append asynchronously to avoid blocking render
      setTimeout(() => renderRotationPreview(cities, next, resultEl), 50);

      // Also update the date picker to jump to that day
      const dateInput = document.getElementById('mp-date');
      if (dateInput) {
        dateInput.value = `${next.getUTCFullYear()}-${String(next.getUTCMonth()+1).padStart(2,'0')}-${String(next.getUTCDate()).padStart(2,'0')}`;
        renderMeetingScheduler();
      }
    } else {
      resultEl.innerHTML = `<span class="mp-overlap-none">${t('meeting.no_overlap',{count:cities.length})}</span>`;
    }
  }, 30);
});
document.getElementById('mp-close').addEventListener('click', () => {
  closeMeetingPanel();
});

// Best windows button
document.getElementById('mp-signal-btn').addEventListener('click', () => {
  document.getElementById('mp-overlap-result').innerHTML = '';
  document.getElementById('mp-async-result').innerHTML = '';
  findBestWindows();
});

// ── Async send-window planner (Story 7.1) ────────────────────────────────────
// "Send now?" — find when to send an async message so it arrives at the
// start of each recipient's work day, accounting for signal propagation delay.

function _workDayStart(city, d) {
  // Returns the UTC time of the start of city's next work day (from d)
  const STEP = 5 * 60000; // 5-min steps
  const MAX  = d.getTime() + 3 * 24 * 3600000;
  for (let t = d.getTime(); t < MAX; t += STEP) {
    const ts = new Date(t);
    let status;
    if (city.type === 'planet') {
      const pt = PlanetTime.getPlanetTime(city.planet, ts, city.tzOffset || 0);
      status = pt.isWorkHour ? 'work' : 'rest';
    } else {
      status = workStatusAt(city.tz, city.workWeek, ts);
    }
    if (status === 'work') return ts;
  }
  return null;
}

function findAsyncWindows(cities, currentDelayMin) {
  // For each non-sender city, find the optimal send time so the message
  // arrives at the start of their work day.
  // Assumes the first city is the "sender" (or the user's location).
  // delayMin is one-way delay; if 0 (Earth-only) just show work-day start.
  const results = [];
  const now = new Date();
  const delayMs = (currentDelayMin || 0) * 60000;
  const senderTz = cities[0]?.tz || null;

  cities.forEach((city, i) => {
    const name = city.customName || city.city || city.planet;
    const cityTz = city.tz || null;
    // Find when the work day starts for this city
    const arrivalTime = _workDayStart(city, now);
    if (!arrivalTime) { results.push({ name, sendAt: null, arrivalAt: null, cityTz, senderTz }); return; }

    // Ideal send time = work-day start minus one-way delay (so message arrives at start)
    const sendAt = delayMs > 0 ? new Date(arrivalTime.getTime() - delayMs) : arrivalTime;
    const sendPast = sendAt < now;
    results.push({ name, sendAt, arrivalAt: arrivalTime, sendPast, delayMin: currentDelayMin || 0, cityTz, senderTz });
  });
  return results;
}

function renderAsyncResult(cities, currentDelayMin) {
  const resultEl = document.getElementById('mp-async-result');
  if (!resultEl) return;
  if (cities.length < 1) { resultEl.innerHTML = `<span style="opacity:.5">${t('meeting.no_cities')}</span>`; return; }

  const windows = findAsyncWindows(cities, currentDelayMin);
  const locale  = window.I18N ? window.I18N.getLocale() : 'en-US';
  const fmtTime = (d, tz) => new Intl.DateTimeFormat(locale, {
    weekday:'short', month:'short', day:'numeric',
    hour:'2-digit', minute:'2-digit', hour12:_use12h(),
    timeZone: tz || 'UTC', timeZoneName:'short',
  }).format(d);

  let html = `<div class="mp-async-result">`;
  html += `<div class="mp-async-hdr">${t('meeting.async_hdr')}</div>`;

  windows.forEach(w => {
    if (!w.sendAt) {
      html += `<div class="mp-async-row"><span class="mp-async-name">${w.name}</span>` +
        `<span class="mp-async-note">${t('meeting.async_no_window')}</span></div>`;
      return;
    }
    const sendClass = w.sendPast ? 'mp-async-past' : 'mp-async-future';
    const delayNote = w.delayMin > 0 ? ` <span class="mp-async-delay">(+${w.delayMin.toFixed(0)} min in transit)</span>` : '';
    html += `<div class="mp-async-row">` +
      `<span class="mp-async-name">${w.name}</span>` +
      `<span class="${sendClass}">` +
        `${w.sendPast ? t('meeting.async_send_now') : t('meeting.async_send_at', { time: fmtTime(w.sendAt, w.senderTz) })}` +
        delayNote +
      `</span>` +
      ` <span class="mp-async-arrives">${t('meeting.async_arrives', { time: fmtTime(w.arrivalAt, w.cityTz) })}</span>` +
      `</div>`;
  });

  html += `</div>`;
  resultEl.innerHTML = html;
}

// ════════════════════════════════════════════════════════════════════════════
// AGENTIC MEETING MODE (Story 16.4)
// ════════════════════════════════════════════════════════════════════════════

/**
 * Dual-agent autonomous meeting negotiation.
 *
 * Agent A represents the first location; Agent B the second.
 * They exchange chat-bubble messages (rule-based, up to 3 rounds)
 * and reach an agreed meeting time using findNextMeetingSlot().
 */
async function runAgentNegotiation() {
  const resultEl = document.getElementById('mp-agent-result');
  if (!resultEl) return;

  resultEl.innerHTML = '';
  const cities = STATE.cities;
  if (cities.length < 2) {
    resultEl.innerHTML = `<div class="mp-agent-no-slot">${t('meeting.agent_no_cities')}</div>`;
    return;
  }

  function _cityToLoc(c) {
    if (c.type === 'planet') {
      return { type:'planet', planet: c.planet, tzOffset: c.tzOffset || 0,
               label: c.zoneName || (c.planet.charAt(0).toUpperCase() + c.planet.slice(1)) };
    }
    return { type:'earth', tz: c.tz || c.zoneId || 'UTC',
             workWeek: c.workWeek, label: c.city || c.zoneId || 'Earth' };
  }

  const locs = cities.map(_cityToLoc);
  const labelA = locs[0].label;
  const labelB = locs[1].label;

  function _fmtUtc(ms) {
    const d = new Date(ms);
    const loc = window.I18N ? window.I18N.getLocale() : 'en-US';
    return new Intl.DateTimeFormat(loc, {
      weekday:'short', month:'short', day:'numeric',
      hour:'2-digit', minute:'2-digit', hour12:_use12h(), timeZone:'UTC'
    }).format(d) + ' UTC';
  }

  function _fmtLocal(ms, loc) {
    const d = new Date(ms);
    if (loc.type === 'planet') {
      try {
        const pt = PlanetTime.getPlanetTime(loc.planet, d, loc.tzOffset || 0);
        const h12 = _use12h();
        let tStr;
        if (h12) {
          const h = pt.hour % 12 || 12;
          const ampm = pt.hour < 12 ? ' AM' : ' PM';
          tStr = `${String(h).padStart(2,'0')}:${String(pt.minute).padStart(2,'0')}${ampm}`;
        } else {
          tStr = pt.timeString;
        }
        return `${tStr} ${loc.label}`;
      } catch(_) { return loc.label; }
    }
    const fmt = new Intl.DateTimeFormat('en-US', {
      hour:'2-digit', minute:'2-digit', hour12:_use12h(), timeZone: loc.tz
    }).format(d);
    return `${fmt} ${loc.label}`;
  }

  function _delayStr(planet) {
    try {
      const secs = PlanetTime.lightTravelSeconds('earth', planet, Date.now());
      return secs < 90 ? `${Math.round(secs)} s` : `${(secs/60).toFixed(1)} min`;
    } catch(_) { return ''; }
  }

  // Find overlapping work windows
  const result = PlanetTime.findNextMeetingSlot(locs, { from: new Date(), maxDays: 14, maxOptions: 3 });

  // Build chat container
  const chat = document.createElement('div');
  chat.className = 'mp-agent-chat';
  const agentHeaderNote = locs.length > 2 ? ` <span style="font-size:.68rem;opacity:.55">(${locs.length} locations)</span>` : '';
  chat.innerHTML = `<div class="mp-agent-header">${t('meeting.agent_header')}${agentHeaderNote}</div>`;
  resultEl.appendChild(chat);

  if (!result.found || !result.slots.length) {
    const msg = document.createElement('div');
    msg.className = 'mp-agent-no-slot';
    msg.textContent = t('meeting.agent_no_slots');
    chat.appendChild(msg);
    return;
  }

  const slots = result.slots;

  async function _bubble(side, name, html, delay) {
    const wrap = document.createElement('div');
    wrap.className = `mp-agent-bubble ${side}`;
    const av = document.createElement('div');
    av.className = 'mp-agent-avatar';
    av.textContent = name.slice(0, 2).toUpperCase();
    wrap.appendChild(av);
    const dotWrap = document.createElement('div');
    dotWrap.innerHTML = `<div class="mp-agent-typing"><span></span><span></span><span></span></div>`;
    wrap.appendChild(dotWrap);
    chat.appendChild(wrap);
    await new Promise(r => setTimeout(r, delay));
    dotWrap.remove();
    const body = document.createElement('div');
    body.className = 'mp-agent-body';
    body.innerHTML = `<div class="mp-agent-name">${name}</div><div class="mp-agent-text">${html}</div>`;
    wrap.appendChild(body);
  }

  function _agreed(ms, label) {
    const div = document.createElement('div');
    div.className = 'mp-agent-agreed';
    const allCityTimes = fmtAllCityTimes(ms);
    const localTimesHtml = allCityTimes ? `<div class="mp-local-times" style="margin:.2rem 0">${allCityTimes}</div>` : '';
    div.innerHTML =
      `<div class="mp-agent-agreed-title"><i class="fa-solid fa-check" aria-hidden="true"></i> ${t('meeting.agent_agreed')}</div>` +
      `<div>${label}</div>` +
      localTimesHtml +
      `<div class="mp-agent-agreed-actions">` +
        `<button class="mp-agent-agreed-btn" onclick="downloadICS(new Date(${ms}),60)">` +
          `<i class="fa-solid fa-calendar-arrow-down" aria-hidden="true"></i> ${t('meeting.agent_cal_ics')}</button>` +
        `<button class="mp-agent-agreed-btn" onclick="window.open(_gcalUrl(${ms},60),'_blank')">G Cal</button>` +
        `<button class="mp-agent-agreed-btn" onclick="window.open(_outlookUrl(${ms},60),'_blank')">Outlook</button>` +
      `</div>`;
    chat.appendChild(div);
  }

  // Slot midpoints (30 min into window, capped at window length)
  function _mid(slot) {
    return slot.startMs + Math.min(30 * 60000, Math.floor((slot.endMs - slot.startMs) / 2));
  }

  const ms0 = _mid(slots[0]);
  const ms1 = slots.length > 1 ? _mid(slots[1]) : ms0;
  const ms2 = slots.length > 2 ? _mid(slots[2]) : ms1;

  const utc0 = _fmtUtc(ms0);
  const utc1 = _fmtUtc(ms1);
  const utc2 = _fmtUtc(ms2);

  const planetLoc = locs.find(l => l.type === 'planet');
  const delayNote = planetLoc ? ` Signal delay: ${_delayStr(planetLoc.planet)} each way.` : '';

  const workForB0 = slots[0].localTimes?.[1]?.isWorkHour ?? true;
  const workForAll0 = slots[0].localTimes?.every(lt => lt.isWorkHour !== false) ?? true;
  const workForA1 = slots.length > 1 ? (slots[1].localTimes?.[0]?.isWorkHour ?? true) : true;
  const workForAll1 = slots.length > 1 ? (slots[1].localTimes?.every(lt => lt.isWorkHour !== false) ?? true) : true;

  // Additional agents (cities 3+) confirm after primary two-party negotiation
  async function _confirmOthers(ms, slotIdx) {
    if (locs.length <= 2) return;
    const slot = slots[slotIdx] || slots[slots.length - 1];
    for (let i = 2; i < locs.length; i++) {
      const workOk = slot?.localTimes?.[i]?.isWorkHour ?? true;
      const side = i % 2 === 0 ? 'agent-a' : 'agent-b';
      const note = workOk ? ' Works for me!' : ' (outside my preferred hours but I\'ll join)';
      await _bubble(side, locs[i].label,
        `${_fmtLocal(ms, locs[i])} for me.${note}`,
        350 + (i - 2) * 250);
    }
  }

  // Round 1 — Agent A proposes slot 0
  await _bubble('agent-a', labelA,
    `Hi! I'd like to schedule our meeting. How about <strong>${utc0}</strong>` +
    ` — that's ${_fmtLocal(ms0, locs[0])} for me?`,
    450);

  if (workForB0) {
    await _bubble('agent-b', labelB,
      `That works — it's ${_fmtLocal(ms0, locs[1])} here.${delayNote} Let's do it!`,
      750);
    await _confirmOthers(ms0, 0);
    _agreed(ms0, utc0);
    return;
  }

  // Slot 0 bad for B — B counter-proposes slot 1
  await _bubble('agent-b', labelB,
    `${utc0} is rest hours here (${_fmtLocal(ms0, locs[1])}).${delayNote}` +
    ` Could we try <strong>${utc1}</strong> instead?`,
    750);

  if (workForA1) {
    await _bubble('agent-a', labelA,
      `${utc1} works for me — ${_fmtLocal(ms1, locs[0])}. Agreed!`,
      750);
    await _confirmOthers(ms1, 1);
    _agreed(ms1, utc1);
    return;
  }

  // Slot 1 also bad for A — A tries slot 2
  await _bubble('agent-a', labelA,
    `That's tricky for me too. How about <strong>${utc2}</strong>?`,
    750);

  await _bubble('agent-b', labelB,
    `${utc2} — ${_fmtLocal(ms2, locs[1])} for me.${delayNote} That works!`,
    750);

  await _confirmOthers(ms2, 2);
  _agreed(ms2, utc2);
}

document.getElementById('mp-agent-btn').addEventListener('click', () => {
  document.getElementById('mp-overlap-result').innerHTML = '';
  document.getElementById('mp-signal-result').innerHTML = '';
  document.getElementById('mp-async-result').innerHTML = '';
  runAgentNegotiation();
});

document.getElementById('mp-async-btn').addEventListener('click', () => {
  document.getElementById('mp-overlap-result').innerHTML = '';
  document.getElementById('mp-signal-result').innerHTML = '';

  // Get current delay — from planet cities in STATE
  let currentDelayMin = 0;
  const planetCity = STATE.cities.find(c => c.type === 'planet');
  if (planetCity) {
    try {
      const pt = PlanetTime.getPlanetTime(planetCity.planet, new Date(), planetCity.tzOffset || 0);
      currentDelayMin = pt.lightMinutes || 0;
    } catch(_) {}
  }
  renderAsyncResult(STATE.cities, currentDelayMin);
});

// Cookie (inline in settings)
document.getElementById('ck-yes').addEventListener('click', () => {
  STATE.cookieConsent = true;
  setCookie('sky_consent','1');
  try { localStorage.setItem('sky_consent','1'); } catch(_) {}
  syncSettingsUI(); saveState(); updateNotifDot();
});
document.getElementById('ck-no').addEventListener('click', () => {
  STATE.cookieConsent = false;
  setCookie('sky_consent','0');
  try { localStorage.setItem('sky_consent','0'); } catch(_) {}
  syncSettingsUI(); updateNotifDot();
});

// Advanced section toggle
(function() {
  const toggle = document.getElementById('adv-toggle');
  const body   = document.getElementById('adv-body');
  function doToggle() {
    const open = body.classList.toggle('open');
    toggle.classList.toggle('open', open);
    toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
  }
  toggle.addEventListener('click', doToggle);
  toggle.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); doToggle(); }
  });
})();


// Forecast API URL input — update settings, invalidate cache, refresh
document.getElementById('hdtn-api-url').addEventListener('change', e => {
  const url = e.target.value.trim();
  STATE.settings.hdtnApiUrl = url;
  // Invalidate cache so next refresh fetches fresh data
  Object.keys(_hdtnCache).forEach(k => delete _hdtnCache[k]);
  saveState(); syncHash();
  refreshAllHdtn();
});

// Forecast API test-connection button
document.getElementById('hdtn-test-btn').addEventListener('click', async () => {
  const url = STATE.settings.hdtnApiUrl;
  if (!url) { showToast(t('settings.hdtn_url_placeholder')); return; }
  // Find first planet city to test with, or use 'mars' as fallback
  const firstPlanet = STATE.cities.find(c => c.type === 'planet');
  const testBody = firstPlanet ? firstPlanet.planet : 'mars';
  try {
    const r = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ body: testBody,
        start_iso: new Date().toISOString(), horizon_hours: 6 }),
    });
    if (r.ok) {
      showToast(t('settings.hdtn_connected'));
    } else {
      showToast(t('settings.hdtn_unreachable'));
    }
  } catch(e) {
    showToast(t('settings.hdtn_unreachable'));
  }
});

// AI Assistant URL input — update settings
document.getElementById('llm-api-url').addEventListener('change', e => {
  STATE.settings.llmApiUrl = e.target.value.trim();
  saveSettings();
});

// AI Assistant test-connection button
document.getElementById('llm-test-btn').addEventListener('click', async () => {
  const url = STATE.settings.llmApiUrl;
  if (!url) { showToast(t('settings.llm_enter_url')); return; }
  const btn = document.getElementById('llm-test-btn');
  const orig = btn.textContent;
  btn.textContent = t('settings.llm_connecting');
  btn.disabled = true;
  try {
    // Send a minimal test payload — 1 window, Earth→Mars, short delay
    const r = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        query_locale: 'en',
        bodies: ['Earth/London', 'Mars/AMT'],
        current_delay_min: 14.0,
        conjunction_in_days: 180,
        ka_risk_max: 0.05,
        windows: [{
          rank: 1, start_utc: new Date(Date.now() + 86400000).toISOString(),
          duration_hours: 6, overlap_score: 0.8, ka_risk: 0.05, delay_trend: '+0.1 min/wk',
        }],
      }),
    });
    btn.textContent = r.ok ? t('settings.llm_connected') : `✗ HTTP ${r.status}`;
    btn.disabled = false;
    setTimeout(() => { btn.textContent = orig; }, 3000);
  } catch(e) {
    btn.textContent = t('settings.llm_unreachable');
    btn.disabled = false;
    setTimeout(() => { btn.textContent = orig; }, 3000);
  }
});

// ── AI Provider UI (Story 16.1) ─────────────────────────────────────────────

function _populateProviderModels(provKey) {
  const modelSel = document.getElementById('llm-provider-model');
  if (!modelSel) return;
  modelSel.innerHTML = '';
  const provDef = window.LLM_PROVIDERS && window.LLM_PROVIDERS[provKey];
  const models = provDef ? provDef.models : [];
  if (!models.length) {
    const opt = document.createElement('option');
    opt.value = ''; opt.textContent = 'Enter model name below…';
    modelSel.appendChild(opt);
  } else {
    models.forEach(m => {
      const opt = document.createElement('option');
      opt.value = m; opt.textContent = m;
      modelSel.appendChild(opt);
    });
  }
}

function _syncProviderUI() {
  const cfg = loadLlmProviderCfg();
  const selEl    = document.getElementById('llm-provider-sel');
  const cfgDiv   = document.getElementById('llm-provider-cfg');
  const keyEl    = document.getElementById('llm-provider-key');
  const modelSel = document.getElementById('llm-provider-model');
  const urlEl    = document.getElementById('llm-provider-url');
  const statusEl = document.getElementById('llm-provider-status');
  if (!selEl || !cfgDiv) return;

  const savedKey = cfg?.provider || '';
  selEl.value = savedKey;
  const showCfg = !!savedKey;
  cfgDiv.hidden = !showCfg;
  const hostedCfg = document.getElementById('llm-hosted-cfg');
  if (hostedCfg) hostedCfg.hidden = !!savedKey; // show only when Hosted SLM (empty key)

  if (showCfg) {
    _populateProviderModels(savedKey);
    if (keyEl) keyEl.value = cfg?.apiKey || '';
    if (modelSel && cfg?.model) modelSel.value = cfg.model;
    const provDef = window.LLM_PROVIDERS && window.LLM_PROVIDERS[savedKey];
    if (urlEl) urlEl.value = cfg?.baseUrl || (provDef ? provDef.baseUrl : '') || '';
  }
  if (statusEl) statusEl.textContent = cfg?.provider ? t('settings.llm_provider_configured') : '';
}

document.getElementById('llm-provider-sel').addEventListener('change', e => {
  const provKey = e.target.value;
  const cfgDiv  = document.getElementById('llm-provider-cfg');
  const urlEl   = document.getElementById('llm-provider-url');
  const statusEl = document.getElementById('llm-provider-status');
  if (!cfgDiv) return;

  cfgDiv.hidden = !provKey;
  const hostedCfg = document.getElementById('llm-hosted-cfg');
  if (hostedCfg) hostedCfg.hidden = !!provKey;
  if (provKey) {
    _populateProviderModels(provKey);
    const provDef = window.LLM_PROVIDERS && window.LLM_PROVIDERS[provKey];
    if (urlEl) urlEl.value = provDef?.baseUrl || '';
    if (provDef?.note) {
      if (statusEl) statusEl.textContent = provDef.note;
    }
  }
});

document.getElementById('llm-provider-save').addEventListener('click', () => {
  const provKey  = document.getElementById('llm-provider-sel').value;
  const keyEl    = document.getElementById('llm-provider-key');
  const modelSel = document.getElementById('llm-provider-model');
  const urlEl    = document.getElementById('llm-provider-url');
  const statusEl = document.getElementById('llm-provider-status');

  if (!provKey) {
    if (statusEl) statusEl.textContent = t('settings.llm_provider_select_first');
    return;
  }
  const provDef = window.LLM_PROVIDERS && window.LLM_PROVIDERS[provKey];
  const needsKey = provDef?.auth !== 'none';
  const apiKey = keyEl ? keyEl.value.trim() : '';
  if (needsKey && !apiKey) {
    if (statusEl) statusEl.textContent = t('settings.llm_provider_key_required');
    return;
  }

  saveLlmProviderCfg({
    provider: provKey,
    apiKey,
    model: modelSel ? modelSel.value : '',
    baseUrl: urlEl ? urlEl.value.trim() : '',
  });
  if (statusEl) statusEl.textContent = t('settings.llm_provider_saved');
  setTimeout(() => { if (statusEl) statusEl.textContent = t('settings.llm_provider_configured'); }, 2000);
});

document.getElementById('llm-provider-test').addEventListener('click', async () => {
  const statusEl = document.getElementById('llm-provider-status');
  const testBtn  = document.getElementById('llm-provider-test');
  const cfg = loadLlmProviderCfg();
  if (!cfg?.provider || (!cfg.apiKey && window.LLM_PROVIDERS?.[cfg.provider]?.auth !== 'none')) {
    if (statusEl) statusEl.textContent = t('settings.llm_provider_save_first');
    return;
  }
  const origTxt = testBtn.textContent;
  testBtn.textContent = t('settings.llm_provider_testing');
  testBtn.disabled = true;

  try {
    const provDef = window.LLM_PROVIDERS[cfg.provider];
    const baseUrl = cfg.baseUrl || provDef?.baseUrl || '';
    const model   = cfg.model || (provDef?.models?.[0] || '');
    const headers = { 'Content-Type': 'application/json' };
    if (provDef?.auth === 'bearer')    headers['Authorization'] = `Bearer ${cfg.apiKey}`;
    if (provDef?.auth === 'api-key')   headers['api-key'] = cfg.apiKey;
    if (provDef?.auth === 'anthropic') {
      headers['x-api-key'] = cfg.apiKey;
      headers['anthropic-version'] = '2023-06-01';
    }

    let url, body;
    if (cfg.provider === 'anthropic') {
      url  = `${baseUrl}/v1/messages`;
      body = JSON.stringify({ model, max_tokens: 8,
        messages: [{ role:'user', content:'Hi' }] });
    } else if (cfg.provider === 'gemini') {
      url  = `${baseUrl}/models/${model}:generateContent?key=${cfg.apiKey}`;
      body = JSON.stringify({ contents: [{ parts: [{ text:'Hi' }] }],
        generationConfig: { maxOutputTokens: 8 } });
      delete headers['Content-Type']; headers['Content-Type'] = 'application/json';
    } else {
      url  = `${baseUrl}/chat/completions`;
      body = JSON.stringify({ model, max_tokens: 8, stream: false,
        messages: [{ role:'user', content:'Hi' }] });
    }

    const r = await fetch(url, { method:'POST', headers, body,
      signal: AbortSignal.timeout(10000) });
    if (statusEl) statusEl.textContent = r.ok ? `${t('settings.llm_connected')} (HTTP ${r.status})` : `✗ HTTP ${r.status}`;
  } catch(err) {
    if (statusEl) statusEl.textContent = `✗ ${err.message || t('settings.svc_err')}`;
  } finally {
    testBtn.textContent = origTxt;
    testBtn.disabled = false;
  }
});

document.getElementById('llm-provider-clear').addEventListener('click', () => {
  saveLlmProviderCfg(null);
  document.getElementById('llm-provider-sel').value = '';
  document.getElementById('llm-provider-cfg').hidden = true;
  const keyEl = document.getElementById('llm-provider-key');
  if (keyEl) keyEl.value = '';
  const statusEl = document.getElementById('llm-provider-status');
  if (statusEl) statusEl.textContent = t('settings.llm_provider_cleared');
  setTimeout(() => { if (statusEl) statusEl.textContent = ''; }, 2000);
});

// Manual location JSON — apply and clear
const VALID_BODIES = new Set(['earth','mars','moon','mercury','venus','jupiter','saturn','uranus','neptune','transit']);

function applyManualLocation(jsonStr) {
  const loc = typeof jsonStr === 'string' ? JSON.parse(jsonStr) : jsonStr;
  const body = (loc.body || 'earth').toLowerCase();
  if (!VALID_BODIES.has(body)) throw new Error(`Unknown body: ${loc.body}`);
  if (!('lat' in loc) || !('lon' in loc)) throw new Error('lat and lon are required');
  STATE.userBody = body;
  STATE.userLat  = parseFloat(loc.lat);
  STATE.userLon  = parseFloat(loc.lon);
  STATE.userLocation = loc;
  const label = loc.label ? `${loc.label} (${loc.body || 'Earth'})` : `${loc.body || 'Earth'} ${STATE.userLat.toFixed(2)},${STATE.userLon.toFixed(2)}`;
  document.getElementById('loc-status').innerHTML = `<i class="fa-solid fa-location-dot" aria-hidden="true"></i> ${label}`;
  STATE.cities.forEach(c => updateCityDisplay(c));
}

document.getElementById('manual-location-apply').addEventListener('click', () => {
  const ta  = document.getElementById('manual-location-json');
  const st  = document.getElementById('manual-location-status');
  const txt = ta.value.trim();
  if (!txt) { st.textContent = ''; return; }
  try {
    applyManualLocation(txt);
    st.innerHTML = '<i class="fa-solid fa-check" aria-hidden="true"></i> Location applied';
    st.style.color = 'rgba(76,175,80,0.9)';
  } catch(e) {
    st.innerHTML = `<i class="fa-solid fa-triangle-exclamation" aria-hidden="true"></i> ${e.message}`;
    st.style.color = 'rgba(255,100,60,0.9)';
  }
});

document.getElementById('manual-location-clear').addEventListener('click', () => {
  document.getElementById('manual-location-json').value = '';
  document.getElementById('manual-location-status').textContent = '';
  STATE.userBody = 'earth';
  STATE.userLat  = null;
  STATE.userLon  = null;
  STATE.userLocation = null;
  document.getElementById('loc-status').textContent = t('settings.location_not_acquired');
  STATE.cities.forEach(c => updateCityDisplay(c));
});


// Weather API URL input — update settings, re-fetch all cities
document.getElementById('weather-api-url').addEventListener('change', e => {
  STATE.settings.weatherApiUrl = e.target.value.trim();
  saveState();
  // Clear cache so cities re-fetch from the new base URL, stagger to avoid bursts
  const earthCities = STATE.cities.filter(c => c.type === 'earth');
  earthCities.forEach(c => _wxCacheClear(c.lat, c.lon));
  earthCities.forEach((c, i) => setTimeout(() => fetchAndUpdateCity(c, { forceRefresh: true }), i * 400));
});

// Weather API test-connection button
document.getElementById('weather-test-btn').addEventListener('click', async () => {
  const url = STATE.settings.weatherApiUrl;
  if (!url) { showToast(t('settings.weather_url_placeholder')); return; }
  try {
    const r = await fetch(`${url}/forecast?latitude=51.5&longitude=-0.1&current=temperature_2m&timezone=UTC`);
    showToast(r.ok ? t('settings.weather_connected') : t('settings.weather_unreachable'));
  } catch(e) {
    showToast(t('settings.weather_unreachable'));
  }
});

// Random locations
const RANDOM_POOL = [
  'Sydney','Tokyo','New York','London','São Paulo','Mumbai','Cairo','Moscow',
  'Mexico City','Lagos','Shanghai','Paris','Los Angeles','Buenos Aires','Istanbul',
  'Nairobi','Seoul','Toronto','Dubai','Singapore','Jakarta','Lima','Bangkok','Bogotá'
];
function loadRandomCities() {
  STATE.cities.forEach(c => { if (c.refreshTimer) clearInterval(c.refreshTimer); });
  STATE.cities = [];
  document.querySelectorAll('.city-col').forEach(el => el.remove());
  const pool = [...RANDOM_POOL].sort(() => Math.random() - 0.5);
  let added = 0;
  const count = window.innerWidth < 768 ? 8 : 6;
  for (const name of pool) {
    if (added >= count) break;
    const entry = CITY_DB.find(c => c.city.toLowerCase() === name.toLowerCase());
    if (entry) { addEarthCity(entry, { silent: true }); added++; }
  }
  if (added === 1) {
    showToast(t('toast.city_added', { name: STATE.cities[STATE.cities.length - 1]?.city || '' }));
  } else if (added > 1) {
    showToast(t('toast.cities_added_n', { n: added }));
  }
  saveState(); syncHash();
}
document.getElementById('qa-random').addEventListener('click', loadRandomCities);

// Earth-only preset — 4 representative Earth cities across major timezones
function loadEarthOnlyCities() {
  STATE.cities.forEach(c => { if (c.refreshTimer) clearInterval(c.refreshTimer); });
  STATE.cities = [];
  document.querySelectorAll('.city-col').forEach(el => el.remove());

  const targets = [
    { city: 'New York',  country: 'USA',       tz: 'America/New_York',    lat: 40.71,  lon: -74.01 },
    { city: 'London',    country: 'UK',         tz: 'Europe/London',       lat: 51.51,  lon: -0.13  },
    { city: 'Tokyo',     country: 'Japan',      tz: 'Asia/Tokyo',          lat: 35.68,  lon: 139.69 },
    { city: 'Sydney',    country: 'Australia',  tz: 'Australia/Sydney',    lat: -33.87, lon: 151.21 },
  ];

  targets.forEach(t => {
    const entry = CITY_DB.find(c => c.city.toLowerCase() === t.city.toLowerCase() && c.country === t.country)
                || CITY_DB.find(c => c.city.toLowerCase() === t.city.toLowerCase())
                || { ...t, pop: 1000000, workWeek: 'mon-fri' };
    addEarthCity(entry, { silent: true });
  });

  saveState(); syncHash();
}

// Interplanet preset — Earth city closest to current Mars time + Mars AMT-0
function loadInterplanetDemo() {
  STATE.cities.forEach(c => { if (c.refreshTimer) clearInterval(c.refreshTimer); });
  STATE.cities = [];
  document.querySelectorAll('.city-col').forEach(el => el.remove());

  // Get current Mars sol hour
  const now = new Date();
  const pt = PlanetTime.getPlanetTime('mars', now, 0);
  const marsHour = pt.hour;

  // Curated Earth cities with approximate standard UTC offsets
  const candidates = [
    { city: 'New York',   country: 'USA',       tz: 'America/New_York',  utcOffset: -5 },
    { city: 'Los Angeles',country: 'USA',        tz: 'America/Los_Angeles',utcOffset: -8 },
    { city: 'Chicago',    country: 'USA',        tz: 'America/Chicago',   utcOffset: -6 },
    { city: 'London',     country: 'UK',         tz: 'Europe/London',     utcOffset: 0  },
    { city: 'Dubai',      country: 'UAE',        tz: 'Asia/Dubai',        utcOffset: 4  },
    { city: 'Tokyo',      country: 'Japan',      tz: 'Asia/Tokyo',        utcOffset: 9  },
    { city: 'Sydney',     country: 'Australia',  tz: 'Australia/Sydney',  utcOffset: 10 },
    { city: 'Singapore',  country: 'Singapore',  tz: 'Asia/Singapore',    utcOffset: 8  },
  ];

  const utcHour = now.getUTCHours() + now.getUTCMinutes() / 60;

  let best = candidates[0];
  let bestDiff = Infinity;
  candidates.forEach(c => {
    const localHour = ((utcHour + c.utcOffset) % 24 + 24) % 24;
    const diff = Math.min(Math.abs(localHour - marsHour), 24 - Math.abs(localHour - marsHour));
    if (diff < bestDiff) { bestDiff = diff; best = c; }
  });

  // Add chosen Earth city from CITY_DB or fallback
  const dbEntry = CITY_DB.find(c => c.city.toLowerCase() === best.city.toLowerCase() && c.country === best.country)
               || CITY_DB.find(c => c.city.toLowerCase() === best.city.toLowerCase())
               || { city: best.city, country: best.country, tz: best.tz, lat: 0, lon: 0, pop: 1000000, workWeek: 'mon-fri' };
  addEarthCity(dbEntry, { silent: true });

  // Add Mars at AMT-0 (Airy Mean Time, UTC+0 offset)
  addPlanet('mars', 0, 'AMT', 'Airy Mean Time');

  saveState(); syncHash();
}

// Demo mode — Houston + London + a random Mars zone, then open meeting panel
document.getElementById('qa-demo').addEventListener('click', () => {
  // Clear existing cities
  STATE.cities.forEach(c => { if (c.refreshTimer) clearInterval(c.refreshTimer); });
  STATE.cities = [];
  document.querySelectorAll('.city-col').forEach(el => el.remove());

  // Add Houston and London from CITY_DB
  const houston = CITY_DB.find(c => c.city === 'Houston' && c.country === 'USA');
  const london  = CITY_DB.find(c => c.city === 'London'  && c.country === 'UK');
  if (houston) addEarthCity(houston);
  if (london)  addEarthCity(london);

  // Add a random Mars AMT zone
  const marsZones = PlanetTime.MARS_ZONES || [];
  const zone = marsZones[Math.floor(Math.random() * marsZones.length)] || { id: 'AMT', name: 'Airy Mean Time', offset: 0 };
  addPlanet('mars', zone.offset || 0, zone.id || 'AMT', zone.name || 'Airy Mean Time');

  saveState(); syncHash();
  setTimeout(() => openMeetingPanel(), 300);
});

// My location
document.getElementById('qa-myloc').addEventListener('click', async () => {
  const btn = document.getElementById('qa-myloc');
  btn.disabled = true;
  // Use cached coords if available
  if (STATE.userLat !== null && STATE.userLon !== null) {
    const nearest = CITY_DB.reduce((best, c) => {
      const d = Math.abs(c.lat - STATE.userLat) + Math.abs(c.lon - STATE.userLon);
      return d < best.d ? { c, d } : best;
    }, { c: null, d: Infinity }).c;
    if (nearest) {
      const already = STATE.cities.some(c => c.type==='earth' && c.tz===nearest.tz && c.city===nearest.city);
      if (!already) addEarthCity(nearest);
    }
    updateMyLocButton();
    btn.disabled = false;
    return;
  }
  try {
    const pos = await new Promise((res, rej) =>
      navigator.geolocation.getCurrentPosition(res, rej, {timeout: 12000, maximumAge: 300000})
    );
    STATE.userLat = pos.coords.latitude;
    STATE.userLon = pos.coords.longitude;
    saveLocation(STATE.userLat, STATE.userLon, null);
    // Update Settings location status
    const locStatus = document.getElementById('loc-status');
    if (locStatus) locStatus.innerHTML = `<i class="fa-solid fa-location-dot" aria-hidden="true"></i> ${STATE.userLat.toFixed(2)}, ${STATE.userLon.toFixed(2)}`;
    const reqBtn = document.getElementById('req-loc-btn');
    if (reqBtn) reqBtn.innerHTML = `<i class="fa-solid fa-location-crosshairs" aria-hidden="true"></i> <span data-i18n="settings.location_acquired">${t('settings.location_acquired')}</span>`;
    // Refresh city displays so ping times appear
    STATE.cities.forEach(c => updateCityDisplay(c));
    const nearest = CITY_DB.reduce((best, c) => {
      const d = Math.abs(c.lat - STATE.userLat) + Math.abs(c.lon - STATE.userLon);
      return d < best.d ? { c, d } : best;
    }, { c: null, d: Infinity }).c;
    if (nearest) {
      const already = STATE.cities.some(c => c.type==='earth' && c.tz===nearest.tz && c.city===nearest.city);
      if (!already) addEarthCity(nearest);
    }
  } catch(e) {
    showToast(t('toast.location_unavailable'));
  }
  updateMyLocButton();
  btn.disabled = false;
});

function updateMyLocButton() {
  const btn = document.getElementById('qa-myloc');
  if (!btn) return;
  // Hide if my location is already on screen
  if (STATE.userLat !== null) {
    const nearest = CITY_DB.reduce((best, c) => {
      const d = Math.abs(c.lat - STATE.userLat) + Math.abs(c.lon - STATE.userLon);
      return d < best.d ? { c, d } : best;
    }, { c: null, d: Infinity }).c;
    const onScreen = nearest && STATE.cities.some(c => c.type==='earth' && c.tz===nearest.tz);
    btn.classList.toggle('hidden', !!onScreen);
  } else {
    btn.classList.remove('hidden');
  }
}

// Share button — copy shareable URL to clipboard (Story 25.1)
function _flashShareBtn(ok) {
  const btn = document.getElementById('share-ctl');
  if (!btn) return;
  const icon = btn.querySelector('i');
  if (!icon) return;
  icon.className = ok ? 'fa-solid fa-check' : 'fa-solid fa-share-from-square';
  setTimeout(() => { icon.className = 'fa-solid fa-share-from-square'; }, 2000);
}

async function _copyShareUrl(url) {
  if (navigator.clipboard && navigator.clipboard.writeText) {
    await navigator.clipboard.writeText(url);
    return true;
  }
  // Fallback: execCommand (legacy browsers)
  const ta = document.createElement('textarea');
  ta.value = url; ta.style.cssText = 'position:fixed;opacity:0';
  document.body.appendChild(ta); ta.select();
  const ok = document.execCommand('copy');
  document.body.removeChild(ta);
  if (!ok) throw new Error('execCommand failed');
  return true;
}

document.getElementById('share-ctl').addEventListener('click', async () => {
  if (!STATE.cities.length) {
    showToast(t('toast.share_no_cities'));
    return;
  }

  // Always sync hash first so location.href is up-to-date
  syncHash();
  const hashUrl = location.href;

  // file:// — skip share.php, just copy hash URL
  if (location.protocol === 'file:') {
    try {
      await _copyShareUrl(hashUrl);
      _flashShareBtn(true);
      showToast(t('toast.share_url_copied'));
    } catch(_) {
      showToast(t('toast.hash_bookmark'));
    }
    return;
  }

  // HTTP — try share.php first, fall back to hash URL
  const cfg = JSON.stringify(getConfigJSON());
  try {
    const resp = await fetch('share.php', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ config: cfg }),
    });
    if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
    const data = await resp.json();
    if (data.url) {
      try { await _copyShareUrl(data.url); } catch(_) {}
      _flashShareBtn(true);
      showToast(t('toast.link_copied', {url: data.url}));
    } else {
      throw new Error(data.error || 'No URL returned');
    }
  } catch(e) {
    // share.php unavailable — fall back to hash URL
    try {
      await _copyShareUrl(hashUrl);
      _flashShareBtn(true);
      showToast(t('toast.share_url_copied'));
    } catch(_) {
      console.error('Share failed', e);
      showToast(t('toast.share_unavailable'));
    }
  }
});

// Config export
document.getElementById('cfg-export-btn').addEventListener('click', async () => {
  const json = JSON.stringify(getConfigJSON(), null, 2);
  try { await navigator.clipboard.writeText(json); showToast(t('toast.config_copied')); }
  catch(_) {
    document.getElementById('cfg-import-txt').value = json;
    showToast(t('toast.config_textarea'));
  }
});

// Config import
document.getElementById('cfg-import-btn').addEventListener('click', () => {
  const txt = document.getElementById('cfg-import-txt').value.trim();
  const status = document.getElementById('cfg-status');
  if (!txt) { status.textContent = t('toast.paste_json'); return; }
  try {
    const cfg = JSON.parse(txt);
    applyConfig(cfg);
    status.textContent = t('toast.cities_loaded', {count: cfg.cities?.length||0});
    document.getElementById('cfg-import-txt').value = '';
    saveState();
  } catch(e) {
    status.textContent = 'Parse error: ' + e.message;
    console.error('Config import error', e);
  }
});

// Custom solar system — parse JSON and add custom planets
document.getElementById('cfg-custom-sys-btn').addEventListener('click', () => {
  const txt = document.getElementById('cfg-import-txt').value.trim();
  const status = document.getElementById('cfg-status');
  if (!txt) {
    document.getElementById('cfg-import-txt').value = JSON.stringify({
      type: 'customSystem',
      star: { name: 'Proxima Centauri', luminosity: 0.0017 },
      planets: [
        { key: 'proxb', name: 'Proxima b', symbol: '◉', color: '#8fa8d0',
          solarDayMs: 11.2 * 86400000, siderealYrMs: 11.2 * 86400000, a_AU: 0.048 }
      ]
    }, null, 2);
    status.textContent = 'Edit the template above then click again.';
    return;
  }
  try {
    const sys = JSON.parse(txt);
    if (sys.type !== 'customSystem' || !sys.planets) throw new Error('Not a customSystem object');
    sys.planets.forEach(p => {
      LOCAL_PLANETS[p.key] = {
        name: p.name, symbol: p.symbol, color: p.color,
        solarDayMs: p.solarDayMs,
        workHoursStart: p.workHoursStart ?? 9, workHoursEnd: p.workHoursEnd ?? 17,
        notes: `Custom planet in ${sys.star?.name || 'custom'} system.`,
      };
    });
    status.textContent = `Added ${sys.planets.length} custom planet(s). Search for them by name.`;
    document.getElementById('cfg-import-txt').value = '';
  } catch(e) {
    status.textContent = 'Parse error: ' + e.message;
    console.error('Custom system error', e);
  }
});

// Location request
document.getElementById('req-loc-btn').addEventListener('click', requestLocation);

// Clear data
document.getElementById('clear-btn').addEventListener('click', () => {
  showConfirm(() => {
    location.hash = '';
    ['sky_cities','sky_settings','sky_consent'].forEach(delCookie);
    try { ['sky_cities','sky_settings','sky_consent','sky_location'].forEach(k => localStorage.removeItem(k)); } catch(_) {}
    STATE.userLat = null; STATE.userLon = null;
    STATE.cookieConsent = null;
    STATE.cities.forEach(c => { if (c.refreshTimer) clearInterval(c.refreshTimer); });
    STATE.cities = [];
    document.querySelectorAll('.city-col').forEach(el => el.remove());
    syncSettingsUI();
    updatePlaceholder();
  });
});

// Keyboard: navigation between city cards, detail expansion, and modal close
document.addEventListener('keydown', e => {
  const focused = document.activeElement;

  if ((e.ctrlKey || e.metaKey) && e.key === 'k') {
    e.preventDefault(); openSearch(); return;
  }

  if (e.key === '?' && !e.ctrlKey && !e.metaKey) {
    const tag = focused ? focused.tagName : '';
    if (tag !== 'INPUT' && tag !== 'TEXTAREA' && tag !== 'SELECT') {
      e.preventDefault(); toggleKbd(); return;
    }
  }

  if (e.key === 'Escape') {
    // If focus is in an a11y details panel, Escape returns focus to the parent card
    if (focused && focused.id && focused.id.startsWith('a11y-')) {
      e.preventDefault();
      const cityId = focused.id.replace('a11y-', '');
      const card = document.getElementById(`city-${cityId}`);
      if (card) { card.focus(); return; }
    }
    closeSearch(); closeSettings(); closeMeetingPanel(); closeVideoModal(); closeKbd();
    if (focused && focused.classList.contains('city-col')) focused.blur();
    return;
  }

  // Navigation when a city card is focused
  if (focused && focused.classList.contains('city-col')) {
    const cols = Array.from(document.querySelectorAll('.city-col'));
    const idx = cols.indexOf(focused);
    const cityId = focused.id.replace('city-', '');
    if (e.key === 'ArrowLeft') {
      e.preventDefault();
      if (idx > 0) cols[idx - 1].focus();
    } else if (e.key === 'ArrowRight') {
      e.preventDefault();
      if (idx < cols.length - 1) cols[idx + 1].focus();
    } else if (e.key === 'ArrowDown') {
      e.preventDefault();
      const a11y = document.getElementById(`a11y-${cityId}`);
      if (a11y) a11y.focus(); // screen reader reads the detailed info text
    }
    return;
  }

  // Navigation when an a11y details panel is focused (after pressing Down)
  if (focused && focused.id && focused.id.startsWith('a11y-')) {
    const cityId = focused.id.replace('a11y-', '');
    const card = document.getElementById(`city-${cityId}`);
    if (e.key === 'ArrowUp' || e.key === 'Escape') {
      e.preventDefault();
      if (card) card.focus(); // return to card summary
    } else if (e.key === 'ArrowLeft') {
      e.preventDefault();
      if (card) {
        const cols = Array.from(document.querySelectorAll('.city-col'));
        const idx = cols.indexOf(card);
        if (idx > 0) cols[idx - 1].focus();
      }
    } else if (e.key === 'ArrowRight') {
      e.preventDefault();
      if (card) {
        const cols = Array.from(document.querySelectorAll('.city-col'));
        const idx = cols.indexOf(card);
        if (idx < cols.length - 1) cols[idx + 1].focus();
      }
    }
  }
});

bindSettingsToggles();

// Time format segmented control
document.querySelectorAll('#time-format-seg .sp-seg-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    STATE.settings.timeFormat = btn.dataset.val;
    document.querySelectorAll('#time-format-seg .sp-seg-btn').forEach(b =>
      b.classList.toggle('active', b.dataset.val === btn.dataset.val));
    saveSettings();
    applySettings();
  });
});

// ── 58.9 Contextual info (i) popovers ─────────────────────────────────────
const INFO_CONTENT = {
  amt: { titleKey: 'info.amt_title', textKey: 'info.amt_text', learnUrl: 'https://github.com/karwalski/interplanet/blob/main/docs/GLOSSARY.md' },
  sol: { titleKey: 'info.sol_title', textKey: 'info.sol_text', learnUrl: 'https://github.com/karwalski/interplanet/blob/main/docs/GLOSSARY.md' },
  work_hours: { titleKey: 'info.work_title', textKey: 'info.work_text', learnUrl: 'https://github.com/karwalski/interplanet/blob/main/docs/WHITEPAPER.md' },
  scheduler: { titleKey: 'info.scheduler_title', textKey: 'info.scheduler_text', learnUrl: 'https://github.com/karwalski/interplanet/blob/main/demo/ltx.html' },
};

document.addEventListener('click', function(e) {
  const btn = e.target.closest('.info-btn');
  if (btn) {
    e.stopPropagation();
    const key = btn.dataset.info;
    const info = INFO_CONTENT[key];
    if (!info) return;
    const pop = document.getElementById('info-pop');
    const ov = document.getElementById('info-pop-overlay');
    pop.innerHTML = '<span class="info-pop-title">' + t(info.titleKey) + '</span>' +
      t(info.textKey) +
      '<div class="info-pop-links"><a href="' + info.learnUrl + '" target="_blank" rel="noopener">' + t('info.learn_more') + '</a></div>';
    const rect = btn.getBoundingClientRect();
    pop.style.display = 'block';
    pop.style.top = Math.min(rect.bottom + 8, window.innerHeight - 200) + 'px';
    pop.style.left = Math.max(8, Math.min(rect.left, window.innerWidth - 276)) + 'px';
    ov.classList.add('on');
    return;
  }
  if (e.target.id === 'info-pop-overlay') {
    document.getElementById('info-pop').style.display = 'none';
    e.target.classList.remove('on');
  }
});

document.addEventListener('keydown', function(e) {
  if (e.key === 'Escape') {
    const pop = document.getElementById('info-pop');
    const ov = document.getElementById('info-pop-overlay');
    if (pop) pop.style.display = 'none';
    if (ov) ov.classList.remove('on');
  }
});

// Dismiss pinned hour popup when clicking outside
document.addEventListener('pointerdown', e => {
  if (_popPinned && !e.target.closest('#hpop') && !e.target.closest('.hour-cell')) {
    _popPinned = false;
    document.getElementById('hpop').classList.remove('on');
  }
});

// ════════════════════════════════════════════════════════════════════════════
// GEOLOCATION
// ════════════════════════════════════════════════════════════════════════════
async function requestLocation() {
  const btn = document.getElementById('req-loc-btn');
  const status = document.getElementById('loc-status');
  btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin" aria-hidden="true"></i> <span data-i18n="settings.req_location">Requesting…</span>';
  try {
    const pos = await new Promise((res, rej) =>
      navigator.geolocation.getCurrentPosition(res, rej, {timeout:12000, maximumAge:300000})
    );
    const { latitude: lat, longitude: lon } = pos.coords;
    STATE.userLat = lat; STATE.userLon = lon;
    status.innerHTML = `<i class="fa-solid fa-location-dot" aria-hidden="true"></i> ${lat.toFixed(2)}, ${lon.toFixed(2)}`;
    btn.textContent = t('settings.location_acquired');

    const placeName = await reverseGeocode(lat, lon);
    // Find nearest timezone city in DB by distance
    const nearest = CITY_DB.reduce((best, c) => {
      const d = Math.hypot(c.lat-lat, c.lon-lon);
      return d < best.d ? {c, d} : best;
    }, {c:CITY_DB[0], d:Infinity}).c;

    const localCity = {
      ...nearest,
      city: placeName || nearest.city,
      lat, lon,
      pop: nearest.pop,
      customName: placeName || null,
    };
    saveLocation(lat, lon, placeName || nearest.city);
    addEarthCity(localCity);
  } catch(e) {
    const msgs = {1:t('settings.loc_err_1'),2:t('settings.loc_err_2'),3:t('settings.loc_err_3')};
    status.textContent = msgs[e.code]||e.message||'Failed.';
    btn.textContent = t('settings.req_location');
  }
}

// ════════════════════════════════════════════════════════════════════════════
// TICK — refresh times every second
// ════════════════════════════════════════════════════════════════════════════
function tick() {
  updatePlaceholder();
  STATE.cities.forEach(c => {
    // Only refresh the time/work fields live (not the full sky gradient — too heavy)
    if (c.type === 'earth') {
      const now = getNow();
      const timeEl = document.getElementById(`time-${c.id}`);
      if (timeEl && STATE.settings.showTime) timeEl.textContent = formatLocalTime(c.tz, now);
      const dowEl = document.getElementById(`dow-${c.id}`);
      if (dowEl && STATE.settings.showTime) {
        const _loc = window.I18N ? window.I18N.getLocale() : 'en-US';
        dowEl.textContent = new Intl.DateTimeFormat(_loc,{timeZone:c.tz,weekday:'short'}).format(now);
      }
      // Keep aria-label current for screen readers
      const colEl = document.getElementById(`city-${c.id}`);
      if (colEl) {
        const _loc = window.I18N ? window.I18N.getLocale() : 'en';
        const weekday = new Intl.DateTimeFormat(_loc,{timeZone:c.tz,weekday:'long'}).format(now);
        const skyPart = c._skyDesc ? ` Sky: ${c._skyDesc}.` : '';
        colEl.setAttribute('aria-label',
          `${c.customName||c.city}, ${c.country}. ${weekday}, ${formatLocalTime(c.tz, now)}.${skyPart}`);
      }

      const workEl = document.getElementById(`work-${c.id}`);
      if (workEl && STATE.settings.showWork) {
        const ws = workStatus(c.tz, c.workWeek, now);
        const dotClass = ws==='work'?'work':ws==='marginal'?'marginal':'rest';
        const dotColor = ws==='work'?'#4caf50':ws==='marginal'?'#ff9800':'#f44336';
        const label = ws==='work'?t('work.status_work'):ws==='marginal'?t('work.status_marginal'):t('work.status_rest');
        workEl.innerHTML = `<div class="work-dot ${dotClass}" style="background:${dotColor}"></div><span>${label}</span>`;
      }
    } else if (c.type === 'planet') {
      updatePlanetDisplay(c, getNow());
    }
  });
}
setInterval(tick, 1000);

// Full refresh every 10 minutes (sky colour recalc)
setInterval(() => STATE.cities.forEach(c => {
  if (c.type === 'earth') updateCityDisplay(c);
}), 10 * 60000);

// ════════════════════════════════════════════════════════════════════════════
// INIT
// ════════════════════════════════════════════════════════════════════════════
function addBrowserTimezoneCity() {
  try {
    const tzBrowser = Intl.DateTimeFormat().resolvedOptions().timeZone;
    // Find city in DB with matching timezone (exact match preferred)
    let match = CITY_DB.find(c => c.tz === tzBrowser);
    if (!match) {
      // Fall back to closest UTC offset match
      const offsetMin = getUTCOffsetMin(tzBrowser);
      match = CITY_DB.reduce((best, c) => {
        const d = Math.abs(getUTCOffsetMin(c.tz) - offsetMin);
        return d < best.d ? {c, d} : best;
      }, {c: CITY_DB[0], d: Infinity}).c;
    }
    return addEarthCity({...match});
  } catch(e) {
    return null;
  }
}

// ── Demo video modal (Story 13.2) ───────────────────────────────────────────
// Replace DEMO_VIDEO_ID with the actual YouTube video ID when available.
const DEMO_VIDEO_ID = 'YOUR_VIDEO_ID';
const _videoBtnEl = document.getElementById('sp-video-btn');
if (_videoBtnEl && (!DEMO_VIDEO_ID || DEMO_VIDEO_ID === 'YOUR_VIDEO_ID')) {
  _videoBtnEl.hidden = true;
}

function openVideoModal() {
  const modal  = document.getElementById('video-modal');
  const iframe = document.getElementById('video-iframe');
  iframe.src = `https://www.youtube.com/embed/${DEMO_VIDEO_ID}?autoplay=1&rel=0`;
  modal.classList.remove('off');
  modal.focus();
}
function closeVideoModal() {
  const modal  = document.getElementById('video-modal');
  const iframe = document.getElementById('video-iframe');
  iframe.src = '';   // stop playback
  modal.classList.add('off');
}
document.getElementById('sp-video-btn').addEventListener('click', () => {
  closeSettings();
  openVideoModal();
});
document.getElementById('video-modal-close').addEventListener('click', closeVideoModal);
document.getElementById('video-modal').addEventListener('click', e => {
  if (e.target === e.currentTarget) closeVideoModal();
});

// ── City-info height equalization ──────────────────────────────────────────
function equalizeInfoHeights() {
  if (STATE.settings.horiz) return; // horizontal layout uses fixed CSS heights
  const infos = [...document.querySelectorAll('#cities-wrap .city-info')];
  if (infos.length < 2) { infos.forEach(el => (el.style.minHeight = '')); return; }
  infos.forEach(el => (el.style.minHeight = ''));
  requestAnimationFrame(() => {
    const maxH = Math.max(172, ...infos.map(el => el.scrollHeight));
    infos.forEach(el => (el.style.minHeight = maxH + 'px'));
  });
}

// ── Welcome splash + feature tour ──────────────────────────────────────────
function getTourSteps() {
  if (window.innerWidth < 768) {
    // 58.6 — Mobile-specific tour steps
    return [
      { sel:'#cities-wrap',  title:t('tour.mobile_step1_title'), place:'top',    text:t('tour.mobile_step1_text') },
      { sel:'#controls',     title:t('tour.mobile_step2_title'), place:'bottom', text:t('tour.mobile_step2_text') },
      { sel:'#meeting-btn',  title:t('tour.mobile_step3_title'), place:'bottom', text:t('tour.mobile_step3_text') },
      { sel:'#add-col',      title:t('tour.mobile_step4_title'), place:'top',    text:t('tour.mobile_step4_text') },
    ];
  }
  return [
    { sel:'#add-col',      title:t('tour.step1_title'), place:'bottom',
      text:t('tour.step1_text') },
    { sel:'#cities-wrap',  title:t('tour.step2_title'), place:'top',
      text:t('tour.step2_text') },
    { sel:'#meeting-btn',  title:t('tour.step3_title'), place:'top',
      text:t('tour.step3_text') },
    { sel:'#layout-ctl',   title:t('tour.step4_title'), place:'bottom',
      text:t('tour.step4_text') },
    { sel:'#settings-ctl', title:t('tour.step5_title'), place:'bottom',
      text:t('tour.step5_text') },
  ];
}
window.getTourSteps = getTourSteps;
let _tourStep = 0;

function openSplash() {
  const modal = document.getElementById('splash-modal');
  modal.classList.remove('off');
  trapFocus(modal);
}
function closeSplash() {
  document.getElementById('splash-modal').classList.add('off');
  try { localStorage.setItem('tour_seen','1'); } catch(_) {}
  releaseTrap();
}
function startTour() {
  closeSplash(); closeSettings(); _tourStep = 0;
  document.getElementById('tour-overlay').classList.add('on');
  document.getElementById('tour-spotlight').style.display = 'block';
  document.getElementById('tour-popup').style.display = 'block';
  showTourStep(0);
  trapFocus(document.getElementById('tour-popup'));
}
function showTourStep(n) {
  const steps = getTourSteps();
  const step = steps[n];
  const el   = document.querySelector(step.sel);
  if (!el) { nextTourStep(); return; }
  document.getElementById('tp-title').textContent = step.title;
  document.getElementById('tp-text').textContent  = step.text;
  document.getElementById('tp-count').textContent = `${n+1} / ${steps.length}`;
  srAnnounce(`Tour step ${n+1} of ${steps.length}: ${step.title}. ${step.text}`);
  document.getElementById('tp-prev').style.display = n === 0 ? 'none' : '';
  document.getElementById('tp-next').innerHTML = n === steps.length-1
    ? `${t('tour.done')} <i class="fa-solid fa-check" aria-hidden="true"></i>`
    : `<span>${t('tour.next')}</span> <i class="fa-solid fa-arrow-right" aria-hidden="true"></i>`;
  const PAD = 6, r = el.getBoundingClientRect();
  const spot = document.getElementById('tour-spotlight');
  spot.style.left   = `${r.left - PAD}px`;
  spot.style.top    = `${r.top  - PAD}px`;
  spot.style.width  = `${r.width  + PAD * 2}px`;
  spot.style.height = `${r.height + PAD * 2}px`;
  requestAnimationFrame(() => {
    const popup = document.getElementById('tour-popup');
    const pw = popup.offsetWidth || 240, ph = popup.offsetHeight || 140, GAP = 12;
    // Prefer placing the popup above or below the element; fall back to the other side
    let top = step.place === 'top' ? r.top - PAD - GAP - ph : r.bottom + PAD + GAP;
    if (top < 8) top = r.bottom + PAD + GAP;
    if (top + ph > window.innerHeight - 8) top = r.top - PAD - GAP - ph;
    // Final clamp: always keep popup inside the viewport even for full-height elements
    top  = Math.max(8, Math.min(top,  window.innerHeight - ph - 8));
    // Horizontal: prefer aligning with element left, but stay inside viewport
    // If element is on the right edge (like #add-col), slide popup left
    let left = r.left + r.width / 2 - pw / 2;          // centred on element
    left = Math.max(8, Math.min(left, window.innerWidth - pw - 8));
    popup.style.top = top + 'px'; popup.style.left = left + 'px';
  });
}
function prevTourStep() { if (_tourStep > 0) showTourStep(--_tourStep); }
function nextTourStep() {
  if (_tourStep < getTourSteps().length - 1) showTourStep(++_tourStep);
  else closeTour(false);
}
function closeTour(cancelled = true) {
  document.getElementById('tour-overlay').classList.remove('on');
  document.getElementById('tour-spotlight').style.display = 'none';
  document.getElementById('tour-popup').style.display = 'none';
  releaseTrap();
  if (cancelled) {
    const tip = document.getElementById('tour-cancel-tip');
    tip.classList.add('show');
    srAnnounce(t('tour.cancelled'));
    setTimeout(() => tip.classList.remove('show'), 4000);
  } else {
    srAnnounce(t('tour.complete'));
  }
}

// Close ✕ button
document.getElementById('splash-close').addEventListener('click', closeSplash);

// Click backdrop to close (not the box itself)
document.getElementById('splash-modal').addEventListener('click', function(e) {
  if (e.target === this) closeSplash();
});

// "Earth cities" — seed representative Earth cities only
document.getElementById('splash-earth').addEventListener('click', () => {
  closeSplash();
  loadEarthOnlyCities();
});

// "Start Exploring" — primary CTA: load the interplanet demo and close splash
document.getElementById('splash-start').addEventListener('click', () => {
  closeSplash();
  loadInterplanetDemo();
});

// "Include Mars" — seed an Earth city aligned with current Mars time + Mars
document.getElementById('splash-demo').addEventListener('click', () => {
  closeSplash();
  loadInterplanetDemo();
});

// "Start empty" — close splash and remove all cities
document.getElementById('splash-skip').addEventListener('click', () => {
  closeSplash();
  [...STATE.cities].forEach(c => removeCity(c.id));
});

// 58.5 — Mobile back button closes the scheduler panel
window.addEventListener('popstate', function() {
  if (document.getElementById('meeting-panel').classList.contains('on')) {
    closeMeetingPanel();
  }
});

// "Take a tour ↗"
document.getElementById('splash-tour').addEventListener('click', (e) => {
  e.preventDefault();
  closeSplash();
  if (STATE.cities.length === 0) loadInterplanetDemo();
  startTour();
});

function showWelcomeBack() {
  if (localStorage.getItem('skip_welcome_back')) return;
  const n = STATE.cities.length;
  if (n === 0) return;

  let msg = `Welcome back · ${n} ${n === 1 ? 'city' : 'cities'} loaded`;
  const hasMars = STATE.cities.some(c => c.type === 'planet' && c.planet === 'mars');
  if (hasMars) {
    const mtc = PlanetTime.getMTC(new Date());
    msg += ` · Mars ${mtc.hour.toString().padStart(2,'0')}:${mtc.minute.toString().padStart(2,'0')} MTC`;
  }
  document.getElementById('wb-msg').textContent = msg;

  const el = document.getElementById('welcome-back');
  el.classList.remove('wb-off');
  requestAnimationFrame(() => requestAnimationFrame(() => el.classList.add('wb-on')));

  const dismiss = () => {
    el.classList.remove('wb-on');
    el.addEventListener('transitionend', () => el.classList.add('wb-off'), { once: true });
  };
  const timer = setTimeout(dismiss, 2500);
  document.getElementById('wb-close').onclick = () => { clearTimeout(timer); dismiss(); };
}
// ── User feedback prompt (Story 8.2) ──────────────────────────────────────
// Shows a gentle toast-style prompt after 5+ sessions, once per user.
// Dismissed state persists in localStorage. No personal data collected.

function _maybeShowFeedbackPrompt() {
  try {
    if (localStorage.getItem('feedback_prompted')) return;  // already shown
    const sessions = parseInt(localStorage.getItem('sky_session_count') || '0', 10) + 1;
    localStorage.setItem('sky_session_count', String(sessions));
    if (sessions < 5) return;                               // show after 5th session

    // Delay until user is settled, then show
    setTimeout(() => {
      const toast = document.createElement('div');
      toast.id = 'feedback-prompt';
      toast.setAttribute('role', 'status');
      toast.setAttribute('aria-live', 'polite');
      toast.innerHTML =
        `<span>${t('feedback.prompt')}</span>` +
        `<a href="https://github.com/karwalski/interplanet/issues" target="_blank" rel="noopener noreferrer" ` +
        `style="color:#5b8def;margin-left:.5rem;text-decoration:underline">GitHub</a>` +
        `<button id="feedback-dismiss" aria-label="${t('feedback.dismiss')}" ` +
        `style="background:none;border:none;cursor:pointer;margin-left:.75rem;opacity:.55;color:inherit;font-size:.9rem">✕</button>`;
      toast.style.cssText =
        'position:fixed;bottom:4.5rem;left:50%;transform:translateX(-50%);' +
        'background:rgba(30,32,48,.95);color:#e8eaf2;border:1px solid rgba(255,255,255,.12);' +
        'border-radius:10px;padding:.6rem 1rem;font-size:.82rem;z-index:200;max-width:90vw;' +
        'box-shadow:0 4px 18px rgba(0,0,0,.4);display:flex;align-items:center;gap:.25rem;';
      document.body.appendChild(toast);

      const dismiss = () => {
        toast.remove();
        try { localStorage.setItem('feedback_prompted', '1'); } catch(_) {}
      };
      document.getElementById('feedback-dismiss').onclick = dismiss;
      setTimeout(dismiss, 30000);   // auto-dismiss after 30s
    }, 8000);   // wait 8s into session
  } catch(_) {}
}

document.getElementById('tour-overlay').addEventListener('click', () => closeTour(true));
document.getElementById('tp-prev').addEventListener('click', prevTourStep);
document.getElementById('tp-next').addEventListener('click', nextTourStep);
document.getElementById('sp-about-btn').addEventListener('click', openSplash);

// "How it works" expandable panel (Story 6.1)
document.getElementById('sp-hiw-btn').addEventListener('click', () => {
  const panel = document.getElementById('sp-hiw-panel');
  const btn   = document.getElementById('sp-hiw-btn');
  const open  = !panel.hidden;
  panel.hidden = open;
  btn.setAttribute('aria-expanded', open ? 'false' : 'true');
});

// Escape closes tour or splash
document.addEventListener('keydown', (e) => {
  if (e.key !== 'Escape') return;
  if (document.getElementById('tour-overlay').classList.contains('on')) closeTour(true);
  if (!document.getElementById('splash-modal').classList.contains('off')) closeSplash();
});

function buildLangSelector() {
  const sel = document.getElementById('s-lang');
  if (!sel || !window.I18N) return;
  sel.innerHTML = '';
  window.I18N.SUPPORTED_LANGS.forEach(lang => {
    const opt = document.createElement('option');
    opt.value = lang;
    opt.textContent = window.I18N.LANGUAGE_NAMES[lang];
    if (lang === window.I18N.getLocale()) opt.selected = true;
    sel.appendChild(opt);
  });
}

// ── Font size controls ──────────────────────────────────────────────────────
let _fontScale = 1.0;
function setFontScale(scale) {
  _fontScale = Math.max(0.8, Math.min(1.3, Math.round(scale * 10) / 10));
  document.documentElement.style.fontSize = (_fontScale * 16) + 'px';
  try { localStorage.setItem('sky_font_scale', _fontScale.toFixed(1)); } catch(_) {}
  document.getElementById('font-dec').disabled = _fontScale <= 0.8;
  document.getElementById('font-inc').disabled = _fontScale >= 1.3;
}
document.getElementById('font-dec').addEventListener('click', () => setFontScale(_fontScale - 0.1));
document.getElementById('font-inc').addEventListener('click', () => setFontScale(_fontScale + 0.1));
(function initFontScale() {
  try {
    const saved = parseFloat(localStorage.getItem('sky_font_scale'));
    if (!isNaN(saved)) setFontScale(saved); else setFontScale(1.0);
  } catch(_) { setFontScale(1.0); }
})();

document.getElementById('s-lang').addEventListener('change', e => {
  if (!window.I18N) return;
  window.I18N.setLocale(e.target.value);
  window.I18N.applyTranslations();
  buildLangSelector();
  // Re-apply tour button label if tour is open
  if (_tourStep >= 0 && document.getElementById('tour-popup').style.display !== 'none') {
    showTourStep(_tourStep);
  }
  STATE.cities.forEach(c => updateCityDisplay(c));
  if (document.getElementById('meeting-panel').classList.contains('on'))
    renderMeetingScheduler();
  if (document.getElementById('search-modal').classList.contains('on'))
    renderSearchResults(document.getElementById('search-input').value);
});

function init() {
  // Parse URL params before anything else
  const _qp = new URLSearchParams(location.search);
  const _qpLang    = _qp.get('lang');
  const _qpCompact = _qp.get('compact') === '1';
  const _qpSched   = _qp.get('schedule');  // 'fullscreen'
  const _qpTz      = _qp.get('tz');        // e.g. '+11,-5,0' or 'Sydney,London,Tokyo'
  const _qpWidget  = _qp.get('widget') === '1';   // Story 6.2 — embed mode
  const _qpPreset  = _qp.get('preset');            // 'demo' | 'random'
  if (_qpLang && window.I18N?.SUPPORTED_LANGS.includes(_qpLang)) {
    try { localStorage.setItem('sky_lang', _qpLang); } catch(_) {}
  }
  if (_qpCompact) STATE.settings.compact = true;
  if (_qpSched === 'fullscreen') document.body.classList.add('scheduler-fullscreen');

  // ── Widget mode (Story 6.2) ───────────────────────────────────────────────
  if (_qpWidget) {
    document.body.classList.add('widget-mode');
    // Suppress welcome splash so the board appears immediately
    try { localStorage.setItem('tour_seen', '1'); } catch(_) {}
    try { localStorage.setItem('skip_welcome_back', '1'); } catch(_) {}

    // postMessage API — lets the parent frame control the widget
    window.addEventListener('message', (ev) => {
      if (!ev.data || ev.data.source !== 'interplanet-widget') return;
      const { action, payload } = ev.data;
      if (action === 'clear') {
        STATE.cities.forEach(c => { if (c.refreshTimer) clearInterval(c.refreshTimer); });
        STATE.cities = [];
        document.querySelectorAll('.city-col').forEach(el => el.remove());
        saveState(); syncHash();
      } else if (action === 'setLang' && payload?.lang) {
        if (window.I18N) { window.I18N.setLocale(payload.lang); window.I18N.applyTranslations(); }
      } else if (action === 'setTheme' && payload?.theme) {
        STATE.settings.theme = payload.theme;
        applyTheme(payload.theme);
        saveSettings();
      } else if (action === 'addPlanet' && payload?.planet) {
        addPlanet(payload.planet, payload.offset || 0, payload.zoneId || null, payload.zoneName || null);
      } else if (action === 'getState') {
        const cities = STATE.cities.map(c => ({ id: c.id, name: c.name, planet: c.planet, tz: c.tz }));
        ev.source?.postMessage({ source: 'interplanet-widget', type: 'state', payload: { cities } }, ev.origin || '*');
      }
    });
  }

  // Detect and apply language first
  if (window.I18N) {
    const lang = window.I18N.detectLanguage();
    window.I18N.setLocale(lang);
  }

  // Check URL for share code via ?share=XXXXXX query param — only over HTTP
  const shareCode = location.protocol !== 'file:'
    ? new URLSearchParams(location.search).get('share')
    : null;
  if (shareCode && /^[A-Za-z0-9]{6}$/.test(shareCode)) {
    fetch(`share.php?code=${shareCode}`)
      .then(r => r.ok ? r.json() : null)
      .then(data => {
        if (data && data.config) {
          try { applyConfig(JSON.parse(data.config)); saveState(); } catch(_) {}
        }
      })
      .catch(() => {});
  }

  // Load settings first (always — no consent needed for UI prefs)
  loadSettings();
  loadLocation();   // restore cached user location (no prompt needed)
  // Load from URL hash first; fall back to cookie state
  const _loadedFromHash = loadFromHash();
  if (!_loadedFromHash) loadState();
  if (window.I18N) { window.I18N.applyTranslations(); buildLangSelector(); }

  const isFirstTime = !localStorage.getItem('tour_seen') && !_loadedFromHash;
  const isReturning = !!localStorage.getItem('tour_seen');

  // Enforce horizontal layout on mobile regardless of persisted desktop setting
  if (window.innerWidth < 768) STATE.settings.horiz = true;
  // On first mobile visit, hide heavyweight metrics to keep the view clean
  if (window.innerWidth < 768 && isFirstTime) {
    STATE.settings.showWeather = false;
    STATE.settings.showSunMoon = false;
    STATE.settings.showPing    = false;
  }

  if (!_qpWidget) {
    if (isFirstTime && !shareCode) {
      openSplash();
    } else if (isReturning && STATE.cities.length > 0) {
      showWelcomeBack();
    } else if (isReturning && STATE.cities.length === 0) {
      openSplash();   // cleared data — treat as first-time
    }
  }

  applySettings();
  syncSettingsUI();
  updateNotifDot();
  updatePlaceholder();
  updateManageBtn();
  updateMyLocButton();

  // Show cookie banner only if never answered
  if (STATE.cookieConsent === null) {
    setTimeout(() => document.getElementById('cookie-bar').classList.add('on'), 3000);
  }

  // ── Responsive layout auto-switch at 768px breakpoint ──
  // When the window crosses the 768px threshold, auto-switch horizontal/vertical
  // and animate the layout button so the user sees it triggered.
  // Manual clicks set STATE._manualLayoutOverride = true; this resets on threshold crossing.
  STATE._manualLayoutOverride = false;
  // Manage button click
  document.getElementById('manage-btn').addEventListener('click', toggleManageMode);

  // More menu (hamburger) — mobile overflow panel
  (function() {
    const moreBtn  = document.getElementById('more-btn');
    const moreMenu = document.getElementById('more-menu');
    if (!moreBtn || !moreMenu) return;
    moreBtn.addEventListener('click', e => {
      e.stopPropagation();
      const open = moreMenu.classList.toggle('on');
      moreBtn.setAttribute('aria-expanded', String(open));
    });
    document.addEventListener('click', e => {
      if (!e.target.closest('#more-menu') && !e.target.closest('#more-btn')) {
        moreMenu.classList.remove('on');
        moreBtn.setAttribute('aria-expanded', 'false');
      }
    });
    moreMenu.querySelectorAll('.mm-btn[data-target]').forEach(btn => {
      btn.addEventListener('click', () => {
        const target = document.getElementById(btn.dataset.target);
        if (target) target.click();
        if (btn.dataset.keepOpen !== 'true') {
          moreMenu.classList.remove('on');
          moreBtn.setAttribute('aria-expanded', 'false');
        }
      });
    });
  })();

  let _prevNarrow = window.innerWidth < 768;
  let _eqTimer    = null;
  window.addEventListener('resize', () => {
    clearTimeout(_eqTimer);
    _eqTimer = setTimeout(equalizeInfoHeights, 80);
    const narrow = window.innerWidth < 768;
    updateManageBtn();
    if (narrow === _prevNarrow) return; // no threshold crossing
    _prevNarrow = narrow;
    STATE._manualLayoutOverride = false; // threshold cross clears manual override
    STATE.settings.horiz = narrow;
    document.getElementById('s-horiz').checked = narrow;
    applySettings();
    saveState();
    // Pulse animation to show the auto-switch was triggered by resize
    const lb = document.getElementById('layout-ctl');
    lb.classList.remove('auto-switched');
    void lb.offsetWidth; // force reflow to restart animation
    lb.classList.add('auto-switched');
    setTimeout(() => lb.classList.remove('auto-switched'), 800);
  });

  // ── City-info height self-healing ────────────────────────────────────────
  new MutationObserver(() => {
    clearTimeout(_eqTimer);
    _eqTimer = setTimeout(equalizeInfoHeights, 80);
  }).observe(document.getElementById('cities-wrap'), { childList: true, subtree: true, attributes: true, attributeFilter: ['style'] });

  // ?tz= URL param — add cities from UTC offsets or names
  if (_qpTz && STATE.cities.length === 0) {
    _qpTz.split(',').forEach(raw => {
      const val = raw.trim();
      if (!val) return;
      // Numeric offset: +11, -5, 0
      const offsetMatch = val.match(/^([+-]?\d+(?:\.\d+)?)$/);
      if (offsetMatch) {
        const want = parseFloat(offsetMatch[1]);
        // Find first CITY_DB city whose timezone offset is closest to want
        let best = null, bestDiff = Infinity;
        CITY_DB.forEach(c => {
          try {
            const parts = new Intl.DateTimeFormat('en', {
              timeZone: c.tz, timeZoneName: 'shortOffset'
            }).formatToParts(new Date());
            const offStr = parts.find(p => p.type === 'timeZoneName')?.value || 'GMT';
            const m = offStr.match(/GMT([+-])(\d+)(?::(\d+))?/);
            const off = m ? (m[1]==='+' ? 1 : -1) * (parseInt(m[2]) + parseInt(m[3]||0)/60) : 0;
            const diff = Math.abs(off - want);
            if (diff < bestDiff) { bestDiff = diff; best = c; }
          } catch(_) {}
        });
        if (best) addEarthCity({...best});
        return;
      }
      // Planet zone: AMT+1, LMT-3, etc.
      const planetMatch = val.match(/^(AMT|LMT|MMT|VMT|JMT|SMT|UMT|NMT)([+-]\d+)$/i);
      if (planetMatch) {
        const prefix = planetMatch[1].toUpperCase();
        const bodyMap = {AMT:'mars',LMT:'moon',MMT:'mercury',VMT:'venus',
                         JMT:'jupiter',SMT:'saturn',UMT:'uranus',NMT:'neptune'};
        const planet = bodyMap[prefix];
        const offset = parseFloat(planetMatch[2]);
        if (planet) addPlanet(planet, offset, val, val);
        return;
      }
      // City name: case-insensitive match
      const nameLower = val.toLowerCase();
      const city = CITY_DB.find(c => c.city.toLowerCase() === nameLower);
      if (city) addEarthCity({...city});
    });
  }

  // ?preset= — pre-seed the board with a named configuration (Story 6.2)
  if (_qpPreset && STATE.cities.length === 0) {
    if (_qpPreset === 'demo') {
      // Same as qa-demo: Houston + London + random Mars zone
      const houston = CITY_DB.find(c => c.city === 'Houston' && c.country === 'USA');
      const london  = CITY_DB.find(c => c.city === 'London'  && c.country === 'UK');
      if (houston) addEarthCity(houston);
      if (london)  addEarthCity(london);
      const marsZones = PlanetTime.MARS_ZONES || [];
      const zone = marsZones[Math.floor(Math.random() * marsZones.length)]
               || { id: 'AMT', name: 'Airy Mean Time', offsetH: 0 };
      addPlanet('mars', zone.offsetH || 0, zone.id || 'AMT', zone.name || 'Airy Mean Time');
    } else if (_qpPreset === 'random') {
      loadRandomCities();
    } else if (_qpPreset === 'earth') {
      loadEarthOnlyCities();
    } else if (_qpPreset === 'interplanet') {
      loadInterplanetDemo();
    }
  }

  // ?schedule=fullscreen — open meeting panel in fullscreen mode
  if (_qpSched === 'fullscreen') {
    // Update fullscreen link to include current hash config so users can bookmark
    const fsl = document.getElementById('mp-fullscreen-link');
    if (fsl) fsl.href = '?schedule=fullscreen' + location.hash;
    // Open after a short delay to let rendering settle
    setTimeout(() => openMeetingPanel(), 100);
  }

  // Initial HDTN fetch (runs after state is loaded)
  refreshAllHdtn();

  // Story 8.2 — gentle user feedback prompt after 5+ returning sessions
  _maybeShowFeedbackPrompt();
}

init();

// ════════════════════════════════════════════════════════════════════════════
// EASTER EGGS
// ════════════════════════════════════════════════════════════════════════════

// ── 19.1 — Pluto Is A Planet ───────────────────────────────────────────────
// Pluto can be added via the custom system importer, but a hidden toggle in
// Settings adds it instantly. Activated by clicking the settings gear 8× fast.
(function initPlutoEasterEgg() {
  let clickCount = 0;
  let clickTimer = null;
  const gear = document.getElementById('settings-ctl');
  if (!gear) return;

  // Load any previous Pluto unlock
  if (localStorage.getItem('ee_pluto') === '1') _addPluto();

  gear.addEventListener('click', () => {
    clickCount++;
    clearTimeout(clickTimer);
    clickTimer = setTimeout(() => { clickCount = 0; }, 2000);
    if (clickCount >= 8) {
      clickCount = 0;
      if (!LOCAL_PLANETS.pluto) {
        _addPluto();
        try { localStorage.setItem('ee_pluto', '1'); } catch(_) {}
        showToast('🪐 Pluto is a planet! (added to planet search)');
      }
    }
  });

  function _addPluto() {
    // 24 Pluto Mean Time zones (PMT), named from IAU-recognised New Horizons features.
    // Prime meridian (PMT+0) = sub-Charon point (0°E, facing Charon).
    // Anti-Charon hemisphere (PMT±12 = 180°E) contains Tombaugh Regio / Sputnik Planitia.
    const plutoZones = _makeBodyZones('PMT', [
      /* +0  0°E   */ 'Sub-Charon Hemisphere',    // faces Charon; IAU 0° prime meridian
      /* +1  15°E  */ 'Charon-facing Lowlands',   // poorly imaged (facing away during flyby)
      /* +2  30°E  */ 'Pioneer Terra',             // rugged highland terrain
      /* +3  45°E  */ 'Lowell Regio (west)',       // N polar methane/nitrogen ice cap
      /* +4  60°E  */ 'Lowell Regio',              // N polar region; named for Percival Lowell
      /* +5  75°E  */ 'Lowell Regio (east)',       // eastern edge of polar cap
      /* +6  90°E  */ 'Viking Terra',              // rugged northern highlands
      /* +7  105°E */ 'Hayabusa Terra',            // cratered mid-latitude terrain
      /* +8  120°E */ 'Cthulhu Macula (west)',     // dark tholin-rich region; whale-shaped
      /* +9  135°E */ 'Cthulhu Macula',            // centre of dark equatorial belt
      /* +10 150°E */ 'Cthulhu Macula (east)',     // eastern lobe
      /* +11 165°E */ 'Tenzing Montes',            // ~163°E; mountain chain bordering Sputnik
      /* ±12 180°E */ 'Tombaugh Regio',            // anti-Charon; heart feature; Sputnik Planitia
      /* -11 165°W */ 'Al-Idrisi Montes',          // mountains N of Sputnik Planitia
      /* -10 150°W */ 'Tartarus Dorsa',            // ~220°E; distinctive bladed terrain
      /* -9  135°W */ 'Djanggawul Fossae',         // fracture/canyon system
      /* -8  120°W */ 'Wright Montes',             // ice-volcano candidate; ~300°E
      /* -7  105°W */ 'Krun Macula',               // southern dark region; Mesopotamian underworld
      /* -6  90°W  */ 'Adlivun Cavus',             // large depression; Inuit afterlife
      /* -5  75°W  */ 'Sleipnir Fossa',            // canyon; Norse mythological horse
      /* -4  60°W  */ 'Virgil Fossae',             // fracture system; nitrogen-ice extrusion hints
      /* -3  45°W  */ 'Mwindo Fossae',             // fracture; African epic hero
      /* -2  30°W  */ 'Hillary Montes',            // mountains; named for Sir Edmund Hillary
      /* -1  15°W  */ 'Pigafetta Montes',          // mountains W of Sputnik; explorer namesake
    ]);

    LOCAL_PLANETS.pluto = {
      name: 'Pluto', symbol: '🪐', color: '#b8956a',
      // Rotation / orbital mechanics
      solarDayMs:          6.387 * 86400000,            // 153.28 h; retrograde; mutual tidal lock with Charon
      orbitalPeriodYears:  248.09,                      // Earth years per Pluto orbit
      perihelionEpoch:     Date.UTC(1989, 8, 5),        // most recent perihelion: 1989-09-05
      orbitA:              39.48,                       // semi-major axis (AU)
      orbitE:              0.2488,                      // eccentricity (perihelion 29.6 AU, aphelion 49.3 AU)
      // Display
      workHoursStart: 9, workHoursEnd: 17,
      albedo: 0.52,    // averaged; Sputnik Planitia ~0.9, Cthulhu Macula ~0.03
      // New Horizons (2015): black sky with faint blue N₂/CH₄ photochemical haze at limb
      skyPalette: {
        n:  {r:3,  g:4,  b:9 },   // night: near-black with star glow
        tw: {r:8,  g:14, b:30},   // sunrise haze: very faint blue (NH detected haze)
        dH: {r:12, g:18, b:36},   // daytime horizon: dark blue-black
        dZ: {r:3,  g:4,  b:9 },   // zenith: black; Sun ≈ bright star at 35+ AU
        airless: false,            // thin N₂ atmosphere (~10 μbar)
        twRange: 5,
      },
      zones: plutoZones,
      notes: 'Dwarf planet — or PLANET, depending on your feelings about the 2006 IAU vote. ' +
             'Mutually tidally locked with Charon. 1 Pluto day = 6.387 Earth days. ' +
             '~14,180 sols per Pluto year (248.09 Earth years). ' +
             'Surface: ~−229°C. Diameter: 2,376 km. Distance: 29.6–49.3 AU.',
    };

    // Register zones so existing PLANET_ZONES lookups also find them
    PlanetTime.PLANET_ZONES.pluto = plutoZones;
  }
})();

// ── 19.2 — Unix Epoch Meltdown (Y2K38 countdown) ──────────────────────────
// Shows a subtle countdown chip to 2038-01-19T03:14:08Z (32-bit Unix overflow).
(function initY2K38() {
  const Y2K38_UTC = 2147483648000;  // 2038-01-19T03:14:08Z in Unix ms
  const chip = document.createElement('div');
  chip.id = 'y2k38-chip';
  document.body.appendChild(chip);

  function _updateChip() {
    const ms = Y2K38_UTC - Date.now();
    if (ms <= 0) { chip.textContent = '⚠ Epoch meltdown'; return; }
    const days  = Math.floor(ms / 86400000);
    const hrs   = Math.floor((ms % 86400000) / 3600000);
    const mins  = Math.floor((ms % 3600000) / 60000);
    const secs  = Math.floor((ms % 60000) / 1000);
    chip.textContent = `Y2K38: ${days}d ${String(hrs).padStart(2,'0')}:${String(mins).padStart(2,'0')}:${String(secs).padStart(2,'0')}`;
  }
  _updateChip();
  setInterval(_updateChip, 1000);
})();

// ── 19.3 — Kerbal Mode (Konami code) ──────────────────────────────────────
// ↑ ↑ ↓ ↓ ← → ← → B A → shows Hohmann transfer windows + plays Web Audio chime.
(function initKerbalMode() {
  const KONAMI = ['ArrowUp','ArrowUp','ArrowDown','ArrowDown',
                  'ArrowLeft','ArrowRight','ArrowLeft','ArrowRight','b','a'];
  let seq = [];

  document.addEventListener('keydown', e => {
    seq.push(e.key);
    if (seq.length > KONAMI.length) seq.shift();
    if (seq.join(',') === KONAMI.join(',')) {
      seq = [];
      _showKerbalMode();
    }
  });

  function _hohmannDv(r1, r2) {
    // Simplified Hohmann Δv calculation (circular orbits, AU units)
    const mu = 1.0; // GM_sun normalised to 1 in AU/yr² units
    const v1  = Math.sqrt(mu / r1);
    const v2  = Math.sqrt(mu / r2);
    const va  = Math.sqrt(mu * (2 / r1 - 2 / (r1 + r2)));
    const vb  = Math.sqrt(mu * (2 / r2 - 2 / (r1 + r2)));
    const dv1 = Math.abs(va - v1);
    const dv2 = Math.abs(v2 - vb);
    const tof = Math.PI * Math.sqrt(Math.pow((r1 + r2) / 2, 3) / mu);  // years
    return { dv1: dv1.toFixed(3), dv2: dv2.toFixed(3), tofDays: Math.round(tof * 365.25) };
  }

  function _showKerbalMode() {
    // Play ascending chime via Web Audio
    try {
      const ctx  = new (window.AudioContext || window.webkitAudioContext)();
      [523.25, 659.25, 783.99, 1046.5].forEach((freq, i) => {
        const osc  = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.connect(gain); gain.connect(ctx.destination);
        osc.frequency.value = freq;
        osc.type = 'sine';
        gain.gain.setValueAtTime(0, ctx.currentTime + i * 0.18);
        gain.gain.linearRampToValueAtTime(0.18, ctx.currentTime + i * 0.18 + 0.05);
        gain.gain.linearRampToValueAtTime(0, ctx.currentTime + i * 0.18 + 0.35);
        osc.start(ctx.currentTime + i * 0.18);
        osc.stop(ctx.currentTime + i * 0.18 + 0.4);
      });
    } catch(_) {}

    // Build Hohmann table for inner planets
    const pairs = [
      { from: 'Earth', to: 'Mars',    r1: 1.000, r2: 1.524 },
      { from: 'Earth', to: 'Jupiter', r1: 1.000, r2: 5.203 },
      { from: 'Earth', to: 'Venus',   r1: 0.723, r2: 1.000 },
      { from: 'Mars',  to: 'Earth',   r1: 1.524, r2: 1.000 },
    ];

    let rows = pairs.map(p => {
      const h = _hohmannDv(p.r1, p.r2);
      return `<tr><td>${p.from} → ${p.to}</td><td>${h.dv1}</td><td>${h.dv2}</td><td>${h.tofDays} days</td></tr>`;
    }).join('');

    let overlay = document.getElementById('kerbal-overlay');
    if (!overlay) {
      overlay = document.createElement('div');
      overlay.id = 'kerbal-overlay';
      overlay.innerHTML = `<div id="kerbal-banner">
        <h2>🚀 Kerbal Mode Activated</h2>
        <p>Hohmann Transfer Windows — simplified (circular orbits)</p>
        <table style="width:100%;font-size:.75rem;border-collapse:collapse;margin:.75rem 0">
          <thead><tr style="opacity:.5"><th style="text-align:left">Route</th><th>Δv₁ (AU/yr)</th><th>Δv₂ (AU/yr)</th><th>TOF</th></tr></thead>
          <tbody>${rows}</tbody>
        </table>
        <p style="font-size:.68rem;opacity:.5">↑↑↓↓←→←→BA — now you know the secret</p>
        <button class="kerbal-close">Roger that, KSC 🛸</button>
      </div>`;
      document.body.appendChild(overlay);
      overlay.querySelector('.kerbal-close').addEventListener('click', () => {
        overlay.classList.remove('active');
      });
      overlay.addEventListener('click', e => {
        if (e.target === overlay) overlay.classList.remove('active');
      });
    }
    requestAnimationFrame(() => requestAnimationFrame(() => overlay.classList.add('active')));
  }
})();

// ── 19.4 — Great Year Drift Indicator ─────────────────────────────────────
// Shows subtle axial precession drift indicator. Vernal equinox precesses
// one full cycle in ~25,772 years (the "Great Year" / Platonic Year).
(function initGreatYearIndicator() {
  const GREAT_YEAR = 25772;  // years per precession cycle
  const J2000      = 2451545.0;
  const JD_NOW     = Date.now() / 86400000 + 2440587.5;
  const yearsFromJ2000 = (JD_NOW - J2000) / 365.25;
  const phasePct   = ((yearsFromJ2000 % GREAT_YEAR) + GREAT_YEAR) % GREAT_YEAR / GREAT_YEAR;
  const ageDeg     = (phasePct * 360).toFixed(2);

  const el = document.createElement('div');
  el.className = 'great-year-indicator';
  el.title = 'Great Year (axial precession) drift from J2000.0';
  el.textContent = `precession ${ageDeg}°`;
  document.body.appendChild(el);
})();

// ── 19.5 — Apollo 11 Reference ────────────────────────────────────────────
// On 20 Jul 20:17 UTC, show a small memorial badge for Eagle's landing.
(function initApollo11() {
  const badge = document.createElement('div');
  badge.id = 'apollo-badge';
  badge.innerHTML =
    '🌕 <strong>Apollo 11</strong><br>' +
    'Eagle landed — 20 Jul 1969 20:17 UTC<br>' +
    '<span style="font-size:.6rem;opacity:.6">\"That\'s one small step…\"</span>';
  document.body.appendChild(badge);

  function _checkApollo() {
    const now = new Date();
    const isAnniversary =
      now.getUTCMonth() === 6 &&   // July
      now.getUTCDate()  === 20 &&
      now.getUTCHours() >= 20 && now.getUTCHours() < 22;
    badge.classList.toggle('visible', isAnniversary);
  }
  _checkApollo();
  setInterval(_checkApollo, 60000);
})();

// ── 19.6 — Leap Second Easter Egg ─────────────────────────────────────────
// At exactly 23:59:59 UTC on 31 Dec of any even year, briefly simulate 23:59:60.
(function initLeapSecond() {
  function _checkLeapSecond() {
    const now = new Date();
    // Only trigger on NYE at 23:59:59 UTC — roughly every ~2 years (simplified)
    if (now.getUTCMonth()   !== 11) return;
    if (now.getUTCDate()    !== 31) return;
    if (now.getUTCHours()   !== 23) return;
    if (now.getUTCMinutes() !== 59) return;
    if (now.getUTCSeconds() !== 59) return;
    showToast('🕛 23:59:60 — Inserting leap second! (simulated)');
  }
  setInterval(_checkLeapSecond, 1000);
})();

// ── 27.1 — Drag-to-reorder city cards ─────────────────────────────────────
// HTML5 drag-and-drop (desktop) + touch events (mobile) activated in manage mode.
// After first reorder: STATE.settings.manualOrder = true → sortCities() preserves order.
(function initDragReorder() {
  let _dragId    = null;   // id of city being dragged (desktop)
  let _touchId   = null;   // id of city being touch-dragged (mobile)
  let _touchOver = null;   // { id, after } of current drop target (mobile)

  // ── Perform the reorder ──────────────────────────────────────────────────
  function _performReorder(fromId, toId, insertAfter) {
    const fromIdx = STATE.cities.findIndex(c => c.id === fromId);
    const toIdx   = STATE.cities.findIndex(c => c.id === toId);
    if (fromIdx < 0 || toIdx < 0 || fromIdx === toIdx) return;

    const [moved] = STATE.cities.splice(fromIdx, 1);
    let insertIdx = STATE.cities.findIndex(c => c.id === toId);
    if (insertAfter) insertIdx++;
    STATE.cities.splice(insertIdx, 0, moved);

    // Re-sync DOM order
    const wrap   = document.getElementById('cities-wrap');
    const addBtn = document.getElementById('add-col');
    STATE.cities.forEach(c => {
      const el = document.getElementById(`city-${c.id}`);
      if (el) wrap.insertBefore(el, addBtn);
    });

    STATE.settings.manualOrder = true;
    saveState();
    syncHash();
  }

  function _clearIndicators() {
    document.querySelectorAll('.city-col.drag-over-before, .city-col.drag-over-after')
      .forEach(el => el.classList.remove('drag-over-before', 'drag-over-after'));
  }

  function _getInsertSide(el, clientX, clientY) {
    const horiz = document.getElementById('cities-wrap').classList.contains('horiz');
    const rect  = el.getBoundingClientRect();
    const mid   = horiz ? rect.top + rect.height / 2 : rect.left + rect.width / 2;
    return (horiz ? clientY : clientX) >= mid;  // true = insert after
  }

  // ── Desktop drag handlers ────────────────────────────────────────────────
  function _onDragStart(e) {
    _dragId = parseInt(this.id.replace('city-', ''), 10);
    this.classList.add('dragging');
    e.dataTransfer.effectAllowed = 'move';
    e.dataTransfer.setData('text/plain', String(_dragId));
  }

  function _onDragEnd() {
    this.classList.remove('dragging');
    _clearIndicators();
    _dragId = null;
  }

  function _onDragOver(e) {
    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
    const targetId = parseInt(this.id.replace('city-', ''), 10);
    if (!_dragId || targetId === _dragId) return;
    _clearIndicators();
    const after = _getInsertSide(this, e.clientX, e.clientY);
    this.classList.add(after ? 'drag-over-after' : 'drag-over-before');
  }

  function _onDragLeave() {
    this.classList.remove('drag-over-before', 'drag-over-after');
  }

  function _onDrop(e) {
    e.preventDefault();
    const targetId = parseInt(this.id.replace('city-', ''), 10);
    const after    = this.classList.contains('drag-over-after');
    _clearIndicators();
    if (_dragId && _dragId !== targetId) _performReorder(_dragId, targetId, after);
  }

  // ── Touch drag handlers (on drag-handle element) ─────────────────────────
  function _onHandleTouchStart(e) {
    e.preventDefault();  // prevent page scroll while dragging
    _touchId   = parseInt(this.closest('.city-col').id.replace('city-', ''), 10);
    _touchOver = null;
    const col = document.getElementById(`city-${_touchId}`);
    if (col) col.classList.add('dragging');
  }

  function _onHandleTouchMove(e) {
    e.preventDefault();
    if (_touchId === null) return;
    const touch = e.touches[0];

    // Temporarily hide dragged col so elementFromPoint finds what's beneath
    const draggingEl = document.getElementById(`city-${_touchId}`);
    if (draggingEl) draggingEl.style.visibility = 'hidden';
    const under = document.elementFromPoint(touch.clientX, touch.clientY);
    if (draggingEl) draggingEl.style.visibility = '';

    const targetCol = under && under.closest('.city-col');
    _clearIndicators();

    if (targetCol && targetCol.id !== `city-${_touchId}`) {
      const targetId = parseInt(targetCol.id.replace('city-', ''), 10);
      const after    = _getInsertSide(targetCol, touch.clientX, touch.clientY);
      targetCol.classList.add(after ? 'drag-over-after' : 'drag-over-before');
      _touchOver = { id: targetId, after };
    } else {
      _touchOver = null;
    }
  }

  function _onHandleTouchEnd() {
    const col = document.getElementById(`city-${_touchId}`);
    if (col) col.classList.remove('dragging');
    _clearIndicators();
    if (_touchId !== null && _touchOver) {
      _performReorder(_touchId, _touchOver.id, _touchOver.after);
    }
    _touchId   = null;
    _touchOver = null;
  }

  // ── Init / teardown ───────────────────────────────────────────────────────
  window._dragInit = function() {
    STATE.cities.forEach(c => {
      const el     = document.getElementById(`city-${c.id}`);
      const handle = el && el.querySelector('.drag-handle');
      if (!el || !handle) return;

      // Desktop HTML5 DnD
      el.setAttribute('draggable', 'true');
      el.addEventListener('dragstart', _onDragStart);
      el.addEventListener('dragend',   _onDragEnd);
      el.addEventListener('dragover',  _onDragOver);
      el.addEventListener('dragleave', _onDragLeave);
      el.addEventListener('drop',      _onDrop);

      // Mobile touch (on handle only to avoid fighting scroll)
      handle.addEventListener('touchstart', _onHandleTouchStart, { passive: false });
      handle.addEventListener('touchmove',  _onHandleTouchMove,  { passive: false });
      handle.addEventListener('touchend',   _onHandleTouchEnd);
    });
  };

  window._dragTeardown = function() {
    document.querySelectorAll('.city-col').forEach(el => {
      el.removeAttribute('draggable');
      el.removeEventListener('dragstart', _onDragStart);
      el.removeEventListener('dragend',   _onDragEnd);
      el.removeEventListener('dragover',  _onDragOver);
      el.removeEventListener('dragleave', _onDragLeave);
      el.removeEventListener('drop',      _onDrop);
      el.classList.remove('dragging', 'drag-over-before', 'drag-over-after');

      const handle = el.querySelector('.drag-handle');
      if (handle) {
        handle.removeEventListener('touchstart', _onHandleTouchStart);
        handle.removeEventListener('touchmove',  _onHandleTouchMove);
        handle.removeEventListener('touchend',   _onHandleTouchEnd);
      }
    });
    _dragId = null; _touchId = null; _touchOver = null;
  };
})();

// ── 28.1 — Time Travel mode ────────────────────────────────────────────────
// Lets the user scrub to any moment in time; all city clocks, work indicators,
// planet positions, and sky gradients reflect the chosen moment.
//
// STATE.timeTravelMs = 0 → live (default)
//                   ≠ 0 → offset in ms from Date.now()
// getNow() is used everywhere in the display path instead of new Date().
(function initTimeTravel() {
  const HR_MS  = 3600000;
  const DAY_MS = 86400000;

  function _isoLocalForInput(d) {
    const off = d.getTimezoneOffset() * 60000;
    return new Date(d.getTime() - off).toISOString().slice(0, 16);
  }

  function _refreshAll() {
    STATE.cities.forEach(c => updateCityDisplay(c));
    updatePlaceholder();
    _updateBadge();
  }

  function _updateBadge() {
    const badge = document.getElementById('tt-badge');
    if (!badge) return;
    const offset = STATE.timeTravelMs;
    if (offset === 0) { badge.classList.remove('visible'); badge.textContent = ''; return; }
    const abs  = Math.abs(offset);
    const sign = offset > 0 ? '+' : '−';
    let label;
    if      (abs >= DAY_MS)  label = `${sign}${Math.round(abs / DAY_MS)}d`;
    else if (abs >= HR_MS)   label = `${sign}${Math.round(abs / HR_MS)}h`;
    else                     label = `${sign}${Math.round(abs / 60000)}m`;
    badge.textContent = `⏱ ${label}`;
    badge.classList.add('visible');
  }

  function _syncInput() {
    const inp = document.getElementById('tt-input');
    if (inp) inp.value = _isoLocalForInput(getNow());
  }

  window.timeTravelTo = function(isoOrDate) {
    const target = isoOrDate instanceof Date ? isoOrDate : new Date(isoOrDate);
    if (isNaN(target.getTime())) return;
    STATE.timeTravelMs = target.getTime() - Date.now();
    _syncInput();
    _refreshAll();
  };

  window.timeTravelStep = function(deltaMs) {
    STATE.timeTravelMs += deltaMs;
    _syncInput();
    _refreshAll();
  };

  window.timeTravelLive = function() {
    STATE.timeTravelMs = 0;
    _syncInput();
    _refreshAll();
  };

  window.toggleTimeTravel = function() {
    const bar = document.getElementById('tt-bar');
    const btn = document.getElementById('tt-btn');
    if (!bar) return;
    const on = bar.classList.toggle('on');
    if (btn) { btn.classList.toggle('active', on); btn.setAttribute('aria-pressed', String(on)); }
    if (on) _syncInput();
  };

  document.addEventListener('DOMContentLoaded', () => {
    const inp   = document.getElementById('tt-input');
    if (inp) inp.addEventListener('change', () => { if (inp.value) window.timeTravelTo(inp.value); });
    const btnLive = document.getElementById('tt-live-btn');
    if (btnLive) btnLive.addEventListener('click', window.timeTravelLive);
    [['tt-back-day', -DAY_MS], ['tt-back-hour', -HR_MS],
     ['tt-fwd-hour',  HR_MS],  ['tt-fwd-day',   DAY_MS]].forEach(([id, delta]) => {
      const b = document.getElementById(id);
      if (b) b.addEventListener('click', () => window.timeTravelStep(delta));
    });
  });
})();

// ── Solar system orrery (Story 31.1) ──────────────────────────────────────────
(() => {
  'use strict';

  const PLANET_KEYS  = ['mercury','venus','earth','mars','jupiter','saturn','uranus','neptune'];
  const DOT_RADIUS   = { mercury:2, venus:2.5, earth:2.5, mars:2.5, jupiter:4, saturn:3.5, uranus:3, neptune:3 };
  const FALLBACK_COL = { mercury:'#b0b0b0', venus:'#e8cda0', earth:'#4fa3e8', mars:'#e27b58',
                         jupiter:'#c88b3a', saturn:'#e8d9a0', uranus:'#7de8e8', neptune:'#5b7fde' };

  let _timer  = null;
  let _canvas = null;
  let _ctx    = null;

  function _planetColor(key) {
    try {
      const P = PlanetTime.PLANETS[key];
      return (P && P.color) || FALLBACK_COL[key] || '#fff';
    } catch(_) { return FALLBACK_COL[key] || '#fff'; }
  }

  function _helioPos(key, date) {
    try { return PlanetTime.planetHelioXY(key, date); } catch(_) { return null; }
  }

  // Square-root scale so outer planets remain visible:  R_screen = k * sqrt(r_AU)
  function _sqrtScale(rAU, k) { return k * Math.sqrt(rAU); }

  function _draw() {
    if (!_canvas || !_ctx) return;
    const now  = (typeof getNow === 'function') ? getNow() : new Date();
    const W    = _canvas.width;
    const H    = _canvas.height;
    if (!W || !H) return;

    _ctx.clearRect(0, 0, W, H);

    // k = pixels per sqrt(AU), fit Neptune (~30 AU) within the half-size with 5% margin
    const half = Math.min(W, H) / 2 * 0.93;
    const k    = half / Math.sqrt(30);
    const cx   = W / 2;
    const cy   = H / 2;

    // Board planets (highlighted) — include 'earth' when any Earth city is on the board
    const boardSet = new Set(
      (STATE && STATE.cities ? STATE.cities : [])
        .filter(c => c.type === 'planet').map(c => c.planet)
    );
    if ((STATE && STATE.cities ? STATE.cities : []).some(c => c.type === 'earth')) boardSet.add('earth');

    // ── Orbit rings ────────────────────────────────────────────────────────────
    _ctx.lineWidth = 0.6;
    for (const key of PLANET_KEYS) {
      const pos = _helioPos(key, now);
      if (!pos) continue;
      const sr = _sqrtScale(pos.r, k);
      _ctx.beginPath();
      _ctx.arc(cx, cy, sr, 0, 2 * Math.PI);
      _ctx.strokeStyle = boardSet.has(key) ? 'rgba(255,255,255,0.18)' : 'rgba(255,255,255,0.07)';
      _ctx.stroke();
    }

    // ── Sun ────────────────────────────────────────────────────────────────────
    const glow = _ctx.createRadialGradient(cx, cy, 0, cx, cy, 11);
    glow.addColorStop(0, 'rgba(255,230,50,0.55)');
    glow.addColorStop(1, 'rgba(255,200,0,0)');
    _ctx.fillStyle = glow;
    _ctx.beginPath(); _ctx.arc(cx, cy, 11, 0, 2 * Math.PI); _ctx.fill();

    _ctx.fillStyle = '#ffe040';
    _ctx.beginPath(); _ctx.arc(cx, cy, 4, 0, 2 * Math.PI); _ctx.fill();

    // ── Planets ────────────────────────────────────────────────────────────────
    for (const key of PLANET_KEYS) {
      const pos = _helioPos(key, now);
      if (!pos) continue;

      const sr   = _sqrtScale(pos.r, k);
      const ang  = Math.atan2(pos.y, pos.x);
      const px   = cx + Math.cos(ang) * sr;
      const py   = cy - Math.sin(ang) * sr;   // y flipped for screen
      const col  = _planetColor(key);
      const dr   = DOT_RADIUS[key] || 3;
      const onBd = boardSet.has(key);

      // Highlight ring for board planets
      if (onBd) {
        _ctx.beginPath(); _ctx.arc(px, py, dr + 4, 0, 2 * Math.PI);
        _ctx.strokeStyle = col; _ctx.globalAlpha = 0.45; _ctx.lineWidth = 1.5; _ctx.stroke();
        _ctx.globalAlpha = 1;
      }

      // Dot
      _ctx.beginPath(); _ctx.arc(px, py, dr, 0, 2 * Math.PI);
      _ctx.fillStyle = col; _ctx.fill();

      // Label (board planets only — avoids clutter)
      if (onBd) {
        _ctx.fillStyle = col;
        _ctx.font = `bold 8px system-ui,sans-serif`;
        _ctx.textAlign = 'center';
        _ctx.textBaseline = 'bottom';
        _ctx.fillText(key.charAt(0).toUpperCase() + key.slice(1), px, py - dr - 2);
        _ctx.textBaseline = 'alphabetic';
      }
    }

    // ── Date label ─────────────────────────────────────────────────────────────
    const dateEl = document.getElementById('orrery-date');
    if (dateEl) {
      const iso = now.toISOString().replace('T', ' ').slice(0, 16) + ' UTC';
      if (STATE && STATE.timeTravelMs) {
        dateEl.textContent = '⏱ ' + iso;
      } else {
        dateEl.textContent = iso;
      }
    }
  }

  // ── Open / close / toggle ───────────────────────────────────────────────────

  window.openOrrery = function() {
    const panel = document.getElementById('orrery-panel');
    if (!panel) return;
    panel.classList.add('on');
    document.getElementById('orrery-btn').setAttribute('aria-expanded', 'true');
    document.getElementById('orrery-btn').classList.add('active');

    // Size canvas to container
    _canvas = document.getElementById('orrery-canvas');
    if (_canvas) {
      const rect = _canvas.getBoundingClientRect();
      _canvas.width  = rect.width  || 290;
      _canvas.height = rect.height || 274;
      _ctx = _canvas.getContext('2d');
    }
    _draw();
    if (!_timer) _timer = setInterval(_draw, 1000);
  };

  window.closeOrrery = function() {
    const panel = document.getElementById('orrery-panel');
    if (!panel || !panel.classList.contains('on')) return;
    panel.classList.remove('on');
    document.getElementById('orrery-btn').setAttribute('aria-expanded', 'false');
    document.getElementById('orrery-btn').classList.remove('active');
    if (_timer) { clearInterval(_timer); _timer = null; }
  };

  window.toggleOrrery = function() {
    const panel = document.getElementById('orrery-panel');
    if (panel && panel.classList.contains('on')) { window.closeOrrery(); } else { window.openOrrery(); }
  };

  // Wire up controls
  document.addEventListener('DOMContentLoaded', () => {
    const btn = document.getElementById('orrery-btn');
    if (btn) btn.addEventListener('click', window.toggleOrrery);
    const cls = document.getElementById('orrery-close');
    if (cls) cls.addEventListener('click', window.closeOrrery);

    // Resize canvas when window resizes while panel is open
    window.addEventListener('resize', () => {
      if (_canvas && document.getElementById('orrery-panel').classList.contains('on')) {
        const rect = _canvas.getBoundingClientRect();
        _canvas.width  = rect.width  || 290;
        _canvas.height = rect.height || 274;
        _ctx = _canvas.getContext('2d');
        _draw();
      }
    });
  });
})();
