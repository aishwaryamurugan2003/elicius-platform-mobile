import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/dashboards_api.dart';
import '../../state/auth.dart';
import '../../state/data.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';
import '../dashboards/dashboard_body.dart';

/// Home — the dashboard saved in the user's reserved "Home_page" folder
/// (same one the web Home page shows). Created on first visit if missing.
final homeFolderProvider = FutureProvider.autoDispose<Folder>((ref) async {
  final user = ref.watch(authProvider).user;
  if (user?.userId == null) throw Exception('Not signed in.');
  final api = ref.watch(dashboardsApiProvider);
  final folders = await api.allFolders(user!.userId!);
  final existing = folders.where((f) => f.isHome).firstOrNull;
  if (existing != null) return existing;
  final groups = await ref.watch(groupsProvider.future);
  if (groups.isEmpty) throw Exception("You aren't assigned to any device group yet.");
  return api.createFolder(user.userId!, groups.first.id, homeFolderName);
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final folder = ref.watch(homeFolderProvider);
    return AppShell(
      eyebrow: 'Home',
      title: user?.organisationName ?? '',
      actions: [
        IconButton(tooltip: 'Device alerts', icon: const Icon(Icons.notifications_none), onPressed: () => context.go('/alerts')),
      ],
      body: AsyncBody<Folder>(
        value: folder,
        onRetry: () => ref.invalidate(homeFolderProvider),
        data: (f) => DashboardBody(
          folderId: f.id,
          emptyMessage: 'Your Home page has no widgets yet. Add them from Home on the web app.',
        ),
      ),
    );
  }
}
