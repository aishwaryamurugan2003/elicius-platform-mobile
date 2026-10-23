import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/telemetry_api.dart';
import '../../core/fields.dart';
import '../../core/ist_time.dart';
import '../../core/theme/app_theme.dart';
import '../../state/data.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// A device is Inactive when its newest packet is older than this (web: STALE_MS).
const _staleAfter = Duration(seconds: 90);

enum DeviceStatus { live, threshold, inactive }

DeviceStatus statusOf(TelemetryPoint? p, DateTime now) {
  if (p == null || now.difference(p.time) > _staleAfter) return DeviceStatus.inactive;
  final v = asNumber(p.data['rmsX']), warn = asNumber(p.data['thr_warn']);
  return v != null && warn != null && v >= warn ? DeviceStatus.threshold : DeviceStatus.live;
}

/// Live status of one group — the web LiveStatusPage: connection + last
/// update, total / active counts, a filter, and a card per device. Tap a
/// device for its latest readings and a live trend.
class LiveStatusScreen extends ConsumerStatefulWidget {
  const LiveStatusScreen({super.key, required this.groupId});
  final String groupId;

  @override
  ConsumerState<LiveStatusScreen> createState() => _LiveStatusScreenState();
}

class _LiveStatusScreenState extends ConsumerState<LiveStatusScreen> {
  String _query = '';
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    // Re-evaluate Live/Inactive as time passes even without new packets.
    _tick = Timer.periodic(const Duration(seconds: 10), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(liveGroupProvider(widget.groupId));
    final group = ref.watch(groupsProvider).value?.where((g) => g.id == widget.groupId).firstOrNull;
    final now = DateTime.now().toUtc();
    final devices = {...?group?.devices, ...live.latest.keys}.toList()..sort();
    final shown = devices.where((d) => d.toLowerCase().contains(_query.toLowerCase())).toList();
    final active = devices.where((d) => statusOf(live.latest[d], now) != DeviceStatus.inactive).length;
    DateTime? newest;
    for (final p in live.latest.values) {
      if (newest == null || p.time.isAfter(newest)) newest = p.time;
    }

    return AppShell(
      eyebrow: 'Live status',
      title: 'Live: ${group?.name ?? widget.groupId}',
      showDrawer: false,
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(children: [
            Icon(Icons.circle, size: 10, color: live.connected ? AppColors.green600 : AppColors.grey400),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${live.connected ? 'CONNECTED' : 'DISCONNECTED'} · LAST UPDATE ${newest == null ? '—:—:—' : formatIstDateTime(newest)}',
                style: AppTheme.eyebrow(),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: KpiTile(label: 'Total devices', value: '${devices.length}')),
            const SizedBox(width: 10),
            Expanded(child: KpiTile(label: 'Active', value: '$active', color: AppColors.green600)),
          ]),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(hintText: 'Filter by device', prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 12),
          if (shown.isEmpty) const EmptyState(message: 'No devices match.'),
          for (final d in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DeviceCard(
                deviceId: d,
                point: live.latest[d],
                packets: live.packetCounts[d],
                status: statusOf(live.latest[d], now),
                onTap: () => _openDevice(context, d),
              ),
            ),
        ],
      ),
    );
  }

  void _openDevice(BuildContext context, String deviceId) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (_, scroll) => _DeviceSheet(groupId: widget.groupId, deviceId: deviceId, scroll: scroll),
      ),
    );
  }
}

(String, Color, Color) _statusStyle(DeviceStatus s) => switch (s) {
      DeviceStatus.live => ('Live', AppColors.green600, AppColors.green100),
      DeviceStatus.threshold => ('Threshold', AppColors.navy700, AppColors.navy100),
      DeviceStatus.inactive => ('Inactive', AppColors.grey500, AppColors.grey100),
    };

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.deviceId, required this.point, required this.packets, required this.status, required this.onTap});
  final String deviceId;
  final TelemetryPoint? point;
  final int? packets;
  final DeviceStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = _statusStyle(status);
    final readings = point == null
        ? const <MapEntry<String, dynamic>>[]
        : point!.data.entries.where((e) => !nonReadingKeys.contains(e.key) && asNumber(e.value) != null).take(4).toList();
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.navy050,
                child: Text(deviceId.replaceAll(RegExp('[^A-Za-z]'), '').padRight(2).substring(0, 2).toUpperCase(),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.navy700)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(deviceId, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16), overflow: TextOverflow.ellipsis)),
              StatusPill(label, fg: fg, bg: bg),
            ]),
            if (readings.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 14, runSpacing: 6, children: [
                for (final r in readings)
                  Text('${fieldLabel(r.key)}: ${formatValue(r.value)}', style: const TextStyle(fontSize: 12, color: AppColors.grey700)),
              ]),
            ] else if (point == null) ...[
              const SizedBox(height: 8),
              const Text('Waiting for signal…', style: TextStyle(fontStyle: FontStyle.italic, color: AppColors.grey500, fontSize: 12)),
            ],
            const Divider(height: 20),
            Row(children: [
              const Icon(Icons.speed, size: 16, color: AppColors.grey400),
              const SizedBox(width: 4),
              Text('Packet ${packets?.toString() ?? '—'}', style: const TextStyle(fontSize: 12, color: AppColors.grey600)),
              const Spacer(),
              Text(point == null ? '—:—:—' : formatIstDateTime(point!.time),
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppColors.grey500)),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// A device's latest packet (every reading) plus a live trend of one field.
class _DeviceSheet extends ConsumerStatefulWidget {
  const _DeviceSheet({required this.groupId, required this.deviceId, required this.scroll});
  final String groupId;
  final String deviceId;
  final ScrollController scroll;

  @override
  ConsumerState<_DeviceSheet> createState() => _DeviceSheetState();
}

class _DeviceSheetState extends ConsumerState<_DeviceSheet> {
  String? _field;

  @override
  Widget build(BuildContext context) {
    final live = ref.watch(liveGroupProvider(widget.groupId));
    final point = live.latest[widget.deviceId];
    final history = live.history[widget.deviceId] ?? const [];
    final numeric = point == null
        ? <String>[]
        : point.data.entries.where((e) => !nonReadingKeys.contains(e.key) && asNumber(e.value) != null).map((e) => e.key).toList();
    final field = _field ?? (numeric.isNotEmpty ? numeric.first : null);
    final spots = field == null
        ? <FlSpot>[]
        : [
            for (final p in history)
              if (asNumber(p.data[field]) case final v?) FlSpot(p.time.millisecondsSinceEpoch.toDouble(), v),
          ];

    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      Text(widget.deviceId, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      Text(point == null ? 'No packet yet' : 'Last packet ${formatIstDateTime(point.time)}', style: const TextStyle(color: AppColors.grey600)),
      const SizedBox(height: 16),
      if (field != null) ...[
        DropdownButtonFormField<String>(
          initialValue: field,
          decoration: const InputDecoration(labelText: 'Trend'),
          items: [for (final f in numeric) DropdownMenuItem(value: f, child: Text(fieldLabel(f)))],
          onChanged: (v) => setState(() => _field = v),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: spots.length < 2
              ? const Center(child: Text('Collecting live readings…', style: TextStyle(color: AppColors.grey500)))
              : LineChart(LineChartData(
                  gridData: const FlGridData(drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                  titlesData: const FlTitlesData(topTitles: AxisTitles(), rightTitles: AxisTitles(), bottomTitles: AxisTitles()),
                  lineBarsData: [
                    LineChartBarData(spots: spots, color: AppColors.navy700, barWidth: 2, dotData: const FlDotData(show: false)),
                  ],
                )),
        ),
        const SizedBox(height: 16),
      ],
      SectionCard(
        title: 'Latest payload',
        padding: EdgeInsets.zero,
        child: Column(children: [
          if (point == null) const Padding(padding: EdgeInsets.all(16), child: Text('No data yet.')),
          if (point != null)
            for (final e in point.data.entries)
              ListTile(
                dense: true,
                title: Text(fieldLabel(e.key)),
                subtitle: fieldLabel(e.key) != e.key ? Text(e.key, style: const TextStyle(fontSize: 11)) : null,
                trailing: Text(
                  asNumber(e.value) != null ? '${formatValue(e.value)} ${fieldUnit(e.key)}' : '${e.value}',
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
        ]),
      ),
    ]);
  }
}
