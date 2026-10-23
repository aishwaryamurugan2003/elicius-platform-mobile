import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dashboards_api.dart';
import '../api/telemetry_api.dart';
import 'auth.dart';

final telemetryApiProvider = Provider((ref) => TelemetryApi(ref.watch(apiServiceProvider)));
final dashboardsApiProvider = Provider((ref) => DashboardsApi(ref.watch(apiServiceProvider)));

/// Groups the signed-in user can access (`/mappings/user`).
final groupsProvider = FutureProvider<List<UserGroup>>((ref) async {
  ref.watch(authProvider.select((a) => a.user?.userId));
  return ref.watch(telemetryApiProvider).myGroups();
});

/// Which group a device belongs to (first match), for opening the right live stream.
String? groupOfDevices(List<UserGroup> groups, List<String> deviceIds) {
  for (final g in groups) {
    if (deviceIds.any(g.devices.contains)) return g.id;
  }
  return null;
}

/// Live state of one group: latest packet + a rolling history per device,
/// and whether the socket is connected. Seeded from last-packet, then fed by
/// the WebSocket; the socket closes when no screen watches this group.
class LiveGroupState {
  const LiveGroupState({this.connected = false, this.latest = const {}, this.history = const {}, this.packetCounts = const {}});

  final bool connected;
  final Map<String, TelemetryPoint> latest;
  final Map<String, List<TelemetryPoint>> history;
  final Map<String, int> packetCounts;

  LiveGroupState copyWith({
    bool? connected,
    Map<String, TelemetryPoint>? latest,
    Map<String, List<TelemetryPoint>>? history,
    Map<String, int>? packetCounts,
  }) =>
      LiveGroupState(
        connected: connected ?? this.connected,
        latest: latest ?? this.latest,
        history: history ?? this.history,
        packetCounts: packetCounts ?? this.packetCounts,
      );
}

const _maxLivePoints = 240;

class LiveGroupNotifier extends Notifier<LiveGroupState> {
  LiveGroupNotifier(this.groupId);
  final String groupId;

  @override
  LiveGroupState build() {
    final api = ref.watch(apiServiceProvider);
    final stream = LiveGroupStream(
      api,
      groupId,
      onStatus: (c) => state = state.copyWith(connected: c),
      onMessage: (m) => _add(m.deviceId, TelemetryPoint(m.time, m.data), counted: true),
    );
    ref.onDispose(stream.close);
    ref.read(telemetryApiProvider).lastPackets(groupId).then((packets) {
      for (final p in packets) {
        final id = '${p.data['dID']}';
        if (!state.latest.containsKey(id)) _add(id, p, counted: false);
      }
    }).catchError((_) {});
    return const LiveGroupState();
  }

  void _add(String deviceId, TelemetryPoint p, {required bool counted}) {
    final list = [...?state.history[deviceId], p];
    if (list.length > _maxLivePoints) list.removeRange(0, list.length - _maxLivePoints);
    final pid = p.data['pID'];
    state = state.copyWith(
      latest: {...state.latest, deviceId: p},
      history: {...state.history, deviceId: list},
      packetCounts: {
        ...state.packetCounts,
        deviceId: pid is num ? pid.toInt() : (state.packetCounts[deviceId] ?? 0) + (counted ? 1 : 0),
      },
    );
  }
}

final liveGroupProvider = NotifierProvider.autoDispose.family<LiveGroupNotifier, LiveGroupState, String>(LiveGroupNotifier.new);

/// Every folder the user owns (all groups).
final allFoldersProvider = FutureProvider.autoDispose<List<Folder>>((ref) async {
  final uid = ref.watch(authProvider.select((a) => a.user?.userId));
  if (uid == null) return const [];
  return ref.watch(dashboardsApiProvider).allFolders(uid);
});

final folderDashboardProvider = FutureProvider.autoDispose.family<DashboardData?, int>(
  (ref, folderId) => ref.watch(dashboardsApiProvider).folderDashboard(folderId),
);
