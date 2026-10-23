import '../core/api/api_service.dart';
import '../core/api/endpoints.dart';
import '../core/ist_time.dart';

/// Device alerts (bs7, iot-device-monitoring) — a port of `src/api/alertsApi.ts`.

String mapSeverity(String? sev) {
  final s = (sev ?? '').toUpperCase();
  if (const ['HIGH', 'CRITICAL', 'ALARM'].contains(s)) return 'Alarm';
  if (const ['MEDIUM', 'WARNING'].contains(s)) return 'Warning';
  return 'Info';
}

class AlertKpis {
  AlertKpis(this.raised, this.open, this.autoActioned, this.meanTimeToAction, this.devicesAffected);
  final int raised, open, autoActioned;
  final String meanTimeToAction, devicesAffected;
}

class ActionEntry {
  ActionEntry(this.id, this.performedAt, this.status, this.ack, this.by);
  factory ActionEntry.fromJson(Map<String, dynamic> j) => ActionEntry(
        j['id'] as int? ?? 0,
        parseUtcTimestamp(j['performed_at']),
        '${j['status'] ?? ''}',
        j['mqtt_ack'] == true,
        '${j['performed_by'] ?? ''}',
      );
  final int id;
  final DateTime? performedAt;
  final String status;
  final bool ack;
  final String by;
}

class Issue {
  Issue({
    required this.id,
    required this.deviceId,
    required this.issueType,
    required this.status,
    required this.actionStatus,
    required this.severity,
    required this.firstDetected,
    required this.lastDetected,
    required this.resolvedAt,
    required this.rule,
    required this.actions,
  });

  factory Issue.fromJson(Map<String, dynamic> j) {
    final r = j['threshold_rule'] as Map<String, dynamic>?;
    String rule = '${j['issue_type'] ?? 'N/A'}';
    if (r != null) {
      final p = r['parameter'] ?? j['issue_type'] ?? 'parameter';
      final lo = r['min_value'], hi = r['max_value'];
      rule = lo != null && hi != null
          ? '$p < $lo or > $hi'
          : hi != null
              ? '$p > $hi'
              : lo != null
                  ? '$p < $lo'
                  : '$p breach';
    }
    return Issue(
      id: j['id'] as int,
      deviceId: '${j['device_id']}',
      issueType: '${j['issue_type'] ?? ''}',
      status: '${j['status'] ?? ''}',
      actionStatus: '${j['action_status'] ?? ''}',
      severity: mapSeverity(j['severity'] as String?),
      firstDetected: parseUtcTimestamp(j['first_detected']),
      lastDetected: parseUtcTimestamp(j['last_detected']),
      resolvedAt: parseUtcTimestamp(j['resolved_at']),
      rule: rule,
      actions: [for (final a in (j['action_histories'] as List? ?? const [])) ActionEntry.fromJson(a as Map<String, dynamic>)],
    );
  }

  final int id;
  final String deviceId, issueType, status, actionStatus, severity, rule;
  final DateTime? firstDetected, lastDetected, resolvedAt;
  final List<ActionEntry> actions;

  bool get resolved => status.toUpperCase() == 'RESOLVED';

  String get duration {
    if (firstDetected == null) return '—';
    final end = resolvedAt ?? lastDetected ?? DateTime.now().toUtc();
    final m = end.difference(firstDetected!).inMinutes.clamp(0, 1 << 30);
    if (m < 60) return '$m m';
    if (m < 60 * 24) return '${m ~/ 60} h';
    return '${m ~/ (60 * 24)} d';
  }

  String get actionText {
    if (actions.isNotEmpty) return 'Action ${actions.first.status} (${actions.first.by})';
    if (actionStatus.isNotEmpty) return 'Action $actionStatus';
    return 'Pending action';
  }

  /// Timeline built only from real fields (never fabricated steps).
  List<(String label, String detail, String tone)> get timeline => [
        (
          'Threshold breached',
          '${firstDetected == null ? '' : formatIstClock(firstDetected!)} · $issueType detected on $deviceId',
          severity == 'Alarm' ? 'danger' : 'accent',
        ),
        for (final a in actions)
          (
            a.by == 'system' || a.by == 'auto_remediator' ? 'Automated reset executed' : 'Manual action triggered by ${a.by}',
            '${a.performedAt == null ? '' : formatIstClock(a.performedAt!)} · Status: ${a.status}, ACK: ${a.ack ? 'received' : 'pending'}',
            a.status == 'SUCCESS' ? 'success' : 'danger',
          ),
        if (resolved)
          (
            'Alert resolved',
            '${(resolvedAt ?? lastDetected) == null ? '' : formatIstClock((resolvedAt ?? lastDetected)!)} · Status updated to RESOLVED',
            'success',
          ),
      ];
}

class AlertFilters {
  const AlertFilters({this.search = '', this.severity = 'all', this.status = 'all', this.page = 1});
  final String search, severity, status;
  final int page;

  Map<String, dynamic> query({int size = 50}) => {
        if (search.trim().isNotEmpty) 'search': search.trim(),
        if (severity != 'all') 'severity': severity.toUpperCase(),
        if (status != 'all') 'status': status.toUpperCase(),
        'page': page,
        'size': size,
      };

  @override
  bool operator ==(Object other) =>
      other is AlertFilters && other.search == search && other.severity == severity && other.status == status && other.page == page;
  @override
  int get hashCode => Object.hash(search, severity, status, page);
}

class AlertsApi {
  AlertsApi(this._api);
  final ApiService _api;

  Future<AlertKpis> kpis(AlertFilters f) async {
    final d = await _api.get<Map<String, dynamic>>(Endpoint.issuesSummary, query: {
      if (f.search.trim().isNotEmpty) 'search': f.search.trim(),
      if (f.severity != 'all') 'severity': f.severity.toUpperCase(),
    });
    final sec = (d['mean_time_to_action_seconds'] as num?)?.toDouble() ?? 0;
    return AlertKpis(
      d['alerts_raised'] as int? ?? 0,
      d['open'] as int? ?? 0,
      d['auto_actioned'] as int? ?? 0,
      sec >= 60 ? '${(sec / 60).toStringAsFixed(1)} m' : '${sec.round()} s',
      '${d['devices_affected'] ?? 0} / ${d['total_devices'] ?? 0}',
    );
  }

  Future<(int total, List<Issue>)> issues(AlertFilters f) async {
    final d = await _api.get<Map<String, dynamic>>(Endpoint.issues, query: f.query());
    return (
      d['total'] as int? ?? 0,
      [for (final i in (d['items'] as List? ?? const [])) Issue.fromJson(i as Map<String, dynamic>)],
    );
  }

  Future<Issue> issue(int id) async =>
      Issue.fromJson(await _api.get<Map<String, dynamic>>(Endpoint.issue.withParams({'id': '$id'})));

  /// Breaches per day: (day label, warning count, alarm count).
  Future<List<(String, int, int)>> breachesByDay(String search) async {
    final d = await _api.get<Map<String, dynamic>>(Endpoint.issuesTimeseries, query: {
      'bucket': 'day',
      if (search.trim().isNotEmpty) 'search': search.trim(),
    });
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return [
      for (final p in (d['points'] as List? ?? const []))
        if (parseUtcTimestamp((p as Map)['timestamp']) case final t?)
          ('${toIst(t).day} ${months[toIst(t).month - 1]}', p['warning'] as int? ?? 0, p['alarm'] as int? ?? 0),
    ];
  }

  /// POST /actions/trigger — returns the created action's real status.
  Future<String> troubleshoot(String deviceId, String issueType) async {
    final d = await _api.post<Map<String, dynamic>>(Endpoint.triggerAction, {'device_id': deviceId, 'issue_type': issueType});
    return '${d['status'] ?? ''}';
  }

  /// PUT /issues/{id}/resolve (no body).
  Future<Issue> resolve(int id) async =>
      Issue.fromJson(await _api.put<Map<String, dynamic>>(Endpoint.resolveIssue.withParams({'id': '$id'}), null));

  Future<List<ActionEntry>> deviceActions(String deviceId) async {
    final d = await _api.get<Map<String, dynamic>>(Endpoint.actionsHistory, query: {'device_id': deviceId, 'page': 1, 'size': 20});
    return [for (final a in (d['items'] as List? ?? const [])) ActionEntry.fromJson(a as Map<String, dynamic>)];
  }
}
