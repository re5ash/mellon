import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_access.dart';
import '../../../core/errors/app_failure.dart';
import '../../../design_system/components/content_frame.dart';
import '../../../design_system/tokens.dart';
import '../application/auth_controller.dart';
import '../application/email_auth_controller.dart';

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key});
  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _repeatFocus = FocusNode();
  int _inputRevision = 0;
  bool _reconnectingInputs = false;
  bool _register = false;
  bool _visible = false;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _repeat.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _repeatFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reconnectingInputs || ref.read(authControllerProvider).isLoading)
      return;
    ref.read(authControllerProvider.notifier).clearMessage();
    if (!_form.currentState!.validate()) return;
    // Keep the submitted values stable while the user can still edit fields.
    final submittedEmail = _email.text.trim();
    final submittedPassword = _password.text;
    final registering = _register;
    final destination = safeDestination(
      GoRouter.maybeOf(
            context,
          )?.routeInformationProvider.value.uri.queryParameters['from'] ??
          '/my-parish',
    );
    await ref
        .read(authControllerProvider.notifier)
        .submit(
          email: submittedEmail,
          password: submittedPassword,
          register: registering,
        );
    if (!mounted) return;
    final result = ref.read(authControllerProvider);
    if (result.isLoading) return;
    if (result.hasError) {
      _reconnectInputsAfterFailure();
      return;
    }
    if (registering && result.asData?.value != null) {
      ref.read(emailAuthControllerProvider.notifier).noteRegistrationEmail();
      _password.clear();
      _repeat.clear();
      context.go('/auth/confirm', extra: submittedEmail);
    } else {
      context.go(destination);
    }
  }

  void _reconnectInputsAfterFailure() {
    // A web input can have disappeared while Flutter still retains its client.
    // Replacing the field states disposes those clients. Keep the controllers
    // outside the replaced fields so text and selection survive the recovery.
    final target = _emailFocus.hasFocus
        ? _emailFocus
        : _repeatFocus.hasFocus
        ? _repeatFocus
        : _passwordFocus;
    final registering = _register;
    _emailFocus.unfocus();
    _passwordFocus.unfocus();
    _repeatFocus.unfocus();
    setState(() {
      _reconnectingInputs = true;
      _inputRevision++;
    });
    final revision = _inputRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || revision != _inputRevision) return;
      _reconnectingInputs = false;
      if (registering != _register ||
          ModalRoute.of(context)?.isCurrent == false ||
          target.context == null ||
          !target.canRequestFocus) {
        return;
      }
      // Only attach after the old EditableText states have been disposed.
      target.requestFocus();
    });
  }

  void _emailAction(String path) {
    ref.read(emailAuthControllerProvider.notifier).clearFeedback();
    unawaited(context.push<void>(path, extra: _email.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_register ? 'Регистрация' : 'Вход')),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: ContentFrame(
            maxWidth: AppLayout.formMaxWidth,
            child: AutofillGroup(
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Добро пожаловать',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      _register
                          ? 'Создайте аккаунт, чтобы присоединиться к своему приходу.'
                          : 'Войдите, чтобы присоединиться к своему приходу.',
                    ),
                    const SizedBox(height: AppSpace.lg),
                    TextFormField(
                      key: ValueKey('auth-email-$_inputRevision'),
                      controller: _email,
                      focusNode: _emailFocus,
                      selectAllOnFocus: _inputRevision == 0 ? null : false,
                      onChanged: (_) => ref
                          .read(authControllerProvider.notifier)
                          .clearMessage(),
                      autocorrect: false,
                      autofillHints: const [AutofillHints.email],
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Электронная почта',
                      ),
                      validator: (v) =>
                          v != null &&
                              RegExp(
                                r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                              ).hasMatch(v.trim())
                          ? null
                          : 'Введите адрес почты',
                    ),
                    const SizedBox(height: AppSpace.md),
                    TextFormField(
                      key: ValueKey('auth-password-$_inputRevision'),
                      controller: _password,
                      focusNode: _passwordFocus,
                      selectAllOnFocus: _inputRevision == 0 ? null : false,
                      textInputAction: _register
                          ? TextInputAction.next
                          : TextInputAction.done,
                      // Do not detach browser text input when Enter submits.
                      onEditingComplete: () {},
                      onChanged: (_) => ref
                          .read(authControllerProvider.notifier)
                          .clearMessage(),
                      obscureText: !_visible,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: [
                        _register
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      decoration: InputDecoration(
                        labelText: 'Пароль',
                        suffixIcon: IconButton(
                          tooltip: _visible
                              ? 'Скрыть пароль'
                              : 'Показать пароль',
                          onPressed: () => setState(() => _visible = !_visible),
                          icon: Icon(
                            _visible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                      onFieldSubmitted: (_) {
                        if (_register) {
                          _repeatFocus.requestFocus();
                        } else {
                          unawaited(_submit());
                        }
                      },
                      validator: (v) => (v?.length ?? 0) >= (_register ? 12 : 1)
                          ? null
                          : _register
                          ? 'Минимум 12 символов'
                          : 'Введите пароль',
                    ),
                    if (_register) ...[
                      const SizedBox(height: AppSpace.md),
                      TextFormField(
                        key: ValueKey('auth-repeat-$_inputRevision'),
                        controller: _repeat,
                        focusNode: _repeatFocus,
                        selectAllOnFocus: _inputRevision == 0 ? null : false,
                        textInputAction: TextInputAction.done,
                        onEditingComplete: () {},
                        onFieldSubmitted: (_) => unawaited(_submit()),
                        obscureText: !_visible,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: const InputDecoration(
                          labelText: 'Повторите пароль',
                        ),
                        validator: (value) => value == _password.text
                            ? null
                            : 'Пароли не совпадают',
                      ),
                    ],
                    const SizedBox(height: AppSpace.lg),
                    Consumer(
                      builder: (context, ref, child) {
                        final state = ref.watch(authControllerProvider);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // A mouse click on submit belongs to the form's
                            // text-input region, including while disabled.
                            TextFieldTapRegion(
                              child: FilledButton(
                                onPressed: state.isLoading
                                    ? null
                                    : () => unawaited(_submit()),
                                child: Text(
                                  state.isLoading
                                      ? 'Подождите…'
                                      : _register
                                      ? 'Зарегистрироваться'
                                      : 'Войти',
                                ),
                              ),
                            ),
                            if (state.hasError)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpace.md,
                                ),
                                child: Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    userError(state.error!),
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                ),
                              ),
                            if (state.asData?.value != null)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpace.md,
                                ),
                                child: Text(state.asData!.value!),
                              ),
                            TextButton(
                              onPressed: state.isLoading
                                  ? null
                                  : () {
                                      ref
                                          .read(authControllerProvider.notifier)
                                          .clearMessage();
                                      _repeat.clear();
                                      setState(() => _register = !_register);
                                    },
                              child: Text(
                                _register
                                    ? 'Уже есть аккаунт'
                                    : 'Создать аккаунт',
                              ),
                            ),
                            TextButton(
                              onPressed: state.isLoading
                                  ? null
                                  : () => _emailAction('/auth/forgot-password'),
                              child: const Text('Забыли пароль?'),
                            ),
                            TextButton(
                              onPressed: state.isLoading
                                  ? null
                                  : () => _emailAction('/auth/confirm'),
                              child: const Text(
                                'Подтвердить почту / отправить письмо повторно',
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
