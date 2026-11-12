import 'package:flutter/material.dart';

import '../../../data/models/photo_model.dart';
import '../../../shared/widgets/common.dart';

/// Grid tile with stamp / GPS badges and a selection overlay.
class PhotoGridTile extends StatelessWidget {
  const PhotoGridTile({
    super.key,
    required this.photo,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
    this.selecting = false,
    this.size = 200,
  });

  final PhotoModel photo;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool selecting;
  final int size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            PhotoThumb(path: photo.displayPath, thumbnailPath: photo.thumbnailPath, size: size),
            Positioned(
              left: 4,
              bottom: 4,
              child: Row(
                children: [
                  if (photo.hasVisibleStamp) const _Badge(icon: Icons.approval_outlined, tooltip: 'Visible stamp'),
                  if (photo.hasGps) const _Badge(icon: Icons.location_on, tooltip: 'GPS metadata'),
                  if (photo.addressPending) const _Badge(icon: Icons.cloud_off_outlined, tooltip: 'Address pending'),
                ],
              ),
            ),
            if (selecting)
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                color: selected ? scheme.secondary.withValues(alpha: 0.28) : Colors.transparent,
                alignment: Alignment.topRight,
                padding: const EdgeInsets.all(6),
                child: Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: selected ? Colors.white : Colors.white70,
                  shadows: const [Shadow(blurRadius: 4)],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.tooltip});
  final IconData icon;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        margin: const EdgeInsets.only(right: 3),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
        child: Icon(icon, size: 12, color: Colors.white),
      ),
    );
  }
}
