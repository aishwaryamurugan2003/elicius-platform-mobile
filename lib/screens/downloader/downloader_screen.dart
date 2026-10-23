import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../api/telemetry_api.dart';
import '../../core/api/endpoints.dart';
import '../../core/ist_time.dart';
import '../../core/theme/app_theme.dart';
import '../../state/auth.dart';
import '../../state/data.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

/// Every export targets this database (the web page's DB picker is hidden too).
const _exportDb = 'coloc4';

/// UI interval -> backend processing/freq (same table as the web downloaderApi).
const _intervals = {
  'raw': ('raw', '30min'),
  '1 min': ('downsampled', '1min'),
  '15 min': ('downsampled', '15min'),
  '1 h': ('downsampled', '1h'),
  '1 d': ('downsampled', '1D'),
};

class _Job {
  _Job.fromJson(Map<String, dynamic> j)
      : id = '${j['job_id']}',
        name = (j['job_name'] ?? j['file_name'] ?? j['job_id']).toString(),
        fileName = j['file_name'] as String?,
        devices = '${j['cols'] ?? ''}',
        status = '${j['status']}',
        progress = (j['progress'] as num?)?.toInt() ?? 0,
        error = j['error'] as String?,
        submitted = parseUtcTimestamp(j['submitted_at']),
        start = parseUtcTimestamp(j['start_time']),
        end = parseUtcTimestamp(j['end_time']);

  final String id, name, devices, status;
  final String? fileName, error;
  final int progress;
  final DateTime? submitted, start, end;

  bool get active => status == 'queued' || status == 'running';
}

final _jobsProvider = FutureProvider.autoDispose<List<_Job>>((ref) async {
  final res = await ref.watch(apiServiceProvider).get<dynamic>(Endpoint.jobHistory, query: {'limit': 50, 'offset': 0});
  List list = const [];
  if (res is List) {
    list = res;
  } else if (res is Map) {
    for (final k in ['data', 'jobs', 'items', 'history']) {
      if (res[k] is List) {
        list = res[k] as List;
        break;
      }
    }
  }
  return [for (final j in list) _Job.fromJson(j as Map<String, dynamic>)];
});

/// Data downloader — export a group's telemetry for a time range (the web DataDownloaderPage).
class DownloaderScreen extends ConsumerStatefulWidget {
  const DownloaderScreen({super.key});

  @override
  ConsumerState<DownloaderScreen> createState() => _DownloaderScreenState();
}

class _DownloaderScreenState extends ConsumerState<DownloaderScreen> {
  String? _groupId;
  final Set<String> _devices = {};
  DateTime _from = DateTime.now().subtract(const Duration(days: 1));
  DateTime _to = DateTime.now();
  final _email = TextEditingController();
  final _jobName = TextEditingController();
  String _interval = '15 min';
  bool _submitting = false;
  String? _downloading;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _email.text = ref.read(authProvider).user?.email ?? '';
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      final jobs = ref.read(_jobsProvider).value ?? const [];
      if (jobs.any((j) => j.active)) ref.invalidate(_jobsProvider);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _email.dispose();
    _jobName.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool from) async {
    final initial = from ? _from : _to;
    final d = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(2020), lastDate: DateTime.now());
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    final v = DateTime(d.year, d.month, d.day, t?.hour ?? 0, t?.minute ?? 0);
    setState(() => from ? _from = v : _to = v);
  }

  List<String> get _missing => [
        if (_groupId == null) 'pick a group',
        if (_devices.isEmpty) 'pick at least one device',
        if (!_from.isBefore(_to)) 'make From earlier than To',
        if (!_email.text.contains('@')) 'enter an email',
      ];

  Future<void> _submit() async {
    if (_missing.isNotEmpty) return;
    setState(() => _submitting = true);
    final (processing, freq) = _intervals[_interval]!;
    try {
      await ref.read(apiServiceProvider).post<dynamic>(Endpoint.submitExport, {
        'st': '${_from.millisecondsSinceEpoch}',
        'et': '${_to.millisecondsSinceEpoch}',
        'cols': _devices.join(','),
        'db': _exportDb,
        'dt': '*',
        'email': _email.text.trim(),
        'processing': processing,
        'freq': freq,
        'job_name': _jobName.text.trim(),
      });
      if (mounted) showToast(context, 'Export submitted — it will also be emailed when ready.');
      ref.invalidate(_jobsProvider);
    } catch (e) {
      if (mounted) showToast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _download(_Job j) async {
    setState(() => _downloading = j.id);
    try {
      final bytes = await ref.read(apiServiceProvider).getBytes(Endpoint.downloadJob.withParams({'job_id': j.id}));
      final name = '${j.fileName ?? j.id}.zip';
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(Uint8List.fromList(bytes), name: name, mimeType: 'application/zip')],
        fileNameOverrides: [name],
      ));
    } catch (e) {
      if (mounted) showToast(context, 'Download failed — $e', error: true);
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(groupsProvider).value ?? const <UserGroup>[];
    final group = groups.where((g) => g.id == _groupId).firstOrNull;
    final jobs = ref.watch(_jobsProvider);
    final missing = _missing;

    return AppShell(
      eyebrow: 'Data downloader',
      title: 'Export telemetry',
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_jobsProvider),
        child: ListView(padding: const EdgeInsets.all(12), children: [
          SectionCard(
            title: 'Query',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DropdownButtonFormField<String>(
                initialValue: _groupId,
                decoration: const InputDecoration(labelText: 'Group'),
                hint: const Text('Select a group'),
                items: [for (final g in groups) DropdownMenuItem(value: g.id, child: Text(g.name))],
                onChanged: (v) => setState(() {
                  _groupId = v;
                  _devices
                    ..clear()
                    ..addAll(groups.firstWhere((g) => g.id == v).devices);
                }),
              ),
              const SizedBox(height: 12),
              Text('DEVICES', style: AppTheme.eyebrow().copyWith(color: AppColors.navy900, fontWeight: FontWeight.w700)),
              if (group == null)
                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Select a group first', style: TextStyle(color: AppColors.grey500)))
              else
                Wrap(spacing: 6, runSpacing: 0, children: [
                  for (final d in group.devices)
                    FilterChip(
                      label: Text(d),
                      selected: _devices.contains(d),
                      onSelected: (s) => setState(() => s ? _devices.add(d) : _devices.remove(d)),
                    ),
                ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _DateField(label: 'From', value: _from, onTap: () => _pickDate(true))),
                const SizedBox(width: 8),
                Expanded(child: _DateField(label: 'To', value: _to, onTap: () => _pickDate(false))),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email', helperText: 'The finished export is emailed here on completion.'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(controller: _jobName, decoration: const InputDecoration(labelText: 'Job name', hintText: 'Optional label')),
              const SizedBox(height: 12),
              Text('INTERVAL', style: AppTheme.eyebrow().copyWith(color: AppColors.navy900, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [for (final i in _intervals.keys) ButtonSegment(value: i, label: Text(i, style: const TextStyle(fontSize: 12)))],
                selected: {_interval},
                onSelectionChanged: (s) => setState(() => _interval = s.first),
              ),
              const SizedBox(height: 12),
              if (missing.isNotEmpty)
                Text('To generate the export, ${missing.join(', ')}.', style: const TextStyle(color: AppColors.amber600, fontSize: 12)),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: missing.isEmpty && !_submitting ? _submit : null,
                child: Text(_submitting ? 'Submitting…' : 'Generate export'),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Recent exports',
            padding: EdgeInsets.zero,
            child: jobs.when(
              loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
              error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text('$e', style: const TextStyle(color: AppColors.red600))),
              data: (list) => list.isEmpty
                  ? const Padding(padding: EdgeInsets.all(16), child: Text('No exports yet.'))
                  : Column(children: [
                      for (final j in list)
                        ListTile(
                          title: Text(j.name, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                          subtitle: Text([
                            j.devices,
                            if (j.submitted != null) formatIstDateTime(j.submitted!),
                          ].join(' · ')),
                          trailing: switch (j.status) {
                            'completed' || 'failed' => Row(mainAxisSize: MainAxisSize.min, children: [
                                if (j.status == 'failed')
                                  Tooltip(
                                    message: j.error ?? 'Failed',
                                    child: const Text('Failed', style: TextStyle(color: AppColors.red600, fontSize: 12)),
                                  ),
                                IconButton(
                                  tooltip: 'Download',
                                  icon: _downloading == j.id
                                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.download),
                                  onPressed: _downloading == null ? () => _download(j) : null,
                                ),
                              ]),
                            'running' => Text('Building ${j.progress}%', style: const TextStyle(fontSize: 12)),
                            _ => const Text('Queued', style: TextStyle(fontSize: 12)),
                          },
                        ),
                    ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onTap});
  final String label;
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, suffixIcon: const Icon(Icons.calendar_today, size: 18)),
          child: Text(
            '${value.day}/${value.month}/${value.year} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}',
            style: const TextStyle(fontSize: 13),
          ),
        ),
      );
}
