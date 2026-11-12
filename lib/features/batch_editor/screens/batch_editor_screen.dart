import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../app/theme/colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/photo_metadata_model.dart';
import '../../../data/models/photo_model.dart';
import '../../../shared/widgets/common.dart';
import '../../gallery/screens/photo_details_screen.dart' show fileExifProvider;
import '../../gallery/widgets/photo_grid_tile.dart';
import '../services/batch_service.dart';

enum _BF {
  city('City', Icons.location_city),
  area('Area', Icons.map_outlined),
  address('Address', Icons.home_work_outlined),
  state('State', Icons.flag_outlined),
  country('Country', Icons.public),
  latitude('Latitude', Icons.my_location),
  longitude('Longitude', Icons.my_location),
  altitude('Altitude', Icons.terrain_outlined),
  date('Date', Icons.event),
  time('Time', Icons.schedule),
  author('Author (EXIF Artist)', Icons.person_outline),
  copyright('Copyright', Icons.copyright);

  const _BF(this.label, this.icon);
  final String label;
  final IconData icon;

  bool get isText => index <= _BF.country.index || this == author || this == copyright;
}

class BatchEditorScreen extends ConsumerStatefulWidget {
  const BatchEditorScreen({super.key});

  @override
  ConsumerState<BatchEditorScreen> createState() => _BatchEditorScreenState();
}

class _BatchEditorScreenState extends ConsumerState<BatchEditorScreen> {
  int _step = 0;
  final Set<String> _selected = {};
  final Map<_BF, bool> _enabled = {for (final f in _BF.values) f: false};
  final Map<_BF, TextEditingController> _ctrl = {
    for (final f in _BF.values)
      if (f != _BF.date) f: TextEditingController(),
  };
  DateTime? _date;
  bool _saveAsNew = true;
  bool _updateStamp = true;

  BatchChanges? _changes;
  List<PhotoModel> _queue = const [];
  final List<BatchItemResult> _results = [];
  bool _processing = false;
  bool _cancelRequested = false;
  bool _finished = false;

  static const _steps = ['Select', 'Fields', 'Preview', 'Process'];

  @override
  void initState() {
    super.initState();
    final pre = ref.read(batchPreselectionProvider);
    if (pre.isNotEmpty) {
      _selected.addAll(pre);
      Future.microtask(() => ref.read(batchPreselectionProvider.notifier).clear());
    }
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------ validation

  (BatchChanges?, List<String>) _build(AppSettings s) {
    final errors = <String>[];
    String? text(_BF f) => _enabled[f]! ? _ctrl[f]!.text.trim() : null;
    double? lat, lon, alt;
    if (_enabled[_BF.latitude]!) {
      lat = Fmt.parseCoordinate(_ctrl[_BF.latitude]!.text, isLatitude: true);
      if (lat == null) errors.add('Latitude: enter a value between -90 and 90 (e.g. 12.9716 or 12°58\'17.8"N).');
    }
    if (_enabled[_BF.longitude]!) {
      lon = Fmt.parseCoordinate(_ctrl[_BF.longitude]!.text, isLatitude: false);
      if (lon == null) errors.add('Longitude: enter a value between -180 and 180.');
    }
    if (_enabled[_BF.altitude]!) {
      alt = Fmt.parseAltitude(_ctrl[_BF.altitude]!.text, s.altitudeUnit);
      if (alt == null) errors.add('Altitude: enter a number (${s.altitudeUnit == AltitudeUnit.metres ? 'metres' : 'feet'}).');
    }
    if (_enabled[_BF.date]! && _date == null) errors.add('Date: pick a date.');
    ({int h, int m, int s})? time;
    if (_enabled[_BF.time]!) {
      time = Fmt.parseTime(_ctrl[_BF.time]!.text);
      if (time == null) errors.add('Time: use HH:MM:SS (24-hour), e.g. 14:05:30.');
    }
    final ascii = RegExp(r'^[\x20-\x7E]*$');
    for (final f in [_BF.author, _BF.copyright]) {
      final v = text(f);
      if (v != null && !ascii.hasMatch(v)) {
        errors.add('${f.label}: EXIF stores this as plain ASCII; remove accented or non-Latin characters.');
      }
    }
    if (!_enabled.values.any((e) => e)) errors.add('Select at least one field to change.');
    if (errors.isNotEmpty) return (null, errors);
    return (
      BatchChanges(
        city: text(_BF.city),
        area: text(_BF.area),
        address: text(_BF.address),
        state: text(_BF.state),
        country: text(_BF.country),
        latitude: lat,
        longitude: lon,
        altitude: alt,
        date: _enabled[_BF.date]! ? _date : null,
        time: time,
        artist: text(_BF.author),
        copyright: text(_BF.copyright),
      ),
      errors
    );
  }

  void _next(List<PhotoModel> all) {
    final s = ref.read(settingsProvider);
    switch (_step) {
      case 0:
        if (_selected.isEmpty) {
          showSnack(context, 'Select at least one photo.', error: true);
          return;
        }
        setState(() => _step = 1);
      case 1:
        final (changes, errors) = _build(s);
        if (changes == null) {
          showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Check the values'),
              content: Text(errors.join('\n\n')),
              actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
            ),
          );
          return;
        }
        setState(() {
          _changes = changes;
          _queue = all.where((p) => _selected.contains(p.id)).toList();
          _step = 2;
        });
      case 2:
        _process();
    }
  }

  Future<void> _process() async {
    final ok = await confirm(
      context,
      title: 'Apply changes to ${_queue.length} photo${_queue.length == 1 ? '' : 's'}?',
      message: _saveAsNew
          ? 'New copies will be created; the existing photos stay unchanged.'
          : 'The edited versions of the selected photos will be replaced. Preserved originals are never modified.',
      confirmLabel: 'Apply',
    );
    if (!ok || !mounted) return;
    setState(() {
      _step = 3;
      _processing = true;
      _cancelRequested = false;
      _results.clear();
    });
    final service = ref.read(batchServiceProvider);
    for (final photo in _queue) {
      if (_cancelRequested || !mounted) break;
      // One photo at a time keeps memory bounded for large batches.
      final r = await service.applyTo(photo, _changes!, saveAsNew: _saveAsNew, updateStamp: _updateStamp);
      if (!mounted) return;
      setState(() => _results.add(r));
    }
    if (mounted) {
      setState(() {
        _processing = false;
        _finished = true;
      });
    }
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final photos = ref.watch(photosProvider);
    final all = photos.value ?? const <PhotoModel>[];
    return PopScope(
      canPop: !_processing && (_step == 0 || _finished),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_processing) {
          showSnack(context, 'Processing… tap "Stop" to cancel after the current photo.');
        } else if (_step > 0 && !_finished) {
          setState(() => _step--);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Batch edit'),
          bottom: PreferredSize(preferredSize: const Size.fromHeight(44), child: _stepHeader()),
        ),
        body: photos.when(
          loading: () => const LoadingView(),
          error: (e, _) => ErrorView(message: '$e', onRetry: () => ref.invalidate(photosProvider)),
          data: (list) => switch (_step) {
            0 => _selectStep(list),
            1 => _fieldsStep(),
            2 => _previewStep(),
            _ => _processStep(),
          },
        ),
        bottomNavigationBar: _bottomBar(all),
      ),
    );
  }

  Widget _stepHeader() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          for (var i = 0; i < _steps.length; i++) ...[
            CircleAvatar(
              radius: 11,
              backgroundColor: i <= _step ? scheme.secondary : scheme.surfaceContainerHighest,
              child: i < _step
                  ? Icon(Icons.check, size: 13, color: scheme.onSecondary)
                  : Text('${i + 1}',
                      style: TextStyle(
                          fontSize: 11, color: i <= _step ? scheme.onSecondary : scheme.onSurfaceVariant)),
            ),
            const SizedBox(width: 4),
            Text(_steps[i], style: Theme.of(context).textTheme.labelSmall),
            if (i < _steps.length - 1) const Expanded(child: Divider(indent: 6, endIndent: 6)),
          ],
        ],
      ),
    );
  }

  Widget? _bottomBar(List<PhotoModel> all) {
    if (_step == 3) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _processing
              ? OutlinedButton.icon(
                  onPressed: _cancelRequested ? null : () => setState(() => _cancelRequested = true),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: Text(_cancelRequested ? 'Stopping after current photo…' : 'Stop'),
                )
              : Row(children: [
                  Expanded(
                    child: OutlinedButton(onPressed: () => context.pop(), child: const Text('Done')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(onPressed: () => context.go(Routes.gallery), child: const Text('Open gallery')),
                  ),
                ]),
        ),
      );
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: [
            if (_step > 0)
              Expanded(
                child: OutlinedButton(onPressed: () => setState(() => _step--), child: const Text('Back')),
              ),
            if (_step > 0) const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: () => _next(all),
                child: Text(switch (_step) {
                  0 => 'Next (${_selected.length} selected)',
                  1 => 'Preview changes',
                  _ => 'Apply to ${_queue.length} photo${_queue.length == 1 ? '' : 's'}',
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ step 1

  Widget _selectStep(List<PhotoModel> list) {
    if (list.isEmpty) {
      return const EmptyState(
        icon: Icons.photo_library_outlined,
        title: 'No photos to edit',
        message: 'Take or import photos first.',
      );
    }
    final width = MediaQuery.sizeOf(context).width;
    final columns = width > 700 ? 5 : 3;
    final allSelected = list.every((p) => _selected.contains(p.id));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text('${_selected.length} of ${list.length} selected',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              TextButton(
                onPressed: () => setState(() {
                  allSelected ? _selected.clear() : _selected.addAll(list.map((p) => p.id));
                }),
                child: Text(allSelected ? 'Clear' : 'Select all'),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final p = list[i];
              void toggle() => setState(() => _selected.contains(p.id) ? _selected.remove(p.id) : _selected.add(p.id));
              return PhotoGridTile(
                photo: p,
                size: (width / columns).round(),
                selecting: true,
                selected: _selected.contains(p.id),
                onTap: toggle,
                onLongPress: toggle,
              );
            },
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ step 2

  Widget _fieldsStep() {
    final s = ref.watch(settingsProvider);
    final t = Theme.of(context);
    Widget field(_BF f, {String? hint, TextInputType? keyboard, Widget? suffix}) {
      final on = _enabled[f]!;
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: on, onChanged: (v) => setState(() => _enabled[f] = v ?? false)),
            Expanded(
              child: f == _BF.date
                  ? InkWell(
                      onTap: on ? _pickDate : () => setState(() => _enabled[f] = true),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: f.label,
                          prefixIcon: Icon(f.icon, size: 20),
                          enabled: on,
                        ),
                        child: Text(_date == null ? 'Pick a date' : Fmt.date(_date!, s)),
                      ),
                    )
                  : TextField(
                      controller: _ctrl[f],
                      enabled: on,
                      keyboardType: keyboard,
                      decoration: InputDecoration(
                        labelText: f.label,
                        hintText: hint,
                        prefixIcon: Icon(f.icon, size: 20),
                        suffixIcon: suffix,
                      ),
                    ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(
            'Tick the fields to change. Unticked fields are left exactly as they are.',
            style: t.textTheme.bodySmall,
          ),
        ),
        const Padding(padding: EdgeInsets.only(left: 8), child: SectionHeader('Location text', padding: EdgeInsets.fromLTRB(4, 8, 4, 8))),
        field(_BF.city),
        field(_BF.area),
        field(_BF.address),
        field(_BF.state),
        field(_BF.country),
        const Padding(
            padding: EdgeInsets.only(left: 8),
            child: SectionHeader('GPS metadata (EXIF)', padding: EdgeInsets.fromLTRB(4, 8, 4, 8))),
        field(_BF.latitude, hint: 'e.g. 12.971599 or 12°58\'17.8"N', keyboard: TextInputType.text),
        field(_BF.longitude, hint: 'e.g. 77.594566 or 77°35\'40.4"E', keyboard: TextInputType.text),
        field(_BF.altitude,
            hint: s.altitudeUnit == AltitudeUnit.metres ? 'Metres, e.g. 920' : 'Feet, e.g. 3018',
            keyboard: const TextInputType.numberWithOptions(signed: true, decimal: true)),
        Padding(
          padding: const EdgeInsets.only(left: 48, bottom: 8),
          child: Text(
            'If only latitude or longitude is ticked, each photo\'s existing value is used for the other.',
            style: t.textTheme.bodySmall,
          ),
        ),
        const Padding(
            padding: EdgeInsets.only(left: 8),
            child: SectionHeader('Date taken (EXIF)', padding: EdgeInsets.fromLTRB(4, 8, 4, 8))),
        field(_BF.date),
        field(_BF.time,
            hint: 'HH:MM:SS (24 h)',
            suffix: IconButton(icon: const Icon(Icons.access_time), onPressed: _pickTime)),
        Padding(
          padding: const EdgeInsets.only(left: 48, bottom: 8),
          child: Text(
            'Updates DateTimeOriginal and DateTimeDigitized. If only the date or time is changed, '
            'each photo keeps its own value for the other part.',
            style: t.textTheme.bodySmall,
          ),
        ),
        const Padding(
            padding: EdgeInsets.only(left: 8),
            child: SectionHeader('Ownership (EXIF)', padding: EdgeInsets.fromLTRB(4, 8, 4, 8))),
        field(_BF.author),
        field(_BF.copyright),
        const Padding(padding: EdgeInsets.only(left: 8), child: SectionHeader('Options')),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: true, label: Text('Save as new copies'), icon: Icon(Icons.copy_all_outlined)),
              ButtonSegment(value: false, label: Text('Overwrite edited'), icon: Icon(Icons.save_outlined)),
            ],
            selected: {_saveAsNew},
            onSelectionChanged: (v) => setState(() => _saveAsNew = v.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 0, 0),
          child: InfoBanner(
            tone: _saveAsNew ? ChipTone.info : ChipTone.warning,
            message: _saveAsNew
                ? 'Each photo gets a new copy with the changes. The existing photos are not changed.'
                : 'The current edited version of each photo is replaced. Preserved originals are never modified.',
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Update visible stamp text'),
            subtitle: const Text('Re-renders stamped photos so the stamp shows the new values'),
            value: _updateStamp,
            onChanged: (v) => setState(() => _updateStamp = v),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final current = Fmt.parseTime(_ctrl[_BF.time]!.text);
    final t = await showTimePicker(
      context: context,
      initialTime: current == null ? TimeOfDay.now() : TimeOfDay(hour: current.h, minute: current.m),
    );
    if (t == null) return;
    setState(() {
      _enabled[_BF.time] = true;
      _ctrl[_BF.time]!.text =
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${(current?.s ?? 0).toString().padLeft(2, '0')}';
    });
  }

  // ------------------------------------------------------------ step 3

  Widget _previewStep() {
    final c = _changes!;
    final s = ref.watch(settingsProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        InfoBanner(
          tone: ChipTone.info,
          icon: Icons.preview_outlined,
          message: '${_queue.length} photo${_queue.length == 1 ? '' : 's'} · '
              '${_saveAsNew ? 'saved as new copies' : 'overwriting edited versions'}'
              '${_updateStamp ? ' · stamp text updated' : ''}',
        ),
        const SizedBox(height: 12),
        for (final p in _queue) _PreviewCard(photo: p, changes: c, settings: s, updateStamp: _updateStamp),
      ],
    );
  }

  // ------------------------------------------------------------ step 4

  Widget _processStep() {
    final total = _queue.length;
    final done = _results.length;
    final ok = _results.where((r) => r.success).length;
    final failed = done - ok;
    final notProcessed = _finished ? total - done : 0;
    final t = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _processing ? 'Processing ${done + 1 > total ? total : done + 1} of $total…' : 'Finished',
                style: t.textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(value: total == 0 ? 0 : done / total, minHeight: 6, borderRadius: BorderRadius.circular(4)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [
                StatusChip(label: '$ok succeeded', tone: ChipTone.success, icon: Icons.check_circle_outline),
                StatusChip(label: '$failed failed', tone: failed > 0 ? ChipTone.error : ChipTone.neutral, icon: Icons.error_outline),
                if (notProcessed > 0)
                  StatusChip(label: '$notProcessed not processed (stopped)', tone: ChipTone.warning, icon: Icons.stop_circle_outlined),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final r in _results.reversed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              padding: const EdgeInsets.all(10),
              onTap: r.result == null ? null : () => context.push(Routes.photo(r.result!.id)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: PhotoThumb(path: r.photo.displayPath, thumbnailPath: r.photo.thumbnailPath, size: 56),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(r.success ? Icons.check_circle : Icons.error,
                              size: 18, color: r.success ? context.status.success : context.status.error),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              Fmt.dateTime(r.photo.capturedAt, ref.read(settingsProvider)),
                              style: t.textTheme.titleSmall,
                            ),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        Text(r.message, style: t.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_finished && failed > 0)
          Text(
            'Failed photos were left unchanged${_saveAsNew ? '' : ' unless noted'}. '
            'Fix the reported problem and run the batch again for those photos.',
            style: t.textTheme.bodySmall?.copyWith(color: AppColors.error),
          ),
      ],
    );
  }
}

/// Current → new values for one photo. The current EXIF is read lazily.
class _PreviewCard extends ConsumerWidget {
  const _PreviewCard({required this.photo, required this.changes, required this.settings, required this.updateStamp});

  final PhotoModel photo;
  final BatchChanges changes;
  final AppSettings settings;
  final bool updateStamp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final exif = changes.hasExif ? ref.watch(fileExifProvider(photo.displayPath)) : null;
    final m = exif?.value;
    final rows = <(String, String, String)>[];
    String v(String? s) => (s == null || s.isEmpty) ? '—' : s;

    if (changes.city != null) rows.add(('City', v(photo.city), v(changes.city)));
    if (changes.area != null) rows.add(('Area', v(photo.area), v(changes.area)));
    if (changes.address != null) rows.add(('Address', v(photo.address), v(changes.address)));
    if (changes.state != null) rows.add(('State', v(photo.state), v(changes.state)));
    if (changes.country != null) rows.add(('Country', v(photo.country), v(changes.country)));
    if (changes.hasCoordinates) {
      final lat = changes.latitude ?? m?.latitude;
      final lon = changes.longitude ?? m?.longitude;
      final cur = m?.hasGps == true ? Fmt.latLng(m!.latitude!, m.longitude!, settings.coordinateFormat) : 'No GPS';
      final next = (lat != null && lon != null)
          ? Fmt.latLng(lat, lon, settings.coordinateFormat)
          : (m == null ? '…' : 'Missing ${lat == null ? 'latitude' : 'longitude'} – will fail');
      rows.add(('GPS', exif?.isLoading == true ? '…' : cur, next));
    }
    if (changes.altitude != null) {
      rows.add(('Altitude', m == null ? '…' : Fmt.altitude(m.altitude, settings.altitudeUnit),
          Fmt.altitude(changes.altitude, settings.altitudeUnit)));
    }
    if (changes.hasDateTime) {
      final base = m?.dateTimeOriginal ?? photo.capturedAt;
      rows.add((
        'Date taken',
        m == null ? '…' : (m.dateTimeOriginal == null ? 'Not set' : PhotoMetadataModel.formatExifDate(m.dateTimeOriginal!)),
        PhotoMetadataModel.formatExifDate(changes.combineDateTime(base)),
      ));
    }
    if (changes.artist != null) rows.add(('Author', m == null ? '…' : v(m.artist), v(changes.artist)));
    if (changes.copyright != null) rows.add(('Copyright', m == null ? '…' : v(m.copyright), v(changes.copyright)));

    final notes = <String>[
      if (exif?.hasError == true) 'Metadata could not be read: ${exif!.error}',
      if (m != null && changes.hasExif && !m.writeSupported && !photo.hasVisibleStamp)
        '${m.format?.toUpperCase() ?? 'This format'} is EXIF read-only on this device – will fail.',
      if (updateStamp && photo.hasVisibleStamp && !photo.isOriginalPreserved)
        'Original not preserved – the stamp cannot be re-rendered.',
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 64,
                height: 64,
                child: PhotoThumb(path: photo.displayPath, thumbnailPath: photo.thumbnailPath, size: 64),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(Fmt.dateTime(photo.capturedAt, settings), style: t.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: '${r.$1}: ', style: t.textTheme.labelMedium),
                          TextSpan(
                            text: r.$2,
                            style: t.textTheme.bodySmall?.copyWith(decoration: TextDecoration.lineThrough),
                          ),
                          TextSpan(text: '  →  ', style: t.textTheme.bodySmall),
                          TextSpan(
                            text: r.$3,
                            style: t.textTheme.bodySmall?.copyWith(
                              color: t.colorScheme.secondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ]),
                      ),
                    ),
                  for (final n in notes)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(n, style: t.textTheme.bodySmall?.copyWith(color: context.status.warning)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
