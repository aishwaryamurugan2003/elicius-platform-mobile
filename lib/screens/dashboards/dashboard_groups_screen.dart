import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/telemetry_api.dart';
import '../../core/theme/app_theme.dart';
import '../../state/data.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// Dashboards — pick a device group (the web Dashboard gallery).
class DashboardGroupsScreen extends ConsumerWidget {
  const DashboardGroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsProvider);
    return AppShell(
      eyebrow: 'Dashboards',
      title: 'Select a group',
      body: AsyncBody<List<UserGroup>>(
        value: groups,
        onRetry: () => ref.invalidate(groupsProvider),
        data: (list) => list.isEmpty
            ? const EmptyState(message: "You aren't assigned to any device group yet.")
            : RefreshIndicator(
                onRefresh: () => ref.refresh(groupsProvider.future),
                child: ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final g = list[i];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        leading: const CircleAvatar(
                          backgroundColor: AppColors.navy050,
                          child: Icon(Icons.grid_view, color: AppColors.navy700, size: 20),
                        ),
                        title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${g.devices.length} device${g.devices.length == 1 ? '' : 's'}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/dashboards/group/${Uri.encodeComponent(g.id)}'),
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
