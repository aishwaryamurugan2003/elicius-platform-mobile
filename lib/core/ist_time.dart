/// Every timestamp is shown in IST (UTC+05:30, no DST), whatever the phone's
/// timezone — same rule as the web app's `src/lib/istTime.ts`.
library;

const _istOffset = Duration(hours: 5, minutes: 30);
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// A backend/device timestamp -> UTC DateTime. ISO strings without a zone are
/// UTC on this platform; numbers are epoch seconds or milliseconds.
DateTime? parseUtcTimestamp(Object? value) {
  if (value is num) {
    final ms = value < 1e12 ? (value * 1000).round() : value.round();
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }
  if (value is! String || value.trim().isEmpty) return null;
  final v = value.trim();
  final hasZone = RegExp(r'([zZ]|[+-]\d\d:?\d\d)$').hasMatch(v);
  return DateTime.tryParse(hasZone ? v : '${v.replaceFirst(' ', 'T')}Z')?.toUtc();
}

DateTime toIst(DateTime t) => t.toUtc().add(_istOffset);

String _two(int n) => n.toString().padLeft(2, '0');

/// "17:05:35"
String formatIstClock(DateTime t) {
  final i = toIst(t);
  return '${_two(i.hour)}:${_two(i.minute)}:${_two(i.second)}';
}

/// "8 Oct 2026, 17:05:35"
String formatIstDateTime(DateTime t) {
  final i = toIst(t);
  return '${i.day} ${_months[i.month - 1]} ${i.year}, ${formatIstClock(t)}';
}

/// "8 Oct 17:05"
String formatIstShort(DateTime t) {
  final i = toIst(t);
  return '${i.day} ${_months[i.month - 1]} ${_two(i.hour)}:${_two(i.minute)}';
}

/// Today's IST date as "YYYY-MM-DD", optionally `daysAgo` days back.
String istDate([int daysAgo = 0]) {
  final i = toIst(DateTime.now()).subtract(Duration(days: daysAgo));
  return '${i.year}-${_two(i.month)}-${_two(i.day)}';
}
