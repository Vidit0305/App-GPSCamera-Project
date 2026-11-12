import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/app_settings.dart';
import '../../../data/models/location_model.dart';
import '../../../data/models/photo_metadata_model.dart';
import '../../../data/models/photo_model.dart';
import '../../../shared/widgets/common.dart';
import '../../photo_editor/services/photo_service.dart';
import '../widgets/share_helper.dart';

/// Actual EXIF metadata of a file, re-read from disk.
final fileExifProvider = FutureProvider.autoDispose.family<PhotoMetadataModel, String>(
  (ref, path) => ref.read(exifServiceProvider).read(path),
);

class PhotoDetailsScreen extends ConsumerStatefulWidget {
  const PhotoDetailsScreen({super.key, required this.photoId});
  final String photoId;

  @override
  ConsumerState<PhotoDetailsScreen> createState() => _PhotoDetailsScreenState();
}

class _PhotoDetailsScreenState extends ConsumerState<PhotoDetailsScreen> {
  bool _showOriginal = false;
  bool _deleting = false;

  Future<void> _export(PhotoModel photo) async {
    var original = false;
    final hasSeparateOriginal = photo.isEdited && photo.isOriginalPreserved && photo.originalFilePath != photo.editedFilePath;
    if (hasSeparateOriginal) {
      final choice = await showModalBottomSheet<bool>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.approval_outlined),
                title: const Text('Save edited version'),
                subtitle: const Text('With the visible stamp and edited metadata'),
                onTap: () => Navigator.pop(ctx, false),
              ),
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('Save original'),
                subtitle: const Text('The unstamped photo as captured / imported'),
                onTap: () => Navigator.pop(ctx, true),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (choice == null) return;
      original = choice;
    }
    if (!mounted) return;
    try {
      await runWithProgress(context, 'Saving to device gallery…',
          () => ref.read(photoServiceProvider).exportToDevice(photo, original: original));
      if (mounted) showSnack(context, 'Saved to the "${PhotoService.deviceAlbum}" album.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _duplicate(PhotoModel photo) async {
    try {
      final copy =
          await runWithProgress(context, 'Saving a copy…', () => ref.read(photoServiceProvider).duplicate(photo));
      if (!mounted) return;
      showSnack(
        context,
        'Copy saved to the gallery.',
        action: SnackBarAction(label: 'Open', onPressed: () => context.push(Routes.photo(copy.id))),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete(PhotoModel photo) async {
    final ok = await confirm(
      context,
      title: 'Delete photo?',
      message: 'The photo, its preserved original and edits will be permanently removed from GPS Camera. '
          'Copies saved to your device gallery are not affected.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _deleting = true);
    try {
      await ref.read(photoServiceProvider).delete(photo);
      if (mounted) {
        showSnack(context, 'Photo deleted.');
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _deleting = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = ref.watch(photoByIdProvider(widget.photoId));
    final loading = ref.watch(photosProvider).isLoading;
    final settings = ref.watch(settingsProvider);

    if (_deleting) return const Scaffold(body: LoadingView(message: 'Deleting…'));
    if (photo == null) {
      return Scaffold(
        appBar: AppBar(),
        body: loading
            ? const LoadingView()
            : EmptyState(
                icon: Icons.image_not_supported_outlined,
                title: 'Photo not found',
                message: 'It may have been deleted.',
                action: OutlinedButton(onPressed: () => context.pop(), child: const Text('Back')),
              ),
      );
    }

    final canToggle = photo.isEdited && photo.isOriginalPreserved && photo.originalFilePath != photo.editedFilePath;
    final showingOriginal = canToggle && _showOriginal;
    final path = showingOriginal ? photo.originalFilePath : photo.displayPath;
    final t = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(Fmt.dateTime(photo.capturedAt, settings)),
        actions: [
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => sharePhotosWithPrivacy(context, ref, [photo]),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'export':
                  _export(photo);
                case 'copy':
                  _duplicate(photo);
                case 'delete':
                  _delete(photo);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'export',
                  child: ListTile(leading: Icon(Icons.download_outlined), title: Text('Export to device gallery'))),
              PopupMenuItem(value: 'copy', child: ListTile(leading: Icon(Icons.copy_all_outlined), title: Text('Save a copy'))),
              PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete'))),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Container(
            height: MediaQuery.sizeOf(context).height * 0.48,
            color: Colors.black,
            child: InteractiveViewer(
              maxScale: 6,
              child: Center(
                child: Image.file(
                  File(path),
                  key: ValueKey(path),
                  fit: BoxFit.contain,
                  cacheWidth: (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context) * 1.5).round(),
                  errorBuilder: (_, _, _) => const Center(
                    child: Text('Image file is missing or unreadable.', style: TextStyle(color: Colors.white70)),
                  ),
                ),
              ),
            ),
          ),
          if (canToggle)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Edited'), icon: Icon(Icons.approval_outlined, size: 18)),
                  ButtonSegment(value: true, label: Text('Original'), icon: Icon(Icons.image_outlined, size: 18)),
                ],
                selected: {_showOriginal},
                onSelectionChanged: (s) => setState(() => _showOriginal = s.first),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => context.push(Routes.editor(photo.id)),
                    icon: const Icon(Icons.approval_outlined),
                    label: const Text('Edit stamp'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push(Routes.editor(photo.id, tab: 'exif')),
                    icon: const Icon(Icons.data_object),
                    label: const Text('Edit EXIF'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => sharePhotosWithPrivacy(context, ref, [photo]),
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('Share'),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _export(photo),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Export'),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _duplicate(photo),
                    icon: const Icon(Icons.copy_all_outlined),
                    label: const Text('Copy'),
                  ),
                ),
              ],
            ),
          ),
          if (photo.addressResolvedLater)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: InfoBanner(
                tone: ChipTone.info,
                icon: Icons.place_outlined,
                message: 'The address for this photo was found after it was taken. Open the editor to apply it to the stamp.',
                action: TextButton(onPressed: () => context.push(Routes.editor(photo.id)), child: const Text('Open')),
              ),
            ),
          if (photo.addressPending)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: InfoBanner(
                icon: Icons.cloud_off_outlined,
                message: 'Coordinates were saved but the address has not been looked up yet. '
                    'It will be resolved automatically when online services are available.',
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader('Capture'),
                _CaptureCard(photo: photo, settings: settings),
                const SectionHeader('Location'),
                _LocationCard(photo: photo, settings: settings),
                const SectionHeader('EXIF metadata'),
                _ExifCard(photo: photo, path: path, settings: settings),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'Stored privately in the app. ${photo.isOriginalPreserved ? 'The original is preserved.' : 'The original was not preserved.'}',
              style: t.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.label, this.value, {this.muted = false});
  final IconData icon;
  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: t.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          SizedBox(width: 108, child: Text(label, style: t.textTheme.bodySmall)),
          Expanded(
            child: SelectableText(
              value,
              style: t.textTheme.bodyMedium?.copyWith(color: muted ? t.colorScheme.onSurfaceVariant : null),
            ),
          ),
        ],
      ),
    );
  }
}

class _CaptureCard extends StatelessWidget {
  const _CaptureCard({required this.photo, required this.settings});
  final PhotoModel photo;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final dims = photo.imageWidth != null && photo.imageHeight != null
        ? '${photo.imageWidth} × ${photo.imageHeight} px'
        : 'Unknown';
    return AppCard(
      child: Column(
        children: [
          _InfoRow(Icons.event, 'Date', Fmt.date(photo.capturedAt, settings)),
          _InfoRow(Icons.schedule, 'Time', Fmt.time(photo.capturedAt, settings)),
          _InfoRow(Icons.photo_size_select_large, 'Dimensions', dims),
          _InfoRow(Icons.sd_storage_outlined, 'File size', Fmt.fileSize(photo.fileSize)),
          _InfoRow(Icons.input, 'Source', photo.source.label),
          if (photo.originalFileName != null) _InfoRow(Icons.description_outlined, 'File name', photo.originalFileName!),
          _InfoRow(Icons.approval_outlined, 'Visible stamp', photo.hasVisibleStamp ? 'Applied' : 'None'),
          _InfoRow(Icons.update, 'Last edited', Fmt.dateTime(photo.updatedAt, settings)),
        ],
      ),
    );
  }
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.photo, required this.settings});
  final PhotoModel photo;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final d = photo.detectedLocation;
    final place = [photo.city, photo.state, photo.country].whereType<String>().where((e) => e.isNotEmpty).join(', ');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            StatusChip(
              label: d?.source.label ?? LocationSource.none.label,
              icon: switch (d?.source) {
                LocationSource.gps => Icons.gps_fixed,
                LocationSource.manual => Icons.edit_location_alt_outlined,
                LocationSource.lastKnown => Icons.history,
                LocationSource.exif => Icons.data_object,
                _ => Icons.location_disabled,
              },
              tone: switch (d?.source) {
                LocationSource.gps => ChipTone.success,
                LocationSource.manual || LocationSource.exif => ChipTone.info,
                LocationSource.lastKnown => ChipTone.warning,
                _ => ChipTone.neutral,
              },
            ),
            if (d?.isMocked ?? false)
              const StatusChip(label: 'Mock location reported', icon: Icons.warning_amber, tone: ChipTone.warning),
          ]),
          const SizedBox(height: 6),
          _InfoRow(Icons.location_city, 'Place', place.isEmpty ? 'No address' : place, muted: place.isEmpty),
          if ((photo.area ?? '').isNotEmpty) _InfoRow(Icons.map_outlined, 'Area', photo.area!),
          if ((photo.address ?? '').isNotEmpty) _InfoRow(Icons.home_work_outlined, 'Address', photo.address!),
          _InfoRow(
            Icons.my_location,
            'Coordinates',
            photo.hasGps ? Fmt.latLng(photo.latitude!, photo.longitude!, settings.coordinateFormat) : 'No GPS data in file',
            muted: !photo.hasGps,
          ),
          _InfoRow(Icons.terrain_outlined, 'Altitude',
              photo.hasGps ? Fmt.altitude(photo.altitude, settings.altitudeUnit) : '—',
              muted: photo.altitude == null),
          _InfoRow(Icons.gps_not_fixed, 'GPS accuracy',
              photo.gpsAccuracy == null ? 'Not recorded' : Fmt.accuracy(photo.gpsAccuracy, settings.distanceUnit),
              muted: photo.gpsAccuracy == null),
          if (d?.detectedAt != null) _InfoRow(Icons.access_time, 'Fix time', Fmt.dateTime(d!.detectedAt!, settings)),
          if (photo.detectedWeather != null)
            _InfoRow(Icons.wb_cloudy_outlined, 'Weather',
                '${photo.detectedWeather!.description}, ${Fmt.temperature(photo.detectedWeather!.temperatureC, settings.temperatureUnit)}'),
        ],
      ),
    );
  }
}

class _ExifCard extends ConsumerWidget {
  const _ExifCard({required this.photo, required this.path, required this.settings});
  final PhotoModel photo;
  final String path;
  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exif = ref.watch(fileExifProvider(path));
    final (label, tone, icon) = switch (photo.exifStatus) {
      ExifStatus.verified => ('Written & verified', ChipTone.success, Icons.verified_outlined),
      ExifStatus.partial => ('Partially written', ChipTone.warning, Icons.warning_amber),
      ExifStatus.failed => ('Write failed', ChipTone.error, Icons.error_outline),
      ExifStatus.unsupported => ('Format not writable', ChipTone.warning, Icons.block),
      ExifStatus.untouched => ('Not edited', ChipTone.neutral, Icons.data_object),
    };
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusChip(label: label, tone: tone, icon: icon),
          if ((photo.exifStatusMessage ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(photo.exifStatusMessage!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 6),
          exif.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => InfoBanner(
              tone: ChipTone.error,
              message: 'Could not read metadata: $e',
              action: TextButton(onPressed: () => ref.invalidate(fileExifProvider(path)), child: const Text('Retry')),
            ),
            data: (m) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(Icons.insert_drive_file_outlined, 'Format',
                    '${m.format?.toUpperCase() ?? 'Unknown'} · ${m.writeSupported ? 'EXIF writable' : 'EXIF read-only'}'),
                _InfoRow(Icons.event, 'DateTimeOriginal',
                    m.dateTimeOriginal == null
                        ? 'Not set'
                        : '${PhotoMetadataModel.formatExifDate(m.dateTimeOriginal!)}${m.offsetTime == null ? '' : ' (${m.offsetTime})'}',
                    muted: m.dateTimeOriginal == null),
                _InfoRow(
                  Icons.my_location,
                  'GPS',
                  m.hasGps
                      ? '${Fmt.latLng(m.latitude!, m.longitude!, settings.coordinateFormat)}'
                          '${m.altitude == null ? '' : '\n${Fmt.altitude(m.altitude, settings.altitudeUnit)}'}'
                      : 'No GPS metadata',
                  muted: !m.hasGps,
                ),
                if (m.gpsDateStamp != null || m.gpsTimeStamp != null)
                  _InfoRow(Icons.public, 'GPS time (UTC)', '${m.gpsDateStamp ?? ''} ${m.gpsTimeStamp ?? ''}'.trim()),
                _InfoRow(Icons.phone_android, 'Camera',
                    [m.make, m.model].whereType<String>().join(' ').trim().isEmpty
                        ? 'Unknown'
                        : [m.make, m.model].whereType<String>().join(' ')),
                if (m.orientation != null) _InfoRow(Icons.screen_rotation_alt, 'Orientation', '${m.orientation}'),
                if (m.artist != null) _InfoRow(Icons.person_outline, 'Artist', m.artist!),
                if (m.copyright != null) _InfoRow(Icons.copyright, 'Copyright', m.copyright!),
                if (m.imageDescription != null) _InfoRow(Icons.notes, 'Description', m.imageDescription!),
                if (m.userComment != null) _InfoRow(Icons.comment_outlined, 'User comment', m.userComment!),
                if (m.rawTags.isNotEmpty)
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text('View all EXIF tags (${m.rawTags.length})'),
                      children: [
                        for (final e in (m.rawTags.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 2, child: Text(e.key, style: Theme.of(context).textTheme.bodySmall)),
                                Expanded(flex: 3, child: SelectableText(e.value, style: Theme.of(context).textTheme.bodySmall)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
