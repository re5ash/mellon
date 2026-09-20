import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design_system/mellon_theme.dart';
import 'club_photo_cache.dart';

class ClubPhoto extends ConsumerStatefulWidget {
  const ClubPhoto({
    this.path,
    this.onEdit,
    this.onAddStory,
    this.onViewStories,
    this.hasStories = false,
    this.halo = false,
    super.key,
  });
  final String? path;
  final VoidCallback? onEdit, onAddStory, onViewStories;
  final bool hasStories;
  final bool halo;
  @override
  ConsumerState<ClubPhoto> createState() => _ClubPhotoState();
}

class _ClubPhotoState extends ConsumerState<ClubPhoto> {
  bool _armed = false;
  @override
  void didUpdateWidget(ClubPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onEdit == null || widget.path != oldWidget.path) _armed = false;
  }

  @override
  Widget build(BuildContext context) {
    final editable = widget.onEdit != null;
    final path = widget.path;
    final visible = editable && _armed;
    Widget picture;
    if (path == null) {
      picture = const ClubPhotoPlaceholder();
    } else {
      final state = ref.watch(clubPhotoImageProvider(path));
      final image =
          ref.watch(clubPhotoCacheProvider).peek(path) ?? state.asData?.value;
      picture = image == null
          ? ClubPhotoLoading(
              onRetry: state.hasError
                  ? () => ref.invalidate(clubPhotoImageProvider(path))
                  : null,
            )
          : Image(
              key: ValueKey(path),
              image: image,
              fit: BoxFit.cover,
              gaplessPlayback: false,
              excludeFromSemantics: true,
              frameBuilder: (_, child, frame, synchronous) =>
                  synchronous || frame != null
                  ? child
                  : const ClubPhotoLoading(),
              errorBuilder: (_, error, stack) => ClubPhotoLoading(
                onRetry: () {
                  ref.invalidate(clubPhotoCacheProvider);
                },
              ),
            );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final size = box.maxWidth.clamp(
          MellonThemeStyle.of(context).enabled ? 64.0 : 88.0,
          152.0,
        );
        final duration = MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 200);
        return Center(
          child: SizedBox(
            width: size,
            height: size + (editable ? 48 : 0),
            child: Column(
              children: [
                SizedBox(
                  width: size,
                  height: size,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Semantics(
                        label: widget.hasStories
                            ? 'Смотреть истории клуба'
                            : 'Фотография клуба',
                        button: widget.hasStories,
                        child: GestureDetector(
                          key: const ValueKey('club-story-ring'),
                          onTap: widget.hasStories
                              ? widget.onViewStories
                              : null,
                          child: AnimatedContainer(
                            duration: duration,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: widget.hasStories
                                    ? const Color(0xff2c92d1)
                                    : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (widget.halo)
                        Positioned.fill(
                          left: 5,
                          top: 5,
                          right: 5,
                          bottom: 5,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              key: const ValueKey('club-photo-halo'),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: MellonThemeStyle.of(context).halo,
                                  width: MellonThemeStyle.of(context).haloWidth,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x55fff4d7),
                                    blurRadius: 9,
                                    spreadRadius: 1,
                                  ),
                                  BoxShadow(
                                    color: Color(0x66ffffff),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(7),
                        child: ClipOval(
                          key: const ValueKey('club-photo-circle'),
                          child: GestureDetector(
                            key: const ValueKey('club-photo'),
                            behavior: HitTestBehavior.opaque,
                            onTap: editable
                                ? () {
                                    if (_armed && widget.hasStories) {
                                      widget.onViewStories?.call();
                                      return;
                                    }
                                    setState(() => _armed = !_armed);
                                  }
                                : widget.onViewStories,
                            child: picture,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (editable)
                  SizedBox(
                    height: 48,
                    child: AnimatedOpacity(
                      duration: duration,
                      opacity: visible ? 1 : 0,
                      child: AnimatedSlide(
                        duration: duration,
                        offset: visible ? Offset.zero : const Offset(0, -.2),
                        child: IgnorePointer(
                          ignoring: !visible,
                          child: ExcludeSemantics(
                            excluding: !visible,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton.filledTonal(
                                  key: const ValueKey('edit-club-photo'),
                                  tooltip: 'Изменить фотографию клуба',
                                  onPressed: widget.onEdit,
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 20,
                                  ),
                                ),
                                if (widget.onAddStory != null) ...[
                                  const SizedBox(width: 4),
                                  IconButton.filledTonal(
                                    key: const ValueKey('add-club-story'),
                                    tooltip: 'Добавить историю',
                                    onPressed: widget.onAddStory,
                                    icon: const Icon(Icons.add, size: 22),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class ClubPhotoPlaceholder extends StatelessWidget {
  const ClubPhotoPlaceholder({super.key});
  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Color(0xffe6f3fe),
    child: Center(
      child: Icon(Icons.groups_outlined, color: Color(0xff6097be), size: 48),
    ),
  );
}

class ClubPhotoLoading extends StatelessWidget {
  const ClubPhotoLoading({this.onRetry, super.key});
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xffe6f3fe),
    child: onRetry == null
        ? const SizedBox.expand()
        : Center(
            child: IconButton(
              tooltip: 'Повторить загрузку фотографии',
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ),
  );
}
