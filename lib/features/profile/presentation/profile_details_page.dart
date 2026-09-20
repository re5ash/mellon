import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/backend/backend_provider.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/id/new_uuid.dart';
import '../../../design_system/components/async_content.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/presentation/club_registration_dialog.dart';
import '../../community/community_widgets.dart';
import '../application/profile_providers.dart';
import '../domain/user_profile.dart';
import 'profile_form.dart';

class ProfileDetailsPage extends ConsumerWidget {
  const ProfileDetailsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => CommunityScaffold(
    title: 'Профиль',
    protectSession: false,
    children: [
      AsyncContent<UserProfile?>(
        value: ref.watch(ownProfileProvider),
        preserveOnRefresh: true,
        onRetry: () => ref.invalidate(ownProfileProvider),
        builder: (p) =>
            p == null ||
                p.userId != ref.watch(authUserProvider).asData?.value?.id
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Войдите в аккаунт, чтобы открыть профиль.'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () =>
                        openClubRegistration(context, startWithSignIn: true),
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Войти'),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ProfileAvatar(
                    key: ValueKey((p.userId, p.avatarPath)),
                    profile: p,
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: ProfileForm(key: ValueKey(p.userId), profile: p),
                    ),
                  ),
                  CommunityTile(
                    title: 'Email',
                    subtitle: p.email.isEmpty ? 'Не указан' : p.email,
                    icon: Icons.alternate_email,
                    onTap: () =>
                        openCommunity(context, EmailChangePage(profile: p)),
                  ),
                  CommunityTile(
                    title: 'Молодёжные клубы',
                    subtitle: p.youthName ?? 'Вы пока не вступили в клуб',
                    icon: Icons.groups_rounded,
                  ),
                ],
              ),
      ),
    ],
  );
}

class ProfileAvatar extends ConsumerStatefulWidget {
  const ProfileAvatar({required this.profile, super.key});
  final UserProfile profile;
  @override
  ConsumerState<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends ConsumerState<ProfileAvatar> {
  String? _url, _error;
  bool _busy = false;
  bool get _same =>
      mounted &&
      ref.read(authUserProvider).asData?.value?.id == widget.profile.userId;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final path = widget.profile.avatarPath;
    if (path == null) return;
    try {
      final url = await ref
          .read(backendProvider)
          .storage
          .from('profile-avatars')
          .createSignedUrl(path, 3600);
      if (_same) setState(() => _url = url);
    } on Object catch (e) {
      if (_same) setState(() => _error = userError(e));
    }
  }

  Future<void> _change({bool remove = false}) async {
    if (_busy || !_same) return;
    if (remove &&
        !await confirmAction(
          context,
          'Удалить фото?',
          'Вместо фотографии будет показана иконка профиля.',
        ))
      return;
    if (!mounted || !_same) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final client = ref.read(backendProvider);
      String? path;
      if (!remove) {
        final file = await openFile(
          acceptedTypeGroups: [
            const XTypeGroup(
              label: 'Фото',
              extensions: ['jpg', 'jpeg', 'png', 'webp'],
              mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
              uniformTypeIdentifiers: [
                'public.jpeg',
                'public.png',
                'org.webmproject.webp',
              ],
            ),
          ],
        );
        if (file == null || !_same) return;
        if (await file.length() > 5242880)
          throw StateError('Фото должно быть не больше 5 МБ.');
        final bytes = await file.readAsBytes();
        if (bytes.length < 12) throw StateError('Не удалось прочитать фото.');
        final jpeg = bytes[0] == 255 && bytes[1] == 216 && bytes[2] == 255;
        final png =
            bytes[0] == 137 &&
            bytes[1] == 80 &&
            bytes[2] == 78 &&
            bytes[3] == 71;
        final webp =
            String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
            String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP';
        if (!jpeg && !png && !webp)
          throw StateError('Выберите фото JPG, PNG или WebP.');
        if (!_same) return;
        final extension = jpeg
            ? 'jpg'
            : png
            ? 'png'
            : 'webp';
        path = '${widget.profile.userId}/${newUuid()}.$extension';
        await client.storage
            .from('profile-avatars')
            .uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(
                contentType: jpeg
                    ? 'image/jpeg'
                    : png
                    ? 'image/png'
                    : 'image/webp',
              ),
            );
      }
      if (!_same) return;
      final saved = UserProfile.fromJson(
        await client.rpc<Map<String, dynamic>>(
          'set_profile_avatar',
          params: {
            'p_path': path,
            'p_revision': widget.profile.profileRevision,
            'p_expected_user': widget.profile.userId,
          },
        ),
      );
      if (!_same) return;
      ref.read(ownProfileProvider.notifier).accept(saved);
      // Unlink first; a lost RPC response must never delete a possibly committed photo.
      final old = widget.profile.avatarPath;
      if (old != null && old != path) {
        try {
          await client.storage.from('profile-avatars').remove([old]);
        } on Object {
          /* Unlinked object may be cleaned up later. */
        }
      }
    } on Object catch (e) {
      if (_same)
        setState(
          () => _error = e is StateError ? e.message.toString() : userError(e),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            child: CircleAvatar(
              key: ValueKey(_url),
              radius: 52,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: _url == null
                  ? Icon(
                      Icons.person_rounded,
                      size: 52,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : ClipOval(
                      child: Image.network(
                        _url!,
                        width: 104,
                        height: 104,
                        fit: BoxFit.cover,
                        errorBuilder: (_, error, stack) =>
                            const Icon(Icons.person_rounded, size: 52),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _change(),
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text(
                  widget.profile.avatarPath == null
                      ? 'Добавить фото'
                      : 'Заменить фото',
                ),
              ),
              if (widget.profile.avatarPath != null)
                TextButton(
                  onPressed: _busy ? null : () => _change(remove: true),
                  child: const Text('Удалить фото'),
                ),
            ],
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
        ],
      ),
    ),
  );
}

class EmailChangePage extends ConsumerStatefulWidget {
  const EmailChangePage({required this.profile, super.key});
  final UserProfile profile;
  @override
  ConsumerState<EmailChangePage> createState() => _EmailChangePageState();
}

class _EmailChangePageState extends ConsumerState<EmailChangePage> {
  final _email = TextEditingController();
  bool _busy = false;
  String? _message;
  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy ||
        ref.read(authUserProvider).asData?.value?.id != widget.profile.userId)
      return;
    final email = _email.text.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _message = 'Введите корректный Email.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(backendProvider)
          .auth
          .updateUser(UserAttributes(email: email));
      if (mounted)
        setState(
          () => _message =
              'Подтвердите смену почты по письмам Supabase. При включённой безопасной смене нужно подтверждение и на старой, и на новой почте.',
        );
      ref.invalidate(ownProfileProvider);
    } on Object catch (e) {
      if (mounted) setState(() => _message = userError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => CommunityScaffold(
    title: 'Изменить Email',
    children: [
      Text('Текущий Email: ${widget.profile.email}'),
      const SizedBox(height: 16),
      TextField(
        controller: _email,
        enabled: !_busy,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        decoration: const InputDecoration(labelText: 'Новый Email'),
      ),
      const SizedBox(height: 16),
      if (_message != null) Text(_message!),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: const Text('Отправить подтверждение'),
      ),
    ],
  );
}
