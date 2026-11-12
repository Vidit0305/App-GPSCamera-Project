import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/photo_metadata_model.dart';
import '../../../data/models/photo_model.dart';
import '../../../shared/widgets/common.dart';
import '../services/exif_service.dart';

/// Editor for the real EXIF metadata stored in the image file.
///
/// [current] is what is in the file now; [desired] + [overrides] are the
/// pending changes. Nothing is written until the screen saves.
class ExifEditorPanel extends StatefulWidget {
  const ExifEditorPanel({
    super.key,
    required this.current,
    required this.desired,
    required this.overrides,
    required this.settings,
    required this.onChanged,
    required this.status,
    this.statusMessage,
    this.originalExif,
    this.loadError,
    this.onCopyFromStamp,
    this.onCopyToStamp,
    this.onUseDetected,
    this.onPickOnMap,
  });

  final PhotoMetadataModel? current;
  final PhotoMetadataModel desired;
  final Set<ExifField> overrides;
  final AppSettings settings;
  final void Function(PhotoMetadataModel desired, Set<ExifField> overrides) onChanged;
  final ExifStatus status;
  final String? statusMessage;
  final PhotoMetadataModel? originalExif;
  final String? loadError;
  final VoidCallback? onCopyFromStamp;
  final VoidCallback? onCopyToStamp;
  final VoidCallback? onUseDetected;
  final VoidCallback? onPickOnMap;

  @override
  State<ExifEditorPanel> createState() => _ExifEditorPanelState();
}

class _ExifEditorPanelState extends State<ExifEditorPanel> {
  final _lat = TextEditingController();
  final _lon = TextEditingController();
  final _alt = TextEditingController();
  final _gpsDate = TextEditingController();
  final _gpsTime = TextEditingController();
  final _offset = TextEditingController();
  final _desc = TextEditingController();
  final _artist = TextEditingController();
  final _copyright = TextEditingController();
  final _comment = TextEditingController();
  final _errors = <ExifField, String>{};
  bool _alsoDigitized = false;
  bool _alsoModified = true;

  @override
  void initState() {
    super.initState();
    _syncControllers();
  }

  @override
  void didUpdateWidget(ExifEditorPanel old) {
    super.didUpdateWidget(old);
    // Refresh text when values were changed from outside (sync, reset, map).
    if (!identical(old.desired, widget.desired) && !_editingInternally) _syncControllers();
    _editingInternally = false;
  }

  bool _editingInternally = false;

  void _syncControllers() {
    final d = widget.desired;
    final s = widget.settings;
    void set(TextEditingController c, String v) {
      if (c.text != v) c.text = v;
    }

    set(_lat, d.latitude == null ? '' : d.latitude!.toStringAsFixed(7));
    set(_lon, d.longitude == null ? '' : d.longitude!.toStringAsFixed(7));
    set(
      _alt,
      d.altitude == null
          ? ''
          : (s.altitudeUnit == AltitudeUnit.metres ? d.altitude!.toStringAsFixed(2) : (d.altitude! * 3.28084).toStringAsFixed(1)),
    );
    set(_gpsDate, d.gpsDateStamp ?? '');
    set(_gpsTime, d.gpsTimeStamp ?? '');
    set(_offset, d.offsetTime ?? '');
    set(_desc, d.imageDescription ?? '');
    set(_artist, d.artist ?? '');
    set(_copyright, d.copyright ?? '');
    set(_comment, d.userComment ?? '');
    _errors.clear();
  }

  @override
  void dispose() {
    for (final c in [_lat, _lon, _alt, _gpsDate, _gpsTime, _offset, _desc, _artist, _copyright, _comment]) {
      c.dispose();
    }
    super.dispose();
  }

  void _emit(PhotoMetadataModel d, Set<ExifField> add, {Set<ExifField> remove = const {}}) {
    _editingInternally = true;
    widget.onChanged(d, {...widget.overrides, ...add}..removeAll(remove));
  }

  /// Restores a field to the value currently in the file.
  void _undo(ExifField f) {
    final cur = widget.current ?? const PhotoMetadataModel();
    final d = widget.desired;
    PhotoMetadataModel restored;
    switch (f) {
      case ExifField.gpsCoordinates:
        restored = _with(d, latitude: cur.latitude, longitude: cur.longitude, setCoords: true);
      case ExifField.gpsAltitude:
        restored = _with(d, altitude: cur.altitude, setAlt: true);
      default:
        restored = PhotoMetadataModel.fromJson({...d.toJson(), ..._jsonFor(f, cur)});
    }
    _editingInternally = false;
    widget.onChanged(restored, {...widget.overrides}..remove(f));
  }

  static Map<String, dynamic> _jsonFor(ExifField f, PhotoMetadataModel m) {
    final j = m.toJson();
    final key = switch (f) {
      ExifField.dateTimeOriginal => 'dateTimeOriginal',
      ExifField.dateTimeDigitized => 'dateTimeDigitized',
      ExifField.dateTime => 'dateTime',
      ExifField.offsetTime => 'offsetTime',
      ExifField.gpsDateStamp => 'gpsDateStamp',
      ExifField.gpsTimeStamp => 'gpsTimeStamp',
      ExifField.imageDescription => 'imageDescription',
      ExifField.artist => 'artist',
      ExifField.copyright => 'copyright',
      ExifField.userComment => 'userComment',
      _ => null,
    };
    return key == null ? const {} : {key: j[key]};
  }

  /// Copy of [d] with nullable GPS values set explicitly (copyWith can't null).
  static PhotoMetadataModel _with(
    PhotoMetadataModel d, {
    double? latitude,
    double? longitude,
    double? altitude,
    bool setCoords = false,
    bool setAlt = false,
  }) {
    final j = d.toJson();
    if (setCoords) {
      j['latitude'] = latitude;
      j['longitude'] = longitude;
    }
    if (setAlt) j['altitude'] = altitude;
    return PhotoMetadataModel.fromJson(j);
  }

  void _onCoords() {
    final latText = _lat.text.trim();
    final lonText = _lon.text.trim();
    setState(() => _errors.remove(ExifField.gpsCoordinates));
    if (latText.isEmpty && lonText.isEmpty) {
      _emit(_with(widget.desired, setCoords: true), {ExifField.gpsCoordinates});
      return;
    }
    final lat = Fmt.parseCoordinate(latText, isLatitude: true);
    final lon = Fmt.parseCoordinate(lonText, isLatitude: false);
    if (lat == null || lon == null) {
      setState(() => _errors[ExifField.gpsCoordinates] = lat == null
          ? 'Latitude must be -90…90 (e.g. 12.9716 or 12°58\'17.8"N)'
          : 'Longitude must be -180…180 (e.g. 77.5946 or 77°35\'40.6"E)');
      return;
    }
    _emit(_with(widget.desired, latitude: lat, longitude: lon, setCoords: true), {ExifField.gpsCoordinates});
  }

  void _onAltitude() {
    final t = _alt.text.trim();
    setState(() => _errors.remove(ExifField.gpsAltitude));
    if (t.isEmpty) {
      _emit(_with(widget.desired, setAlt: true), {ExifField.gpsAltitude});
      return;
    }
    final v = Fmt.parseAltitude(t, widget.settings.altitudeUnit);
    if (v == null) {
      setState(() => _errors[ExifField.gpsAltitude] = 'Enter a number');
      return;
    }
    _emit(_with(widget.desired, altitude: v, setAlt: true), {ExifField.gpsAltitude});
  }

  void _onText(ExifField f, String text) {
    final v = text.trim().isEmpty ? null : text.trim();
    final j = widget.desired.toJson();
    final key = _jsonFor(f, widget.desired).keys.firstOrNull;
    if (key == null) return;
    j[key] = v;
    final d = PhotoMetadataModel.fromJson(j);
    final err = ExifService.validate(f, d);
    setState(() => err == null ? _errors.remove(f) : _errors[f] = err);
    if (err == null) _emit(d, {f});
  }

  Future<void> _pickDateTaken() async {
    final base = widget.desired.dateTimeOriginal ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (time == null) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute, base.second);
    _applyDateTaken(dt);
  }

  void _applyDateTaken(DateTime dt) {
    final fields = <ExifField>{ExifField.dateTimeOriginal};
    var d = widget.desired.copyWith(dateTimeOriginal: dt);
    if (_alsoDigitized) {
      d = d.copyWith(dateTimeDigitized: dt);
      fields.add(ExifField.dateTimeDigitized);
    }
    if (_alsoModified) {
      d = d.copyWith(dateTime: dt);
      fields.add(ExifField.dateTime);
    }
    _emit(d, fields);
  }

  Future<void> _editSeconds() async {
    final base = widget.desired.dateTimeOriginal;
    if (base == null) return;
    final ctrl = TextEditingController(text: DateFormat('HH:mm:ss').format(base));
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exact time taken'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'HH:MM:SS (24 h, local time)'),
          keyboardType: TextInputType.datetime,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Set')),
        ],
      ),
    );
    ctrl.dispose();
    if (r == null) return;
    final t = Fmt.parseTime(r);
    if (t == null) {
      if (mounted) showSnack(context, 'Invalid time. Use HH:MM:SS.', error: true);
      return;
    }
    _applyDateTaken(DateTime(base.year, base.month, base.day, t.h, t.m, t.s));
  }

  void _removeGps() {
    final d = PhotoMetadataModel.fromJson({
      ...widget.desired.toJson(),
      'latitude': null,
      'longitude': null,
      'altitude': null,
      'gpsDateStamp': null,
      'gpsTimeStamp': null,
    });
    _editingInternally = false;
    widget.onChanged(d, {
      ...widget.overrides,
      ExifField.gpsCoordinates,
      ExifField.gpsAltitude,
      ExifField.gpsDateStamp,
      ExifField.gpsTimeStamp,
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cur = widget.current;
    final d = widget.desired;
    final fmt = DateFormat('yyyy-MM-dd  HH:mm:ss');
    final writable = cur?.writeSupported ?? false;

    Widget changed(ExifField f) => widget.overrides.contains(f) && !(cur != null && cur.sameField(f, d))
        ? Padding(
            padding: const EdgeInsets.only(left: 6),
            child: InkWell(
              onTap: () => _undo(f),
              child: const StatusChip(label: 'Changed · undo', tone: ChipTone.info, icon: Icons.undo, dense: true),
            ),
          )
        : const SizedBox.shrink();

    Widget fieldLabel(String text, ExifField f) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Row(children: [Text(text, style: theme.textTheme.labelMedium), changed(f)]),
        );

    final (statusTone, statusLabel) = switch (widget.status) {
      ExifStatus.verified => (ChipTone.success, 'Verified'),
      ExifStatus.partial => (ChipTone.warning, 'Partially written'),
      ExifStatus.failed => (ChipTone.error, 'Write failed'),
      ExifStatus.unsupported => (ChipTone.error, 'Not supported'),
      ExifStatus.untouched => (ChipTone.neutral, 'Not edited'),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.data_object, color: theme.colorScheme.secondary),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Metadata inside the file', style: theme.textTheme.titleSmall)),
                  StatusChip(label: statusLabel, tone: statusTone),
                ]),
                const SizedBox(height: 8),
                Text(
                  'Format: ${cur?.format?.toUpperCase() ?? 'unknown'} · '
                  '${writable ? 'EXIF writing supported' : 'EXIF writing not supported'}',
                  style: theme.textTheme.bodySmall,
                ),
                if (widget.statusMessage != null) ...[
                  const SizedBox(height: 4),
                  Text(widget.statusMessage!, style: theme.textTheme.bodySmall),
                ],
                const SizedBox(height: 6),
                Text(
                  'This edits the real EXIF data, separately from the visible stamp. Changes are written when you '
                  'save and verified by re-opening the saved file. The preserved original is never modified.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (widget.loadError != null) ...[
            const SizedBox(height: 12),
            InfoBanner(message: widget.loadError!, tone: ChipTone.error, icon: Icons.error_outline),
          ],
          if (cur != null && !writable) ...[
            const SizedBox(height: 12),
            InfoBanner(
              message: 'EXIF cannot be written to ${cur.format?.toUpperCase() ?? 'this'} files on this device. '
                  'Turn on the visible stamp and save – the exported JPEG supports full metadata editing.',
              tone: ChipTone.warning,
            ),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (widget.onCopyFromStamp != null)
              ActionChip(
                avatar: const Icon(Icons.south, size: 16),
                label: const Text('Copy from stamp'),
                onPressed: widget.onCopyFromStamp,
              ),
            if (widget.onCopyToStamp != null)
              ActionChip(
                avatar: const Icon(Icons.north, size: 16),
                label: const Text('Copy to stamp'),
                onPressed: widget.onCopyToStamp,
              ),
            if (widget.onUseDetected != null)
              ActionChip(
                avatar: const Icon(Icons.gps_fixed, size: 16),
                label: const Text('Reset to detected'),
                onPressed: widget.onUseDetected,
              ),
            if (widget.onPickOnMap != null)
              ActionChip(
                avatar: const Icon(Icons.map_outlined, size: 16),
                label: const Text('Pick on map'),
                onPressed: widget.onPickOnMap,
              ),
          ]),

          // ------------------------------------------------ Date & time
          const SectionHeader('Date & time'),
          fieldLabel('Date taken (DateTimeOriginal, local time)', ExifField.dateTimeOriginal),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickDateTaken,
                icon: const Icon(Icons.event, size: 18),
                label: Text(d.dateTimeOriginal == null ? 'Not set – choose' : fmt.format(d.dateTimeOriginal!)),
              ),
            ),
            IconButton(
              tooltip: 'Edit exact time with seconds',
              onPressed: d.dateTimeOriginal == null ? null : _editSeconds,
              icon: const Icon(Icons.more_time),
            ),
          ]),
          if (widget.originalExif?.dateTimeOriginal != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Original capture time: ${fmt.format(widget.originalExif!.dateTimeOriginal!)} (kept in the app record)',
                style: theme.textTheme.bodySmall,
              ),
            ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _alsoDigitized,
            onChanged: (v) => setState(() => _alsoDigitized = v ?? false),
            title: const Text('Also change DateTimeDigitized'),
            subtitle: const Text('Leave off to preserve the original digitized timestamp'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _alsoModified,
            onChanged: (v) => setState(() => _alsoModified = v ?? true),
            title: const Text('Also change DateTime (modified)'),
          ),
          if (d.dateTimeDigitized != null)
            Text('DateTimeDigitized: ${fmt.format(d.dateTimeDigitized!)}', style: theme.textTheme.bodySmall),
          fieldLabel('Timezone offset (OffsetTimeOriginal)', ExifField.offsetTime),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _offset,
                decoration: InputDecoration(hintText: '+05:30', errorText: _errors[ExifField.offsetTime]),
                onChanged: (v) => _onText(ExifField.offsetTime, v),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () {
                final base = d.dateTimeOriginal ?? DateTime.now();
                _offset.text = PhotoMetadataModel.formatOffset(base.timeZoneOffset);
                _onText(ExifField.offsetTime, _offset.text);
              },
              child: const Text('Device zone'),
            ),
          ]),

          // ------------------------------------------------ GPS
          const SectionHeader('GPS location'),
          fieldLabel('Latitude / Longitude (decimal or DMS)', ExifField.gpsCoordinates),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _lat,
                keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                decoration: InputDecoration(
                  labelText: 'Latitude',
                  suffixText: d.latitudeReference,
                  suffixIcon: _clear(_lat, _onCoords),
                ),
                onChanged: (_) => _onCoords(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _lon,
                keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                decoration: InputDecoration(
                  labelText: 'Longitude',
                  suffixText: d.longitudeReference,
                  suffixIcon: _clear(_lon, _onCoords),
                ),
                onChanged: (_) => _onCoords(),
              ),
            ),
          ]),
          if (_errors[ExifField.gpsCoordinates] != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_errors[ExifField.gpsCoordinates]!, style: TextStyle(color: context.status.error, fontSize: 12)),
            ),
          if (d.hasGps)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Stored as ${Fmt.latLng(d.latitude!, d.longitude!, CoordinateFormat.dms)} '
                '(GPSLatitudeRef ${d.latitudeReference}, GPSLongitudeRef ${d.longitudeReference})',
                style: theme.textTheme.bodySmall,
              ),
            ),
          fieldLabel('Altitude (${widget.settings.altitudeUnit == AltitudeUnit.metres ? 'metres' : 'feet'})',
              ExifField.gpsAltitude),
          TextField(
            controller: _alt,
            keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
            decoration: InputDecoration(
              hintText: 'Empty = no altitude',
              errorText: _errors[ExifField.gpsAltitude],
              helperText: d.altitude == null ? null : 'GPSAltitudeRef: ${d.altitudeReference == 0 ? 'above' : 'below'} sea level',
              suffixIcon: _clear(_alt, _onAltitude),
            ),
            onChanged: (_) => _onAltitude(),
          ),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                fieldLabel('GPS date (UTC)', ExifField.gpsDateStamp),
                TextField(
                  controller: _gpsDate,
                  decoration: InputDecoration(hintText: 'YYYY:MM:DD', errorText: _errors[ExifField.gpsDateStamp]),
                  onChanged: (v) => _onText(ExifField.gpsDateStamp, v),
                ),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                fieldLabel('GPS time (UTC)', ExifField.gpsTimeStamp),
                TextField(
                  controller: _gpsTime,
                  decoration: InputDecoration(hintText: 'HH:MM:SS', errorText: _errors[ExifField.gpsTimeStamp]),
                  onChanged: (v) => _onText(ExifField.gpsTimeStamp, v),
                ),
              ]),
            ),
          ]),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: d.dateTimeOriginal == null
                  ? null
                  : () {
                      final local = d.dateTimeOriginal!;
                      final utc = local.toUtc();
                      _gpsDate.text = DateFormat('yyyy:MM:dd').format(utc);
                      _gpsTime.text = DateFormat('HH:mm:ss').format(utc);
                      _onText(ExifField.gpsDateStamp, _gpsDate.text);
                      _onText(ExifField.gpsTimeStamp, _gpsTime.text);
                    },
              icon: const Icon(Icons.sync, size: 18),
              label: const Text('Set GPS date/time from date taken'),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              onPressed: _removeGps,
              icon: const Icon(Icons.location_off_outlined, size: 18),
              label: const Text('Remove all GPS metadata'),
            ),
          ),

          // ------------------------------------------------ Descriptive
          const SectionHeader('Description & rights'),
          fieldLabel('Image description', ExifField.imageDescription),
          _textField(_desc, ExifField.imageDescription, 'e.g. Site inspection, north wall'),
          fieldLabel('Artist / Author', ExifField.artist),
          _textField(_artist, ExifField.artist, 'Your name'),
          fieldLabel('Copyright', ExifField.copyright),
          _textField(_copyright, ExifField.copyright, '© 2026 Your name'),
          fieldLabel('User comment', ExifField.userComment),
          _textField(_comment, ExifField.userComment, 'Any note', maxLines: 3),

          // ------------------------------------------------ Read-only
          const SectionHeader('Camera & image (read-only)'),
          AppCard(
            child: Column(children: [
              _kv('Make', cur?.make),
              _kv('Model', cur?.model),
              _kv('Software', cur?.software),
              _kv('Orientation', cur?.orientation?.toString()),
              _kv('Stored dimensions',
                  cur?.imageWidth == null ? null : '${cur!.imageWidth} × ${cur.imageHeight}'),
            ]),
          ),
          if (cur != null && cur.rawTags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: ExpansionTile(
                shape: const Border(),
                title: Text('All tags (${cur.rawTags.length})', style: theme.textTheme.titleSmall),
                children: [
                  for (final e in (cur.rawTags.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
                    ListTile(
                      dense: true,
                      title: Text(e.key, style: theme.textTheme.labelMedium),
                      subtitle: Text(e.value, style: theme.textTheme.bodySmall),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget? _clear(TextEditingController c, VoidCallback after) => c.text.isEmpty
      ? null
      : IconButton(
          icon: const Icon(Icons.clear, size: 18),
          onPressed: () {
            c.clear();
            after();
            setState(() {});
          },
        );

  Widget _textField(TextEditingController c, ExifField f, String hint, {int maxLines = 1}) => TextField(
        controller: c,
        maxLines: maxLines,
        decoration: InputDecoration(
          hintText: hint,
          errorText: _errors[f],
          suffixIcon: _clear(c, () => _onText(f, '')),
        ),
        onChanged: (v) => _onText(f, v),
      );

  Widget _kv(String k, String? v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          SizedBox(width: 140, child: Text(k, style: Theme.of(context).textTheme.labelMedium)),
          Expanded(child: Text(v ?? '—', style: Theme.of(context).textTheme.bodyMedium)),
        ]),
      );
}
