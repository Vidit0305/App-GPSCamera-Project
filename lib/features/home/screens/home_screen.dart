import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/router.dart';
import '../../../app/theme/colors.dart';
import '../../../core/permissions/permission_flows.dart';
import '../../../core/utils/haptics.dart';
import '../../../data/models/photo_model.dart';
import '../../../shared/widgets/common.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../location/services/location_controller.dart';
import '../../location/services/location_service.dart';
import '../../photo_editor/services/photo_service.dart';
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

  Future<void> _clearAll(int count) async {
    if (count == 0) {
      showSnack(context, 'There are no photos to clear.');
      return;
    }
    final ok = await confirm(
      context,
      title: 'Are you sure?',
      message:
          'This will permanently delete all $count photo${count == 1 ? '' : 's'} from GPS Camera. '
          'This cannot be undone.\n\nCopies already saved to your phone\'s gallery are not affected.',
      confirmLabel: 'OK',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      final n = await ref.read(photoServiceProvider).deleteAll();
      if (mounted) showSnack(context, 'Deleted $n photo${n == 1 ? '' : 's'}.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final online = ref.watch(isOnlineProvider);
    final photos = ref.watch(photosProvider);
    final count = photos.value?.length ?? 0;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => ref.read(locationControllerProvider.notifier).restart(),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                sliver: SliverList.list(
                  children: [
                    // ---------------------------------------------- header
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: Image.asset('assets/icon/app_icon.png', width: 44, height: 44, cacheWidth: 132),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('GPS Camera', style: theme.textTheme.titleLarge),
                              Text(DateFormat('EEEE, d MMMM').format(DateTime.now()), style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ),
                        _RoundIconButton(
                          tooltip: isDark ? 'Light theme' : 'Dark theme',
                          onPressed: _toggleTheme,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder: (child, a) => RotationTransition(
                              turns: Tween(begin: 0.5, end: 1.0).animate(a),
                              child: FadeTransition(opacity: a, child: child),
                            ),
                            child: Icon(
                              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                              key: ValueKey(isDark),
                              color: isDark ? const Color(0xFFFFC94D) : AppColors.navy,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (!online) ...[
                      const InfoBanner(
                        message: 'You\'re offline. Taking and editing photos still works.',
                        tone: ChipTone.info,
                        icon: Icons.cloud_off_rounded,
                      ),
                      const SizedBox(height: 14),
                    ],
                    const _CameraHero(),
                    const SizedBox(height: 16),
                    const LocationStatusCard(),
                    const SizedBox(height: 16),
                    // ---------------------------------------------- clear history
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.error,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () {
                          Haptics.heavy();
                          _clearAll(count);
                        },
                        icon: const Icon(Icons.delete_sweep_rounded),
                        label: const Text('Clear all photos'),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Text('Your photos', style: theme.textTheme.titleMedium),
                        const SizedBox(width: 8),
                        if (count > 0) StatusChip(label: '$count', tone: ChipTone.info, dense: true),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              ...photos.when(
                loading: () => [const _PhotoGridSkeleton()],
                error: (e, _) => [
                  SliverToBoxAdapter(
                    child: Padding(padding: const EdgeInsets.all(20), child: Text('Could not load photos: $e')),
                  ),
                ],
                data: (list) => list.isEmpty
                    ? [const SliverToBoxAdapter(child: _EmptyPhotos())]
                    : [
                        _PhotoGrid(photos: [...list]..sort((a, b) => b.createdAt.compareTo(a.createdAt))),
                      ],
              ),
              SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 24)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.onPressed, required this.child, required this.tooltip});
  final VoidCallback onPressed;
  final Widget child;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: scheme.surface,
        shape: CircleBorder(side: BorderSide(color: scheme.outlineVariant)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: hx(onPressed),
          child: Padding(padding: const EdgeInsets.all(11), child: child),
        ),
      ),
    );
  }
}

class _CameraHero extends StatelessWidget {
  const _CameraHero();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navy, AppColors.navyLight, AppColors.royal],
          stops: [0, 0.5, 1],
        ),
        boxShadow: [
          BoxShadow(color: AppColors.royal.withValues(alpha: 0.28), blurRadius: 28, offset: const Offset(0, 12)),
        ],
      ),
      child: Stack(
        children: [
          // Decorative rings, echoing the app icon.
          Positioned(
            right: -60,
            top: -60,
            child: CustomPaint(size: const Size(220, 220), painter: _RingsPainter()),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.photo_camera_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(height: 16),
                Text('Take a photo', style: theme.textTheme.headlineSmall?.copyWith(color: Colors.white)),
                const SizedBox(height: 6),
                Text(
                  'Location, coordinates and time are stamped on your photo automatically.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.78)),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.navy,
                      textStyle: theme.textTheme.titleMedium,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: hx(() => context.push(Routes.camera)),
                    icon: const Icon(Icons.camera_rounded),
                    label: const Text('Open camera'),
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

class _RingsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.08);
    for (var i = 1; i <= 4; i++) {
      canvas.drawCircle(size.center(Offset.zero), 26.0 * i, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _EmptyPhotos extends StatelessWidget {
  const _EmptyPhotos();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: AppCard(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        child: Column(
          children: [
            Icon(Icons.photo_library_outlined, size: 36, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 10),
            Text('No photos yet', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text('Your GPS photos will appear here.', style: theme.textTheme.bodySmall),
          ],
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid.builder(
        itemCount: photos.length,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 170,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
        ),
        itemBuilder: (context, i) {
          final p = photos[i];
          return GestureDetector(
            onTap: hx(() => context.push(Routes.editor(p.id))),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PhotoThumb(path: p.displayPath, thumbnailPath: p.thumbnailPath, size: 170),
                  if (p.city != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(8, 18, 8, 7),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black54],
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.location_on_rounded, size: 12, color: Colors.white),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                p.city!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
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

/// Placeholder tiles while the photo list loads.
class _PhotoGridSkeleton extends StatelessWidget {
  const _PhotoGridSkeleton();

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverToBoxAdapter(
        child: Shimmer(
          child: LayoutBuilder(
            builder: (context, c) {
              final cols = (c.maxWidth / 170).ceil().clamp(2, 6);
              final w = (c.maxWidth - 10 * (cols - 1)) / cols;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [for (var i = 0; i < cols * 2; i++) SkeletonBox(width: w, height: w, radius: 16)],
              );
            },
          ),
        ),
      ),
    );
  }
}
