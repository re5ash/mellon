import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/components/content_frame.dart';
import '../../../design_system/tokens.dart';
import '../application/auth_providers.dart';
import '../application/email_auth_controller.dart';
import '../domain/auth_link.dart';
import '../domain/email_auth_repository.dart';

class AuthEmailFrame extends StatelessWidget {
  const AuthEmailFrame({
    required this.title,
    required this.children,
    super.key,
  });
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SafeArea(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: ContentFrame(
          maxWidth: AppLayout.formMaxWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children
                .expand((child) => [child, const SizedBox(height: AppSpace.md)])
                .toList(),
          ),
        ),
      ),
    ),
  );
}

class EmailFeedback extends ConsumerWidget {
  const EmailFeedback({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(emailAuthControllerProvider);
    final message = state.error ?? state.message;
    if (message == null) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: TextStyle(
          color: state.error == null
              ? null
              : Theme.of(context).colorScheme.error,
        ),
      ),
    );
  }
}

class EmailRequestPage extends ConsumerStatefulWidget {
  const EmailRequestPage({
    required this.purpose,
    this.initialEmail = '',
    super.key,
  });
  final EmailPurpose purpose;
  final String initialEmail;
  @override
  ConsumerState<EmailRequestPage> createState() => _EmailRequestPageState();
}

class _EmailRequestPageState extends ConsumerState<EmailRequestPage> {
  final _emailForm = GlobalKey<FormState>();
  final _codeForm = GlobalKey<FormState>();
  late final TextEditingController _email;
  final _code = TextEditingController();
  Timer? _timer;
  bool _confirmed = false;
  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_emailForm.currentState!.validate()) return;
    final sent = await ref
        .read(emailAuthControllerProvider.notifier)
        .send(_email.text, widget.purpose);
    if (sent && mounted) _code.clear();
  }

  Future<void> _verify() async {
    if (!_emailForm.currentState!.validate() ||
        !_codeForm.currentState!.validate())
      return;
    final verified = await ref
        .read(emailAuthControllerProvider.notifier)
        .verify(purpose: widget.purpose, email: _email.text, code: _code.text);
    if (!mounted || !verified) return;
    _code.clear();
    if (widget.purpose == EmailPurpose.recovery) {
      context.go('/auth/new-password');
    } else {
      ref.invalidate(authUserProvider);
      setState(() => _confirmed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(emailAuthControllerProvider);
    final seconds = ref
        .read(emailAuthControllerProvider.notifier)
        .remainingSeconds;
    final recovery = widget.purpose == EmailPurpose.recovery;
    return AuthEmailFrame(
      title: recovery ? 'Восстановление пароля' : 'Подтверждение почты',
      children: [
        if (_confirmed) ...[
          const Text(
            'Почта подтверждена. Теперь можно открыть молодёжный клуб.',
          ),
          FilledButton(
            onPressed: () => context.go('/my-youth'),
            child: const Text('Продолжить'),
          ),
        ] else ...[
          Text(
            recovery
                ? 'Введите почту своего аккаунта. Мы отправим письмо для установки нового пароля.'
                : 'Введите почту, указанную при регистрации. Если письмо уже пришло, введите код ниже.',
          ),
          Form(
            key: _emailForm,
            child: TextFormField(
              controller: _email,
              enabled: !state.busy,
              autocorrect: false,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Электронная почта'),
              validator: (value) =>
                  RegExp(
                    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                  ).hasMatch(value?.trim() ?? '')
                  ? null
                  : 'Введите адрес почты',
            ),
          ),
          OutlinedButton(
            onPressed: state.busy || seconds > 0
                ? null
                : () => unawaited(_send()),
            child: Text(
              seconds > 0
                  ? 'Отправить повторно через $seconds с'
                  : 'Отправить письмо',
            ),
          ),
          const EmailFeedback(),
          Form(
            key: _codeForm,
            child: TextFormField(
              controller: _code,
              enabled: !state.busy,
              autocorrect: false,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              decoration: const InputDecoration(labelText: 'Код из письма'),
              validator: (value) =>
                  RegExp(r'^\d{6,10}$').hasMatch(value?.trim() ?? '')
                  ? null
                  : 'Введите код из письма (6–10 цифр)',
              onFieldSubmitted: (_) => unawaited(_verify()),
            ),
          ),
          FilledButton(
            onPressed: state.busy ? null : () => unawaited(_verify()),
            child: Text(state.busy ? 'Подождите…' : 'Подтвердить код'),
          ),
          const Text(
            'Используйте последнее полученное письмо. Если срок действия истёк, запросите новое.',
          ),
        ],
        TextButton(
          onPressed: state.busy ? null : () => context.go('/auth'),
          child: const Text('Вернуться ко входу'),
        ),
      ],
    );
  }
}

class EmailLinkPage extends ConsumerStatefulWidget {
  const EmailLinkPage({required this.uri, super.key});
  final Uri uri;
  @override
  ConsumerState<EmailLinkPage> createState() => _EmailLinkPageState();
}

class _EmailLinkPageState extends ConsumerState<EmailLinkPage> {
  Future<void> _verify(AuthLink link) async {
    final verified = await ref
        .read(emailAuthControllerProvider.notifier)
        .verify(purpose: link.purpose, tokenHash: link.tokenHash);
    if (!mounted || !verified) return;
    if (link.purpose == EmailPurpose.confirmation)
      ref.invalidate(authUserProvider);
    // Remove the one-time credential from the current browser history entry.
    Router.neglect(
      context,
      () => context.go(
        link.purpose == EmailPurpose.recovery
            ? '/auth/new-password'
            : '/my-youth',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(emailAuthControllerProvider);
    final link = AuthLink.parse(widget.uri);
    return AuthEmailFrame(
      title: 'Проверка письма',
      children: [
        Text(
          link == null
              ? 'Ссылка недействительна или устарела. Запросите новое письмо.'
              : link.purpose == EmailPurpose.recovery
              ? 'Нажмите кнопку, чтобы подтвердить доступ к почте и установить новый пароль.'
              : 'Нажмите кнопку, чтобы подтвердить вашу электронную почту.',
        ),
        if (link != null)
          FilledButton(
            onPressed: state.busy ? null : () => unawaited(_verify(link)),
            child: Text(state.busy ? 'Проверяем…' : 'Подтвердить'),
          ),
        const EmailFeedback(),
        TextButton(
          onPressed: state.busy
              ? null
              : () {
                  ref
                      .read(emailAuthControllerProvider.notifier)
                      .clearFeedback();
                  Router.neglect(
                    context,
                    () => context.go('/auth/forgot-password'),
                  );
                },
          child: const Text('Получить новое письмо для восстановления'),
        ),
        TextButton(
          onPressed: state.busy
              ? null
              : () {
                  ref
                      .read(emailAuthControllerProvider.notifier)
                      .clearFeedback();
                  Router.neglect(context, () => context.go('/auth/confirm'));
                },
          child: const Text('Повторить подтверждение почты'),
        ),
      ],
    );
  }
}

class NewPasswordPage extends ConsumerStatefulWidget {
  const NewPasswordPage({super.key});
  @override
  ConsumerState<NewPasswordPage> createState() => _NewPasswordPageState();
}

class _NewPasswordPageState extends ConsumerState<NewPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  bool _visible = false;
  bool _saved = false;
  @override
  void dispose() {
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final saved = await ref
        .read(emailAuthControllerProvider.notifier)
        .setPassword(_password.text);
    if (!mounted || !saved) return;
    _password.clear();
    _repeat.clear();
    setState(() => _saved = true);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(emailAuthControllerProvider);
    final allowed = ref
        .read(emailAuthControllerProvider.notifier)
        .canSetPassword;
    return AuthEmailFrame(
      title: 'Новый пароль',
      children: [
        if (_saved) ...[
          const Text(
            'Новый пароль сохранён. Используйте его при следующем входе.',
          ),
          FilledButton(
            onPressed: () => context.go('/my-parish'),
            child: const Text('Открыть приложение'),
          ),
        ] else if (!allowed) ...[
          const Text(
            'Сначала подтвердите доступ по письму. После обновления этой страницы может потребоваться новое письмо.',
          ),
          FilledButton(
            onPressed: state.busy
                ? null
                : () => context.go('/auth/forgot-password'),
            child: const Text('Запросить новое письмо'),
          ),
        ] else ...[
          const Text('Придумайте новый пароль длиной не менее 12 символов.'),
          Form(
            key: _form,
            child: AutofillGroup(
              child: Column(
                children: [
                  TextFormField(
                    controller: _password,
                    enabled: !state.busy,
                    obscureText: !_visible,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'Новый пароль',
                      suffixIcon: IconButton(
                        tooltip: _visible ? 'Скрыть пароль' : 'Показать пароль',
                        onPressed: () => setState(() => _visible = !_visible),
                        icon: Icon(
                          _visible
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                    validator: (value) => (value?.length ?? 0) >= 12
                        ? null
                        : 'Минимум 12 символов',
                  ),
                  const SizedBox(height: AppSpace.md),
                  TextFormField(
                    controller: _repeat,
                    enabled: !state.busy,
                    obscureText: !_visible,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(
                      labelText: 'Повторите новый пароль',
                    ),
                    validator: (value) =>
                        value == _password.text ? null : 'Пароли не совпадают',
                    onFieldSubmitted: (_) => unawaited(_save()),
                  ),
                ],
              ),
            ),
          ),
          FilledButton(
            onPressed: state.busy ? null : () => unawaited(_save()),
            child: Text(state.busy ? 'Сохраняем…' : 'Сохранить новый пароль'),
          ),
        ],
        const EmailFeedback(),
      ],
    );
  }
}
