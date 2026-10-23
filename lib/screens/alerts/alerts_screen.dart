import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/alerts_api.dart';
import '../../core/ist_time.dart';
import '../../core/permissions.dart';
import '../../core/theme/app_theme.dart';
import '../../state/auth.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

final alertsApiProvider = Provider((ref) => AlertsApi(ref.watch(apiServiceProvider)));
final _kpisProvider = FutureProvider.autoDispose.family<AlertKpis, AlertFilters>((ref, f) => ref.watch(alertsApiProvider).kpis(f));
final _issuesProvider =
    FutureProvider.autoDispose.family<(int, List<Issue>), AlertFilters>((ref, f) => ref.watch(alertsApiProvider).issues(f));
final _breachesProvider =
    FutureProvider.autoDispose.family<List<(String, int, int)>, String>((ref, s) => ref.watch(alertsApiProvider).breachesByDay(s));

/// Device alerts — threshold breaches and actions taken (the web DeviceAlertsPage).
class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  AlertFilters _f = const AlertFilters();
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(_kpisProvider(_f));
    ref.invalidate(_issuesProvider(_f));
    ref.invalidate(_breachesProvider(_f.search));
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(roleProvider);
    final kpis = ref.watch(_kpisProvider(_f));
    final issues = ref.watch(_issuesProvider(_f));
    final breaches = ref.watch(_breachesProvider(_f.search));

    return AppShell(
      eyebrow: 'Device alerts',
      title: 'Threshold breaches & actions',
      actions: [
        if (canAccessPage(role, '/thresholds'))
          IconButton(tooltip: 'Alert rules', icon: const Icon(Icons.rule), onPressed: () => context.push('/thresholds')),
      ],
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: ListView(padding: const EdgeInsets.all(12), children: [
          kpis.when(
            data: (k) => GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.9,
              children: [
                KpiTile(label: 'Alerts raised', value: '${k.raised}'),
                KpiTile(label: 'Open', value: '${k.open}', color: AppColors.red600),
                KpiTile(label: 'Auto-actioned', value: '${k.autoActioned}', color: AppColors.teal600),
                KpiTile(label: 'Mean time to action', value: k.meanTimeToAction),
                KpiTile(label: 'Devices affected', value: k.devicesAffected),
              ],
            ),
            loading: () => const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
            error: (e, _) => ErrorState(message: '$e', onRetry: _refresh),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Breaches by day · warning vs alarm',
            child: SizedBox(
              height: 180,
              child: breaches.when(
                data: (pts) => pts.isEmpty
                    ? const Center(child: Text('No breaches in this period.', style: TextStyle(color: AppColors.grey500)))
                    : BarChart(BarChartData(
                        borderData: FlBorderData(show: false),
                        gridData: const FlGridData(drawVerticalLine: false),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(),
                          rightTitles: const AxisTitles(),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (v, _) => Text(pts[v.toInt()].$1, style: const TextStyle(fontSize: 9)),
                            ),
                          ),
                        ),
                        barGroups: [
                          for (var i = 0; i < pts.length; i++)
                            BarChartGroupData(x: i, barRods: [
                              BarChartRodData(toY: pts[i].$2.toDouble(), color: AppColors.amber600, width: 8, borderRadius: BorderRadius.zero),
                              BarChartRodData(toY: pts[i].$3.toDouble(), color: AppColors.red600, width: 8, borderRadius: BorderRadius.zero),
                            ]),
                        ],
                      )),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('$e', style: const TextStyle(color: AppColors.red600))),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _search,
            decoration: const InputDecoration(hintText: 'Filter by device, rule or action', prefixIcon: Icon(Icons.search)),
            textInputAction: TextInputAction.search,
            onSubmitted: (v) => setState(() => _f = AlertFilters(search: v, severity: _f.severity, status: _f.status)),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _f.severity,
                decoration: const InputDecoration(labelText: 'Severity'),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All')),
                  DropdownMenuItem(value: 'high', child: Text('Alarm')),
                  DropdownMenuItem(value: 'medium', child: Text('Warning')),
                  DropdownMenuItem(value: 'low', child: Text('Info')),
                ],
                onChanged: (v) => setState(() => _f = AlertFilters(search: _f.search, severity: v!, status: _f.status)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _f.status,
                decoration: const InputDecoration(labelText: 'State'),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All')),
                  DropdownMenuItem(value: 'open', child: Text('Open')),
                  DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
                ],
                onChanged: (v) => setState(() => _f = AlertFilters(search: _f.search, severity: _f.severity, status: v!)),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          issues.when(
            data: (r) {
              final (total, items) = r;
              if (items.isEmpty) return const EmptyState(message: 'No alerts match these filters.');
              return Column(children: [
                for (final i in items)
                  Padding(padding: const EdgeInsets.only(bottom: 8), child: _IssueTile(issue: i, onChanged: _refresh)),
                Row(children: [
                  Text('Showing ${(_f.page - 1) * 50 + 1}–${(_f.page - 1) * 50 + items.length} of $total',
                      style: const TextStyle(color: AppColors.grey600, fontSize: 12)),
                  const Spacer(),
                  TextButton(
                    onPressed: _f.page > 1
                        ? () => setState(() => _f = AlertFilters(search: _f.search, severity: _f.severity, status: _f.status, page: _f.page - 1))
                        : null,
                    child: const Text('Previous'),
                  ),
                  TextButton(
                    onPressed: _f.page * 50 < total
                        ? () => setState(() => _f = AlertFilters(search: _f.search, severity: _f.severity, status: _f.status, page: _f.page + 1))
                        : null,
                    child: const Text('Next'),
                  ),
                ]),
              ]);
            },
            loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => ErrorState(message: '$e', onRetry: _refresh),
          ),
        ]),
      ),
    );
  }
}

Color _sevColor(String s) => s == 'Alarm' ? AppColors.red600 : s == 'Warning' ? AppColors.amber600 : AppColors.navy500;

class _IssueTile extends StatelessWidget {
  const _IssueTile({required this.issue, required this.onChanged});
  final Issue issue;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final i = issue;
    return Card(
      child: InkWell(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.8,
            builder: (_, scroll) => _IssueSheet(issueId: i.id, scroll: scroll, onChanged: onChanged),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.circle, size: 9, color: _sevColor(i.severity)),
              const SizedBox(width: 6),
              Text(i.severity, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              Expanded(child: Text(i.deviceId, style: const TextStyle(fontWeight: FontWeight.w600))),
              if (i.resolved)
                const StatusPill('Resolved', fg: AppColors.green600, bg: AppColors.green100)
              else
                const StatusPill('Open', fg: AppColors.red600, bg: AppColors.red100),
            ]),
            const SizedBox(height: 6),
            Text('${i.issueType} · ${i.rule}', style: const TextStyle(fontSize: 13, color: AppColors.grey700)),
            const SizedBox(height: 4),
            Text(
              '${i.firstDetected == null ? '' : formatIstShort(i.firstDetected!)} · ${i.duration} · ${i.actionText}',
              style: const TextStyle(fontSize: 12, color: AppColors.grey500),
            ),
          ]),
        ),
      ),
    );
  }
}

final _issueProvider = FutureProvider.autoDispose.family<Issue, int>((ref, id) => ref.watch(alertsApiProvider).issue(id));
final _deviceActionsProvider =
    FutureProvider.autoDispose.family<List<ActionEntry>, String>((ref, d) => ref.watch(alertsApiProvider).deviceActions(d));

class _IssueSheet extends ConsumerStatefulWidget {
  const _IssueSheet({required this.issueId, required this.scroll, required this.onChanged});
  final int issueId;
  final ScrollController scroll;
  final VoidCallback onChanged;

  @override
  ConsumerState<_IssueSheet> createState() => _IssueSheetState();
}

class _IssueSheetState extends ConsumerState<_IssueSheet> {
  bool _busy = false;
  String? _message;
  bool _messageError = false;

  Future<void> _run(Future<String> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final m = await action();
      setState(() {
        _message = m;
        _messageError = false;
      });
      ref.invalidate(_issueProvider(widget.issueId));
      widget.onChanged();
    } catch (e) {
      setState(() {
        _message = '$e';
        _messageError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final issue = ref.watch(_issueProvider(widget.issueId));
    return issue.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(message: '$e'),
      data: (i) {
        final actions = ref.watch(_deviceActionsProvider(i.deviceId));
        final api = ref.read(alertsApiProvider);
        return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          Text('SELECTED ALERT', style: AppTheme.eyebrow()),
          Text('${i.deviceId} · ${i.severity.toLowerCase()}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          if (i.firstDetected != null) Text(formatIstShort(i.firstDetected!), style: const TextStyle(color: AppColors.grey600)),
          const SizedBox(height: 12),
          Text('RULE', style: AppTheme.eyebrow()),
          Text(i.rule, style: const TextStyle(fontFamily: 'monospace')),
          const SizedBox(height: 16),
          Text('TIMELINE', style: AppTheme.eyebrow().copyWith(color: AppColors.navy900, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final (label, detail, tone) in i.timeline)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.circle,
                  size: 12,
                  color: switch (tone) {
                    'success' => AppColors.green600,
                    'danger' => AppColors.red600,
                    'accent' => AppColors.amber600,
                    _ => AppColors.navy700,
                  }),
              title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(detail, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
          const SizedBox(height: 12),
          Text('ACTION HISTORY — ${i.deviceId}', style: AppTheme.eyebrow().copyWith(color: AppColors.navy900, fontWeight: FontWeight.w700)),
          actions.when(
            data: (list) => list.isEmpty
                ? const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No actions recorded for this device yet.'))
                : Column(children: [
                    for (final a in list)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${a.status} · ${a.by}'),
                        subtitle: Text('${a.performedAt == null ? '' : formatIstDateTime(a.performedAt!)} · ACK ${a.ack ? 'received' : 'pending'}'),
                      ),
                  ]),
            loading: () => const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
            error: (e, _) => Text('$e', style: const TextStyle(color: AppColors.red600)),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : () => _run(() async => 'Troubleshoot sent — action ${await api.troubleshoot(i.deviceId, i.issueType)}'),
                child: const Text('Troubleshoot'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: _busy || i.resolved ? null : () => _run(() async => 'Backend issue status: ${(await api.resolve(i.id)).status}'),
                child: const Text('Acknowledge'),
              ),
            ),
          ]),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_message!, style: TextStyle(color: _messageError ? AppColors.red600 : AppColors.teal700, fontFamily: 'monospace', fontSize: 12)),
            ),
        ]);
      },
    );
  }
}
