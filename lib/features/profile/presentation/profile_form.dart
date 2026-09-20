import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../design_system/tokens.dart';
import '../../auth/application/auth_providers.dart';
import '../application/profile_providers.dart';
import '../domain/user_profile.dart';

class ProfileForm extends ConsumerStatefulWidget {
  const ProfileForm({required this.profile, super.key});
  final UserProfile profile;

  @override
  ConsumerState<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<ProfileForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _displayName, _givenName, _familyName;
  final _phone = TextEditingController();
  late UserProfile _saved;
  late ProfileVisibility _visibility;
  DateTime? _birthDate;
  bool _busy = false;
  String? _message;
  bool _hasError = false;

  bool get _sameAccount =>
      ref.read(authUserProvider).asData?.value?.id == _saved.userId;

  bool get _dirty =>
      _displayName.text.trim() != _saved.displayName ||
      _givenName.text.trim() != _saved.givenName ||
      _familyName.text.trim() != _saved.familyName ||
      _phone.text.trim() != _saved.phone ||
      _visibility != _saved.visibility ||
      _birthDate != _saved.birthDate;

  @override
  void initState() {
    super.initState();
    _displayName = TextEditingController();
    _givenName = TextEditingController();
    _familyName = TextEditingController();
    _apply(widget.profile);
  }

  @override
  void didUpdateWidget(covariant ProfileForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dirty && !_busy) _apply(widget.profile);
  }

  void _apply(UserProfile profile) {
    _saved = profile;
    _phone.text = profile.phone;
    _displayName.text = profile.displayName;
    _givenName.text = profile.givenName;
    _familyName.text = profile.familyName;
    _visibility = profile.visibility;
    _birthDate = profile.birthDate;
  }

  @override
  void dispose() {
    _phone.dispose();
    _displayName.dispose();
    _givenName.dispose();
    _familyName.dispose();
    super.dispose();
  }

  void _changed() {
    if (_message != null) setState(() => _message = null);
  }

  Future<void> _save() async {
    if (_busy || !_sameAccount || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final input = ProfileInput(
      expectedUserId: _saved.userId,
      displayName: _displayName.text,
      givenName: _givenName.text,
      familyName: _familyName.text,
      visibility: _visibility,
      birthDate: _birthDate,
      profileRevision: _saved.profileRevision,
      privateRevision: _saved.privateRevision,
      phone: _phone.text,
    );
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final saved = await ref.read(profileRepositoryProvider).save(input);
      if (!mounted || !_sameAccount || saved.userId != _saved.userId) return;
      setState(() {
        _apply(saved);
        _hasError = false;
        _message = 'Профиль сохранён';
      });
      ref.read(ownProfileProvider.notifier).accept(saved);
    } on Object catch (error) {
      if (mounted && _sameAccount) {
        setState(() {
          _hasError = true;
          _message = userError(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload() async {
    if (_busy || !_sameAccount) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Загрузить сохранённый профиль?'),
          content: const Text(
            'Несохранённые изменения в этой форме будут заменены данными из аккаунта.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Загрузить'),
            ),
          ],
        ),
      );
      if (!mounted || discard != true || !_sameAccount || _busy) return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final saved = await ref.read(profileRepositoryProvider).read();
      if (!mounted || !_sameAccount || saved.userId != _saved.userId) return;
      setState(() {
        _apply(saved);
        _hasError = false;
        _message = 'Сохранённый профиль загружен';
      });
      ref.read(ownProfileProvider.notifier).accept(saved);
    } on Object catch (error) {
      if (mounted && _sameAccount) {
        setState(() {
          _hasError = true;
          _message = userError(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseDate() async {
    if (_busy || !_sameAccount) return;
    final now = DateTime.now().toUtc();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? today,
      firstDate: DateTime(1900),
      lastDate: today,
      helpText: 'Дата рождения',
      cancelText: 'Отмена',
      confirmText: 'Выбрать',
    );
    if (mounted && _sameAccount && !_busy && picked != null) {
      setState(() {
        _birthDate = picked;
        _message = null;
      });
    }
  }

  String? _nameError(String? value, {bool required = false}) {
    final text = (value ?? '').trim();
    if (required && text.isEmpty) return 'Введите отображаемое имя';
    if (text.runes.length > 100) return 'Не более 100 символов';
    return null;
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    onChanged: _changed,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Профиль', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpace.md),
        TextFormField(
          key: const ValueKey('profile-display-name'),
          controller: _displayName,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Отображаемое имя'),
          validator: (value) => _nameError(value, required: true),
        ),
        const SizedBox(height: AppSpace.sm),
        const Text(
          'Так вас будут узнавать в приложении. Можно использовать короткое имя.',
        ),
        const SizedBox(height: AppSpace.lg),
        Text('Личные данные', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpace.sm),
        const Text(
          'Эти поля доступны только вам через приложение. Их можно оставить пустыми или очистить.',
        ),
        const SizedBox(height: AppSpace.md),
        TextFormField(
          key: const ValueKey('profile-given-name'),
          controller: _givenName,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Имя'),
          validator: _nameError,
        ),
        const SizedBox(height: AppSpace.md),
        TextFormField(
          key: const ValueKey('profile-family-name'),
          controller: _familyName,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Фамилия'),
          validator: _nameError,
        ),
        const SizedBox(height: AppSpace.md),
        Text(
          _birthDate == null
              ? 'Дата рождения не указана'
              : 'Дата рождения: ${MaterialLocalizations.of(context).formatMediumDate(_birthDate!)}',
        ),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _chooseDate,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(
                _birthDate == null ? 'Указать дату' : 'Изменить дату',
              ),
            ),
            if (_birthDate != null)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _birthDate = null;
                        _message = null;
                      }),
                child: const Text('Убрать дату'),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        TextFormField(
          key: const ValueKey('profile-phone'),
          controller: _phone,
          enabled: !_busy,
          keyboardType: TextInputType.phone,
          maxLength: 32,
          decoration: const InputDecoration(labelText: 'Телефон'),
          validator: (v) =>
              v == null ||
                  v.trim().isEmpty ||
                  RegExp(r'^[+0-9 ()-]{5,32}$').hasMatch(v.trim())
              ? null
              : 'Проверьте номер телефона',
        ),
        const SizedBox(height: 16),
        Text('Приватность', style: Theme.of(context).textTheme.titleMedium),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Показывать профиль другим участникам'),
          subtitle: const Text(
            'Участники увидят отображаемое имя. Личные данные останутся закрытыми.',
          ),
          value: _visibility == ProfileVisibility.parish,
          onChanged: _busy
              ? null
              : (value) => setState(() {
                  _visibility = value
                      ? ProfileVisibility.parish
                      : ProfileVisibility.private;
                  _message = null;
                }),
        ),
        const Text(
          'Отображаемое имя также видно администратору, который рассматривает вашу заявку. Отключение видимости не удаляет публикации и сообщения.',
        ),
        const SizedBox(height: AppSpace.lg),
        if (_message != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              _message!,
              style: TextStyle(
                color: _hasError
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Подождите…' : 'Сохранить профиль'),
        ),
        const SizedBox(height: AppSpace.sm),
        OutlinedButton(
          onPressed: _busy ? null : _reload,
          child: const Text('Загрузить сохранённое'),
        ),
      ],
    ),
  );
}
