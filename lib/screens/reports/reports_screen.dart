import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../api/telemetry_api.dart';
import '../../core/api/endpoints.dart';
import '../../core/ist_time.dart';
import '../../core/permissions.dart';
import '../../core/theme/app_theme.dart';
import '../../state/auth.dart';
import '../../state/data.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

class _Template {
  _Template(this.id, this.name, this.description);
  final String id, name, description;
}

class GeneratedReport {
  GeneratedReport.fromJson(Map<String, dynamic> j)
      : filename = '${j['filename']}',
        deviceName = '${j['device_name'] ?? j['device_id']}',
        type = '${j['report_type']}',
        start = '${j['start_date']}',
        end = '${j['end_date']}',
        sizeKb = (j['file_size_kb'] as num?)?.toDouble() ?? 0,
        created = '${j['created_at'] ?? ''}',
        hasHtml = j['has_html'] == true,
        hasPdf = j['has_pdf'] == true;

  final String filename, deviceName, type, start, end, created;
  final double sizeKb;
  final bool hasHtml, hasPdf;

  String get base => filename.replaceAll(RegExp(r'\.(html|pdf)$'), '');
}

class _Task {
  _Task(this.id, this.template, this.devices, this.range);
  final String id, template, range;
  final List<String> devices;
  String status = 'pending';
  int progress = 0;
  String? error;
  bool get done => status == 'completed' || status == 'failed';
}

final _templatesProvider = FutureProvider.autoDispose<List<_Template>>((ref) async {
  final res = await ref.watch(apiServiceProvider).get<Map<String, dynamic>>(Endpoint.reportTemplates);
  return [
    for (final t in (res['templates'] as List? ?? const []))
      _Template('${(t as Map)['id']}', '${t['name']}', '${t['description'] ?? ''}'),
  ];
});

/// Devices the report service is set up for: id -> display name.
final _reportDevicesProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final res = await ref.watch(apiServiceProvider).get<Map<String, dynamic>>(Endpoint.reportDevices);
  return {for (final d in (res['devices'] as List? ?? const [])) '${(d as Map)['id']}': '${d['name']}'};
});

final _reportsProvider = FutureProvider.autoDispose<List<GeneratedReport>>((ref) async {
  final res = await ref.watch(apiServiceProvider).get<Map<String, dynamic>>(Endpoint.reports);
  return [for (final r in (res['reports'] as List? ?? const [])) GeneratedReport.fromJson(r as Map<String, dynamic>)];
});

/// AI reports — generate, view, download, email and delete reports (the web AiReportsPage).
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String? _groupId;
  final Set<String> _devices = {};
  String _template = 'default';
  String _period = 'weekly';
  DateTime? _customFrom, _customTo;
  bool _generating = false;
  final List<_Task> _tasks = [];
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  (String, String) get _range {
    String d(DateTime t) => '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
    return switch (_period) {
      'monthly' => (istDate(29), istDate()),
      'quarterly' => (istDate(89), istDate()),
      'custom' => (_customFrom == null ? '' : d(_customFrom!), _customTo == null ? '' : d(_customTo!)),
      _ => (istDate(6), istDate()),
    };
  }

  Future<void> _generate(String templateName) async {
    final (start, end) = _range;
    if (_devices.isEmpty || start.isEmpty || end.isEmpty) return;
    setState(() => _generating = true);
    try {
      final res = await ref.read(apiServiceProvider).post<Map<String, dynamic>>(Endpoint.generateReport, {
        'device_ids': _devices.toList(),
        'report_type': _period,
        'start_date': start,
        'end_date': end,
        'report_template': _template,
        'compare_previous': true,
      });
      setState(() => _tasks.insert(0, _Task('${res['task_id']}', templateName, _devices.toList(), '$start – $end')));
      _startPolling();
    } catch (e) {
      if (mounted) showToast(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _startPolling() {
    _poll ??= Timer.periodic(const Duration(seconds: 3), (_) async {
      final api = ref.read(apiServiceProvider);
      var anyRunning = false;
      for (final t in _tasks.where((t) => !t.done)) {
        try {
          final s = await api.get<Map<String, dynamic>>(Endpoint.reportTaskStatus.withParams({'task_id': t.id}));
          t.status = '${s['status']}';
          t.progress = ((s['result'] as Map?)?['progress'] as num?)?.toInt() ?? t.progress;
          final failed = [
            for (final r in ((s['result'] as Map?)?['results'] as List? ?? const []))
              if ((r as Map)['status'] == 'failed') '${r['device_id']}: ${r['error'] ?? 'failed'}',
          ];
          t.error = failed.isEmpty ? null : failed.join('\n');
          if (t.done) ref.invalidate(_reportsProvider);
        } catch (_) {}
        anyRunning |= !t.done;
      }
      if (mounted) setState(() {});
      if (!anyRunning) {
        _poll?.cancel();
        _poll = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(groupsProvider).value ?? const <UserGroup>[];
    final known = ref.watch(_reportDevicesProvider).value ?? const <String, String>{};
    final templates = ref.watch(_templatesProvider).value ?? const <_Template>[];
    final reports = ref.watch(_reportsProvider);
    final canDelete = can(ref.watch(roleProvider), Perm.reportsDelete);
    final group = groups.where((g) => g.id == _groupId).firstOrNull;
    final (start, end) = _range;
    final templateName = templates.where((t) => t.id == _template).firstOrNull?.name ?? _template;

    return AppShell(
      eyebrow: 'AI reports',
      title: 'Generate a report',
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(_reportsProvider),
        child: ListView(padding: const EdgeInsets.all(12), children: [
          SectionCard(
            title: 'Configuration',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DropdownButtonFormField<String>(
                initialValue: _groupId,
                decoration: const InputDecoration(labelText: 'Group'),
                hint: const Text('Select a group'),
                items: [for (final g in groups) DropdownMenuItem(value: g.id, child: Text('${g.name} (${g.devices.length})'))],
                onChanged: (v) => setState(() {
                  _groupId = v;
                  _devices
                    ..clear()
                    ..addAll(groups.firstWhere((g) => g.id == v).devices.where(known.containsKey));
                }),
              ),
              const SizedBox(height: 12),
              Text('DEVICES', style: AppTheme.eyebrow().copyWith(color: AppColors.navy900, fontWeight: FontWeight.w700)),
              if (group == null)
                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Select a group first', style: TextStyle(color: AppColors.grey500)))
              else ...[
                Wrap(spacing: 6, children: [
                  for (final d in group.devices)
                    FilterChip(
                      label: Text(known[d] != null && known[d] != d ? '${known[d]} ($d)' : d),
                      selected: _devices.contains(d),
                      tooltip: known.containsKey(d) ? null : 'Not set up for AI reports',
                      onSelected: known.containsKey(d) ? (s) => setState(() => s ? _devices.add(d) : _devices.remove(d)) : null,
                    ),
                ]),
                if (!group.devices.any(known.containsKey))
                  const Text(
                    "None of this group's devices are set up in the report service yet, so reports can't be generated for it.",
                    style: TextStyle(color: AppColors.amber600, fontSize: 12),
                  ),
              ],
              const SizedBox(height: 12),
              Text('TEMPLATE', style: AppTheme.eyebrow().copyWith(color: AppColors.navy900, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              RadioGroup<String>(
                groupValue: _template,
                onChanged: (v) => setState(() => _template = v!),
                child: Column(children: [
                  for (final t in templates)
                    RadioListTile<String>(
                      value: t.id,
                      contentPadding: EdgeInsets.zero,
                      title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(t.description, style: const TextStyle(fontSize: 12)),
                    ),
                ]),
              ),
              const SizedBox(height: 8),
              Text('PERIOD', style: AppTheme.eyebrow().copyWith(color: AppColors.navy900, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'weekly', label: Text('7 d')),
                  ButtonSegment(value: 'monthly', label: Text('30 d')),
                  ButtonSegment(value: 'quarterly', label: Text('Quarter')),
                  ButtonSegment(value: 'custom', label: Text('Custom')),
                ],
                selected: {_period},
                onSelectionChanged: (s) => setState(() => _period = s.first),
              ),
              if (_period == 'custom') ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final d = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now());
                        if (d != null) setState(() => _customFrom = d);
                      },
                      child: Text(start.isEmpty ? 'From' : start),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final d = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now());
                        if (d != null) setState(() => _customTo = d);
                      },
                      child: Text(end.isEmpty ? 'To' : end),
                    ),
                  ),
                ]),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _devices.isNotEmpty && start.isNotEmpty && end.isNotEmpty && !_generating ? () => _generate(templateName) : null,
                child: Text(_generating ? 'Generating…' : 'Generate'),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Reports',
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (final t in _tasks)
                ListTile(
                  title: Text(t.template, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${t.devices.length} device${t.devices.length == 1 ? '' : 's'} · ${t.range}${t.error == null ? '' : '\n${t.error}'}'),
                  isThreeLine: t.error != null,
                  trailing: t.done
                      ? Text(t.status.toUpperCase(),
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: t.status == 'failed' ? AppColors.red600 : AppColors.teal600))
                      : Text('${t.progress}%', style: const TextStyle(color: AppColors.teal600, fontWeight: FontWeight.w700)),
                ),
              reports.when(
                loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
                error: (e, _) => Padding(padding: const EdgeInsets.all(16), child: Text('$e', style: const TextStyle(color: AppColors.red600))),
                data: (list) => list.isEmpty && _tasks.isEmpty
                    ? const Padding(padding: EdgeInsets.all(16), child: Text('No reports yet — pick a template and press Generate.'))
                    : Column(children: [for (final r in list) _ReportTile(report: r, canDelete: canDelete)]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _ReportTile extends ConsumerStatefulWidget {
  const _ReportTile({required this.report, required this.canDelete});
  final GeneratedReport report;
  final bool canDelete;

  @override
  ConsumerState<_ReportTile> createState() => _ReportTileState();
}

class _ReportTileState extends ConsumerState<_ReportTile> {
  bool _busy = false;

  Future<void> _download() async {
    final r = widget.report;
    setState(() => _busy = true);
    try {
      final api = ref.read(apiServiceProvider);
      // The backend's own PDF when it made one; otherwise the HTML report.
      final ext = r.hasPdf ? 'pdf' : 'html';
      final bytes = await api.getBytes(Endpoint.viewReport.withParams({'filename': '${r.base}.$ext'}));
      final name = '${r.base}.$ext';
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(Uint8List.fromList(bytes), name: name, mimeType: r.hasPdf ? 'application/pdf' : 'text/html')],
        fileNameOverrides: [name],
      ));
    } catch (e) {
      if (mounted) showToast(context, "Couldn't download — $e", error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _email() async {
    final c = TextEditingController(text: ref.read(authProvider).user?.email ?? '');
    final to = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Email report'),
        content: TextField(controller: c, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Recipient email')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Send')),
        ],
      ),
    );
    if (to == null || !to.contains('@')) return;
    final r = widget.report;
    try {
      await ref.read(apiServiceProvider).post<dynamic>(Endpoint.emailReport.withParams({'filename': r.filename}), {
        'recipient_email': to,
        'subject': '${r.deviceName} · ${r.type} report (${r.start} – ${r.end})',
      });
      if (mounted) showToast(context, 'Report emailed to $to');
    } catch (e) {
      if (mounted) showToast(context, '$e', error: true);
    }
  }

  Future<void> _delete() async {
    if (!widget.canDelete) return;
    final r = widget.report;
    final ok = await confirmDialog(context,
        title: 'Delete report?',
        message: '${r.deviceName} · ${r.type} (${r.start} – ${r.end}). Both the View and PDF files will be permanently removed.',
        confirm: 'Delete',
        danger: true);
    if (!ok) return;
    try {
      await ref.read(apiServiceProvider).delete<dynamic>(Endpoint.report.withParams({'filename': r.filename}));
      ref.invalidate(_reportsProvider);
    } catch (e) {
      if (mounted) showToast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    return ListTile(
      title: Text('${r.deviceName} · ${r.type}', style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('${r.start} – ${r.end} · ${r.sizeKb.toStringAsFixed(1)} KB · ${r.created}', style: const TextStyle(fontSize: 12)),
      onTap: r.hasHtml ? () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReportViewerScreen(report: r))) : null,
      trailing: PopupMenuButton<String>(
        icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
        onSelected: (v) => switch (v) {
          'view' => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReportViewerScreen(report: r))),
          'download' => _download(),
          'email' => _email(),
          _ => _delete(),
        },
        itemBuilder: (_) => [
          if (r.hasHtml) const PopupMenuItem(value: 'view', child: Text('View')),
          if (r.hasHtml || r.hasPdf) PopupMenuItem(value: 'download', child: Text(r.hasPdf ? 'Download PDF' : 'Download (HTML)')),
          const PopupMenuItem(value: 'email', child: Text('Email report')),
          if (widget.canDelete) const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}

/// Full-screen report preview. The view route answers with
/// `Content-Disposition: attachment`, so the HTML is fetched and loaded
/// directly (its images are inline data: URIs).
class ReportViewerScreen extends ConsumerStatefulWidget {
  const ReportViewerScreen({super.key, required this.report});
  final GeneratedReport report;

  @override
  ConsumerState<ReportViewerScreen> createState() => _ReportViewerScreenState();
}

class _ReportViewerScreenState extends ConsumerState<ReportViewerScreen> {
  final _controller = WebViewController()..setJavaScriptMode(JavaScriptMode.unrestricted);
  String? _error;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    final e = Endpoint.viewReport.withParams({'filename': '${widget.report.base}.html'});
    ref.read(apiServiceProvider).getBytes(e).then((bytes) async {
      await _controller.loadHtmlString(utf8.decode(bytes, allowMalformed: true), baseUrl: e.url);
      if (mounted) setState(() => _loaded = true);
    }).catchError((Object err) {
      if (mounted) setState(() => _error = '$err');
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r.deviceName),
          Text('${r.type.toUpperCase()} | ${r.start} TO ${r.end}', style: AppTheme.eyebrow()),
        ]),
      ),
      body: _error != null
          ? ErrorState(message: "Couldn't load the report — $_error")
          : !_loaded
              ? const Center(child: Text('Loading report…'))
              : WebViewWidget(controller: _controller),
    );
  }
}
