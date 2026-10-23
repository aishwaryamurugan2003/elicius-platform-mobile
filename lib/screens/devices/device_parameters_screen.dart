import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart';
import '../../core/permissions.dart';
import '../../core/theme/app_theme.dart';
import '../../state/auth.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

typedef Field = ({String key, String value});

class _Params {
  _Params(this.deviceType, this.monitoring, this.all);
  final String deviceType;
  final List<Field> monitoring, all;
}

List<Field> _fields(Object? list) => [
      for (final f in (list as List? ?? const []))
        (key: '${(f as Map)['key']}', value: f['value'] == null ? '' : '${f['value']}'),
    ];

final _paramsProvider = FutureProvider.autoDispose.family<_Params, int>((ref, id) async {
  final r = await ref.watch(apiServiceProvider).get<Map<String, dynamic>>(Endpoint.deviceTypeParameters.withParams({'id': '$id'}));
  return _Params('${r['device_type'] ?? ''}', _fields(r['monitoring_fields']), _fields(r['all_fields']));
});

/// Accepts `[{key, value}]`, `{"key": "value"}`, or `{monitoring_fields, all_fields}`
/// (same rules as the web lib/parametersImport.ts). Returns (monitoring, all).
(List<Field>, List<Field>) parseParametersJson(String text, String section) {
  final Object? data;
  try {
    data = jsonDecode(text);
  } on FormatException catch (e) {
    throw FormatException('Not valid JSON — ${e.message}.');
  }
  String v(Object? x) => x == null ? '' : (x is String ? x : jsonEncode(x));
  List<Field> list(Object? input, String where) {
    if (input is List) {
      return [
        for (var i = 0; i < input.length; i++)
          if (input[i] is Map && input[i]['key'] is String && (input[i]['key'] as String).trim().isNotEmpty)
            (key: (input[i]['key'] as String).trim(), value: v(input[i]['value']))
          else
            throw FormatException('$where: item ${i + 1} needs a non-empty string "key".'),
      ];
    }
    if (input is Map) return [for (final e in input.entries) (key: '${e.key}'.trim(), value: v(e.value))];
    throw FormatException('$where must be a list of {"key","value"} objects or a {"key": "value"} object.');
  }

  var mon = <Field>[], all = <Field>[];
  if (data is Map && (data.containsKey('monitoring_fields') || data.containsKey('all_fields'))) {
    if (data['monitoring_fields'] != null) mon = list(data['monitoring_fields'], 'monitoring_fields');
    if (data['all_fields'] != null) all = list(data['all_fields'], 'all_fields');
  } else if (section == 'monitoring') {
    mon = list(data, 'The JSON');
  } else {
    all = list(data, 'The JSON');
  }
  if (mon.isEmpty && all.isEmpty) throw const FormatException('No fields found in that JSON.');
  return (mon, all);
}

/// Existing fields with imported ones merged in — an imported key replaces the old value.
List<Field> mergeFields(List<Field> existing, List<Field> imported) {
  final byKey = {for (final f in existing) f.key: f};
  for (final f in imported) {
    byKey[f.key] = f;
  }
  return byKey.values.toList();
}

/// A device type's monitoring fields and all fields — add, delete, import JSON
/// (the web DeviceParametersPage). platform_admin only.
class DeviceParametersScreen extends ConsumerWidget {
  const DeviceParametersScreen({super.key, required this.deviceTypeId, this.name});
  final int deviceTypeId;
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = ref.watch(_paramsProvider(deviceTypeId));
    final canManage = can(ref.watch(roleProvider), Perm.devicesManageTypes);
    final api = ref.read(apiServiceProvider);
    final id = '$deviceTypeId';

    Future<void> run(Future<void> Function() f, String done) async {
      try {
        await f();
        if (context.mounted) showToast(context, done);
        ref.invalidate(_paramsProvider(deviceTypeId));
      } catch (e) {
        if (context.mounted) showToast(context, '$e', error: true);
      }
    }

    Future<void> addField(String section) async {
      final k = TextEditingController(), v = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(section == 'monitoring' ? 'Add monitoring field' : 'Add field'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: k, decoration: const InputDecoration(labelText: 'Key')),
            const SizedBox(height: 10),
            TextField(controller: v, decoration: const InputDecoration(labelText: 'Value')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Add')),
          ],
        ),
      );
      if (ok != true || k.text.trim().isEmpty) return;
      final e = section == 'monitoring' ? Endpoint.monitoringFields : Endpoint.allFields;
      await run(() => api.post<dynamic>(e.withParams({'id': id}), {'key': k.text.trim(), 'value': v.text.trim()}), 'Field added');
    }

    Future<void> importJson(_Params current) async {
      final text = TextEditingController();
      var section = 'monitoring';
      String? error;
      final result = await showDialog<(List<Field>, List<Field>)>(
        context: context,
        builder: (d) => StatefulBuilder(
          builder: (d, set) => AlertDialog(
            title: const Text('Import parameters'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [ButtonSegment(value: 'monitoring', label: Text('Monitoring')), ButtonSegment(value: 'all', label: Text('All fields'))],
                  selected: {section},
                  onSelectionChanged: (s) => set(() => section = s.first),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: text,
                  maxLines: 10,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: const InputDecoration(hintText: '[\n  { "key": "spm10", "value": "PM10" }\n]'),
                ),
                const SizedBox(height: 6),
                const Text('Accepts [{"key","value"}…], {"key": "value"…}, or {"monitoring_fields": […], "all_fields": […]} for both sections. '
                    'Existing keys get their value replaced.', style: TextStyle(fontSize: 11, color: AppColors.grey500)),
                if (error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(error!, style: const TextStyle(color: AppColors.red600, fontSize: 12))),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  try {
                    Navigator.pop(d, parseParametersJson(text.text, section));
                  } on FormatException catch (e) {
                    set(() => error = e.message);
                  }
                },
                child: const Text('Import'),
              ),
            ],
          ),
        ),
      );
      if (result == null) return;
      final (mon, all) = result;
      List<Map<String, String>> wire(List<Field> l) => [for (final f in l) {'key': f.key, 'value': f.value}];
      await run(
        () => api.put<dynamic>(Endpoint.deviceTypeParameters.withParams({'id': id}), {
          'monitoring_fields': wire(mergeFields(current.monitoring, mon)),
          'all_fields': wire(mergeFields(current.all, all)),
        }),
        'Imported ${mon.length + all.length} field${mon.length + all.length == 1 ? '' : 's'}',
      );
    }

    Widget section(String key, String title, List<Field> fields) => SectionCard(
          title: title,
          padding: EdgeInsets.zero,
          trailing: canManage ? TextButton.icon(onPressed: () => addField(key), icon: const Icon(Icons.add, size: 18), label: const Text('Add field')) : null,
          child: Column(children: [
            if (fields.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No fields yet — create one to get started.')),
            for (final f in fields)
              ListTile(
                title: Text(f.key, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(f.value),
                trailing: canManage
                    ? IconButton(
                        tooltip: 'Delete field',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final ok = await confirmDialog(context,
                              title: 'Delete field', message: 'Delete "${f.key}"? This cannot be undone.', confirm: 'Delete', danger: true);
                          if (!ok) return;
                          final e = key == 'monitoring' ? Endpoint.monitoringField : Endpoint.allField;
                          await run(() => api.delete<dynamic>(e.withParams({'id': id, 'key': f.key})), 'Field deleted');
                        },
                      )
                    : null,
              ),
          ]),
        );

    return AppShell(
      eyebrow: 'Devices / Device types',
      title: 'Parameters — ${params.value?.deviceType ?? name ?? ''}',
      showDrawer: false,
      actions: [
        if (canManage && params.hasValue)
          IconButton(tooltip: 'Import JSON', icon: const Icon(Icons.upload_file), onPressed: () => importJson(params.value!)),
      ],
      body: AsyncBody<_Params>(
        value: params,
        onRetry: () => ref.invalidate(_paramsProvider(deviceTypeId)),
        data: (p) => ListView(padding: const EdgeInsets.all(12), children: [
          section('monitoring', 'Monitoring fields', p.monitoring),
          const SizedBox(height: 12),
          section('all', 'All fields', p.all),
        ]),
      ),
    );
  }
}
