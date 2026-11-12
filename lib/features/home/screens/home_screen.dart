import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../app/theme/colors.dart';
import '../../../core/permissions/permission_flows.dart';
import '../../../data/models/location_model.dart';
import '../../../shared/widgets/common.dart';
import '../../location/services/location_controller.dart';
import '../../location/services/location_service.dart';
import '../widgets/location_status_card.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _firstRun());
  }

  /// Starts location and, on first launch, asks for permission and consent.
  Future<void> _firstRun() async {
    final ctrl = ref.read(locationControllerProvider.notifier);
    await ctrl.start();
    if (!mounted) return;
    final settings = ref.read(settingsProvider);
    if (!settings.onboardingDone) {
      await ref.read(settingsProvider.notifier).update((s) => s.copyWith(onboardingDone: true));
      if (!mounted) return;
      final perm = ref.read(locationControllerProvider).permission;
      if (perm == LocationPermissionState.denied || perm == LocationPermissionState.unknown) {
        await ensureLocationPermission(context, ref);
      }
      if (!mounted) return;
      if (ref.read(settingsProvider).onlineConsent == null) await requestOnlineConsent(context, ref);
    }
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final online = ref.watch(isOnlineProvider);
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(locationControllerProvider.notifier).restart(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppColors.navy, AppColors.royal]),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.photo_camera_outlined, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('GPS Camera', style: theme.textTheme.titleLarge),
                        Text(_greeting, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Settings',
                    onPressed: () => context.go(Routes.settings),
                    icon: const Icon(Icons.tune),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (!online) ...[
                const InfoBanner(
                  message: 'You are offline. Camera, GPS coordinates, stamps and EXIF editing all keep working.',
                  tone: ChipTone.info,
                  icon: Icons.cloud_off,
                ),
                const SizedBox(height: 12),
              ],
              const _CameraCard(),
              const SizedBox(height: 16),
              const LocationStatusCard(),
              const SectionHeader('Quick actions'),
              const _QuickActions(),
              const _RecentPhotos(),
            ],
          ),
        ),
      ),
    );
  }
}

class _CameraCard extends StatelessWidget {
  const _CameraCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navy, Color(0xFF173A7A), AppColors.royal],
        ),
        boxShadow: [
          BoxShadow(color: AppColors.navy.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.photo_camera, color: Colors.white, size: 28),
              ),
              const Spacer(),
              Icon(Icons.gps_fixed, color: Colors.white.withValues(alpha: 0.6)),
            ],
          ),
          const SizedBox(height: 18),
          Text('Take a Photo', style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white)),
          const SizedBox(height: 6),
          Text(
            'Capture photos stamped with location, coordinates, altitude and time — with real EXIF GPS metadata.',
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.navy,
                textStyle: theme.textTheme.titleMedium,
              ),
              onPressed: () => context.push(Routes.camera),
              icon: const Icon(Icons.camera),
              label: const Text('Capture'),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = <(IconData, String, String, VoidCallback)>[
      (Icons.photo_library_outlined, 'Open Gallery', 'Browse & manage photos', () => context.go(Routes.gallery)),
      (Icons.data_object, 'Edit EXIF Metadata', 'Real metadata in files', () => context.push(Routes.pick('exif'))),
      (Icons.dashboard_customize_outlined, 'Manage Templates', 'Stamp designs', () => context.go(Routes.templates)),
      (
        Icons.edit_location_alt_outlined,
        'Select Location',
        'Pick a place on the map',
        () async {
          final initial = ref.read(locationControllerProvider).display;
          final picked = await context.push<LocationModel>(Routes.mapLocation, extra: initial);
          if (picked != null) {
            await ref.read(locationControllerProvider.notifier).setManual(picked);
            if (context.mounted) showSnack(context, 'Manual location will be used for new photos.');
          }
        }
      ),
      (Icons.library_add_check_outlined, 'Batch Edit Photos', 'Edit many at once', () => context.push(Routes.batch)),
    ];
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth > 600 ? 3 : 2;
      final w = (c.maxWidth - 12 * (cols - 1)) / cols;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final (icon, title, sub, onTap) in actions)
            SizedBox(
              width: w,
              child: AppCard(
                onTap: onTap,
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: Theme.of(context).colorScheme.secondary, size: 22),
                    ),
                    const SizedBox(height: 10),
                    Text(title, style: Theme.of(context).textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(sub, style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }
}

class _RecentPhotos extends ConsumerWidget {
  const _RecentPhotos();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = ref.watch(photosProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Recent photos',
          action: TextButton(onPressed: () => context.go(Routes.gallery), child: const Text('See all')),
        ),
        photos.when(
          loading: () => const SizedBox(height: 120, child: LoadingView()),
          error: (e, _) => AppCard(child: Text('Could not load photos: $e')),
          data: (list) {
            if (list.isEmpty) {
              return const AppCard(
                child: Row(children: [
                  Icon(Icons.photo_outlined),
                  SizedBox(width: 12),
                  Expanded(child: Text('No photos yet. Tap Capture to take your first GPS photo.')),
                ]),
              );
            }
            final recent = [...list]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
            final items = recent.take(12).toList();
            return SizedBox(
              height: 120,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final p = items[i];
                  return GestureDetector(
                    onTap: () => context.push(Routes.photo(p.id)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 120,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            PhotoThumb(path: p.displayPath, thumbnailPath: p.thumbnailPath, size: 120),
                            if (p.city != null)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [Colors.transparent, Colors.black54],
                                    ),
                                  ),
                                  child: Text(
                                    p.city!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}
