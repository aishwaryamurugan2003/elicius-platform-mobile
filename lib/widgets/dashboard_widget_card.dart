import 'dart:convert';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../api/dashboards_api.dart';
import '../api/telemetry_api.dart';
import '../core/fields.dart';
import '../core/ist_time.dart';
import '../core/theme/app_theme.dart';
import '../state/data.dart';
import 'common.dart';

const defaultTimeRange = '-1h';
const defaultInterval = '5m';

/// Historical data for one widget, keyed by its query (JSON) so identical widgets share a fetch.
final _historyProvider = FutureProvider.autoDispose.family<Map<String, List<TelemetryPoint>>, String>((ref, key) {
  final q = jsonDecode(key) as Map<String, dynamic>;
  return ref.watch(telemetryApiProvider).history(
        deviceIds: (q['d'] as List).cast<String>(),
        fields: (q['f'] as List).cast<String>(),
        start: q['s'] as String,
        stop: q['e'] as String?,
        interval: q['i'] as String,
      );
});

String _historyKey(DashboardWidget w, List<String> devices) {
  final fields = {...w.allFields, if (w.type == 'map') ...['lat', 'long']}.toList();
  final hasAbsolute = w.startTime != null && w.endTime != null;
  return jsonEncode({
    'd': devices,
    'f': fields,
    's': hasAbsolute ? w.startTime : (w.timeRange ?? defaultTimeRange),
    'e': hasAbsolute ? w.endTime : null,
    'i': w.interval ?? defaultInterval,
  });
}

/// A dashboard widget: header (title + LIVE/HISTORICAL badge) and its visual.
class DashboardWidgetCard extends ConsumerWidget {
  const DashboardWidgetCard({super.key, required this.widget, required this.groups, this.fallbackDevices = const [], this.onLongPress});

  final DashboardWidget widget;
  final List<UserGroup> groups;
  final List<String> fallbackDevices;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = widget;
    final devices = w.deviceIds ?? fallbackDevices;
    final height = w.type == 'kpi' || w.type == 'indicator' || w.type == 'note'
        ? null
        : (w.type == 'map' ? 280.0 : 240.0);

    Widget body;
    if (w.type == 'note') {
      body = Text(w.cardLabel ?? w.title, style: const TextStyle(color: AppColors.grey700));
    } else if (devices.isEmpty) {
      body = const _Hint('No devices chosen for this widget.');
    } else if (w.isLive) {
      final gid = groupOfDevices(groups, devices);
      if (gid == null) {
        body = const _Hint("You don't have access to this widget's devices.");
      } else {
        final live = ref.watch(liveGroupProvider(gid));
        final series = {for (final d in devices) d: live.history[d] ?? const <TelemetryPoint>[]};
        body = WidgetVisual(widget: w, series: series, live: true);
      }
    } else {
      final value = ref.watch(_historyProvider(_historyKey(w, devices)));
      body = value.when(
        data: (s) => WidgetVisual(widget: w, series: {for (final d in devices) d: s[d] ?? const []}, live: false),
        loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
        error: (e, _) => _Hint('$e', error: true),
      );
    }

    return Card(
      child: InkWell(
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                  child: Text(w.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14), overflow: TextOverflow.ellipsis),
                ),
                if (w.type != 'note')
                  StatusPill(
                    w.isLive ? '• Live' : 'Historical',
                    fg: w.isLive ? AppColors.teal700 : AppColors.navy700,
                    bg: w.isLive ? AppColors.teal100 : AppColors.navy050,
                  ),
              ]),
              const SizedBox(height: 10),
              if (height != null) SizedBox(height: height, child: body) else body,
            ],
          ),
        ),
      ),
    );
  }
}

/// Y-axis labels on one line, skipping the min/max edge labels fl_chart forces in
/// (e.g. "1.345K"), which don't fit and wrap up into the card title.
final _leftAxis = AxisTitles(
  sideTitles: SideTitles(
    showTitles: true,
    reservedSize: 40,
    getTitlesWidget: (v, meta) => meta.min == v || meta.max == v
        ? const SizedBox.shrink()
        : SideTitleWidget(
            meta: meta,
            child: Text(meta.formattedValue,
                maxLines: 1, softWrap: false, overflow: TextOverflow.fade, style: const TextStyle(fontSize: 10, color: AppColors.grey500)),
          ),
  ),
);

class _Hint extends StatelessWidget {
  const _Hint(this.text, {this.error = false});
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: error ? AppColors.red600 : AppColors.grey500, fontSize: 13)),
        ),
      );
}

Color seriesColor(int i) => AppColors.series[i % AppColors.series.length];

/// Draws one widget type from per-device series.
class WidgetVisual extends StatelessWidget {
  const WidgetVisual({super.key, required this.widget, required this.series, required this.live});

  final DashboardWidget widget;
  final Map<String, List<TelemetryPoint>> series;
  final bool live;

  List<(String, List<(DateTime, double)>)> _values(String field) => [
        for (final e in series.entries)
          (e.key, [for (final p in e.value) if (asNumber(p.data[field]) case final v?) (p.time, v)]),
      ];

  double? _latest(String device, String field) {
    final pts = series[device] ?? const [];
    for (final p in pts.reversed) {
      final v = asNumber(p.data[field]);
      if (v != null) return v;
    }
    return null;
  }

  double? _aggregate(String device, String field) {
    if (live || widget.type != 'kpi') return _latest(device, field);
    final vals = [for (final p in series[device] ?? const <TelemetryPoint>[]) ?asNumber(p.data[field])];
    if (vals.isEmpty) return null;
    return switch (widget.aggregation) {
      'min' => vals.reduce(min),
      'max' => vals.reduce(max),
      _ => vals.reduce((a, b) => a + b) / vals.length,
    };
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final hasData = series.values.any((l) => l.isNotEmpty);
    if (!hasData) return _Hint(live ? 'Waiting for live data…' : 'No data in this time range.');

    switch (w.type) {
      case 'kpi':
        return _kpi();
      case 'indicator':
        return _indicator();
      case 'gauge':
        return _gauge();
      case 'bar':
      case 'devicebar':
      case 'histogram':
        return w.type == 'histogram' ? _histogram() : _deviceBars();
      case 'pie':
        return _pie();
      case 'scatter':
      case 'bubble':
        return _scatter();
      case 'table':
        return _table();
      case 'map':
        return _map();
      case 'heatmap':
        return _heatmap();
      case 'box':
        return _box();
      case 'alert':
        return _alertList();
      default:
        return _line(area: w.type == 'area');
    }
  }

  Widget _legend(List<String> names, {List<Color> colors = AppColors.series}) => Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          for (var i = 0; i < names.length; i++)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 10, height: 3, color: colors[i % colors.length]),
              const SizedBox(width: 4),
              Text(names[i], style: const TextStyle(fontSize: 11, color: AppColors.grey600)),
            ]),
        ],
      );

  Widget _line({required bool area}) {
    final field = widget.field;
    final data = _values(field).where((s) => s.$2.isNotEmpty).toList();
    if (data.isEmpty) return _Hint('No ${fieldLabel(field)} readings.');
    final t0 = data.expand((s) => s.$2).map((p) => p.$1.millisecondsSinceEpoch).reduce(min).toDouble();
    return Column(children: [
      const SizedBox(height: 8),
      Expanded(
        child: LineChart(LineChartData(
          gridData: const FlGridData(drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: _leftAxis,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (v, meta) => meta.min == v || meta.max == v
                    ? const SizedBox.shrink()
                    : Text(formatIstClock(DateTime.fromMillisecondsSinceEpoch((v + t0).round(), isUtc: true)).substring(0, 5),
                        style: const TextStyle(fontSize: 9, color: AppColors.grey500)),
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem('${data[s.barIndex].$1}: ${formatValue(s.y)}',
                      TextStyle(color: Colors.white, fontSize: 11, fontWeight: s.barIndex == 0 ? FontWeight.w700 : FontWeight.w400)),
              ],
            ),
          ),
          lineBarsData: [
            for (var i = 0; i < data.length; i++)
              LineChartBarData(
                spots: [for (final p in data[i].$2) FlSpot(p.$1.millisecondsSinceEpoch - t0, p.$2)],
                isCurved: true,
                preventCurveOverShooting: true,
                color: seriesColor(i),
                barWidth: 2,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(show: area, color: seriesColor(i).withValues(alpha: 0.15)),
              ),
          ],
        )),
      ),
      const SizedBox(height: 6),
      _legend([for (final s in data) s.$1]),
    ]);
  }

  Widget _deviceBars() {
    final field = widget.field;
    final devices = series.keys.toList();
    final values = [for (final d in devices) _latest(d, field) ?? 0];
    return Column(children: [
      Expanded(
        child: BarChart(BarChartData(
          gridData: const FlGridData(drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: _leftAxis,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (v, _) => Text(devices[v.toInt()], style: const TextStyle(fontSize: 9, color: AppColors.grey600)),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < devices.length; i++)
              BarChartGroupData(x: i, barRods: [BarChartRodData(toY: values[i], color: seriesColor(i), width: 18, borderRadius: BorderRadius.zero)]),
          ],
        )),
      ),
      Text('${fieldLabel(field)} · latest per device', style: const TextStyle(fontSize: 11, color: AppColors.grey500)),
    ]);
  }

  Widget _histogram() {
    final vals = _values(widget.field).expand((s) => s.$2.map((p) => p.$2)).toList();
    if (vals.isEmpty) return const _Hint('No readings.');
    final lo = vals.reduce(min), hi = vals.reduce(max);
    const bins = 10;
    final width = (hi - lo) == 0 ? 1.0 : (hi - lo) / bins;
    final counts = List.filled(bins, 0);
    for (final v in vals) {
      counts[min(bins - 1, ((v - lo) / width).floor())]++;
    }
    return BarChart(BarChartData(
      borderData: FlBorderData(show: false),
      gridData: const FlGridData(drawVerticalLine: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (v, _) => v.toInt() % 3 == 0
                ? Text((lo + width * v).toStringAsFixed(0), style: const TextStyle(fontSize: 9))
                : const SizedBox.shrink(),
          ),
        ),
      ),
      barGroups: [
        for (var i = 0; i < bins; i++)
          BarChartGroupData(x: i, barRods: [BarChartRodData(toY: counts[i].toDouble(), color: AppColors.navy700, width: 14, borderRadius: BorderRadius.zero)]),
      ],
    ));
  }

  Widget _pie() {
    final devices = series.keys.toList();
    final values = [for (final d in devices) max(0.0, _latest(d, widget.field) ?? 0)];
    final total = values.fold<double>(0, (a, b) => a + b);
    if (total == 0) return const _Hint('No positive readings to share out.');
    return Row(children: [
      Expanded(
        child: PieChart(PieChartData(sectionsSpace: 0, centerSpaceRadius: 30, sections: [
          for (var i = 0; i < devices.length; i++)
            if (values[i] > 0)
              PieChartSectionData(
                value: values[i],
                color: AppColors.pie[i % AppColors.pie.length],
                radius: 70,
                borderSide: const BorderSide(color: Color(0xFF444444), width: 2),
                title: formatValue(values[i]),
                titleStyle: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
              ),
        ])),
      ),
      SizedBox(width: 90, child: _legend(devices, colors: AppColors.pie)),
    ]);
  }

  Widget _scatter() {
    final xField = widget.allFields.length > 1 ? widget.allFields[0] : 'srvtime';
    final yField = widget.allFields.length > 1 ? widget.allFields[1] : widget.field;
    final spots = <ScatterSpot>[];
    var i = 0;
    for (final e in series.entries) {
      for (final p in e.value) {
        final y = asNumber(p.data[yField]);
        final x = xField == 'srvtime' ? p.time.millisecondsSinceEpoch / 60000 : asNumber(p.data[xField]);
        if (x != null && y != null) {
          spots.add(ScatterSpot(x, y, dotPainter: FlDotCirclePainter(radius: widget.type == 'bubble' ? 6 : 3, color: seriesColor(i))));
        }
      }
      i++;
    }
    if (spots.isEmpty) return const _Hint('No readings.');
    return ScatterChart(ScatterChartData(
      scatterSpots: spots,
      borderData: FlBorderData(show: false),
      titlesData: const FlTitlesData(topTitles: AxisTitles(), rightTitles: AxisTitles(), bottomTitles: AxisTitles()),
    ));
  }

  Widget _kpi() {
    final fields = widget.allFields;
    final devices = series.keys.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in fields) ...[
          Text((fields.length == 1 ? (widget.cardLabel ?? fieldLabel(f)) : fieldLabel(f)).toUpperCase(), style: AppTheme.eyebrow()),
          const SizedBox(height: 4),
          if (devices.length == 1)
            Text('${formatValue(_aggregate(devices.first, f))} ${fieldUnit(f)}',
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.navy700))
          else
            for (final d in devices)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(child: Text(d, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  Text(formatValue(_aggregate(d, f)), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ]),
              ),
          const SizedBox(height: 10),
        ],
        Text(
          live ? 'Latest reading' : '${(widget.aggregation ?? 'avg').toUpperCase()} over the range',
          style: const TextStyle(fontSize: 11, color: AppColors.grey500),
        ),
      ],
    );
  }

  Widget _indicator() {
    final device = series.keys.first;
    final v = _latest(device, widget.field);
    final match = v == null ? null : widget.indicatorRanges?.where((r) => v >= r.min && v <= r.max).firstOrNull;
    final status = match == null ? null : indicatorStatuses[match.status];
    final color = status == null ? AppColors.grey400 : Color(status.$2);
    return Row(children: [
      Container(width: 18, height: 18, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(status?.$1 ?? 'No status', style: TextStyle(fontWeight: FontWeight.w700, color: color)),
          Text('$device · ${fieldLabel(widget.field)} ${formatValue(v)}', style: const TextStyle(fontSize: 12, color: AppColors.grey600)),
        ]),
      ),
    ]);
  }

  Widget _gauge() {
    final device = series.keys.first;
    final v = _latest(device, widget.field) ?? 0;
    final all = _values(widget.field).expand((s) => s.$2.map((p) => p.$2));
    final top = all.isEmpty ? max(1.0, v) : max(all.reduce(max), v) * 1.2;
    final color = widget.gaugeColor != null ? _hex(widget.gaugeColor!) ?? AppColors.teal600 : AppColors.teal600;
    return Center(
      child: SizedBox(
        width: 170,
        height: 170,
        child: Stack(alignment: Alignment.center, children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: top == 0 ? 0 : (v / top).clamp(0, 1),
              strokeWidth: 14,
              backgroundColor: AppColors.grey100,
              color: color,
            ),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text(formatValue(v), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            Text(fieldUnit(widget.field), style: const TextStyle(color: AppColors.grey500)),
            Text(device, style: const TextStyle(fontSize: 11, color: AppColors.grey500)),
          ]),
        ]),
      ),
    );
  }

  Widget _table() {
    final fields = widget.allFields;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowHeight: 32,
          dataRowMinHeight: 30,
          dataRowMaxHeight: 34,
          columns: [
            const DataColumn(label: Text('Device')),
            for (final f in fields) DataColumn(label: Text(fieldLabel(f)), numeric: true),
          ],
          rows: [
            for (final d in series.keys)
              DataRow(cells: [
                DataCell(Text(d)),
                for (final f in fields) DataCell(Text(formatValue(_latest(d, f)))),
              ]),
          ],
        ),
      ),
    );
  }

  Widget _map() {
    final markers = <Marker>[];
    for (final d in series.keys) {
      final lat = _latest(d, 'lat'), lng = _latest(d, 'long');
      if (lat == null || lng == null || (lat == 0 && lng == 0)) continue;
      markers.add(Marker(
        point: LatLng(lat, lng),
        width: 90,
        height: 54,
        alignment: Alignment.topCenter,
        child: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            color: AppColors.navy700,
            child: Text('$d ${formatValue(_latest(d, widget.field))}', style: const TextStyle(color: Colors.white, fontSize: 10)),
          ),
          const Icon(Icons.location_on, color: AppColors.teal700, size: 28),
        ]),
      ));
    }
    if (markers.isEmpty) return const _Hint('No device location (lat / long) in the data.');
    return ClipRect(
      child: FlutterMap(
        options: MapOptions(
          initialCameraFit: markers.length > 1
              ? CameraFit.coordinates(coordinates: [for (final m in markers) m.point], padding: const EdgeInsets.all(40))
              : null,
          initialCenter: markers.first.point,
          initialZoom: 12,
        ),
        children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'in.eliciusenergy.elicius_iot'),
          MarkerLayer(markers: markers),
          const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
        ],
      ),
    );
  }

  Widget _heatmap() {
    final field = widget.field;
    final devices = series.keys.toList();
    final all = _values(field).expand((s) => s.$2.map((p) => p.$2)).toList();
    if (all.isEmpty) return const _Hint('No readings.');
    final lo = all.reduce(min), hi = all.reduce(max);
    return ListView(children: [
      for (final d in devices)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 64, child: Text(d, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
            Expanded(
              child: Row(children: [
                for (final p in (series[d] ?? const <TelemetryPoint>[]).take(60))
                  if (asNumber(p.data[field]) case final v?)
                    Expanded(
                      child: Container(
                        height: 18,
                        color: Color.lerp(AppColors.navy050, AppColors.navy700, hi == lo ? 0.5 : (v - lo) / (hi - lo)),
                      ),
                    ),
              ]),
            ),
          ]),
        ),
      const SizedBox(height: 6),
      Text('${fieldLabel(field)}: ${formatValue(lo)} – ${formatValue(hi)}', style: const TextStyle(fontSize: 11, color: AppColors.grey500)),
    ]);
  }

  Widget _box() {
    final field = widget.field;
    return ListView(children: [
      for (final s in _values(field))
        if (s.$2.isNotEmpty)
          Builder(builder: (_) {
            final v = s.$2.map((p) => p.$2).toList()..sort();
            double q(double f) => v[((v.length - 1) * f).round()];
            return ListTile(
              dense: true,
              title: Text(s.$1),
              subtitle: Text('min ${formatValue(v.first)} · Q1 ${formatValue(q(.25))} · median ${formatValue(q(.5))} · '
                  'Q3 ${formatValue(q(.75))} · max ${formatValue(v.last)}'),
            );
          }),
    ]);
  }

  Widget _alertList() => _table();

  static Color? _hex(String s) {
    final h = s.replaceFirst('#', '');
    final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
    return v == null ? null : Color(v);
  }
}
