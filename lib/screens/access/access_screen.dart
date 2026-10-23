import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart';
import '../../core/permissions.dart';
import '../../core/theme/app_theme.dart';
import '../../state/auth.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

const _orgRoles = ['admin', 'editor', 'viewer'];

final _orgsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
    (ref) async => (await ref.watch(apiServiceProvider).get<List<dynamic>>(Endpoint.organizations)).cast<Map<String, dynamic>>());

final _membersProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, int>((ref, orgId) async =>
    (await ref.watch(apiServiceProvider).get<List<dynamic>>(Endpoint.organizationMembers.withParams({'org_id': '$orgId'})))
        .cast<Map<String, dynamic>>());

final _usersProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, search) async =>
    (await ref.watch(apiServiceProvider).get<List<dynamic>>(Endpoint.keycloakUsers, query: {
      if (search.isNotEmpty) 'search': search,
      'first': 0,
      'max_': 50,
    }))
        .cast<Map<String, dynamic>>());

final _deviceGroupsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
    (ref) async => (await ref.watch(apiServiceProvider).get<List<dynamic>>(Endpoint.groups)).cast<Map<String, dynamic>>());

final _groupDevicesProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, groupId) async =>
    (await ref.watch(apiServiceProvider).get<List<dynamic>>(Endpoint.devicesForGroup.withParams({'group_id': groupId})))
        .cast<Map<String, dynamic>>());

final _userMappingsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, userId) async =>
    (await ref.watch(apiServiceProvider).get<List<dynamic>>(Endpoint.userGroupMappings.withParams({'keycloak_user_id': userId})))
        .cast<Map<String, dynamic>>());

Future<void> _run(BuildContext context, Future<void> Function() f, String done, VoidCallback refresh) async {
  try {
    await f();
    if (context.mounted) showToast(context, done);
    refresh();
  } catch (e) {
    if (context.mounted) showToast(context, '$e', error: true);
  }
}

/// Access management — organisations, members, device-group links and
/// per-user device permissions (the web AccessManagementPage). platform_admin only.
class AccessScreen extends StatelessWidget {
  const AccessScreen({super.key});

  @override
  Widget build(BuildContext context) => const DefaultTabController(
        length: 5,
        child: AppShell(
          eyebrow: 'Access management',
          title: 'Organisations & access',
          bottom: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(text: 'Organisations'),
            Tab(text: 'Members'),
            Tab(text: 'Groups'),
            Tab(text: 'Device permissions'),
            Tab(text: 'Roles'),
          ]),
          body: TabBarView(children: [_OrgsTab(), _MembersTab(), _GroupLinksTab(), _PermissionsTab(), _RolesTab()]),
        ),
      );
}

// ---------------------------------------------------------------- Organisations
class _OrgsTab extends ConsumerWidget {
  const _OrgsTab();

  Future<Map<String, Object?>?> _orgForm(BuildContext context, [Map<String, dynamic>? o]) {
    final name = TextEditingController(text: o?['name'] as String? ?? '');
    final limit = TextEditingController(text: o?['members_limit']?.toString() ?? '');
    return showDialog<Map<String, Object?>>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(o == null ? 'New organisation' : 'Edit organisation'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 10),
          TextField(controller: limit, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Members limit (optional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(d, {'name': name.text.trim(), 'members_limit': int.tryParse(limit.text.trim())}),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orgs = ref.watch(_orgsProvider);
    final canManage = can(ref.watch(roleProvider), Perm.accessManageMembers);
    final api = ref.read(apiServiceProvider);
    void reload() => ref.invalidate(_orgsProvider);
    return Scaffold(
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('New organisation'),
              onPressed: () async {
                final v = await _orgForm(context);
                if (v == null || '${v['name']}'.isEmpty || !context.mounted) return;
                await _run(context, () => api.post<dynamic>(Endpoint.organizations, v), 'Organisation created', reload);
              },
            )
          : null,
      body: AsyncBody<List<Map<String, dynamic>>>(
        value: orgs,
        onRetry: reload,
        data: (list) => list.isEmpty
            ? const EmptyState(message: 'No organisations yet.')
            : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
                for (final o in list)
                  Card(
                    child: ListTile(
                      title: Text('${o['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${o['member_count'] ?? 0} member${o['member_count'] == 1 ? '' : 's'}'
                          '${o['members_limit'] == null ? '' : ' · limit ${o['members_limit']}'}'),
                      trailing: canManage
                          ? PopupMenuButton<String>(
                              onSelected: (a) async {
                                final id = '${o['id']}';
                                if (a == 'edit') {
                                  final v = await _orgForm(context, o);
                                  if (v == null || !context.mounted) return;
                                  await _run(context, () => api.put<dynamic>(Endpoint.organization.withParams({'org_id': id}), v), 'Organisation updated', reload);
                                } else {
                                  final ok = await confirmDialog(context,
                                      title: 'Delete organisation?', message: '"${o['name']}" will be deleted.', confirm: 'Delete', danger: true);
                                  if (ok && context.mounted) {
                                    await _run(context, () => api.delete<dynamic>(Endpoint.organization.withParams({'org_id': id})), 'Organisation deleted', reload);
                                  }
                                }
                              },
                              itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Edit')), PopupMenuItem(value: 'delete', child: Text('Delete'))],
                            )
                          : null,
                    ),
                  ),
              ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- Members
class _MembersTab extends ConsumerStatefulWidget {
  const _MembersTab();

  @override
  ConsumerState<_MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends ConsumerState<_MembersTab> {
  int? _orgId;

  Future<List<String>?> _pickRoles(List<String> initial) {
    final selected = {...initial};
    return showDialog<List<String>>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: const Text('Roles'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final r in _orgRoles)
              CheckboxListTile(
                value: selected.contains(r),
                title: Text(r[0].toUpperCase() + r.substring(1)),
                onChanged: (v) => set(() => v == true ? selected.add(r) : selected.remove(r)),
              ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
            FilledButton(onPressed: selected.isEmpty ? null : () => Navigator.pop(d, selected.toList()), child: const Text('Save')),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final orgs = ref.watch(_orgsProvider).value ?? const <Map<String, dynamic>>[];
    final canManage = can(ref.watch(roleProvider), Perm.accessManageMembers);
    final api = ref.read(apiServiceProvider);
    final members = _orgId == null ? null : ref.watch(_membersProvider(_orgId!));
    void reload() {
      if (_orgId != null) ref.invalidate(_membersProvider(_orgId!));
      ref.invalidate(_orgsProvider);
    }

    return Scaffold(
      floatingActionButton: canManage && _orgId != null
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Add member'),
              onPressed: () async {
                final user = await showModalBottomSheet<Map<String, dynamic>>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => const _UserPicker(),
                );
                if (user == null || !context.mounted) return;
                final roles = await _pickRoles(const ['viewer']);
                if (roles == null || !context.mounted) return;
                await _run(context,
                    () => api.post<dynamic>(Endpoint.organizationMembers.withParams({'org_id': '$_orgId'}), {'user_id': user['id'], 'roles': roles}),
                    'Member added', reload);
              },
            )
          : null,
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
        DropdownButtonFormField<int>(
          initialValue: _orgId,
          decoration: const InputDecoration(labelText: 'Organisation'),
          items: [for (final o in orgs) DropdownMenuItem(value: o['id'] as int, child: Text('${o['name']}'))],
          onChanged: (v) => setState(() => _orgId = v),
        ),
        const SizedBox(height: 12),
        if (members == null)
          const EmptyState(message: 'Pick an organisation to see its members.')
        else
          members.when(
            loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => ErrorState(message: '$e', onRetry: reload),
            data: (list) => list.isEmpty
                ? const EmptyState(message: 'No members yet.')
                : Column(children: [
                    for (final m in list)
                      Card(
                        child: ListTile(
                          title: Text('${m['username'] ?? m['user_id']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('Roles: ${((m['roles'] as List?) ?? const []).join(', ')}'),
                          trailing: canManage
                              ? PopupMenuButton<String>(
                                  onSelected: (a) async {
                                    final e = Endpoint.organizationMember.withParams({'org_id': '$_orgId', 'user_id': '${m['user_id']}'});
                                    if (a == 'roles') {
                                      final roles = await _pickRoles(((m['roles'] as List?) ?? const []).cast<String>());
                                      if (roles == null || !context.mounted) return;
                                      await _run(context, () => api.put<dynamic>(e, {'roles': roles}), 'Roles updated', reload);
                                    } else {
                                      final ok = await confirmDialog(context,
                                          title: 'Remove member?', message: 'They will lose access to this organisation.', confirm: 'Remove', danger: true);
                                      if (ok && context.mounted) await _run(context, () => api.delete<dynamic>(e), 'Member removed', reload);
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'roles', child: Text('Edit roles')),
                                    PopupMenuItem(value: 'remove', child: Text('Remove')),
                                  ],
                                )
                              : null,
                        ),
                      ),
                  ]),
          ),
      ]),
    );
  }
}

/// Search Keycloak users and pick one.
class _UserPicker extends ConsumerStatefulWidget {
  const _UserPicker();

  @override
  ConsumerState<_UserPicker> createState() => _UserPickerState();
}

class _UserPickerState extends ConsumerState<_UserPicker> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(_usersProvider(_search));
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Search users', prefixIcon: Icon(Icons.search)),
            onSubmitted: (v) => setState(() => _search = v.trim()),
          ),
        ),
        Expanded(
          child: users.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorState(message: '$e'),
            data: (list) => ListView(children: [
              for (final u in list)
                ListTile(
                  title: Text('${u['username']}'),
                  subtitle: Text('${u['email'] ?? ''}'),
                  onTap: () => Navigator.pop(context, u),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Groups (device-group links)
class _GroupLinksTab extends ConsumerWidget {
  const _GroupLinksTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(_deviceGroupsProvider);
    return AsyncBody<List<Map<String, dynamic>>>(
      value: groups,
      onRetry: () => ref.invalidate(_deviceGroupsProvider),
      data: (list) => ListView(padding: const EdgeInsets.all(12), children: [
        for (final g in list)
          Card(
            child: ExpansionTile(
              title: Text('${g['group_name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${g['group_id']}'),
              children: [_GroupDevices(groupId: '${g['group_id']}')],
            ),
          ),
      ]),
    );
  }
}

class _GroupDevices extends ConsumerWidget {
  const _GroupDevices({required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(_groupDevicesProvider(groupId));
    final api = ref.read(apiServiceProvider);
    return devices.when(
      loading: () => const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
      error: (e, _) => Padding(padding: const EdgeInsets.all(12), child: Text('$e', style: const TextStyle(color: AppColors.red600))),
      data: (list) => Column(children: [
        if (list.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('No devices in this group.')),
        for (final d in list)
          ListTile(dense: true, title: Text('${d['device_id']}'), subtitle: Text('${d['device_name'] ?? ''} · ${d['device_type'] ?? ''}')),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.add_link),
            label: const Text('Link a device'),
            onPressed: () async {
              final c = TextEditingController();
              final id = await showDialog<String>(
                context: context,
                builder: (dc) => AlertDialog(
                  title: const Text('Link device to group'),
                  content: TextField(controller: c, decoration: const InputDecoration(labelText: 'Device ID')),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(dc), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(dc, c.text.trim()), child: const Text('Link')),
                  ],
                ),
              );
              if (id == null || id.isEmpty || !context.mounted) return;
              await _run(context, () => api.post<dynamic>(Endpoint.deviceGroupLinks, {'group_id': groupId, 'device_id': id}), 'Device linked',
                  () => ref.invalidate(_groupDevicesProvider(groupId)));
            },
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Device permissions
class _PermissionsTab extends ConsumerStatefulWidget {
  const _PermissionsTab();

  @override
  ConsumerState<_PermissionsTab> createState() => _PermissionsTabState();
}

class _PermissionsTabState extends ConsumerState<_PermissionsTab> {
  Map<String, dynamic>? _user;
  String? _groupId;

  /// Mapping ids learned from create responses this session ("group:device" -> id) —
  /// the user-mappings endpoint returns device ids but not mapping ids.
  final Map<String, int> _mappingIds = {};

  @override
  Widget build(BuildContext context) {
    final canAssign = can(ref.watch(roleProvider), Perm.accessAssignDeviceAccess);
    final groups = ref.watch(_deviceGroupsProvider).value ?? const <Map<String, dynamic>>[];
    final api = ref.read(apiServiceProvider);
    final uid = _user?['id'] as String?;
    final mappings = uid == null ? null : ref.watch(_userMappingsProvider(uid));
    final granted = <String>{
      for (final m in mappings?.value ?? const <Map<String, dynamic>>[])
        if ('${m['id']}' == _groupId) ...((m['devices'] as List?) ?? const []).map((d) => '$d'),
    };
    final devices = _groupId == null ? null : ref.watch(_groupDevicesProvider(_groupId!));

    Future<void> toggle(String deviceId, bool grant) async {
      if (!canAssign || uid == null || _groupId == null) return;
      final key = '$_groupId:$deviceId';
      if (grant) {
        await _run(context, () async {
          final res = await api.post<Map<String, dynamic>>(Endpoint.mappings, {'keycloak_user_id': uid, 'device_id': deviceId, 'group_id': _groupId});
          if (res['id'] is int) _mappingIds[key] = res['id'] as int;
        }, '$deviceId added', () => ref.invalidate(_userMappingsProvider(uid)));
      } else {
        final id = _mappingIds[key];
        if (id == null) {
          showToast(context, "Can't remove this access here — the backend doesn't return its mapping id. Remove it from the backend.", error: true);
          return;
        }
        await _run(context, () => api.delete<dynamic>(Endpoint.mapping.withParams({'mapping_id': '$id'})), '$deviceId removed',
            () => ref.invalidate(_userMappingsProvider(uid)));
      }
    }

    return ListView(padding: const EdgeInsets.all(12), children: [
      OutlinedButton.icon(
        icon: const Icon(Icons.person_search),
        label: Text(_user == null ? 'Choose a user' : '${_user!['username']}'),
        onPressed: () async {
          final u = await showModalBottomSheet<Map<String, dynamic>>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => const _UserPicker(),
          );
          if (u != null) setState(() => _user = u);
        },
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        initialValue: _groupId,
        decoration: const InputDecoration(labelText: 'Group'),
        items: [for (final g in groups) DropdownMenuItem(value: '${g['group_id']}', child: Text('${g['group_name']}'))],
        onChanged: (v) => setState(() => _groupId = v),
      ),
      const SizedBox(height: 12),
      if (_user == null || devices == null)
        const EmptyState(message: 'Choose a user and a group to manage which devices they can see.')
      else
        devices.when(
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => ErrorState(message: '$e'),
          data: (list) => Card(
            child: Column(children: [
              for (final d in list)
                CheckboxListTile(
                  value: granted.contains('${d['device_id']}'),
                  title: Text('${d['device_id']}'),
                  subtitle: Text('${d['device_name'] ?? ''}'),
                  onChanged: canAssign ? (v) => toggle('${d['device_id']}', v == true) : null,
                ),
            ]),
          ),
        ),
    ]);
  }
}

// ---------------------------------------------------------------- Roles
class _RolesTab extends StatelessWidget {
  const _RolesTab();

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(12), children: [
        for (final (role, desc) in [
          (Role.platformAdmin, 'Every page, every action — including Device Administration and Access management.'),
          (Role.orgAdmin, 'Every page except Devices and Access management. Full dashboard create / edit / delete.'),
          (Role.orgEditor, 'Every page except Devices and Access management. Dashboard create / edit / delete.'),
          (Role.orgViewer, 'Every page except Devices and Access management. Read-only.'),
        ])
          Card(
            child: ListTile(
              title: Text(roleLabels[role]!, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(desc),
            ),
          ),
      ]);
}
