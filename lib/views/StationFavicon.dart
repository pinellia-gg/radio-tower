import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A consistent cached favicon for station lists and player views.
class StationFavicon extends StatelessWidget {
  const StationFavicon({
    required this.imageUrl,
    required this.size,
    super.key,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
    this.fallbackIconSize,
  });

  final String imageUrl;
  final double size;
  final BorderRadiusGeometry borderRadius;
  final double? fallbackIconSize;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final normalizedImageUrl = imageUrl.trim();
    final fallback = Center(
      child: Icon(
        Icons.radio,
        size: fallbackIconSize ?? size * 0.55,
        color: colorScheme.onSurfaceVariant,
      ),
    );

    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: size,
        height: size,
        child: ColoredBox(
          color: colorScheme.surfaceContainerHighest,
          child:
              normalizedImageUrl.isEmpty
                  ? fallback
                  : CachedNetworkImage(
                    imageUrl: normalizedImageUrl,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    fadeInDuration: Duration.zero,
                    placeholder: (_, _) => fallback,
                    errorWidget: (_, _, _) => fallback,
                  ),
        ),
      ),
    );
  }
}
