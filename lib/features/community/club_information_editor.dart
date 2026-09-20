import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../core/id/new_uuid.dart';
import '../auth/application/auth_providers.dart';
import '../events/application/events_providers.dart';
import '../feed/application/feed_providers.dart';
import '../feed/data/publication_photo_repository.dart';
import '../feed/domain/publication_icon.dart';
import '../feed/presentation/publication_fields.dart';
import '../feed/presentation/publication_photo.dart';
import '../map/application/map_providers.dart';
import '../map/presentation/event_map_field.dart';
import 'club_photo_repository.dart';
import 'community_repository.dart';

class ClubInformationEditor extends ConsumerStatefulWidget {
  const ClubInformationEditor({
    required this.club,
    required this.actor,
    required this.kind,
    this.row,
    super.key,
  });
  final String club, actor, kind;
  final JsonRow? row;
  @override
  ConsumerState<ClubInformationEditor> createState() =>
      _ClubInformationEditorState();
}

class _ClubInformationEditorState extends ConsumerState<ClubInformationEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title, _body, _location;
  late final String _id;
  late DateTime _start, _end;
  late EventMapValue _mapValue;
  bool _busy = false;
  bool _publish = false, _picking = false;
  String? _photoPath, _manualIcon;
  Uint8List? _photoBytes;
  String? _uploadPath;
  PublicationIcon get _icon =>
      publicationIconById(_manualIcon) ??
      suggestPublicationIcon(_title.text, _body.text, seed: _id);
  String? _error;
  bool get _same =>
      mounted && ref.read(authUserProvider).asData?.value?.id == widget.actor;
  @override
  void initState() {
    super.initState();
    _id = widget.row?['id'] as String? ?? newUuid();
    _mapValue = EventMapValue.fromJson(widget.row);
    _publish = widget.row?['publish_to_feed'] == true;
    _photoPath = widget.row?['photo_path'] as String?;
    _manualIcon = widget.row?['icon_manual'] == true
        ? (widget.row?['icon_id'] as String?)
        : null;
    _title = TextEditingController(text: widget.row?['title'] as String? ?? '');
    _body = TextEditingController(
      text: widget.row?['description'] as String? ?? '',
    );
    _location = TextEditingController(
      text: widget.row?['location_label'] as String? ?? '',
    );
    _start =
        DateTime.tryParse(
          widget.row?['starts_at'] as String? ?? '',
        )?.toLocal() ??
        DateTime.now().add(const Duration(days: 1));
    _end =
        DateTime.tryParse(widget.row?['ends_at'] as String? ?? '')?.toLocal() ??
        _start.add(const Duration(hours: 1));
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    if (_busy || _picking || !_same) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final bytes = await ref.read(clubPhotoPickerProvider).pick();
      if (bytes == null || !_same) return;
      final prepared = await ref.read(publicationPhotoProcessorProvider)(bytes);
      if (!_same) return;
      setState(() {
        _photoBytes = prepared;
        _uploadPath = null;
      });
    } on Object catch (_) {
      if (_same)
        setState(
          () => _error =
              'Не удалось открыть фото. Выберите JPG, PNG или другое поддерживаемое изображение.',
        );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _date(bool end) async {
    final value = end ? _end : _start;
    final day = await showDatePicker(
      context: context,
      initialDate: value,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (day == null || !mounted || !_same) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value),
    );
    if (time == null || !_same) return;
    setState(() {
      final date = DateTime(
        day.year,
        day.month,
        day.day,
        time.hour,
        time.minute,
      );
      if (end) {
        _end = date;
      } else {
        _start = date;
        if (!_end.isAfter(_start)) _end = _start.add(const Duration(hours: 1));
      }
    });
  }

  Future<void> _save() async {
    if (_busy || _picking || !_same || !_form.currentState!.validate()) return;
    if (widget.kind != 'help' && !_end.isAfter(_start)) {
      setState(() => _error = 'Окончание должно быть позже начала.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_photoBytes != null && widget.kind != 'help') {
        _uploadPath ??= '${widget.club}/$_id/${newUuid()}.png';
        await ref
            .read(publicationPhotoRepositoryProvider)
            .upload(_uploadPath!, _photoBytes!, widget.actor);
        if (!_same) return;
        _photoPath = _uploadPath;
      }
      await ref
          .read(communityRepositoryProvider)
          .call(
            widget.kind == 'help'
                ? 'save_club_information'
                : 'save_club_publication',
            {
              'p_youth': widget.club,
              'p_id': _id,
              'p_kind': widget.kind,
              'p_expected': widget.row?['updated_at'],
              'p_expected_user': widget.actor,
              'p_data': {
                'title': _title.text.trim(),
                'description': _body.text.trim(),
                if (widget.kind != 'help') ...{
                  'starts_at': _start.toUtc().toIso8601String(),
                  'ends_at': _end.toUtc().toIso8601String(),
                  'location': _location.text.trim(),
                  'publish_to_feed': _publish,
                  'photo_path': _photoPath,
                  'icon_id': _icon.id,
                  'icon_manual': _manualIcon != null,
                  ..._mapValue.payload,
                },
              },
            },
          )
          .timeout(const Duration(seconds: 20));
      if (mounted && _same) {
        ref.invalidate(mapEventsProvider);
        ref.invalidate(feedPageProvider);
        ref.invalidate(eventsProvider);
        ref.invalidate(myParishEventsProvider);
        Navigator.pop(context, true);
      }
    } on Object catch (error) {
      if (_same) setState(() => _error = userError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _label(DateTime value) =>
      '${value.day}.${value.month}.${value.year} · ${TimeOfDay.fromDateTime(value).format(context)}';
  @override
  Widget build(BuildContext context) {
    final same = ref.watch(authUserProvider).asData?.value?.id == widget.actor;
    return PopScope(
      canPop: !_busy && !_picking,
      child: AlertDialog(
        scrollable: true,
        title: Text(
          widget.row != null
              ? 'Редактировать'
              : switch (widget.kind) {
                  'schedule' => 'Добавить расписание',
                  'events' => 'Добавить событие',
                  _ => 'Добавить просьбу о помощи',
                },
        ),
        content: SizedBox(
          width: 520,
          child: !same
              ? const Text('Аккаунт изменился. Откройте редактор заново.')
              : Form(
                  key: _form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.kind != 'help') ...[
                        const ClubFieldLabel(
                          'Фото',
                          'Оформление карточки применяется автоматически.',
                        ),
                        if (_photoBytes != null || _photoPath != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: SizedBox(
                              height: 160,
                              child: _photoBytes != null
                                  ? Image.memory(
                                      _photoBytes!,
                                      fit: BoxFit.cover,
                                    )
                                  : PublicationPhoto(path: _photoPath!),
                            ),
                          ),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              key: const ValueKey('publication-pick-photo'),
                              onPressed: _busy || _picking ? null : _pickPhoto,
                              icon: const Icon(
                                Icons.add_photo_alternate_outlined,
                              ),
                              label: Text(
                                _picking ? 'Готовим фото…' : 'Выбрать фото',
                              ),
                            ),
                            if (_photoBytes != null || _photoPath != null)
                              TextButton(
                                onPressed: _busy || _picking
                                    ? null
                                    : () => setState(() {
                                        _photoBytes = null;
                                        _photoPath = null;
                                        _uploadPath = null;
                                      }),
                                child: const Text('Убрать фото'),
                              ),
                          ],
                        ),
                      ],
                      const ClubFieldLabel(
                        'Название',
                        'Кратко опишите встречу или просьбу.',
                      ),
                      TextFormField(
                        key: const ValueKey('club-information-title'),
                        controller: _title,
                        onChanged: (_) => setState(() {}),
                        readOnly: _busy,
                        maxLength: 200,
                        validator: (value) => (value ?? '').trim().isEmpty
                            ? 'Введите название'
                            : null,
                      ),
                      const ClubFieldLabel(
                        'Описание',
                        'Подробности для участников клуба.',
                      ),
                      TextFormField(
                        key: const ValueKey('club-information-body'),
                        controller: _body,
                        onChanged: (_) => setState(() {}),
                        readOnly: _busy,
                        minLines: 3,
                        maxLines: 8,
                        maxLength: 10000,
                      ),
                      if (widget.kind != 'help') ...[
                        const ClubFieldLabel('Место', 'Где состоится встреча.'),
                        TextFormField(
                          controller: _location,
                          readOnly: _busy,
                          maxLength: 500,
                        ),
                        EventMapField(
                          value: _mapValue,
                          readOnly: _busy,
                          onChanged: (value) =>
                              setState(() => _mapValue = value),
                        ),
                        const ClubFieldLabel('Начало', 'Дата и время начала.'),
                        OutlinedButton(
                          onPressed: _busy ? null : () => _date(false),
                          child: Text(_label(_start)),
                        ),
                        const ClubFieldLabel(
                          'Окончание',
                          'Дата и время завершения.',
                        ),
                        OutlinedButton(
                          onPressed: _busy ? null : () => _date(true),
                          child: Text(_label(_end)),
                        ),
                      ],
                      if (widget.kind != 'help')
                        PublicationFields(
                          published: _publish,
                          icon: _icon,
                          manual: _manualIcon != null,
                          enabled: !_busy && !_picking,
                          onPublished: (value) =>
                              setState(() => _publish = value),
                          onIcon: (value) =>
                              setState(() => _manualIcon = value),
                        ),
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
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const ValueKey('save-club-information'),
            onPressed: !same || _busy || _picking ? null : _save,
            child: Text(_busy ? 'Сохраняем…' : 'Сохранить'),
          ),
        ],
      ),
    );
  }
}

class ClubFieldLabel extends StatelessWidget {
  const ClubFieldLabel(this.title, this.hint, {super.key});
  final String title, hint;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 3),
        Text(
          hint,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}
