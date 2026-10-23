import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'endpoints.dart';

/// An error that says how a request failed, with a message safe to show the
/// user. [status] is null when no response arrived (network down, DNS, timeout).
class ApiError implements Exception {
  ApiError(this.message, this.status);

  final String message;
  final int? status;

  @override
  String toString() => message;
}

/// Token pair from `POST /auth/login`.
class LoginTokens {
  LoginTokens({required this.accessToken, required this.refreshToken});

  factory LoginTokens.fromJson(Map<String, dynamic> j) =>
      LoginTokens(accessToken: j['access_token'] as String, refreshToken: (j['refresh_token'] as String?) ?? '');

  final String accessToken;
  final String refreshToken;
}

/// Decodes a JWT's payload without verifying it — display only; the backend
/// stays the source of truth for authorization.
Map<String, dynamic>? decodeJwt(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    final json = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    final v = jsonDecode(json);
    return v is Map<String, dynamic> ? v : null;
  } catch (_) {
    return null;
  }
}

/// Holds the access/refresh tokens. "Keep me signed in" writes them to the
/// device keystore so they survive an app restart; otherwise they live only
/// in memory for this run (the web app's sessionStorage equivalent).
class SessionStore {
  SessionStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  static const _accessKey = 'elicius_access_token';
  static const _refreshKey = 'elicius_refresh_token';

  final FlutterSecureStorage _storage;
  String? _access;
  String? _refresh;

  String? get accessToken => _access;

  /// Loads a persisted session (if any) at app start.
  Future<void> restore() async {
    _access = await _storage.read(key: _accessKey);
    _refresh = await _storage.read(key: _refreshKey);
  }

  Future<void> save(LoginTokens t, {required bool persist}) async {
    _access = t.accessToken;
    _refresh = t.refreshToken;
    if (persist) {
      await _storage.write(key: _accessKey, value: t.accessToken);
      await _storage.write(key: _refreshKey, value: t.refreshToken);
    } else {
      await _storage.delete(key: _accessKey);
      await _storage.delete(key: _refreshKey);
    }
  }

  Future<void> clear() async {
    _access = null;
    _refresh = null;
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }

  String? get refreshToken => _refresh;
}

/// The only place that knows how to make an HTTP request — a port of the web
/// app's `apiService`. Every call takes an [Endpoint]; the Bearer token is
/// attached automatically, and a 401 clears the session and fires
/// [onUnauthorized] (the router then sends the user to Login).
class ApiService {
  ApiService(this.session, {Dio? dio}) : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 20)));

  final SessionStore session;
  final Dio _dio;

  /// Set by the auth layer; called after a 401 has cleared the session.
  void Function()? onUnauthorized;

  /// `POST /auth/login` — CAAS takes the credentials as query params with an empty body.
  Future<LoginTokens> login(String username, String password) async {
    final res = await _send(() => _dio.post<dynamic>(
          Endpoint.login.url,
          data: '',
          queryParameters: {'username': username, 'password': password},
        ), auth: false);
    return LoginTokens.fromJson(res.data as Map<String, dynamic>);
  }

  Future<T> get<T>(Endpoint e, {Map<String, dynamic>? query, bool auth = true}) async =>
      (await _send(() => _dio.get<T>(e.url, queryParameters: query, options: _opts(auth)), auth: auth)).data as T;

  Future<T> post<T>(Endpoint e, Object? body, {Map<String, dynamic>? query}) async =>
      (await _send(() => _dio.post<T>(e.url, data: body, queryParameters: query, options: _opts(true)))).data as T;

  Future<T> put<T>(Endpoint e, Object? body, {Map<String, dynamic>? query}) async =>
      (await _send(() => _dio.put<T>(e.url, data: body, queryParameters: query, options: _opts(true)))).data as T;

  Future<T> patch<T>(Endpoint e, Object? body) async =>
      (await _send(() => _dio.patch<T>(e.url, data: body, options: _opts(true)))).data as T;

  Future<T?> delete<T>(Endpoint e, {Map<String, dynamic>? query}) async =>
      (await _send(() => _dio.delete<T>(e.url, queryParameters: query, options: _opts(true)))).data;

  /// Raw bytes (report PDFs, export ZIPs).
  Future<List<int>> getBytes(Endpoint e, {Map<String, dynamic>? query}) async {
    final res = await _send(() => _dio.get<List<int>>(
          e.url,
          queryParameters: query,
          options: _opts(true).copyWith(responseType: ResponseType.bytes),
        ));
    return res.data ?? const [];
  }

  /// Text (report HTML).
  Future<String> getText(Endpoint e) async {
    final res = await _send(() => _dio.get<String>(e.url, options: _opts(true).copyWith(responseType: ResponseType.plain)));
    return res.data ?? '';
  }

  /// `wss://…/stream/group/{id}?token=…` — WebSockets can't carry an Authorization header.
  String liveStreamUrl(String groupId) {
    final e = Endpoint.liveGroupStream.withParams({'group_id': groupId});
    return '${e.url}?token=${Uri.encodeComponent(session.accessToken ?? '')}';
  }

  Options _opts(bool auth) {
    final token = session.accessToken;
    return Options(headers: {if (auth && token != null) 'Authorization': 'Bearer $token'});
  }

  Future<Response<T>> _send<T>(Future<Response<T>> Function() call, {bool auth = true}) async {
    try {
      final res = await call();
      final type = res.headers.value('content-type') ?? '';
      if (type.contains('text/html') && res.requestOptions.responseType != ResponseType.plain) {
        throw ApiError("The server returned a web page instead of data — check this service's address.", res.statusCode);
      }
      return res;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (auth && status == 401) {
        await session.clear();
        onUnauthorized?.call();
      }
      throw _toApiError(e);
    }
  }

  static ApiError _toApiError(DioException e) {
    final res = e.response;
    if (res == null) return ApiError('Unable to reach the server. Check your connection and try again.', null);
    final status = res.statusCode;
    if (status == 502 || status == 504) return ApiError('The server took too long to respond (timeout).', status);
    final data = res.data;
    final detail = data is Map ? data['detail'] : null;
    if (detail is String) return ApiError(detail, status);
    if (detail is List && detail.isNotEmpty) {
      return ApiError(detail.map((d) => d is Map && d['msg'] != null ? '${d['msg']}' : '$d').join('; '), status);
    }
    return ApiError('Unable to complete the requested action.', status);
  }
}
