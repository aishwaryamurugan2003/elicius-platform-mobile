import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_service.dart';
import '../core/api/endpoints.dart';
import '../core/permissions.dart';

/// Shared singletons. `sessionStore` is overridden in main() with the
/// already-restored instance so the first frame knows whether we're signed in.
final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());
final apiServiceProvider = Provider<ApiService>((ref) => ApiService(ref.watch(sessionStoreProvider)));

class AuthUser {
  const AuthUser({
    required this.name,
    required this.email,
    required this.role,
    required this.userId,
    this.organisationName = 'UK Pact Project',
    this.orgId,
  });

  final String name;
  final String email;
  final Role role;
  final String? userId;
  final String organisationName;
  final int? orgId;

  AuthUser copyWith({String? organisationName, int? orgId}) => AuthUser(
        name: name,
        email: email,
        role: role,
        userId: userId,
        organisationName: organisationName ?? this.organisationName,
        orgId: orgId ?? this.orgId,
      );

  String get initials {
    final parts = name.split(' ').map((p) => p.replaceAll(RegExp('[^A-Za-z]'), '')).where((p) => p.isNotEmpty).take(2);
    return parts.map((p) => p[0].toUpperCase()).join();
  }

  /// Built from the access token's claims (decoded, not verified — display only).
  static AuthUser? fromToken(String? token, {String fallback = ''}) {
    if (token == null) return null;
    final c = decodeJwt(token);
    if (c == null) return null;
    final roles = (c['realm_access'] as Map?)?['roles'];
    return AuthUser(
      name: (c['name'] ?? c['preferred_username'] ?? fallback) as String,
      email: (c['email'] ?? fallback) as String,
      role: resolveRole(roles is List ? roles.whereType<String>().toList() : null),
      userId: c['sub'] as String?,
    );
  }
}

class AuthState {
  const AuthState({this.user, this.loading = false, this.error});

  final AuthUser? user;
  final bool loading;
  final String? error;

  bool get signedIn => user != null;
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    final api = ref.watch(apiServiceProvider);
    // A 401 anywhere clears the session; reflect that here so the router redirects to Login.
    api.onUnauthorized = () => state = const AuthState();
    final user = AuthUser.fromToken(api.session.accessToken);
    if (user != null) Future.microtask(_loadOrganisation);
    return AuthState(user: user);
  }

  Future<void> login(String username, String password, {required bool keepSignedIn}) async {
    state = const AuthState(loading: true);
    final api = ref.read(apiServiceProvider);
    try {
      final tokens = await api.login(username, password);
      await api.session.save(tokens, persist: keepSignedIn);
      state = AuthState(user: AuthUser.fromToken(tokens.accessToken, fallback: username));
      await _loadOrganisation();
    } on ApiError catch (e) {
      state = AuthState(error: e.status == 401 ? 'Incorrect username or password.' : e.message);
    } catch (_) {
      state = const AuthState(error: 'Sign in failed. Please try again.');
    }
  }

  Future<void> logout() async {
    await ref.read(apiServiceProvider).session.clear();
    state = const AuthState();
  }

  /// `GET /organizations/me` — a failure keeps the placeholder name rather than blanking it.
  Future<void> _loadOrganisation() async {
    try {
      final org = await ref.read(apiServiceProvider).get<Map<String, dynamic>>(Endpoint.myOrganization);
      final u = state.user;
      if (u == null) return;
      state = AuthState(user: u.copyWith(organisationName: org['org_name'] as String?, orgId: org['org_id'] as int?));
    } catch (_) {}
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

/// The signed-in user's role (most restrictive if somehow signed out).
final roleProvider = Provider<Role>((ref) => ref.watch(authProvider).user?.role ?? Role.orgViewer);
