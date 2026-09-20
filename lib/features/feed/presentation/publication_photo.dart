import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/publication_photo_cache.dart';

class PublicationPhoto extends ConsumerWidget {
  const PublicationPhoto({required this.path, super.key});
  final String path;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(publicationPhotoImageProvider(path));
    final cache = ref.watch(publicationPhotoCacheProvider);
    final image = cache.peek(path) ?? source.asData?.value;
    final placeholder = ColoredBox(
      key: const ValueKey('publication-photo-placeholder'),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: const SizedBox.expand(),
    );
    Widget retry() => ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Center(
        child: IconButton(
          tooltip: 'Повторить загрузку фото',
          onPressed: () async {
            await cache.remove(path);
            if (context.mounted)
              ref.invalidate(publicationPhotoImageProvider(path));
          },
          icon: const Icon(Icons.refresh),
        ),
      ),
    );
    if (image == null) return source.hasError ? retry() : placeholder;
    return RepaintBoundary(
      child: Image(
        image: image,
        key: ValueKey(path),
        fit: BoxFit.cover,
        filterQuality: FilterQuality.low,
        gaplessPlayback: false,
        excludeFromSemantics: true,
        frameBuilder: (_, child, frame, synchronous) =>
            synchronous || frame != null ? child : placeholder,
        errorBuilder: (_, error, stack) => retry(),
      ),
    );
  }
}
