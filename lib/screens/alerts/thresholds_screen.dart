import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart';
import '../../core/fields.dart';
import '../../core/permissions.dart';
import '../../core/theme/app_theme.dart';
import '../../state/auth.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

class ThresholdRule {
  ThresholdRule.fromJson(Map<String, dynamic> j)
      : id = j['id'] as int,
        deviceId = j['device_id'] as String?,
        parameter = '${j['parameter']}',
        min = asNumber(j['min_value']),
        max = asNumber(j['max_value']),
        severity = '${j['severity'] ?? ''}',
        issueType = '${j['issue_type'] ?? ''}',
        active = j['is_active'] == true;

  final int id;
  final String? deviceId;
  final String parameter, severity, issueType;
  final double? min, max;
  final bool active;
}

/// Devices the alerts service monitors: (device id, rule count, active count).
final _monitoredProvider = FutureProvider.autoDispose<List<(String, int, int)>>((ref) async {
  final res = await ref.watch(apiServiceProvider).get<List<dynamic>>(Endpoint.monitoredDevices);
  return [
    for (final d in res.cast<Map<String, dynamic>>())
      ('${d['device_id']}', d['rule_count'] as int? ?? 0, d['active_rule_count'] as int? ?? 0),
  ];
});

final _rulesProvider = FutureProvider.autoDispose.family<List<ThresholdRule>, String>((ref, deviceId) async {
  final res = await ref.watch(apiServiceProvider).get<List<dynamic>>(Endpoint.deviceThresholds.withParams({'device_id': deviceId}));
  return [for (final r in res) ThresholdRule.fromJson(r as Map<String, dynamic>)];
});

/// Alert rules (thresholds) per device — the web ThresholdsPage. platform_admin only.
class ThresholdsScreen extends ConsumerWidget {
  const ThresholdsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(_monitoredProvider);
    final canManage = can(ref.watch(roleProvider), Perm.alertsManageThresholds);
    return AppShell(
      eyebrow: 'Device alerts',
      title: 'Alert rules',
      showDrawer: false,
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('New rule'),
              onPressed: () => _editRule(context, ref, null, null),
            )
          : null,
      body: AsyncBody<List<(String, int, int)>>(
        value: devices,
        onRetry: () => ref.invalidate(_monitoredProvider),
        data: (list) => list.isEmpty
            ? const EmptyState(message: 'No monitored devices yet.')
            : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
                for (final (id, rules, active) in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ExpansionTile(
                        title: Text(id, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('$rules rule${rules == 1 ? '' : 's'} · $active active'),
                        children: [_DeviceRules(deviceId: id, canManage: canManage)],
                      ),
                    ),
                  ),
              ]),
      ),
    );
  }
}

class _DeviceRules extends ConsumerWidget {
  const _DeviceRules({required this.deviceId, required this.canManage});
  final String deviceId;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(_rulesProvider(deviceId));
    final api = ref.read(apiServiceProvider);
    Future<void> run(Future<void> Function() f, String done) async {
      try {
        await f();
        if (context.mounted) showToast(context, done);
        ref.invalidate(_rulesProvider(deviceId));
        ref.invalidate(_monitoredProvider);
      } catch (e) {
        if (context.mounted) showToast(context, '$e', error: true);
      }
    }

    return rules.when(
      loading: () => const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
      error: (e, _) => Padding(padding: const EdgeInsets.all(12), child: Text('$e', style: const TextStyle(color: AppColors.red600))),
      data: (list) => Column(children: [
        if (list.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('No rules for this device.')),
        for (final r in list)
          ListTile(
            title: Text('${fieldLabel(r.parameter)} · ${r.issueType}'),
            subtitle: Text('min ${r.min == null ? '—' : formatValue(r.min)} · max ${r.max == null ? '—' : formatValue(r.max)} · ${r.severity}'),
            trailing: canManage
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    Switch(
                      value: r.active,
                      onChanged: (v) => run(
                        () => api.put<dynamic>(Endpoint.threshold.withParams({'id': '${r.id}'}), {'is_active': v}),
                        v ? 'Rule enabled' : 'Rule disabled',
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'edit') return _editRule(context, ref, deviceId, r);
                        final ok = await confirmDialog(context,
                            title: 'Delete rule?', message: 'This alert rule will be removed.', confirm: 'Delete', danger: true);
                        if (ok) await run(() => api.delete<dynamic>(Endpoint.threshold.withParams({'id': '${r.id}'})), 'Rule deleted');
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ])
                : (r.active ? const StatusPill('Active', fg: AppColors.green600, bg: AppColors.green100) : null),
          ),
      ]),
    );
  }
}

/// Create (rule == null) or edit an alert rule.
Future<void> _editRule(BuildContext context, WidgetRef ref, String? deviceId, ThresholdRule? rule) async {
  final devices = TextEditingController(text: deviceId ?? '');
  final param = TextEditingController(text: rule?.parameter ?? '');
  final minC = TextEditingController(text: rule?.min?.toString() ?? '');
  final maxC = TextEditingController(text: rule?.max?.toString() ?? '');
  final issue = TextEditingController(text: rule?.issueType ?? '');
  var severity = (rule?.severity.isNotEmpty ?? false) ? rule!.severity.toUpperCase() : 'MEDIUM';
  final saved = await showDialog<bool>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: Text(rule == null ? 'New alert rule' : 'Edit alert rule'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (rule == null)
              TextField(controller: devices, decoration: const InputDecoration(labelText: 'Device IDs (comma-separated)')),
            const SizedBox(height: 10),
            TextField(controller: param, decoration: const InputDecoration(labelText: 'Parameter (e.g. sPM10)')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: minC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Min'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: maxC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Max'))),
            ]),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: const ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'].contains(severity) ? severity : 'MEDIUM',
              decoration: const InputDecoration(labelText: 'Severity'),
              items: const [
                DropdownMenuItem(value: 'LOW', child: Text('Low')),
                DropdownMenuItem(value: 'MEDIUM', child: Text('Medium (Warning)')),
                DropdownMenuItem(value: 'HIGH', child: Text('High (Alarm)')),
                DropdownMenuItem(value: 'CRITICAL', child: Text('Critical')),
              ],
              onChanged: (v) => set(() => severity = v!),
            ),
            const SizedBox(height: 10),
            TextField(controller: issue, decoration: const InputDecoration(labelText: 'Issue type (e.g. SPM10 HAS EXCEEDED)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save')),
        ],
      ),
    ),
  );
  if (saved != true || !context.mounted) return;
  final body = {
    'parameter': param.text.trim(),
    'min_value': double.tryParse(minC.text.trim()),
    'max_value': double.tryParse(maxC.text.trim()),
    'severity': severity,
    'issue_type': issue.text.trim(),
  };
  final api = ref.read(apiServiceProvider);
  try {
    if (rule == null) {
      final ids = devices.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (ids.isEmpty || body['parameter'] == '' || body['issue_type'] == '') {
        throw Exception('Device IDs, parameter and issue type are required.');
      }
      await api.post<dynamic>(Endpoint.createDeviceThresholds, {...body, 'device_ids': ids, 'is_active': true});
    } else {
      await api.put<dynamic>(Endpoint.threshold.withParams({'id': '${rule.id}'}), body);
    }
    if (context.mounted) showToast(context, 'Rule saved');
    ref.invalidate(_monitoredProvider);
    if (deviceId != null) ref.invalidate(_rulesProvider(deviceId));
  } catch (e) {
    if (context.mounted) showToast(context, '$e', error: true);
  }
}
