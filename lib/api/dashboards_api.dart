import 'dart:convert';

import '../core/api/api_service.dart';
import '../core/api/endpoints.dart';

/// Home page = the dashboard inside the user's folder with this reserved name.
const homeFolderName = 'Home_page';

class Folder {
  Folder({required this.id, required this.groupId, required this.name, this.updatedAt});

  factory Folder.fromJson(Map<String, dynamic> j) => Folder(
        id: j['id'] as int,
        groupId: '${j['group_id']}',
        name: '${j['folder_name']}',
        updatedAt: j['updated_at'] as String?,
      );

  final int id;
  final String groupId;
  final String name;
  final String? updatedAt;

  bool get isHome => name == homeFolderName;
}

class IndicatorRange {
  IndicatorRange(this.min, this.max, this.status);
  final double min;
  final double max;
  final String status;
}

/// Status values for indicator widgets (same set and colours as the web app).
const indicatorStatuses = {
  'normal': ('Normal', 0xFF1F7A4D),
  'warning': ('Warning', 0xFFA1650A),
  'disconnected': ('Disconnected', 0xFF6D7484),
  'incorrect_connection': ('Incorrect connection', 0xFF6B3FA0),
  'communication_failure': ('Communication failure', 0xFFB3271F),
};

/// One widget on a dashboard — the web app's `DashboardWidget`.
class DashboardWidget {
  DashboardWidget({
    required this.id,
    required this.type,
    required this.title,
    required this.field,
    this.fields,
    this.dataMode,
    this.timeRange,
    this.interval,
    this.startTime,
    this.endTime,
    this.aggregation,
    this.cardLabel,
    this.gaugeColor,
    this.indicatorRanges,
    this.deviceIds,
    required this.layoutX,
    required this.layoutY,
    required this.layoutW,
    required this.layoutH,
  });

  final String id;

  /// kpi, indicator, timeseries, bar, devicebar, scatter, area, pie, histogram,
  /// heatmap, bubble, box, table, gauge, map, alert, note.
  final String type;
  final String title;
  final String field;
  final List<String>? fields;
  final String? dataMode; // "historical" | "live"
  final String? timeRange; // e.g. "-1h"
  final String? interval; // e.g. "5m"
  final String? startTime;
  final String? endTime;
  final String? aggregation; // avg | min | max
  final String? cardLabel;
  final String? gaugeColor;
  final List<IndicatorRange>? indicatorRanges;
  final List<String>? deviceIds;
  final int layoutX, layoutY, layoutW, layoutH;

  bool get isLive => dataMode == 'live';
  List<String> get allFields => (fields != null && fields!.isNotEmpty) ? fields! : [field];
}

class DashboardData {
  DashboardData({required this.id, required this.widgets, this.updatedAt});
  final int id;
  final List<DashboardWidget> widgets;
  final String? updatedAt;
}

const _settingsChartId = '__page_settings__';
const _knownTypes = {
  'kpi', 'indicator', 'timeseries', 'bar', 'devicebar', 'scatter', 'area', 'pie', 'histogram', //
  'heatmap', 'bubble', 'box', 'table', 'gauge', 'map', 'alert', 'note',
};
const _wireToType = {'line': 'timeseries', 'area': 'area', 'scatter': 'scatter', 'bar': 'bar', 'gauge': 'gauge', 'kpi': 'kpi'};
final _durationLike = RegExp(r'^-?\d+[mhd]$');

/// Decodes one backend chart into a widget — a port of `chartConfigToWidget`.
/// The widget's extras ride in `measurement` as
/// `type~dataMode~fields~timeRange~interval~indicator`.
DashboardWidget chartToWidget(Map<String, dynamic> chart, Map<String, dynamic>? layout, int index) {
  final parts = ((chart['measurement'] as String?) ?? '').split('~');
  String? seg(int i) => i < parts.length && parts[i].trim().isNotEmpty ? parts[i] : null;
  final typeOrKpi = seg(0);
  final type = (typeOrKpi != null && _knownTypes.contains(typeOrKpi))
      ? typeOrKpi
      : (_wireToType[chart['chart_type']] ?? 'timeseries');
  List<String>? clean(List<String>? l) {
    final c = l?.where((f) => f.isNotEmpty && !_durationLike.hasMatch(f)).toList();
    return (c == null || c.isEmpty) ? null : c;
  }

  final legacyKpi = type == 'kpi' && typeOrKpi != null && typeOrKpi != 'kpi' ? typeOrKpi.split(',') : null;
  final fields = clean(legacyKpi) ?? clean(seg(2)?.split(','));
  final yField = (chart['y_axis'] as Map?)?['field'] as String?;
  final savedField = yField != null && !_durationLike.hasMatch(yField) ? yField : null;

  List<IndicatorRange>? ranges;
  if (type == 'indicator' && seg(5) != null) {
    try {
      final parsed = jsonDecode(Uri.decodeComponent(seg(5)!)) as Map<String, dynamic>;
      ranges = [
        for (final r in (parsed['r'] as List? ?? const []))
          if (r is Map && r['min'] is num && r['max'] is num && r['status'] is String)
            IndicatorRange((r['min'] as num).toDouble(), (r['max'] as num).toDouble(), r['status'] as String),
      ];
    } catch (_) {}
  }

  int? n(Object? v) => v is num ? v.round() : null;
  final lx = n(chart['layout_x']) ?? n(layout?['x']) ?? (index % 3) * 4;
  final ly = n(chart['layout_y']) ?? n(layout?['y']) ?? (index ~/ 3) * 3;
  final lw = n(chart['layout_w']) ?? n(layout?['w']) ?? 4;
  final lh = n(chart['layout_h']) ?? n(layout?['h']) ?? 3;
  final colors = chart['color_scheme'];
  final devices = ((chart['device_ids'] as List?) ?? const []).map((d) => '$d').toList();
  final mode = seg(1);

  return DashboardWidget(
    id: '${chart['chart_id']}',
    type: type,
    title: '${chart['title'] ?? ''}',
    field: fields?.first ?? savedField ?? 'sPM2',
    fields: fields,
    dataMode: mode == 'live' || mode == 'historical' ? mode : null,
    timeRange: seg(3),
    interval: seg(4),
    startTime: chart['start_time'] as String?,
    endTime: chart['end_time'] as String?,
    aggregation: chart['kpi_aggregation'] as String?,
    cardLabel: chart['kpi_label'] as String?,
    gaugeColor: type == 'gauge' && colors is List && colors.isNotEmpty ? '${colors.first}' : null,
    indicatorRanges: ranges,
    deviceIds: devices.isEmpty ? null : devices,
    layoutX: lx,
    layoutY: ly,
    layoutW: lw,
    layoutH: lh,
  );
}

class DashboardsApi {
  DashboardsApi(this._api);
  final ApiService _api;

  /// `GET /v1/allfolders?user_id=` — every folder this user owns, all groups.
  Future<List<Folder>> allFolders(String userId) async {
    final res = await _api.get<Map<String, dynamic>>(Endpoint.allFolders, query: {'user_id': userId});
    return [for (final f in (res['data'] as List? ?? const [])) Folder.fromJson(f as Map<String, dynamic>)];
  }

  /// `GET /v1/folders?user_id=&group_id=`
  Future<List<Folder>> folders(String userId, String groupId) async {
    final res = await _api.get<Map<String, dynamic>>(Endpoint.folders, query: {'user_id': userId, 'group_id': groupId});
    return [for (final f in (res['data'] as List? ?? const [])) Folder.fromJson(f as Map<String, dynamic>)];
  }

  Future<Folder> createFolder(String userId, String groupId, String name) async {
    final res = await _api.post<Map<String, dynamic>>(
        Endpoint.folders, {'user_id': userId, 'group_id': groupId, 'folder_name': name});
    return Folder.fromJson(res['data'] as Map<String, dynamic>);
  }

  Future<void> renameFolder(int folderId, String name) =>
      _api.put<dynamic>(Endpoint.folder.withParams({'folder_id': '$folderId'}), {'folder_name': name});

  /// Also deletes the dashboard inside it.
  Future<void> deleteFolder(int folderId) => _api.delete<dynamic>(Endpoint.folder.withParams({'folder_id': '$folderId'}));

  /// `GET /v1/dashboards/folder/{id}` — the folder's dashboard (latest if
  /// several), with the hidden page-settings entry filtered out.
  Future<DashboardData?> folderDashboard(int folderId) async {
    final res = await _api.get<List<dynamic>>(Endpoint.dashboardsInFolder.withParams({'folder_id': '$folderId'}));
    Map<String, dynamic>? latest;
    for (final d in res.cast<Map<String, dynamic>>()) {
      final t = (d['updated_at'] ?? d['created_at'] ?? '') as String;
      final lt = (latest?['updated_at'] ?? latest?['created_at'] ?? '') as String;
      if (latest == null || t.compareTo(lt) > 0) latest = d;
    }
    if (latest == null) return null;
    final layouts = {
      for (final l in (latest['layout'] as List? ?? const [])) '${(l as Map)['chart_id']}': l.cast<String, dynamic>(),
    };
    final charts = (latest['charts'] as List? ?? const []).cast<Map<String, dynamic>>();
    final widgets = <DashboardWidget>[];
    for (final c in charts) {
      if (c['chart_id'] == _settingsChartId) continue;
      widgets.add(chartToWidget(c, layouts['${c['chart_id']}'], widgets.length));
    }
    widgets.sort((a, b) => a.layoutY != b.layoutY ? a.layoutY.compareTo(b.layoutY) : a.layoutX.compareTo(b.layoutX));
    return DashboardData(id: latest['id'] as int, widgets: widgets, updatedAt: latest['updated_at'] as String?);
  }

  /// Removes one widget and saves (PUT replaces charts + layout). Keeps every
  /// other chart exactly as the backend sent it, including page settings.
  Future<void> removeWidget(int dashboardId, String chartId) async {
    final d = await _api.get<Map<String, dynamic>>(Endpoint.dashboard.withParams({'dashboard_id': '$dashboardId'}));
    final body = (d['data'] ?? d) as Map<String, dynamic>;
    final charts = (body['charts'] as List? ?? const []).where((c) => (c as Map)['chart_id'] != chartId).toList();
    final layout = (body['layout'] as List? ?? const []).where((l) => (l as Map)['chart_id'] != chartId).toList();
    await _api.put<dynamic>(Endpoint.dashboard.withParams({'dashboard_id': '$dashboardId'}), {'charts': charts, 'layout': layout});
  }
}
