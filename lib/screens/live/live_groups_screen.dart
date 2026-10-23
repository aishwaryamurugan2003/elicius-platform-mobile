import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../api/telemetry_api.dart';
import '../../core/theme/app_theme.dart';
import '../../state/data.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// Live status — choose a device group (the web LiveGroupsPage).
class LiveGroupsScreen extends ConsumerWidget {
  const LiveGroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsProvider);
    return AppShell(
      eyebrow: 'Live status',
      title: 'Select a group',
      body: AsyncBody<List<UserGroup>>(
        value: groups,
        onRetry: () => ref.invalidate(groupsProvider),
        data: (list) => list.isEmpty
            ? const EmptyState(message: "You aren't assigned to any device group yet.")
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
                    child: Text('Choose a device group to see live status, sensor readings and streaming payloads.',
                        style: TextStyle(color: AppColors.grey600)),
                  ),
                  for (final g in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          leading: const CircleAvatar(
                            backgroundColor: AppColors.navy050,
                            child: Icon(Icons.sensors, color: AppColors.navy700, size: 20),
                          ),
                          title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('${g.devices.length} device${g.devices.length == 1 ? '' : 's'}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/live/${Uri.encodeComponent(g.id)}'),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
