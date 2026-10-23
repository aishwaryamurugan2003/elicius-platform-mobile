import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/permissions.dart';
import 'screens/access/access_screen.dart';
import 'screens/alerts/alerts_screen.dart';
import 'screens/alerts/thresholds_screen.dart';
import 'screens/dashboards/dashboard_groups_screen.dart';
import 'screens/dashboards/dashboard_view_screen.dart';
import 'screens/dashboards/folders_screen.dart';
import 'screens/devices/device_parameters_screen.dart';
import 'screens/devices/devices_screen.dart';
import 'screens/downloader/downloader_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/live/live_groups_screen.dart';
import 'screens/live/live_status_screen.dart';
import 'screens/login_screen.dart';
import 'screens/plant_view/plant_view_screen.dart';
import 'screens/reports/reports_screen.dart';
import 'state/auth.dart';
import 'widgets/app_shell.dart';

/// Bridges auth changes into go_router's redirect (refreshListenable).
class _AuthListenable extends ChangeNotifier {
  void ping() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthListenable();
  ref.listen(authProvider, (_, _) => refresh.ping());
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final atLogin = state.matchedLocation == '/login';
      if (!auth.signedIn) return atLogin ? null : '/login';
      if (atLogin || state.matchedLocation == '/') return defaultRoute[auth.user!.role];
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/home'),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/live', builder: (_, _) => const LiveGroupsScreen()),
      GoRoute(path: '/live/:groupId', builder: (_, s) => LiveStatusScreen(groupId: s.pathParameters['groupId']!)),
      GoRoute(path: '/digital-twins', builder: (_, _) => const PlantViewScreen()),
      GoRoute(path: '/dashboards', builder: (_, _) => const DashboardGroupsScreen()),
      GoRoute(
        path: '/dashboards/group/:groupId',
        builder: (_, s) => FoldersScreen(groupId: s.pathParameters['groupId']!),
      ),
      GoRoute(
        path: '/dashboards/folder/:folderId',
        builder: (_, s) => DashboardViewScreen(
          folderId: int.parse(s.pathParameters['folderId']!),
          name: s.uri.queryParameters['name'],
        ),
      ),
      GoRoute(path: '/alerts', builder: (_, _) => const AlertsScreen()),
      GoRoute(path: '/downloader', builder: (_, _) => const DownloaderScreen()),
      GoRoute(path: '/reports', builder: (_, _) => const ReportsScreen()),
      // platform_admin-only pages — guarded below as well as hidden from the drawer.
      GoRoute(path: '/devices', builder: (_, _) => const _Guard('/devices', DevicesScreen())),
      GoRoute(
        path: '/device-types/:id/parameters',
        builder: (_, s) => _Guard(
          '/device-types',
          DeviceParametersScreen(deviceTypeId: int.parse(s.pathParameters['id']!), name: s.uri.queryParameters['name']),
        ),
      ),
      GoRoute(path: '/access', builder: (_, _) => const _Guard('/access', AccessScreen())),
      GoRoute(path: '/thresholds', builder: (_, _) => const _Guard('/thresholds', ThresholdsScreen())),
    ],
    errorBuilder: (_, _) => const _NotFound(),
  );
});

/// The web app's RequireAccess: hiding a drawer entry doesn't stop a deep
/// link, so restricted pages render "Restricted access" for other roles.
class _Guard extends ConsumerWidget {
  const _Guard(this.path, this.child);
  final String path;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(roleProvider);
    if (canAccessPage(role, path)) return child;
    return AppShell(
      title: 'Restricted access',
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lock_outline, size: 40),
            const SizedBox(height: 12),
            Text("Your role (${roleLabels[role]}) can't open this page.", textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => context.go(defaultRoute[role]!), child: const Text('Back to your dashboard')),
          ]),
        ),
      ),
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) => AppShell(
        title: 'Page not found',
        body: Center(child: FilledButton(onPressed: () => context.go('/home'), child: const Text('Go home'))),
      );
}
