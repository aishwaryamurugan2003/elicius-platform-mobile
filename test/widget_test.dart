import 'dart:convert';

import 'package:elicius_iot/api/dashboards_api.dart';
import 'package:elicius_iot/core/api/api_service.dart';
import 'package:elicius_iot/core/api/endpoints.dart';
import 'package:elicius_iot/core/fields.dart';
import 'package:elicius_iot/core/ist_time.dart';
import 'package:elicius_iot/core/permissions.dart';
import 'package:flutter_test/flutter_test.dart';

String _jwt(Map<String, dynamic> claims) {
  String seg(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${seg({'alg': 'none'})}.${seg(claims)}.sig';
}

void main() {
  group('permissions (same rules as the web app)', () {
    test('resolveRole picks the highest role and fails closed', () {
      expect(resolveRole(['org_editor', 'platform_admin']), Role.platformAdmin);
      expect(resolveRole(['something_else']), Role.orgViewer);
      expect(resolveRole(null), Role.orgViewer);
    });

    test('Devices / Access / Thresholds are platform_admin only; other pages are open', () {
      expect(canAccessPage(Role.platformAdmin, '/devices'), isTrue);
      expect(canAccessPage(Role.orgAdmin, '/devices'), isFalse);
      expect(canAccessPage(Role.orgAdmin, '/device-types/4/parameters'), isFalse);
      expect(canAccessPage(Role.orgEditor, '/access'), isFalse);
      expect(canAccessPage(Role.orgViewer, '/thresholds'), isFalse);
      expect(canAccessPage(Role.orgViewer, '/dashboards'), isTrue);
      expect(canAccessPage(Role.orgViewer, '/home'), isTrue);
    });

    test('dashboard writes: editor roles yes, viewer no', () {
      expect(can(Role.orgEditor, Perm.dashboardsEdit), isTrue);
      expect(can(Role.orgViewer, Perm.dashboardsEdit), isFalse);
      expect(can(Role.orgAdmin, Perm.reportsDelete), isFalse);
    });
  });

  test('decodeJwt reads the payload', () {
    final t = _jwt({'sub': 'u-1', 'name': 'Hemnath B', 'realm_access': {'roles': ['org_admin']}});
    expect(decodeJwt(t)?['sub'], 'u-1');
    expect(decodeJwt('not-a-jwt'), isNull);
  });

  test('Endpoint.withParams URL-encodes values', () {
    expect(Endpoint.deviceType.withParams({'id': 'a b'}).path, '/device-types/a%20b');
  });

  group('chartToWidget (port of chartConfigToWidget)', () {
    test('decodes type, mode, fields, range and interval from measurement', () {
      final w = chartToWidget({
        'chart_id': 'c1',
        'title': 'PM2.5',
        'chart_type': 'line',
        'measurement': 'bar~live~sPM2,sPM10~-6h~15m',
        'device_ids': ['SIN1', 'SIN2'],
        'y_axis': {'field': 'sPM2', 'label': 'PM2.5'},
        'layout_x': 4, 'layout_y': 0, 'layout_w': 4, 'layout_h': 3,
      }, null, 0);
      expect(w.type, 'bar');
      expect(w.isLive, isTrue);
      expect(w.fields, ['sPM2', 'sPM10']);
      expect(w.timeRange, '-6h');
      expect(w.interval, '15m');
      expect(w.deviceIds, ['SIN1', 'SIN2']);
      expect(w.layoutX, 4);
    });

    test('legacy KPI field list and corrupted duration fields', () {
      final kpi = chartToWidget({
        'chart_id': 'k',
        'title': 'KPI',
        'chart_type': 'kpi',
        'measurement': 'sPM2,sTemp',
        'device_ids': [],
        'y_axis': {'field': '5m', 'label': ''},
      }, null, 0);
      expect(kpi.type, 'kpi');
      expect(kpi.fields, ['sPM2', 'sTemp']);
      expect(kpi.deviceIds, isNull);

      final bad = chartToWidget({
        'chart_id': 'b',
        'title': 'x',
        'chart_type': 'line',
        'device_ids': [],
        'y_axis': {'field': '-1h', 'label': ''},
      }, null, 0);
      expect(bad.field, 'sPM2'); // a duration is never trusted as a field
    });
  });

  group('IST time', () {
    test('timezone-less ISO strings are UTC', () {
      final t = parseUtcTimestamp('2026-10-07T11:35:35')!;
      expect(formatIstDateTime(t), '7 Oct 2026, 17:05:35');
    });
    test('epoch seconds and milliseconds', () {
      expect(parseUtcTimestamp(1791447626), parseUtcTimestamp(1791447626000));
    });
  });

  test('formatValue: 2 decimals, whole numbers as-is, dash when missing', () {
    expect(formatValue(2.634), '2.63');
    expect(formatValue('400'), '400');
    expect(formatValue(null), '—');
    expect(fieldLabel('sPM2'), 'PM2.5');
  });
}
