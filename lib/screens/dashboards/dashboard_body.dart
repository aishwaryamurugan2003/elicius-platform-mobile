import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/dashboards_api.dart';
import '../../core/permissions.dart';
import '../../state/auth.dart';
import '../../state/data.dart';
import '../../widgets/common.dart';
import '../../widgets/dashboard_widget_card.dart';

/// The widgets of one folder's dashboard, stacked for a phone screen (the web
/// grid's order: top-to-bottom, then left-to-right). Shared by Home and the
/// Dashboards viewer. Long-press a widget to remove it (edit roles only).
class DashboardBody extends ConsumerWidget {
  const DashboardBody({super.key, required this.folderId, this.emptyMessage});

  final int folderId;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dash = ref.watch(folderDashboardProvider(folderId));
    final groups = ref.watch(groupsProvider).value ?? const [];
    final canEdit = can(ref.watch(roleProvider), Perm.dashboardsEdit);

    Future<void> refresh() async {
      ref.invalidate(folderDashboardProvider(folderId));
      await ref.read(folderDashboardProvider(folderId).future);
    }

    Future<void> remove(DashboardData d, DashboardWidget w) async {
      if (!canEdit) return;
      final ok = await confirmDialog(context,
          title: 'Remove widget?', message: '"${w.title}" will be removed from this dashboard.', confirm: 'Remove', danger: true);
      if (!ok || !context.mounted) return;
      try {
        await ref.read(dashboardsApiProvider).removeWidget(d.id, w.id);
        if (context.mounted) showToast(context, 'Widget removed');
        await refresh();
      } catch (e) {
        if (context.mounted) showToast(context, '$e', error: true);
      }
    }

    return AsyncBody<DashboardData?>(
      value: dash,
      onRetry: () => ref.invalidate(folderDashboardProvider(folderId)),
      data: (d) {
        if (d == null || d.widgets.isEmpty) {
          return RefreshIndicator(
            onRefresh: refresh,
            child: ListView(children: [
              const SizedBox(height: 120),
              EmptyState(message: emptyMessage ?? 'No widgets on this dashboard yet. Add them from the web dashboard builder.'),
            ]),
          );
        }
        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: d.widgets.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, i) => DashboardWidgetCard(
              widget: d.widgets[i],
              groups: groups,
              onLongPress: canEdit ? () => remove(d, d.widgets[i]) : null,
            ),
          ),
        );
      },
    );
  }
}
