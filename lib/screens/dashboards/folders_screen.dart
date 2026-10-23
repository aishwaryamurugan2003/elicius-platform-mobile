import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/dashboards_api.dart';
import '../../core/permissions.dart';
import '../../core/theme/app_theme.dart';
import '../../state/auth.dart';
import '../../state/data.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

final _groupFoldersProvider = FutureProvider.autoDispose.family<List<Folder>, String>((ref, groupId) async {
  final uid = ref.watch(authProvider.select((a) => a.user?.userId));
  if (uid == null) return const [];
  return ref.watch(dashboardsApiProvider).folders(uid, groupId);
});

/// A group's dashboard folders (the web DashboardSelectorPage): open, and —
/// for edit roles — create, rename and delete.
class FoldersScreen extends ConsumerWidget {
  const FoldersScreen({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(_groupFoldersProvider(groupId));
    final role = ref.watch(roleProvider);
    final groupName = ref.watch(groupsProvider).value?.where((g) => g.id == groupId).firstOrNull?.name ?? groupId;
    final canCreate = can(role, Perm.dashboardsCreate);
    final canEdit = can(role, Perm.dashboardsEdit);
    final canDelete = can(role, Perm.dashboardsDelete);
    void reload() => ref.invalidate(_groupFoldersProvider(groupId));

    Future<String?> askName(String title, [String initial = '']) {
      final c = TextEditingController(text: initial);
      return showDialog<String>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(title),
          content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Folder name')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Save')),
          ],
        ),
      );
    }

    Future<void> run(Future<void> Function() action, String done) async {
      try {
        await action();
        if (context.mounted) showToast(context, done);
        reload();
      } catch (e) {
        if (context.mounted) showToast(context, '$e', error: true);
      }
    }

    return AppShell(
      eyebrow: 'Dashboards',
      title: '$groupName Dashboard',
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('New'),
              onPressed: () async {
                if (!canCreate) return;
                final name = await askName('New folder');
                final uid = ref.read(authProvider).user?.userId;
                if (name == null || name.isEmpty || uid == null) return;
                await run(() => ref.read(dashboardsApiProvider).createFolder(uid, groupId, name), 'Folder created');
              },
            )
          : null,
      body: AsyncBody<List<Folder>>(
        value: folders,
        onRetry: reload,
        data: (list) => list.isEmpty
            ? const EmptyState(message: 'No folders in this group yet.')
            : RefreshIndicator(
                onRefresh: () => ref.refresh(_groupFoldersProvider(groupId).future),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final f = list[i];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
                        title: Text(f.isHome ? 'Home page' : f.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: f.isHome
                            ? const Text('Shown on Home', style: TextStyle(color: AppColors.teal600, fontWeight: FontWeight.w600))
                            : const Text('Custom folder'),
                        onTap: () => context.push('/dashboards/folder/${f.id}?name=${Uri.encodeComponent(f.isHome ? 'Home page' : f.name)}'),
                        trailing: (canEdit || canDelete) && !f.isHome
                            ? PopupMenuButton<String>(
                                onSelected: (v) async {
                                  if (v == 'rename' && canEdit) {
                                    final name = await askName('Rename folder', f.name);
                                    if (name == null || name.isEmpty) return;
                                    await run(() => ref.read(dashboardsApiProvider).renameFolder(f.id, name), 'Folder renamed');
                                  } else if (v == 'delete' && canDelete) {
                                    if (!context.mounted) return;
                                    final ok = await confirmDialog(context,
                                        title: 'Delete folder?',
                                        message: '"${f.name}" and its dashboard will be deleted. This can\'t be undone.',
                                        confirm: 'Delete',
                                        danger: true);
                                    if (ok) await run(() => ref.read(dashboardsApiProvider).deleteFolder(f.id), 'Folder deleted');
                                  }
                                },
                                itemBuilder: (_) => [
                                  if (canEdit) const PopupMenuItem(value: 'rename', child: Text('Rename')),
                                  if (canDelete) const PopupMenuItem(value: 'delete', child: Text('Delete')),
                                ],
                              )
                            : const Icon(Icons.chevron_right),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
