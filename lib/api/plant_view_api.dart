import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../core/api/api_service.dart';
import '../core/api/endpoints.dart';

/// Plant View (digital twins) — same model and wire format as the web app's
/// `digitalTwinsApi.ts`. Every position/size is a fraction (0..1) of the canvas.

class TwinImage {
  TwinImage({required this.url, required this.x, required this.y, required this.width, required this.height});
  String url;
  double x, y, width, height;
}

class TwinMarker {
  TwinMarker({required this.id, required this.deviceId, required this.groupId, required this.field, required this.x, required this.y});
  final String id, deviceId, groupId, field;
  double x, y;
}

class TwinShape {
  TwinShape({required this.id, required this.type, required this.x, required this.y, required this.width, required this.height, this.label = ''});
  final String id;
  final String type; // square | rectangle
  double x, y, width, height;
  String label;
}

class PlantView {
  PlantView({this.id, required this.name, this.width = 800, this.height = 600, this.image, List<TwinMarker>? markers, List<TwinShape>? shapes})
      : markers = markers ?? [],
        shapes = shapes ?? [];

  int? id;
  String name;
  int width, height;
  TwinImage? image;
  final List<TwinMarker> markers;
  final List<TwinShape> shapes;

  Map<String, dynamic> toWire(String userId) => {
        'user_id': userId,
        'name': name,
        'canvas_width': width,
        'canvas_height': height,
        'base_image_url': image?.url,
        'image_x': image?.x,
        'image_y': image?.y,
        'image_width': image?.width,
        'image_height': image?.height,
        'markers': [
          for (final m in markers)
            {'marker_id': m.id, 'device_id': m.deviceId, 'group_id': m.groupId, 'field': m.field, 'pos_x': m.x, 'pos_y': m.y},
        ],
        'shapes': [
          for (final s in shapes)
            {'shape_id': s.id, 'type': s.type, 'x': s.x, 'y': s.y, 'width': s.width, 'height': s.height, 'label': s.label},
        ],
      };

  static PlantView fromWire(Map<String, dynamic> w) {
    double d(Object? v) => (v as num?)?.toDouble() ?? 0;
    final hasImage = w['base_image_url'] != null && w['image_x'] != null;
    return PlantView(
      id: w['id'] as int?,
      name: '${w['name']}',
      width: (w['canvas_width'] as num?)?.toInt() ?? 800,
      height: (w['canvas_height'] as num?)?.toInt() ?? 600,
      image: hasImage
          ? TwinImage(url: '${w['base_image_url']}', x: d(w['image_x']), y: d(w['image_y']), width: d(w['image_width']), height: d(w['image_height']))
          : null,
      markers: [
        for (final m in (w['markers'] as List? ?? const []).cast<Map<String, dynamic>>())
          TwinMarker(id: '${m['marker_id']}', deviceId: '${m['device_id']}', groupId: '${m['group_id']}', field: '${m['field']}', x: d(m['pos_x']), y: d(m['pos_y'])),
      ],
      shapes: [
        for (final s in (w['shapes'] as List? ?? const []).cast<Map<String, dynamic>>())
          TwinShape(
              id: '${s['shape_id']}', type: '${s['type']}', x: d(s['x']), y: d(s['y']), width: d(s['width']), height: d(s['height']), label: '${s['label'] ?? ''}'),
      ],
    );
  }

  PlantView copy() => fromWire({...toWire(''), 'id': id});
}

/// Uses the backend's /v1/digital-twins routes when the server has them;
/// otherwise keeps plant views in a JSON file on this phone ([onDevice] = true).
class PlantViewApi {
  PlantViewApi(this._api);
  final ApiService _api;
  bool onDevice = false;

  Future<File> _file(String userId) async =>
      File('${(await getApplicationDocumentsDirectory()).path}/plant_views_${userId.replaceAll(RegExp('[^A-Za-z0-9-]'), '_')}.json');

  Future<List<PlantView>> _readLocal(String userId) async {
    final f = await _file(userId);
    if (!await f.exists()) return [];
    final list = jsonDecode(await f.readAsString()) as List;
    return [for (final w in list) PlantView.fromWire(w as Map<String, dynamic>)];
  }

  Future<void> _writeLocal(String userId, List<PlantView> views) async =>
      (await _file(userId)).writeAsString(jsonEncode([for (final v in views) {...v.toWire(userId), 'id': v.id}]));

  Future<List<PlantView>> list(String userId) async {
    try {
      final res = await _api.get<Map<String, dynamic>>(Endpoint.digitalTwins, query: {'user_id': userId});
      onDevice = false;
      return [for (final w in (res['data'] as List? ?? const [])) PlantView.fromWire(w as Map<String, dynamic>)];
    } on ApiError catch (e) {
      // 404/405 = this server doesn't have the plant-view routes yet.
      if (e.status != 404 && e.status != 405) rethrow;
      onDevice = true;
      return _readLocal(userId);
    }
  }

  Future<PlantView> save(String userId, PlantView v) async {
    if (onDevice) {
      final all = await _readLocal(userId);
      if (v.id == null) {
        v.id = all.fold<int>(0, (m, x) => (x.id ?? 0) > m ? x.id! : m) + 1;
        all.add(v);
      } else {
        final i = all.indexWhere((x) => x.id == v.id);
        i < 0 ? all.add(v) : all[i] = v;
      }
      await _writeLocal(userId, all);
      return v;
    }
    final res = v.id == null
        ? await _api.post<Map<String, dynamic>>(Endpoint.digitalTwins, v.toWire(userId))
        : await _api.put<Map<String, dynamic>>(Endpoint.digitalTwin.withParams({'twin_id': '${v.id}'}), v.toWire(userId));
    return PlantView.fromWire(res['data'] as Map<String, dynamic>);
  }

  Future<void> delete(String userId, int id) async {
    if (onDevice) {
      await _writeLocal(userId, (await _readLocal(userId)).where((v) => v.id != id).toList());
      return;
    }
    await _api.delete<dynamic>(Endpoint.digitalTwin.withParams({'twin_id': '$id'}), query: {'user_id': userId});
  }

  /// Stores a base image and returns its URL (a data: URL when saved on the phone).
  Future<String> uploadImage(String userId, List<int> jpeg) async {
    if (onDevice) return 'data:image/jpeg;base64,${base64Encode(jpeg)}';
    final form = FormData.fromMap({'file': MultipartFile.fromBytes(jpeg, filename: 'base-image.jpg')});
    final res = await _api.post<Map<String, dynamic>>(Endpoint.digitalTwinImages, form, query: {'user_id': userId});
    return '${(res['data'] as Map)['url']}';
  }
}
