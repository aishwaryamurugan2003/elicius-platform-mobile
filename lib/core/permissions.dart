/// Roles and access rules — a port of the web app's `src/lib/permissions.ts`.
/// Add a rule here, never inline in a screen.
library;

enum Role { platformAdmin, orgAdmin, orgEditor, orgViewer }

const roleLabels = {
  Role.platformAdmin: 'Platform admin',
  Role.orgAdmin: 'Organisation admin',
  Role.orgEditor: 'Organisation editor',
  Role.orgViewer: 'Organisation viewer',
};

/// Highest-privilege match wins; unknown/missing falls back to the most
/// restrictive role (never fail open).
Role resolveRole(List<String>? raw) {
  bool has(String r) => raw?.contains(r) ?? false;
  if (has('platform_admin')) return Role.platformAdmin;
  if (has('org_admin')) return Role.orgAdmin;
  if (has('org_editor')) return Role.orgEditor;
  return Role.orgViewer;
}

/// Pages restricted to some roles; any path not listed is open to everyone.
final List<({bool Function(String) test, List<Role> roles})> _pageRules = [
  (test: (p) => p.startsWith('/devices') || p.startsWith('/device-types'), roles: [Role.platformAdmin]),
  (test: (p) => p.startsWith('/access'), roles: [Role.platformAdmin]),
  (test: (p) => p.startsWith('/thresholds'), roles: [Role.platformAdmin]),
];

bool canAccessPage(Role role, String path) {
  for (final r in _pageRules) {
    if (r.test(path)) return r.roles.contains(role);
  }
  return true;
}

const defaultRoute = {
  Role.platformAdmin: '/home',
  Role.orgAdmin: '/home',
  Role.orgEditor: '/home',
  Role.orgViewer: '/dashboards',
};

enum Perm {
  devicesRegister,
  devicesManageGroups,
  devicesManageServers,
  devicesManageTypes,
  alertsManageThresholds,
  accessManageMembers,
  accessAssignDeviceAccess,
  dashboardsCreate,
  dashboardsEdit,
  dashboardsDelete,
  digitalTwinsEdit,
  reportsDelete,
}

const _dashboardEditRoles = [Role.platformAdmin, Role.orgAdmin, Role.orgEditor];

const Map<Perm, List<Role>> actionAccess = {
  Perm.devicesRegister: [Role.platformAdmin],
  Perm.devicesManageGroups: [Role.platformAdmin],
  Perm.devicesManageServers: [Role.platformAdmin],
  Perm.devicesManageTypes: [Role.platformAdmin],
  Perm.alertsManageThresholds: [Role.platformAdmin],
  Perm.accessManageMembers: [Role.platformAdmin, Role.orgAdmin],
  Perm.accessAssignDeviceAccess: [Role.platformAdmin, Role.orgAdmin],
  Perm.dashboardsCreate: _dashboardEditRoles,
  Perm.dashboardsEdit: _dashboardEditRoles,
  Perm.dashboardsDelete: _dashboardEditRoles,
  Perm.digitalTwinsEdit: _dashboardEditRoles,
  Perm.reportsDelete: [Role.platformAdmin],
};

bool can(Role role, Perm action) => actionAccess[action]!.contains(role);
