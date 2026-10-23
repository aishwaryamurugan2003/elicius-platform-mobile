import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/api/api_service.dart';
import 'core/theme/app_theme.dart';
import 'router.dart';
import 'state/auth.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Restore a "keep me signed in" session before the first frame, so the
  // router knows whether to start at Login or Home.
  final session = SessionStore();
  await session.restore();
  runApp(ProviderScope(
    overrides: [sessionStoreProvider.overrideWithValue(session)],
    child: const EliciusApp(),
  ));
}

class EliciusApp extends ConsumerWidget {
  const EliciusApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Elicius IoT Platform',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
