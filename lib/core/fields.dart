/// Telemetry field labels and units — the web app's TELEMETRY_FIELDS plus the
/// extra labels from `src/lib/digitalTwinFields.ts`.
library;

const _labels = {
  'sPM2': 'PM2.5',
  'sPM1': 'PM1',
  'sPM4': 'PM4',
  'sPM10': 'PM10',
  'temp': 'Temp',
  'sTemp': 'Temperature',
  'rH': 'Rh',
  'rh': 'Humidity',
  'sRh': 'Humidity',
  'k30Co2': 'CO2',
  'CO2': 'CO2',
  'O2': 'O2',
  'co_ppb': 'CO (ppb)',
  'so2_ppb': 'SO2 (ppb)',
  'o3_ppb_compensated': 'O3 (ppb)',
  'o3_ppb': 'O3',
  'no2_ppb': 'NO2 (ppb)',
  'h2s_ppb': 'H2S',
  'rs485_data': 'RS485 data',
  'sVocI': 'VOC',
  'lat': 'Latitude',
  'long': 'Longitude',
  'alt': 'Altitude',
  // Energy monitoring
  'vln_avg': 'Voltage L-N (avg)',
  'vll_avg': 'Voltage L-L (avg)',
  'i_avg': 'Current (avg)',
  't_kw': 'Power (kW)',
  'kwh_imp': 'Energy (kWh)',
  'pf_avg': 'Power factor',
  'freq': 'Frequency',
};

String fieldLabel(String key) => _labels[key] ?? key;

/// Unit shown next to a value (blank when unknown).
String fieldUnit(String key) {
  final f = key.toLowerCase();
  if (f.contains('temp')) return '°C';
  if (f == 'srh' || f == 'rh') return '%';
  if (f.startsWith('spm') || f.startsWith('snpm')) return 'µg/m³';
  if (f.contains('co2')) return 'ppm';
  if (f.endsWith('ppb') || f.contains('_ppb')) return 'ppb';
  if (f == 'o2') return '%';
  if (f.startsWith('kwh')) return 'kWh';
  if (f.contains('kw') && !f.contains('kwh')) return 'kW';
  if (f.startsWith('v')) return 'V';
  if (f.startsWith('i')) return 'A';
  if (f == 'freq') return 'Hz';
  return '';
}

/// Packet keys that are bookkeeping, not readings.
const nonReadingKeys = {'dID', 'dTS', 'pID', 'dUT', 'srvtime', 'lHeap', 'rHeap', 'aTd0', 'aTd1', 'aTd2', 'timestamp'};

double? asNumber(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String && v.trim().isNotEmpty) return double.tryParse(v);
  return null;
}

/// Two decimals (same as Live status / dashboards), whole numbers as-is, "—" when missing.
String formatValue(Object? raw) {
  final n = asNumber(raw);
  if (n == null || !n.isFinite) return '—';
  return n == n.roundToDouble() && n.abs() < 1e15 ? n.toStringAsFixed(0) : n.toStringAsFixed(2);
}
