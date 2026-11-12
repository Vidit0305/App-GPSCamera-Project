import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../app/theme/colors.dart';
import '../../../core/permissions/permission_flows.dart';
import '../../../data/models/photo_model.dart';
import '../../../shared/widgets/common.dart';
import '../../location/services/location_controller.dart';
import '../../location/services/location_service.dart';
import '../widgets/location_status_card.dart';

/// The app's single main screen.
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
    await ref.read(locationControllerProvider.notifier).start();
    if (!mounted) return;
    if (!ref.read(settingsProvider).onboardingDone) {
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

  void _toggleTheme() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(themeMode: isDark ? ThemeMode.light : ThemeMode.dark));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final online = ref.watch(isOnlineProvider);
    final photos = ref.watch(photosProvider);

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(locationControllerProvider.notifier).restart(),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                sliver: SliverList.list(children: [
                  // Header: logo + name, theme toggle on the right.
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset('assets/icon/app_icon.png', width: 42, height: 42, cacheWidth: 126),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text('GPS Camera', style: theme.textTheme.titleLarge)),
                      IconButton.filledTonal(
                        tooltip: isDark ? 'Switch to light theme' : 'Switch to dark theme',
                        onPressed: _toggleTheme,
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          transitionBuilder: (child, a) => RotationTransition(turns: a, child: child),
                          child: Icon(
                            isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                            key: ValueKey(isDark),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (!online) ...[
                    const InfoBanner(
                      message: 'You are offline. Taking and editing photos still works.',
                      tone: ChipTone.info,
                      icon: Icons.cloud_off,
                    ),
                    const SizedBox(height: 12),
                  ],
                  const _CameraCard(),
                  const SizedBox(height: 16),
                  const LocationStatusCard(),
                  const SectionHeader('Your photos'),
                ]),
              ),
              ...photos.when(
                loading: () => [const SliverToBoxAdapter(child: SizedBox(height: 120, child: LoadingView()))],
                error: (e, _) => [
                  SliverToBoxAdapter(
                    child: Padding(padding: const EdgeInsets.all(16), child: Text('Could not load photos: $e')),
                  ),
                ],
                data: (list) => list.isEmpty
                    ? [
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
                            child: AppCard(
                              child: Row(children: [
                                Icon(Icons.photo_outlined),
                                SizedBox(width: 12),
                                Expanded(child: Text('No photos yet. Tap Capture to take your first GPS photo.')),
                              ]),
                            ),
                          ),
                        ),
                      ]
                    : [_PhotoGrid(photos: [...list]..sort((a, b) => b.createdAt.compareTo(a.createdAt)))],
              ),
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
          Text('Take a Photo', style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white)),
          const SizedBox(height: 6),
          Text(
            'Your location, coordinates and time are stamped on the photo automatically.',
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
              icon: const Icon(Icons.photo_camera),
              label: const Text('Capture'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({required this.photos});
  final List<PhotoModel> photos;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      sliver: SliverGrid.builder(
        itemCount: photos.length,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 160,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemBuilder: (context, i) {
          final p = photos[i];
          return GestureDetector(
            onTap: () => context.push(Routes.editor(p.id)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PhotoThumb(path: p.displayPath, thumbnailPath: p.thumbnailPath, size: 160),
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
          );
        },
      ),
    );
  }
}
