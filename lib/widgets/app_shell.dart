import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/permissions.dart';
import '../core/theme/app_theme.dart';
import '../state/auth.dart';

/// Sidebar entries — same order and labels as the web `Sidebar.tsx`.
class NavItem {
  const NavItem(this.path, this.label, this.icon);
  final String path;
  final String label;
  final IconData icon;
}

const navItems = [
  NavItem('/home', 'Home', Icons.dashboard_outlined),
  NavItem('/devices', 'Device Administration', Icons.memory_outlined),
  NavItem('/live', 'Live status', Icons.monitor_heart_outlined),
  NavItem('/digital-twins', 'Plant View', Icons.photo_library_outlined),
  NavItem('/dashboards', 'Dashboards', Icons.grid_view_outlined),
  NavItem('/alerts', 'Device alerts', Icons.notifications_active_outlined),
  NavItem('/downloader', 'Data downloader', Icons.download_outlined),
  NavItem('/reports', 'AI reports', Icons.description_outlined),
  NavItem('/access', 'Access management', Icons.people_outline),
];

/// The chrome every screen except Login shares: an app bar with an eyebrow +
/// title, and the navigation drawer (the web sidebar). [bottom] sits under the
/// app bar (filters, tabs).
class AppShell extends ConsumerWidget {
  const AppShell({
    super.key,
    required this.title,
    required this.body,
    this.eyebrow,
    this.actions = const [],
    this.floatingActionButton,
    this.bottom,
    this.showDrawer = true,
  });

  final String title;
  final String? eyebrow;
  final Widget body;
  final List<Widget> actions;
  final Widget? floatingActionButton;
  final PreferredSizeWidget? bottom;
  final bool showDrawer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: eyebrow == null ? 56 : 64,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (eyebrow != null) Text(eyebrow!.toUpperCase(), style: AppTheme.eyebrow()),
            Text(title, overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: actions,
        bottom: bottom,
      ),
      drawer: showDrawer ? const AppDrawer() : null,
      floatingActionButton: floatingActionButton,
      body: body,
    );
  }
}

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final role = ref.watch(roleProvider);
    final current = GoRouterState.of(context).uri.path;
    final items = navItems.where((i) => canAccessPage(role, i.path));

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Image.asset('assets/logo.png', height: 72, fit: BoxFit.contain, alignment: Alignment.centerLeft),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Text('IOT PLATFORM', style: AppTheme.eyebrow().copyWith(color: AppColors.navy300)),
            ),
            const Divider(color: Color(0x22FFFFFF)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final i in items)
                    _NavTile(item: i, selected: current == i.path || current.startsWith('${i.path}/')),
                ],
              ),
            ),
            const Divider(color: Color(0x22FFFFFF)),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
              child: Text('ORGANISATION', style: AppTheme.eyebrow().copyWith(color: AppColors.navy300)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Text(user?.organisationName ?? '',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
            const Divider(color: Color(0x22FFFFFF)),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.navy700,
                child: Text(user?.initials ?? '', style: const TextStyle(color: Colors.white, fontSize: 13)),
              ),
              title: Text(user?.name ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              subtitle: Text(roleLabels[role] ?? '', style: const TextStyle(color: AppColors.navy300, fontSize: 12)),
              trailing: IconButton(
                tooltip: 'Sign out',
                icon: const Icon(Icons.logout, color: AppColors.navy300),
                onPressed: () => ref.read(authProvider.notifier).logout(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.item, required this.selected});
  final NavItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : AppColors.navy200;
    return Container(
      decoration: BoxDecoration(
        color: selected ? const Color(0x1AFFFFFF) : null,
        border: Border(left: BorderSide(color: selected ? AppColors.teal600 : Colors.transparent, width: 3)),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(item.icon, color: color, size: 20),
        title: Text(item.label,
            style: TextStyle(color: color, fontWeight: selected ? FontWeight.w700 : FontWeight.w400, fontSize: 14)),
        onTap: () {
          Navigator.of(context).pop();
          context.go(item.path);
        },
      ),
    );
  }
}
