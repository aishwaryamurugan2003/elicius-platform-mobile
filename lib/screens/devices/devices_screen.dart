import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/endpoints.dart';
import '../../core/ist_time.dart';
import '../../core/permissions.dart';
import '../../core/theme/app_theme.dart';
import '../../state/auth.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

// ---- Simple list providers (device registration service, bs2).
FutureProvider<List<Map<String, dynamic>>> _listOf(Endpoint e) =>
    FutureProvider.autoDispose((ref) async => (await ref.watch(apiServiceProvider).get<List<dynamic>>(e)).cast<Map<String, dynamic>>());

final _devicesProvider = _listOf(Endpoint.devices);
final _groupsProvider = _listOf(Endpoint.groups);
final _serversProvider = _listOf(Endpoint.mqttServers);
final _typesProvider = _listOf(Endpoint.deviceTypes);

/// A form field for [_formDialog]: key, label, initial value; `options` makes it a dropdown, `isBool` a switch.
class _F {
  const _F(this.key, this.label, {this.initial, this.options, this.isBool = false, this.readOnly = false});
  final String key, label;
  final Object? initial;
  final List<String>? options;
  final bool isBool, readOnly;
}

Future<Map<String, Object?>?> _formDialog(BuildContext context, String title, List<_F> fields) {
  final values = <String, Object?>{for (final f in fields) f.key: f.initial ?? (f.isBool ? true : '')};
  return showDialog<Map<String, Object?>>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final f in fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: f.isBool
                    ? SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(f.label),
                        value: values[f.key] == true,
                        onChanged: (v) => set(() => values[f.key] = v),
                      )
                    : f.options != null
                        ? DropdownButtonFormField<String>(
                            initialValue: f.options!.contains(values[f.key]) ? values[f.key] as String : null,
                            decoration: InputDecoration(labelText: f.label),
                            items: [for (final o in f.options!) DropdownMenuItem(value: o, child: Text(o))],
                            onChanged: (v) => set(() => values[f.key] = v),
                          )
                        : TextFormField(
                            initialValue: '${values[f.key]}',
                            enabled: !f.readOnly,
                            decoration: InputDecoration(labelText: f.label),
                            onChanged: (v) => values[f.key] = v.trim(),
                          ),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, values), child: const Text('Save')),
        ],
      ),
    ),
  );
}

/// Device Administration — devices, groups, MQTT servers and device types
/// (the web DeviceAdministrationPage + registration pages). platform_admin only.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: AppShell(
        eyebrow: 'Devices',
        title: 'Device Administration',
        bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
          Tab(text: 'Devices'),
          Tab(text: 'Groups'),
          Tab(text: 'MQTT servers'),
          Tab(text: 'Device types'),
        ]),
        body: const TabBarView(children: [_DevicesTab(), _GroupsTab(), _ServersTab(), _TypesTab()]),
      ),
    );
  }
}

/// Runs a write, shows the result, and refreshes [refresh].
Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() f, String done, List<ProviderOrFamily> refresh) async {
  try {
    await f();
    if (context.mounted) showToast(context, done);
    for (final p in refresh) {
      ref.invalidate(p);
    }
  } catch (e) {
    if (context.mounted) showToast(context, '$e', error: true);
  }
}

class _ListTab extends ConsumerWidget {
  const _ListTab({required this.provider, required this.tile, required this.empty, this.onAdd, this.addLabel = 'Add'});
  final ProviderListenable<AsyncValue<List<Map<String, dynamic>>>> provider;
  final Widget Function(Map<String, dynamic>) tile;
  final String empty;
  final VoidCallback? onAdd;
  final String addLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(provider);
    return Scaffold(
      floatingActionButton: onAdd == null ? null : FloatingActionButton.extended(onPressed: onAdd, icon: const Icon(Icons.add), label: Text(addLabel)),
      body: AsyncBody<List<Map<String, dynamic>>>(
        value: value,
        data: (list) => list.isEmpty
            ? EmptyState(message: empty)
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => Card(child: tile(list[i])),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Devices
class _DevicesTab extends ConsumerWidget {
  const _DevicesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canRegister = can(ref.watch(roleProvider), Perm.devicesRegister);
    final types = [for (final t in ref.watch(_typesProvider).value ?? const <Map<String, dynamic>>[]) '${t['name']}'];
    final api = ref.read(apiServiceProvider);
    return _ListTab(
      provider: _devicesProvider,
      empty: 'No devices registered yet.',
      addLabel: 'Register device',
      onAdd: canRegister
          ? () async {
              final v = await _formDialog(context, 'Register device', [
                const _F('device_id', 'Device ID'),
                const _F('device_name', 'Device name'),
                _F('device_type', 'Device type', options: types),
                const _F('status', 'Active', isBool: true),
              ]);
              if (v == null || '${v['device_id']}'.isEmpty || !context.mounted) return;
              await _run(context, ref, () => api.post<dynamic>(Endpoint.devices, v), 'Device registered', [_devicesProvider]);
            }
          : null,
      tile: (d) => ListTile(
        title: Text('${d['device_name'] ?? d['device_id']}', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text([
          '${d['device_id']}',
          if (d['device_type'] != null) '${d['device_type']}',
          if (parseUtcTimestamp(d['created_at']) case final t?) 'added ${formatIstDateTime(t)}',
        ].join(' · ')),
        trailing: d['status'] == true
            ? const StatusPill('Active', fg: AppColors.green600, bg: AppColors.green100)
            : const StatusPill('Inactive', fg: AppColors.grey500, bg: AppColors.grey100),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => _DeviceSheet(device: d, types: types),
        ),
      ),
    );
  }
}

final _membershipsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, deviceId) async =>
    (await ref.watch(apiServiceProvider).get<List<dynamic>>(Endpoint.groupsForDevice.withParams({'device_id': deviceId})))
        .cast<Map<String, dynamic>>());

class _DeviceSheet extends ConsumerWidget {
  const _DeviceSheet({required this.device, required this.types});
  final Map<String, dynamic> device;
  final List<String> types;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = '${device['device_id']}';
    final memberships = ref.watch(_membershipsProvider(id));
    final allGroups = ref.watch(_groupsProvider).value ?? const <Map<String, dynamic>>[];
    final api = ref.read(apiServiceProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${device['device_name'] ?? id}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        Text(id, style: const TextStyle(fontFamily: 'monospace', color: AppColors.grey600)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Update device'),
          onPressed: () async {
            final v = await _formDialog(context, 'Update device', [
              _F('device_name', 'Device name', initial: device['device_name'] ?? ''),
              _F('device_type', 'Device type', initial: device['device_type'], options: types),
              _F('status', 'Active', isBool: true, initial: device['status'] == true),
            ]);
            if (v == null || !context.mounted) return;
            await _run(context, ref, () => api.put<dynamic>(Endpoint.device.withParams({'device_id': id}), v), 'Device updated', [_devicesProvider]);
            if (context.mounted) Navigator.pop(context);
          },
        ),
        const SizedBox(height: 16),
        Text('GROUPS', style: AppTheme.eyebrow().copyWith(color: AppColors.navy900, fontWeight: FontWeight.w700)),
        memberships.when(
          loading: () => const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
          error: (e, _) => Text('$e', style: const TextStyle(color: AppColors.red600)),
          data: (list) => Column(children: [
            if (list.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Not in any group.')),
            for (final g in list)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${g['group_name'] ?? g['group_id']}'),
                trailing: IconButton(
                  tooltip: 'Remove from group',
                  icon: const Icon(Icons.link_off),
                  onPressed: () => _run(context, ref, () => api.delete<dynamic>(Endpoint.deviceGroupLink.withParams({'id': '${g['link_id']}'})),
                      'Removed from group', [_membershipsProvider(id)]),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add_link),
                label: const Text('Add to group'),
                onPressed: () async {
                  final v = await _formDialog(context, 'Add to group', [
                    _F('group_id', 'Group', options: [for (final g in allGroups) '${g['group_id']}']),
                  ]);
                  final gid = v?['group_id'];
                  if (gid == null || '$gid'.isEmpty || !context.mounted) return;
                  await _run(context, ref, () => api.post<dynamic>(Endpoint.deviceGroupLinks, {'group_id': gid, 'device_id': id}), 'Added to group',
                      [_membershipsProvider(id)]);
                },
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Groups
class _GroupsTab extends ConsumerWidget {
  const _GroupsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = can(ref.watch(roleProvider), Perm.devicesManageGroups);
    final servers = [for (final s in ref.watch(_serversProvider).value ?? const <Map<String, dynamic>>[]) '${s['server_name']}'];
    final api = ref.read(apiServiceProvider);
    List<_F> form([Map<String, dynamic>? g]) => [
          _F('group_id', 'Group ID', initial: g?['group_id'], readOnly: g != null),
          _F('group_name', 'Group name', initial: g?['group_name']),
          _F('mqtt_topic', 'MQTT topic', initial: g?['mqtt_topic']),
          _F('mqtt_server', 'MQTT server', initial: g?['mqtt_server'], options: servers),
          _F('db_name', 'Database name', initial: g?['db_name']),
          _F('status', 'Active', isBool: true, initial: g == null ? true : g['status'] == true),
        ];
    return _ListTab(
      provider: _groupsProvider,
      empty: 'No groups yet.',
      addLabel: 'New group',
      onAdd: canManage
          ? () async {
              final v = await _formDialog(context, 'New group', form());
              if (v == null || !context.mounted) return;
              await _run(context, ref, () => api.post<dynamic>(Endpoint.groups, v), 'Group created', [_groupsProvider]);
            }
          : null,
      tile: (g) => ListTile(
        title: Text('${g['group_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${g['group_id']} · topic ${g['mqtt_topic']} · ${g['mqtt_server']} · db ${g['db_name']}'),
        trailing: canManage
            ? PopupMenuButton<String>(
                onSelected: (a) async {
                  final gid = '${g['group_id']}';
                  if (a == 'edit') {
                    final v = await _formDialog(context, 'Update group', form(g));
                    if (v == null || !context.mounted) return;
                    v.remove('group_id');
                    await _run(context, ref, () => api.put<dynamic>(Endpoint.group.withParams({'group_id': gid}), v), 'Group updated', [_groupsProvider]);
                  } else {
                    final ok = await confirmDialog(context, title: 'Delete group?', message: '"${g['group_name']}" will be deleted.', confirm: 'Delete', danger: true);
                    if (ok && context.mounted) {
                      await _run(context, ref, () => api.delete<dynamic>(Endpoint.group.withParams({'group_id': gid})), 'Group deleted', [_groupsProvider]);
                    }
                  }
                },
                itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Edit')), PopupMenuItem(value: 'delete', child: Text('Delete'))],
              )
            : null,
      ),
    );
  }
}

// ---------------------------------------------------------------- MQTT servers
class _ServersTab extends ConsumerWidget {
  const _ServersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = can(ref.watch(roleProvider), Perm.devicesManageServers);
    final api = ref.read(apiServiceProvider);
    List<_F> form([Map<String, dynamic>? s]) => [
          _F('server_name', 'Server name', initial: s?['server_name'], readOnly: s != null),
          _F('host', 'Host', initial: s?['host']),
          _F('port', 'Port', initial: s?['port']),
          _F('label', 'Label', initial: s?['label']),
        ];
    return _ListTab(
      provider: _serversProvider,
      empty: 'No MQTT servers yet.',
      addLabel: 'New server',
      onAdd: canManage
          ? () async {
              final v = await _formDialog(context, 'New MQTT server', form());
              if (v == null || !context.mounted) return;
              await _run(context, ref, () => api.post<dynamic>(Endpoint.mqttServers, v), 'Server added', [_serversProvider]);
            }
          : null,
      tile: (s) => ListTile(
        title: Text('${s['server_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${s['host']}:${s['port']} · ${s['label']}'),
        trailing: canManage
            ? PopupMenuButton<String>(
                onSelected: (a) async {
                  final name = '${s['server_name']}';
                  if (a == 'edit') {
                    final v = await _formDialog(context, 'Update MQTT server', form(s));
                    if (v == null || !context.mounted) return;
                    v.remove('server_name');
                    await _run(context, ref, () => api.put<dynamic>(Endpoint.mqttServer.withParams({'server_name': name}), v), 'Server updated',
                        [_serversProvider]);
                  } else {
                    final ok = await confirmDialog(context, title: 'Delete server?', message: '"$name" will be deleted.', confirm: 'Delete', danger: true);
                    if (ok && context.mounted) {
                      await _run(context, ref, () => api.delete<dynamic>(Endpoint.mqttServer.withParams({'server_name': name})), 'Server deleted',
                          [_serversProvider]);
                    }
                  }
                },
                itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Edit')), PopupMenuItem(value: 'delete', child: Text('Delete'))],
              )
            : null,
      ),
    );
  }
}

// ---------------------------------------------------------------- Device types
class _TypesTab extends ConsumerWidget {
  const _TypesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = can(ref.watch(roleProvider), Perm.devicesManageTypes);
    final api = ref.read(apiServiceProvider);
    List<_F> form([Map<String, dynamic>? t]) => [
          _F('name', 'Name', initial: t?['name']),
          _F('description', 'Description', initial: t?['description']),
        ];
    return _ListTab(
      provider: _typesProvider,
      empty: 'No device types yet.',
      addLabel: 'New type',
      onAdd: canManage
          ? () async {
              final v = await _formDialog(context, 'New device type', form());
              if (v == null || !context.mounted) return;
              await _run(context, ref, () => api.post<dynamic>(Endpoint.deviceTypes, v), 'Device type created', [_typesProvider]);
            }
          : null,
      tile: (t) => ListTile(
        title: Text('${t['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${t['description'] ?? ''}'),
        onTap: () => context.push('/device-types/${t['id']}/parameters?name=${Uri.encodeComponent('${t['name']}')}'),
        trailing: canManage
            ? PopupMenuButton<String>(
                onSelected: (a) async {
                  final id = '${t['id']}';
                  if (a == 'params') {
                    context.push('/device-types/$id/parameters?name=${Uri.encodeComponent('${t['name']}')}');
                  } else if (a == 'edit') {
                    final v = await _formDialog(context, 'Update device type', form(t));
                    if (v == null || !context.mounted) return;
                    await _run(context, ref, () => api.put<dynamic>(Endpoint.deviceType.withParams({'id': id}), v), 'Device type updated', [_typesProvider]);
                  } else {
                    final ok = await confirmDialog(context, title: 'Delete device type?', message: '"${t['name']}" will be deleted.', confirm: 'Delete', danger: true);
                    if (ok && context.mounted) {
                      await _run(context, ref, () => api.delete<dynamic>(Endpoint.deviceType.withParams({'id': id})), 'Device type deleted', [_typesProvider]);
                    }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'params', child: Text('Parameters')),
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              )
            : const Icon(Icons.chevron_right),
      ),
    );
  }
}
