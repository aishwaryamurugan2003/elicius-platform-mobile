import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/api/api_service.dart';
import '../core/api/endpoints.dart';
import '../core/ist_time.dart';

/// A group the signed-in user can access, with the device ids they can see in it.
class UserGroup {
  UserGroup({required this.id, required this.name, required this.devices});

  factory UserGroup.fromJson(Map<String, dynamic> j) => UserGroup(
        id: '${j['id']}',
        name: (j['name'] ?? j['id']).toString(),
        devices: ((j['devices'] as List?) ?? const []).map((d) => '$d').toList(),
      );

  final String id;
  final String name;
  final List<String> devices;
}

/// One reading for one device: when, and every field in the packet.
class TelemetryPoint {
  TelemetryPoint(this.time, this.data);
  final DateTime time;
  final Map<String, dynamic> data;
}

class TelemetryApi {
  TelemetryApi(this._api);
  final ApiService _api;

  /// `GET /mappings/user` — groups the user is mapped to (from the bearer token).
  Future<List<UserGroup>> myGroups() async {
    final res = await _api.get<List<dynamic>>(Endpoint.myGroupMappings);
    return res.map((g) => UserGroup.fromJson(g as Map<String, dynamic>)).toList();
  }

  /// `GET /v1/devices/last-packet?group_id=` — the last-known packet per device
  /// (no Authorization header on this host).
  Future<List<TelemetryPoint>> lastPackets(String groupId, {Map<String, String>? deviceIdOut}) async {
    final res = await _api.get<Map<String, dynamic>>(Endpoint.lastPacket, query: {'group_id': groupId}, auth: false);
    final out = <TelemetryPoint>[];
    for (final p in (res['data'] as List? ?? const [])) {
      final m = p as Map<String, dynamic>;
      final t = parseUtcTimestamp(m['srvtime']) ?? parseUtcTimestamp(m['timestamp']) ?? DateTime.now().toUtc();
      final data = {...(m['data'] as Map<String, dynamic>? ?? const {}), 'dID': m['device_id'] ?? m['dID']};
      out.add(TelemetryPoint(t, data));
    }
    return out;
  }

  /// `GET /v1/data` — mean per field per device per [interval] bucket.
  /// [start]/[stop] are either relative ("-1h", "-15m") or absolute UTC times.
  Future<Map<String, List<TelemetryPoint>>> history({
    required List<String> deviceIds,
    required List<String> fields,
    required String start,
    String? stop,
    required String interval,
  }) async {
    if (deviceIds.isEmpty) return {};
    final res = await _api.get<Map<String, dynamic>>(
      Endpoint.telemetryData,
      auth: false,
      query: {
        'device_id': deviceIds.join(','),
        'measurement': 'sendata',
        'start': _toBackendTime(start, isStart: true),
        'stop': stop == null ? 'now()' : _toBackendTime(stop, isStart: false),
        'interval': interval,
        'fields': fields.join(','),
        'timestamp_representation': 'start',
      },
    );
    final byDevice = <String, List<TelemetryPoint>>{};
    for (final s in (res['data'] as List? ?? const [])) {
      final series = s as Map<String, dynamic>;
      if (series['status'] != 200) continue;
      byDevice['${series['dID']}'] = [
        for (final p in (series['data'] as List? ?? const []))
          if (parseUtcTimestamp((p as Map)['srvtime']) case final t?) TelemetryPoint(t, (p['data'] as Map).cast<String, dynamic>()),
      ];
    }
    return byDevice;
  }

  /// /v1/data only aggregates with relative m/h/d bounds — an absolute time is
  /// sent as "minutes ago", rounded inward (same rule as the web app).
  static String _toBackendTime(String value, {required bool isStart}) {
    final t = DateTime.tryParse(value);
    if (t == null || !value.contains('T')) return value;
    final minutesAgo = DateTime.now().toUtc().difference(t.toUtc()).inSeconds / 60;
    final rounded = isStart ? minutesAgo.floor() : minutesAgo.ceil();
    if (rounded <= 0) return isStart ? '-1m' : 'now()';
    return '-${rounded}m';
  }
}

/// A live packet from a group's stream.
class LiveMessage {
  LiveMessage(this.deviceId, this.time, this.data);
  final String deviceId;
  final DateTime time;
  final Map<String, dynamic> data;
}

/// One WebSocket to `/stream/group/{id}`. Reconnects with exponential backoff
/// (1 s → 30 s), rebuilding the URL each time so a fresh token is used. Call
/// [close] when the screen goes away.
class LiveGroupStream {
  LiveGroupStream(this._api, this.groupId, {required this.onMessage, this.onStatus}) {
    _open();
  }

  final ApiService _api;
  final String groupId;
  final void Function(LiveMessage) onMessage;
  final void Function(bool connected)? onStatus;

  WebSocketChannel? _ch;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  int _retryMs = 1000;
  bool _closed = false;

  void _open() {
    if (_closed) return;
    final ch = WebSocketChannel.connect(Uri.parse(_api.liveStreamUrl(groupId)));
    _ch = ch;
    ch.ready.then((_) {
      _retryMs = 1000;
      onStatus?.call(true);
    }).catchError((_) {});
    _sub = ch.stream.listen(
      (event) {
        final msg = _parse(event);
        if (msg != null) onMessage(msg);
      },
      onDone: _scheduleReconnect,
      onError: (_) => _scheduleReconnect(),
      cancelOnError: true,
    );
  }

  void _scheduleReconnect() {
    onStatus?.call(false);
    if (_closed) return;
    _retry?.cancel();
    _retry = Timer(Duration(milliseconds: _retryMs), _open);
    _retryMs = min(_retryMs * 2, 30000);
  }

  static LiveMessage? _parse(dynamic event) {
    try {
      final raw = jsonDecode(event as String);
      if (raw is! Map<String, dynamic>) return null;
      final id = raw['device_id'] ?? raw['dID'];
      if (id is! String || id.isEmpty) return null;
      final nested = raw['data'];
      final data = nested is Map ? {'dID': id, ...nested.cast<String, dynamic>()} : raw;
      final now = DateTime.now().toUtc();
      var t = parseUtcTimestamp(raw['srvtime']) ?? parseUtcTimestamp(raw['timestamp']) ?? parseUtcTimestamp(data['dTS']) ?? now;
      // Some devices stamp IST as if it were UTC — pull an impossible future time back.
      if (t.isAfter(now.add(const Duration(minutes: 2)))) {
        final shifted = t.subtract(const Duration(hours: 5, minutes: 30));
        t = shifted.difference(now).abs() <= const Duration(minutes: 10) ? shifted : now;
      }
      return LiveMessage(id, t, data);
    } catch (_) {
      return null;
    }
  }

  void close() {
    _closed = true;
    _retry?.cancel();
    _sub?.cancel();
    _ch?.sink.close();
  }
}
