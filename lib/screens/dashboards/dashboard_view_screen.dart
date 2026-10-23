import 'package:flutter/material.dart';

import '../../widgets/app_shell.dart';
import 'dashboard_body.dart';

/// One folder's dashboard (the web DashboardBuilderPage, view mode).
class DashboardViewScreen extends StatelessWidget {
  const DashboardViewScreen({super.key, required this.folderId, this.name});
  final int folderId;
  final String? name;

  @override
  Widget build(BuildContext context) => AppShell(
        eyebrow: 'Dashboard',
        title: name ?? 'Dashboard',
        showDrawer: false,
        body: DashboardBody(folderId: folderId),
      );
}
