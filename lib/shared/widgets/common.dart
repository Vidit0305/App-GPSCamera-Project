import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/theme/colors.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/haptics.dart';
import 'skeleton.dart';

/// Rounded card with consistent padding.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final radius = BorderRadius.circular(20);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? scheme.surface,
        borderRadius: radius,
        border: dark ? Border.all(color: scheme.outlineVariant) : null,
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF0B1B3F).withValues(alpha: 0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: const Color(0xFF0B1B3F).withValues(alpha: 0.03),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: hx(onTap),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.padding = const EdgeInsets.fromLTRB(4, 20, 4, 10)});

  final String title;
  final Widget? action;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          ?action,
        ],
      ),
    );
  }
}

enum ChipTone { neutral, info, success, warning, error }

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, this.icon, this.tone = ChipTone.neutral, this.dense = false});

  final String label;
  final IconData? icon;
  final ChipTone tone;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final s = context.status;
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (tone) {
      ChipTone.neutral => (scheme.surfaceContainerHigh, scheme.onSurfaceVariant),
      ChipTone.info => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      ChipTone.success => (s.successContainer, s.success),
      ChipTone.warning => (s.warningContainer, s.warning),
      ChipTone.error => (s.errorContainer, s.error),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: dense ? 12 : 14, color: fg), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg, fontSize: dense ? 10.5 : 11.5),
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: t.colorScheme.secondaryContainer, shape: BoxShape.circle),
              child: Icon(icon, size: 36, color: t.colorScheme.secondary),
            ),
            const SizedBox(height: 16),
            Text(title, style: t.textTheme.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, style: t.textTheme.bodySmall, textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry, this.title = 'Something went wrong'});

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.error_outline,
      title: title,
      message: message,
      action: onRetry == null
          ? null
          : OutlinedButton.icon(onPressed: hx(onRetry), icon: const Icon(Icons.refresh), label: const Text('Retry')),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[const SizedBox(height: 12), Text(message!)],
        ],
      ),
    );
  }
}

/// Inline banner for warnings / info.
class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.message, this.tone = ChipTone.warning, this.icon, this.action});

  final String message;
  final ChipTone tone;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final s = context.status;
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (tone) {
      ChipTone.success => (s.successContainer, s.success),
      ChipTone.warning => (s.warningContainer, s.warning),
      ChipTone.error => (s.errorContainer, s.error),
      _ => (scheme.secondaryContainer, scheme.onSecondaryContainer),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon ?? Icons.info_outline, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurface)),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// Efficient image tile: uses the generated thumbnail when present and
/// decodes at display size.
class PhotoThumb extends StatelessWidget {
  const PhotoThumb({super.key, required this.path, this.thumbnailPath, this.size = 300, this.fit = BoxFit.cover});

  final String path;
  final String? thumbnailPath;
  final int size;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final file = thumbnailPath != null && File(thumbnailPath!).existsSync() ? thumbnailPath! : path;
    return Image.file(
      File(file),
      fit: fit,
      cacheWidth: (size * dpr).round(),
      gaplessPlayback: true,
      // Skeleton until the image is decoded, then a quick fade-in.
      frameBuilder: (context, child, frame, wasSync) {
        if (wasSync) return child;
        return Stack(
          fit: StackFit.passthrough,
          children: [
            if (frame == null)
              const Shimmer(
                child: SkeletonBox(radius: 0, height: double.infinity, width: double.infinity),
              ),
            AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 220), child: child),
          ],
        );
      },
      errorBuilder: (_, _, _) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: const Center(child: Icon(Icons.broken_image_outlined)),
      ),
    );
  }
}

// ------------------------------------------------------------------ helpers

void showSnack(BuildContext context, String message, {bool error = false, SnackBarAction? action}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.error : null,
      action: action,
      duration: Duration(seconds: error ? 6 : 3),
    ),
  );
}

void showError(BuildContext context, Object error) =>
    showSnack(context, error is AppException ? error.message : '$error', error: true);

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: hx(() => Navigator.pop(ctx, false)), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: AppColors.error) : null,
          onPressed: () {
            destructive ? Haptics.heavy() : Haptics.tap();
            Navigator.pop(ctx, true);
          },
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Shows a modal progress dialog while [task] runs.
Future<T> runWithProgress<T>(BuildContext context, String message, Future<T> Function() task) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(width: 20),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
  try {
    return await task();
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}
