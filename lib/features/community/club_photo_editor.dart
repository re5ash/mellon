import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../core/id/new_uuid.dart';
import '../auth/application/auth_providers.dart';
import 'club_photo_cache.dart';
import 'club_photo_crop.dart';
import 'club_photo_repository.dart';

class ClubPhotoEditor extends ConsumerStatefulWidget {
  const ClubPhotoEditor({
    required this.club,
    required this.actor,
    required this.revision,
    this.path,
    super.key,
  });
  final String club, actor;
  final String? path;
  final int revision;
  @override
  ConsumerState<ClubPhotoEditor> createState() => _ClubPhotoEditorState();
}

class _ClubPhotoEditorState extends ConsumerState<ClubPhotoEditor> {
  ui.Image? _image;
  Offset _center = Offset.zero, _anchor = Offset.zero;
  double _zoom = 1, _startZoom = 1;
  bool _loading = false, _saving = false, _dirty = false, _preview = false;
  String? _error, _uploadPath;
  int _generation = 0;
  bool get _same =>
      mounted && ref.read(authUserProvider).asData?.value?.id == widget.actor;
  Size get _size => Size(_image!.width.toDouble(), _image!.height.toDouble());
  Rect get _crop => clubCropRect(_size, _center, _zoom);
  @override
  void initState() {
    super.initState();
    if (widget.path != null) unawaited(_load(existing: true));
  }

  @override
  void dispose() {
    _generation++;
    _image?.dispose();
    super.dispose();
  }

  Future<void> _load({bool existing = false}) async {
    if (_loading || _saving) return;
    final ticket = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    ui.Image? decoded;
    try {
      final bytes = existing
          ? await ref.read(clubPhotoRepositoryProvider).download(widget.path!)
          : await ref.read(clubPhotoPickerProvider).pick();
      if (bytes == null || !_same || ticket != _generation) return;
      final image = await decodeClubPhoto(bytes);
      decoded = image;
      if (!_same || ticket != _generation) return;
      final old = _image;
      setState(() {
        _image = image;
        _center = Offset(image.width / 2, image.height / 2);
        _zoom = 1;
        _dirty = !existing;
        _preview = false;
        _uploadPath = null;
      });
      decoded = null;
      old?.dispose();
    } on Object {
      if (_same)
        setState(
          () => _error =
              'Не удалось открыть фото. Попробуйте выбрать его ещё раз.',
        );
    } finally {
      decoded?.dispose();
      if (mounted) setState(() => _loading = false);
    }
  }

  void _change(VoidCallback change) => setState(() {
    change();
    _center = _crop.center;
    _dirty = true;
    _uploadPath = null;
  });
  Future<void> _save() async {
    if (_saving || _loading || !_dirty || !_same || _image == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final bytes = await encodeClubCrop(_image!, _crop);
      if (!_same) return;
      _uploadPath ??= '${widget.club}/${widget.actor}/${newUuid()}.png';
      final result = await ref
          .read(clubPhotoRepositoryProvider)
          .save(
            club: widget.club,
            actor: widget.actor,
            path: _uploadPath!,
            revision: widget.revision,
            bytes: bytes,
          )
          .timeout(const Duration(seconds: 30));
      if (!mounted || !_same) return;
      final image = ref
          .read(clubPhotoCacheProvider)
          .put(_uploadPath!, MemoryImage(bytes));
      await precacheImage(image, context);
      if (!mounted || !_same) return;
      Navigator.pop(
        context,
        ClubPhotoSaved(
          path: _uploadPath!,
          revision:
              (result['photo_revision'] as num?)?.toInt() ??
              widget.revision + 1,
        ),
      );
    } on Object catch (error) {
      if (_same) setState(() => _error = userError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final same = ref.watch(authUserProvider).asData?.value?.id == widget.actor;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('Фотография клуба'),
        scrollable: true,
        content: SizedBox(
          width: 560,
          child: !same
              ? const Text('Аккаунт изменился. Откройте редактор заново.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Фото',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Перемещайте изображение и выберите подходящий масштаб.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ClipOval(
                      child: AspectRatio(
                        aspectRatio: clubPhotoAspect,
                        child: _image == null
                            ? ColoredBox(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerLow,
                                child: Center(
                                  child: _loading
                                      ? const CircularProgressIndicator()
                                      : const Icon(
                                          Icons.add_photo_alternate_outlined,
                                          size: 48,
                                        ),
                                ),
                              )
                            : LayoutBuilder(
                                builder: (context, constraints) => GestureDetector(
                                  key: const ValueKey('club-photo-crop'),
                                  onScaleStart: _preview || _saving
                                      ? null
                                      : (details) {
                                          _startZoom = _zoom;
                                          _anchor =
                                              _crop.topLeft +
                                              Offset(
                                                details.localFocalPoint.dx /
                                                    constraints.maxWidth *
                                                    _crop.width,
                                                details.localFocalPoint.dy /
                                                    constraints.maxHeight *
                                                    _crop.height,
                                              );
                                        },
                                  onScaleUpdate: _preview || _saving
                                      ? null
                                      : (details) => _change(() {
                                          _zoom = (_startZoom * details.scale)
                                              .clamp(1, 5)
                                              .toDouble();
                                          final rect = _crop;
                                          _center =
                                              _anchor +
                                              Offset(
                                                (.5 -
                                                        details
                                                                .localFocalPoint
                                                                .dx /
                                                            constraints
                                                                .maxWidth) *
                                                    rect.width,
                                                (.5 -
                                                        details
                                                                .localFocalPoint
                                                                .dy /
                                                            constraints
                                                                .maxHeight) *
                                                    rect.height,
                                              );
                                        }),
                                  child: CustomPaint(
                                    painter: ClubCropPainter(
                                      _image!,
                                      _crop,
                                      grid: !_preview,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      key: const ValueKey('choose-club-photo'),
                      onPressed: _loading || _saving ? null : _load,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(
                        _image == null
                            ? 'Загрузить фото'
                            : 'Выбрать другое фото',
                      ),
                    ),
                    if (_image != null) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Масштаб',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Увеличьте фото ползунком или двумя пальцами.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Slider(
                        key: const ValueKey('club-photo-zoom'),
                        value: _zoom,
                        min: 1,
                        max: 5,
                        onChanged: _saving || _preview
                            ? null
                            : (value) => _change(() => _zoom = value),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Предпросмотр'),
                        subtitle: const Text(
                          'Так фотография будет выглядеть в круглом аватаре.',
                        ),
                        value: _preview,
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _preview = value),
                      ),
                    ],
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const ValueKey('save-club-photo'),
            onPressed: !same || _saving || _loading || !_dirty ? null : _save,
            child: Text(_saving ? 'Сохраняем…' : 'Сохранить'),
          ),
        ],
      ),
    );
  }
}
