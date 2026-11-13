import 'package:flutter/material.dart';

/// Skeleton colours for the current theme (or forced dark, e.g. the camera).
({Color base, Color highlight}) skeletonColors(BuildContext context, {bool forceDark = false}) {
  final dark = forceDark || Theme.of(context).brightness == Brightness.dark;
  return dark
      ? (base: const Color(0xFF1A2540), highlight: const Color(0xFF2A3858))
      : (base: const Color(0xFFE6EBF4), highlight: const Color(0xFFF6F8FC));
}

/// Animates a moving highlight across all [SkeletonBox]es below it.
/// Respects the system "reduce motion" setting (static skeleton).
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child, this.forceDark = false});

  final Widget child;
  final bool forceDark;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = skeletonColors(context, forceDark: widget.forceDark);
    if (MediaQuery.of(context).disableAnimations) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [colors.base, colors.highlight, colors.base],
          stops: const [0.35, 0.5, 0.65],
          transform: _SlideGradient(_c.value),
        ).createShader(bounds),
        child: child,
      ),
    );
  }
}

class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.t);
  final double t;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (t * 2 - 1), 0, 0);
}

/// A placeholder block. Put it inside a [Shimmer] to animate it.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 8, this.forceDark = false});

  final double? width;
  final double height;
  final double radius;
  final bool forceDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: skeletonColors(context, forceDark: forceDark).base,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A line of placeholder text that takes [widthFactor] of the available width.
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({super.key, this.widthFactor = 1, this.height = 12});
  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    alignment: Alignment.centerLeft,
    widthFactor: widthFactor,
    child: SkeletonBox(height: height, radius: height / 2),
  );
}
