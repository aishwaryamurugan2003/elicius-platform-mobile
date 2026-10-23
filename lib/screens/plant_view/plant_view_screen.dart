import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/plant_view_api.dart';
import '../../api/telemetry_api.dart';
import '../../core/fields.dart';
import '../../core/permissions.dart';
import '../../core/theme/app_theme.dart';
import '../../state/auth.dart';
import '../../state/data.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

final plantViewApiProvider = Provider((ref) => PlantViewApi(ref.watch(apiServiceProvider)));
final _viewsProvider = FutureProvider.autoDispose<List<PlantView>>((ref) async {
  final uid = ref.watch(authProvider.select((a) => a.user?.userId));
  if (uid == null) return const [];
  return ref.watch(plantViewApiProvider).list(uid);
});

const _shapeColor = Color(0xFFE1E4EA);
const _shapeSizes = {'square': (80.0, 80.0), 'rectangle': (140.0, 80.0)};

/// Plant View — a base image of the site with live readings pinned on it
/// (the web DigitalTwinsPage, shown to users as "Plant View").
class PlantViewScreen extends ConsumerStatefulWidget {
  const PlantViewScreen({super.key});

  @override
  ConsumerState<PlantViewScreen> createState() => _PlantViewScreenState();
}

class _PlantViewScreenState extends ConsumerState<PlantViewScreen> {
  int? _selectedId;
  PlantView? _draft; // non-null while editing
  bool _saving = false;
  final _canvasKey = GlobalKey();

  String get _uid => ref.read(authProvider).user?.userId ?? '';

  void _startEditing(PlantView? v, int count) {
    setState(() => _draft = v?.copy() ?? PlantView(name: 'Plant View ${count + 1}'));
  }

  Future<void> _save() async {
    final d = _draft;
    if (d == null || d.name.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final saved = await ref.read(plantViewApiProvider).save(_uid, d);
      ref.invalidate(_viewsProvider);
      setState(() {
        _selectedId = saved.id;
        _draft = null;
      });
      if (mounted) showToast(context, '"${saved.name}" saved');
    } catch (e) {
      if (mounted) showToast(context, "Couldn't save — $e", error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final d = _draft;
    if (d?.id == null) return;
    final ok = await confirmDialog(context,
        title: 'Delete plant view?', message: '"${d!.name}" and all its markers will be deleted. This can\'t be undone.', confirm: 'Delete', danger: true);
    if (!ok) return;
    try {
      await ref.read(plantViewApiProvider).delete(_uid, d.id!);
      ref.invalidate(_viewsProvider);
      setState(() {
        _draft = null;
        _selectedId = null;
      });
      if (mounted) showToast(context, 'Plant view deleted');
    } catch (e) {
      if (mounted) showToast(context, '$e', error: true);
    }
  }

  Future<void> _pickImage() async {
    final d = _draft;
    if (d == null) return;
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
    if (file == null) return;
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final img = (await codec.getNextFrame()).image;
      final url = await ref.read(plantViewApiProvider).uploadImage(_uid, bytes);
      // Fit inside the canvas, centred, keeping the image's aspect ratio.
      final k = [d.width / img.width, d.height / img.height].reduce((a, b) => a < b ? a : b);
      final fw = img.width * k / d.width, fh = img.height * k / d.height;
      setState(() => d.image = TwinImage(url: url, x: (1 - fw) / 2, y: (1 - fh) / 2, width: fw, height: fh));
    } catch (e) {
      if (mounted) showToast(context, "Couldn't add the image — $e", error: true);
    }
  }

  void _addShape(String type) {
    final d = _draft!;
    final (pw, ph) = _shapeSizes[type]!;
    final w = (pw / d.width).clamp(0.0, 1.0), h = (ph / d.height).clamp(0.0, 1.0);
    setState(() => d.shapes.add(TwinShape(id: 's-${DateTime.now().millisecondsSinceEpoch}', type: type, x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)));
  }

  Future<void> _addMarkerAt(double x, double y) async {
    final groups = ref.read(groupsProvider).value ?? const <UserGroup>[];
    final picked = await showModalBottomSheet<(String, String, String)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddMarkerSheet(groups: groups),
    );
    if (picked == null) return;
    final (groupId, deviceId, field) = picked;
    setState(() => _draft!.markers.add(TwinMarker(
        id: 'm-${DateTime.now().millisecondsSinceEpoch}', deviceId: deviceId, groupId: groupId, field: field, x: x, y: y)));
  }

  Future<void> _canvasSize() async {
    final d = _draft!;
    var w = d.width.toDouble(), h = d.height.toDouble();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Canvas size'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Width ${w.round()} px'),
            Slider(value: w, min: 300, max: 1600, onChanged: (v) => set(() => w = v)),
            Text('Height ${h.round()} px'),
            Slider(value: h, min: 200, max: 1000, onChanged: (v) => set(() => h = v)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Apply')),
          ],
        ),
      ),
    );
    if (ok == true) setState(() => d..width = w.round()..height = h.round());
  }

  Future<void> _exportPng(String name) async {
    try {
      final boundary = _canvasKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      await SharePlus.instance.share(ShareParams(files: [XFile.fromData(png, name: '$name.png', mimeType: 'image/png')], fileNameOverrides: ['$name.png']));
    } catch (e) {
      if (mounted) showToast(context, 'Export failed — $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final views = ref.watch(_viewsProvider);
    final canEdit = can(ref.watch(roleProvider), Perm.digitalTwinsEdit);
    final list = views.value ?? const <PlantView>[];
    final selected = list.where((v) => v.id == _selectedId).firstOrNull ?? list.firstOrNull;
    final shown = _draft ?? selected;
    final editing = _draft != null;
    final onDevice = ref.read(plantViewApiProvider).onDevice;

    return AppShell(
      eyebrow: editing ? 'Plant view editor' : 'Plant view',
      title: shown?.name ?? 'Plant view',
      actions: [
        if (!editing && shown != null)
          IconButton(tooltip: 'Export PNG', icon: const Icon(Icons.ios_share), onPressed: () => _exportPng(shown.name)),
        if (canEdit && !editing)
          IconButton(tooltip: 'Start editing', icon: const Icon(Icons.edit_outlined), onPressed: () => _startEditing(selected, list.length)),
        if (editing) IconButton(tooltip: 'Stop editing', icon: const Icon(Icons.close), onPressed: () => setState(() => _draft = null)),
      ],
      body: AsyncBody<List<PlantView>>(
        value: views,
        onRetry: () => ref.invalidate(_viewsProvider),
        data: (_) => ListView(padding: const EdgeInsets.all(12), children: [
          if (onDevice)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 10),
              color: AppColors.amber100,
              child: const Text('This server has no plant-view storage yet, so plant views are saved on this phone only.',
                  style: TextStyle(color: AppColors.amber600, fontSize: 12)),
            ),
          if (!editing)
            DropdownButtonFormField<int>(
              initialValue: selected?.id,
              decoration: const InputDecoration(labelText: 'Plant views'),
              hint: const Text('No plant views yet'),
              items: [for (final v in list) DropdownMenuItem(value: v.id, child: Text(v.name))],
              onChanged: (v) => setState(() => _selectedId = v),
            )
          else ...[
            TextFormField(
              initialValue: _draft!.name,
              decoration: const InputDecoration(labelText: 'Plant view name'),
              onChanged: (v) => _draft!.name = v,
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton.icon(onPressed: _pickImage, icon: const Icon(Icons.add_photo_alternate_outlined), label: Text(_draft!.image == null ? 'Base image' : 'Replace image')),
              if (_draft!.image != null)
                OutlinedButton.icon(onPressed: () => setState(() => _draft!.image = null), icon: const Icon(Icons.hide_image_outlined), label: const Text('Remove image')),
              OutlinedButton.icon(onPressed: () => _addShape('square'), icon: const Icon(Icons.crop_square), label: const Text('Square')),
              OutlinedButton.icon(onPressed: () => _addShape('rectangle'), icon: const Icon(Icons.crop_16_9), label: const Text('Rectangle')),
              OutlinedButton.icon(onPressed: _canvasSize, icon: const Icon(Icons.aspect_ratio), label: Text('${_draft!.width} × ${_draft!.height}')),
            ]),
            const SizedBox(height: 8),
            const Text('Tap the canvas to add a marker. Drag markers, shapes or the image to move them; drag a corner handle to resize. '
                'Tap a marker or shape to edit or delete it.', style: TextStyle(fontSize: 12, color: AppColors.grey500)),
          ],
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: shown == null
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text('No plant views yet${canEdit ? ' — tap the pencil to create one.' : '.'}', textAlign: TextAlign.center),
                    )
                  : RepaintBoundary(
                      key: _canvasKey,
                      child: _PlantCanvas(view: shown, editing: editing, onChanged: () => setState(() {}), onTapEmpty: _addMarkerAt),
                    ),
            ),
          ),
          if (editing) ...[
            const SizedBox(height: 12),
            Row(children: [
              if (_draft!.id != null)
                TextButton.icon(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline, color: AppColors.red600),
                  label: const Text('Delete', style: TextStyle(color: AppColors.red600)),
                ),
              const Spacer(),
              FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save_outlined), label: Text(_saving ? 'Saving…' : 'Save')),
            ]),
          ],
        ]),
      ),
    );
  }
}

/// The canvas, scaled to the screen width. Positions are canvas fractions.
class _PlantCanvas extends ConsumerWidget {
  const _PlantCanvas({required this.view, required this.editing, required this.onChanged, required this.onTapEmpty});
  final PlantView view;
  final bool editing;
  final VoidCallback onChanged;
  final void Function(double x, double y) onTapEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupIds = {for (final m in view.markers) m.groupId};
    final live = {for (final g in groupIds) g: ref.watch(liveGroupProvider(g))};

    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth, h = w * view.height / view.width;
      double clamp01(double v) => v.clamp(0.0, 1.0);

      Widget handle(void Function(Offset d) onDrag) => Positioned(
            right: -8,
            bottom: -8,
            child: GestureDetector(
              onPanUpdate: (d) => onDrag(d.delta),
              child: Container(width: 18, height: 18, decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.navy500))),
            ),
          );

      final img = view.image;
      return SizedBox(
        width: w,
        height: h,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: editing ? (d) => onTapEmpty(clamp01(d.localPosition.dx / w), clamp01(d.localPosition.dy / h)) : null,
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              decoration: BoxDecoration(color: Colors.white, border: editing ? Border.all(color: AppColors.navy300) : null),
            ),
            if (img != null)
              Positioned(
                left: img.x * w,
                top: img.y * h,
                width: img.width * w,
                height: img.height * h,
                child: GestureDetector(
                  onPanUpdate: editing
                      ? (d) {
                          img.x = (img.x + d.delta.dx / w).clamp(0.0, 1 - img.width);
                          img.y = (img.y + d.delta.dy / h).clamp(0.0, 1 - img.height);
                          onChanged();
                        }
                      : null,
                  child: Stack(clipBehavior: Clip.none, fit: StackFit.expand, children: [
                    _TwinImageView(url: img.url),
                    if (editing)
                      handle((d) {
                        img.width = (img.width + d.dx / w).clamp(0.05, 1 - img.x);
                        img.height = (img.height + d.dy / h).clamp(0.05, 1 - img.y);
                        onChanged();
                      }),
                  ]),
                ),
              ),
            for (final s in view.shapes)
              Positioned(
                left: s.x * w,
                top: s.y * h,
                width: s.width * w,
                height: s.height * h,
                child: GestureDetector(
                  onTap: editing ? () => _editShape(context, s) : null,
                  onPanUpdate: editing
                      ? (d) {
                          s.x = (s.x + d.delta.dx / w).clamp(0.0, 1 - s.width);
                          s.y = (s.y + d.delta.dy / h).clamp(0.0, 1 - s.height);
                          onChanged();
                        }
                      : null,
                  child: Stack(clipBehavior: Clip.none, fit: StackFit.expand, children: [
                    Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: _shapeColor, border: Border.all(color: Colors.black12, width: 2)),
                      child: Text(s.label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                    if (editing)
                      handle((d) {
                        s.width = (s.width + d.dx / w).clamp(0.02, 1 - s.x);
                        s.height = (s.height + d.dy / h).clamp(0.02, 1 - s.y);
                        onChanged();
                      }),
                  ]),
                ),
              ),
            Positioned(
              top: 6,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)]),
                  child: Text(view.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
            for (final m in view.markers)
              Positioned(
                left: m.x * w - 40,
                top: m.y * h - 76,
                width: 80,
                height: 76,
                child: GestureDetector(
                  onTap: editing
                      ? () async {
                          final ok = await confirmDialog(context,
                              title: 'Marker', message: '${fieldLabel(m.field)} on ${m.deviceId}', confirm: 'Delete marker', danger: true);
                          if (ok) {
                            view.markers.remove(m);
                            onChanged();
                          }
                        }
                      : null,
                  onPanUpdate: editing
                      ? (d) {
                          m.x = clamp01(m.x + d.delta.dx / w);
                          m.y = clamp01(m.y + d.delta.dy / h);
                          onChanged();
                        }
                      : null,
                  child: _Pin(marker: m, value: live[m.groupId]?.latest[m.deviceId]?.data[m.field]),
                ),
              ),
          ]),
        ),
      );
    });
  }

  Future<void> _editShape(BuildContext context, TwinShape s) async {
    final c = TextEditingController(text: s.label);
    final r = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(s.type == 'square' ? 'Square' : 'Rectangle'),
        content: TextField(controller: c, maxLength: 60, decoration: const InputDecoration(labelText: 'Label', hintText: 'e.g. Boiler room')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, '__delete__'), child: const Text('Delete', style: TextStyle(color: AppColors.red600))),
          FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('Done')),
        ],
      ),
    );
    if (r == null) return;
    if (r == '__delete__') {
      view.shapes.remove(s);
    } else {
      s.label = r;
    }
    onChanged();
  }
}

/// Network URL or a data: URL (plant views saved on the phone).
class _TwinImageView extends StatelessWidget {
  const _TwinImageView({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.startsWith('data:')) {
      return Image.memory(base64Decode(url.substring(url.indexOf(',') + 1)), fit: BoxFit.fill, gaplessPlayback: true);
    }
    return Image.network(url, fit: BoxFit.fill, errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.grey100));
  }
}

/// Teardrop marker: device + parameter tag above, value + unit inside.
class _Pin extends StatelessWidget {
  const _Pin({required this.marker, required this.value});
  final TwinMarker marker;
  final Object? value;

  @override
  Widget build(BuildContext context) {
    final v = formatValue(value);
    final has = v != '—';
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(color: AppColors.navy700, borderRadius: BorderRadius.circular(4)),
        child: Column(children: [
          Text(marker.deviceId, style: const TextStyle(color: Colors.white70, fontSize: 7, fontFamily: 'monospace')),
          Text(fieldLabel(marker.field), style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w600)),
        ]),
      ),
      const SizedBox(height: 2),
      Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: has ? AppColors.navy700 : AppColors.grey400,
          shape: BoxShape.circle,
          border: Border.all(color: has ? AppColors.teal600 : Colors.white, width: 2),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(v, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: v.length > 5 ? 8 : 10)),
          if (fieldUnit(marker.field).isNotEmpty) Text(fieldUnit(marker.field), style: const TextStyle(color: Colors.white70, fontSize: 6)),
        ]),
      ),
      const Icon(Icons.arrow_drop_down, size: 14, color: AppColors.navy700),
    ]);
  }
}

/// Pick group → device → field (from the device's latest packet) for a new marker.
class _AddMarkerSheet extends ConsumerStatefulWidget {
  const _AddMarkerSheet({required this.groups});
  final List<UserGroup> groups;

  @override
  ConsumerState<_AddMarkerSheet> createState() => _AddMarkerSheetState();
}

class _AddMarkerSheetState extends ConsumerState<_AddMarkerSheet> {
  String? _group, _device, _field;

  @override
  Widget build(BuildContext context) {
    final live = _group == null ? null : ref.watch(liveGroupProvider(_group!));
    final group = widget.groups.where((g) => g.id == _group).firstOrNull;
    final packet = _device == null ? null : live?.latest[_device];
    final fields = packet == null
        ? <String>[]
        : (packet.data.entries.where((e) => !nonReadingKeys.contains(e.key) && asNumber(e.value) != null).map((e) => e.key).toList()
          ..sort((a, b) => fieldLabel(a).compareTo(fieldLabel(b))));
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Add marker', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _group,
          decoration: const InputDecoration(labelText: 'Group'),
          items: [for (final g in widget.groups) DropdownMenuItem(value: g.id, child: Text(g.name))],
          onChanged: (v) => setState(() {
            _group = v;
            _device = null;
            _field = null;
          }),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _device,
          decoration: const InputDecoration(labelText: 'Device'),
          items: [for (final d in group?.devices ?? const <String>[]) DropdownMenuItem(value: d, child: Text(d))],
          onChanged: (v) => setState(() {
            _device = v;
            _field = null;
          }),
        ),
        const SizedBox(height: 10),
        if (_device != null && packet == null)
          const Text('Waiting for this device\'s latest packet to list its fields…', style: TextStyle(fontSize: 12, color: AppColors.grey500))
        else
          DropdownButtonFormField<String>(
            initialValue: _field,
            decoration: const InputDecoration(labelText: 'Parameter'),
            items: [for (final f in fields) DropdownMenuItem(value: f, child: Text('${fieldLabel(f)} ($f)'))],
            onChanged: (v) => setState(() => _field = v),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _group != null && _device != null && _field != null ? () => Navigator.pop(context, (_group!, _device!, _field!)) : null,
          child: const Text('Add marker'),
        ),
      ]),
    );
  }
}
