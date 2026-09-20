import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/access/account_access_provider.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/id/new_uuid.dart';
import '../../../design_system/components/async_content.dart';
import '../../../design_system/tokens.dart';
import '../../community/restricted_guest_card.dart';
import '../application/auth_controller.dart';
import '../application/auth_providers.dart';
import '../application/email_auth_controller.dart';
import '../data/club_registration_repository.dart';
import '../domain/club_registration.dart';
import '../domain/email_auth_repository.dart';
import 'club_welcome_art.dart';

enum ClubRegistrationNext { confirmation, club }

enum _ClubForm { registration, signIn, recovery }

class ClubRegistrationResult {
  const ClubRegistrationResult(this.next, {this.email});
  final ClubRegistrationNext next;
  final String? email;
}

Future<void> openClubRegistration(
  BuildContext context, {
  String? youthId,
  bool startWithSignIn = false,
  bool reviewOnly = false,
}) async {
  final reducedMotion = MediaQuery.disableAnimationsOf(context);
  final result = await showGeneralDialog<ClubRegistrationResult>(
    context: context,
    barrierDismissible: true,
    barrierLabel: reviewOnly ? 'Закрыть окно' : 'Закрыть регистрацию',
    barrierColor: const Color(0xFF132537).withValues(alpha: .28),
    transitionDuration: Duration(milliseconds: reducedMotion ? 0 : 300),
    pageBuilder: (context, animation, secondaryAnimation) =>
        ClubRegistrationDialog(
          youthId: youthId,
          startWithSignIn: startWithSignIn,
          accountOnly: youthId == null,
          reviewOnly: reviewOnly,
        ),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curve = animation.drive(CurveTween(curve: Curves.easeOutCubic));
      return FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, .025),
            end: Offset.zero,
          ).animate(curve),
          child: child,
        ),
      );
    },
  );
  if (!context.mounted || result == null) return;
  switch (result.next) {
    case ClubRegistrationNext.confirmation:
      await context.push<void>('/auth/confirm', extra: result.email);
    case ClubRegistrationNext.club:
      context.go('/my-youth?choose=1');
  }
}

/// Registration starts the joining journey; it never grants membership or roles.
class ClubRegistrationDialog extends ConsumerStatefulWidget {
  const ClubRegistrationDialog({
    super.key,
    this.youthId,
    this.startWithSignIn = false,
    this.accountOnly = false,
    this.reviewOnly = false,
  });
  final bool startWithSignIn, accountOnly, reviewOnly;

  /// The entry point can supply a destination; the form never lists clubs.
  final String? youthId;
  @override
  ConsumerState<ClubRegistrationDialog> createState() =>
      _ClubRegistrationDialogState();
}

class _ClubRegistrationDialogState extends ConsumerState<ClubRegistrationDialog>
    with SingleTickerProviderStateMixin {
  static const _ink = Color(0xFF101F2D);
  static const _muted = Color(0xFF8492A6);
  static const _blue = Color(0xFF529FEC);
  final _form = GlobalKey<FormState>();
  final _sceneKey = GlobalKey();
  final _scroll = ScrollController();
  late final _fade = AnimationController(
    vsync: this,
    value: 1,
    duration: const Duration(milliseconds: 380),
    reverseDuration: const Duration(milliseconds: 260),
  );
  bool _sent = false;
  late _ClubForm _mode;
  String? _reviewUserId;
  @override
  void initState() {
    super.initState();
    _mode = widget.startWithSignIn ? _ClubForm.signIn : _ClubForm.registration;
    if (widget.reviewOnly) {
      _reviewUserId = ref.read(authUserProvider).asData?.value?.id;
    }
  }

  bool get _signIn => _mode == _ClubForm.signIn;
  bool get _recovering => _mode == _ClubForm.recovery;
  Timer? _recoveryTimer;
  String? _recoveryMessage;
  bool _showLoginPassword = false;
  bool _needsEmail = false;
  bool _transitioning = false;
  String? _submittedEmail;
  Object? _receiptIdentity;
  String? _receiptKey;
  double? _lockedHeight;
  final _fields = List.generate(7, (_) => TextEditingController());
  final _focus = List.generate(7, (_) => FocusNode());
  DateTime? _birthDate;
  bool _busy = false;
  bool _showPassword = false;
  bool _showRepeat = false;
  bool _choosingDate = false;
  int _inputRevision = 0;
  bool _reconnectingInputs = false;
  bool _showValidationErrors = false;
  String? _error;

  @override
  void dispose() {
    _recoveryTimer?.cancel();
    _fade.dispose();
    _scroll.dispose();
    for (final controller in _fields) {
      controller.dispose();
    }
    for (final node in _focus) {
      node.dispose();
    }
    super.dispose();
  }

  void _finish(ClubRegistrationResult result) {
    if (mounted && ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop(result);
    }
  }

  Future<void> _pickDate() async {
    if (_choosingDate) return;
    _choosingDate = true;
    final today = DateUtils.dateOnly(DateTime.now());
    final date = await showDatePicker(
      context: context,
      initialDate:
          _birthDate ?? DateTime(today.year - 18, today.month, today.day),
      firstDate: DateTime(1900),
      lastDate: today,
      helpText: 'Дата рождения',
      cancelText: 'Отмена',
      confirmText: 'Выбрать',
    );
    _choosingDate = false;
    if (!mounted || date == null) return;
    setState(() {
      _birthDate = date;
      _fields[2].text =
          '${date.day.toString().padLeft(2, '0')}.'
          '${date.month.toString().padLeft(2, '0')}.${date.year}';
    });
    _focus[3].requestFocus();
  }

  Future<void> _submit() async {
    if (_busy ||
        _sent ||
        _mode != _ClubForm.registration ||
        _transitioning ||
        _reconnectingInputs)
      return;
    final choices = widget.accountOnly
        ? <ClubChoice>[]
        : ref.read(clubChoicesProvider).asData?.value ?? <ClubChoice>[];
    if (!widget.accountOnly) {
      final available = ref.read(clubChoicesProvider);
      if (available.isLoading) {
        _showFormError(
          'Подготавливаем отправку. Подождите немного и нажмите «Продолжить» снова.',
        );
        return;
      }
      if (available.hasError) {
        _showFormError(clubChoicesError(available.error!));
        ref.invalidate(clubChoicesProvider);
        return;
      }

      if (choices.isEmpty) {
        _showFormError('Приём заявок временно недоступен. Попробуйте позже.');
        ref.invalidate(clubChoicesProvider);
        return;
      }
    }
    if (!_form.currentState!.validate()) {
      _showValidationErrors = true;
      _showFormError('Проверьте отмеченные поля выше.');
      return;
    }
    // A sole configured destination remains automatic. With several, use only
    // a destination supplied by the entry point; never pick an arbitrary club.
    final club = widget.accountOnly
        ? null
        : widget.youthId ?? (choices.length == 1 ? choices.single.id : null);
    if (!widget.accountOnly &&
        (club == null || !choices.any((c) => c.id == club))) {
      _showFormError('Приём заявок временно недоступен. Попробуйте позже.');
      return;
    }
    final identity = (
      _fields[3].text.trim(),
      club,
      _fields[0].text.trim(),
      _fields[1].text.trim(),
      _birthDate,
    );
    if (_receiptIdentity != identity) {
      _receiptIdentity = identity;
      _receiptKey = newUuid();
    }
    final registration = ClubRegistration(
      givenName: _fields[0].text.trim(),
      familyName: _fields[1].text.trim(),
      birthDate: _birthDate!,
      email: _fields[3].text.trim(),
      password: _fields[4].text,
      youthId: club,
      receiptKey: _receiptKey!,
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final confirmation = await ref
          .read(clubRegistrationRepositoryProvider)
          .register(registration)
          .timeout(ref.read(authRequestTimeoutProvider));
      if (!mounted) return;
      if (confirmation) {
        ref.read(emailAuthControllerProvider.notifier).noteRegistrationEmail();
      } else {
        ref.invalidate(authUserProvider);
      }
      _submittedEmail = registration.email;
      await _showReceipt(confirmation);
    } on Object catch (error) {
      if (!mounted) return;
      _showFormError(
        error is TimeoutException
            ? 'Ответ задерживается. Проверьте почту: письмо могло уже прийти. Можно войти или повторить регистрацию.'
            : userError(error),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _switchForm(_ClubForm next) async {
    if (_busy ||
        _sent ||
        _transitioning ||
        _reconnectingInputs ||
        _mode == next)
      return;
    final box = _sceneKey.currentContext?.findRenderObject() as RenderBox?;
    setState(() {
      _recoveryTimer?.cancel();
      _lockedHeight ??= box?.size.height;
      _transitioning = true;
    });
    try {
      // Fade only the contents. The scene and the sky's controllers stay mounted.
      if (!MediaQuery.disableAnimationsOf(context))
        await _fade.reverse().orCancel;
      if (!mounted) return;
      for (final node in _focus) {
        node.unfocus();
      }
      if (_scroll.hasClients) _scroll.jumpTo(0);
      ref.read(authControllerProvider.notifier).clearMessage();
      if (next == _ClubForm.recovery) {
        ref.read(emailAuthControllerProvider.notifier).clearFeedback();
      }
      setState(() {
        _mode = next;
        _recoveryMessage = null;
        _error = null;
        _showValidationErrors = false;
        _showPassword = false;
        _showRepeat = false;
        _showLoginPassword = false;
        _inputRevision++;
      });
      if (_recovering) _startRecoveryClock();
      if (MediaQuery.disableAnimationsOf(context)) {
        _fade.value = 1;
      } else {
        await _fade.forward().orCancel;
      }
    } on Object {
      // Dismissing the modal legitimately cancels its animation ticker.
      if (mounted) rethrow;
    } finally {
      if (mounted) setState(() => _transitioning = false);
    }
  }

  Future<void> _submitSignIn() async {
    if (!_signIn || _busy || _sent || _transitioning || _reconnectingInputs)
      return;
    if (ref.read(authControllerProvider).isLoading) return;
    if (!_form.currentState!.validate()) {
      _showValidationErrors = true;
      _showFormError('Проверьте отмеченные поля выше.');
      return;
    }
    final email = _fields[3].text.trim();
    final password = _fields[6].text;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .submit(email: email, password: password, register: false);
      if (!mounted) return;
      final result = ref.read(authControllerProvider);
      if (result.hasError) {
        _showFormError(userError(result.error!));
      } else if (!result.isLoading) {
        for (final index in [4, 5, 6]) {
          _fields[index].clear();
        }
        for (final node in _focus) {
          node.unfocus();
        }
        _finish(const ClubRegistrationResult(ClubRegistrationNext.club));
      }
    } on Object catch (error) {
      if (mounted) _showFormError(userError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startRecoveryClock() {
    _recoveryTimer?.cancel();
    if (!_recovering ||
        ref.read(emailAuthControllerProvider.notifier).remainingSeconds <= 0)
      return;
    _recoveryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || !_recovering) {
        timer.cancel();
        return;
      }
      if (ref.read(emailAuthControllerProvider.notifier).remainingSeconds <= 0)
        timer.cancel();
      setState(() {});
    });
  }

  Future<void> _sendRecovery() async {
    if (!_recovering || _busy || _sent || _transitioning || _reconnectingInputs)
      return;
    final controller = ref.read(emailAuthControllerProvider.notifier);
    if (ref.read(emailAuthControllerProvider).busy ||
        controller.remainingSeconds > 0)
      return;
    if (!_form.currentState!.validate()) {
      _showValidationErrors = true;
      _showFormError('Введите корректный email.');
      return;
    }
    final email = _fields[3].text.trim();
    setState(() {
      _busy = true;
      _error = null;
      _recoveryMessage = null;
    });
    try {
      // The existing controller owns the request and the shared resend limit.
      final request = controller.send(email, EmailPurpose.recovery);
      _startRecoveryClock();
      final sent = await request;
      if (!mounted || !_recovering) return;
      if (sent) {
        setState(() {
          _recoveryMessage =
              'Если для $email доступно восстановление, ссылка придёт на эту почту. Проверьте входящие и «Спам».';
        });
      } else {
        final error = ref.read(emailAuthControllerProvider).error;
        if (error != null) _showFormError(error);
      }
    } on Object catch (error) {
      if (mounted && _recovering) _showFormError(userError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showFormError(String message) {
    // Web input can disappear without notifying Flutter. Recover on local
    // validation/catalogue errors as well as server rejection. Controllers live
    // outside the replaced fields so text and selection survive reconnection.
    final target = _focus.firstWhere(
      (node) => node.hasFocus,
      orElse: () => _focus[_recovering ? 3 : (_signIn ? 6 : 4)],
    );
    for (final node in _focus) {
      node.unfocus();
    }
    setState(() {
      _error = message;
      _busy = false;
      _reconnectingInputs = true;
      _inputRevision++;
    });
    final revision = _inputRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || revision != _inputRevision) return;
      _reconnectingInputs = false;
      if (!_sent &&
          !_choosingDate &&
          ModalRoute.of(context)?.isCurrent == true &&
          target.context != null &&
          target.canRequestFocus) {
        target.requestFocus();
      }
    });
  }

  Future<void> _showReceipt(bool needsEmail) async {
    final box = _sceneKey.currentContext?.findRenderObject() as RenderBox?;
    setState(() {
      _lockedHeight = box?.size.height;
      _transitioning = true;
    });
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (!reducedMotion) await _fade.reverse().orCancel;
    if (!mounted) return;
    for (final node in _focus) {
      node.unfocus();
    }
    _fields[4].clear();
    _fields[5].clear();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    setState(() {
      _sent = true;
      _needsEmail = needsEmail;
    });
    if (!reducedMotion) await _fade.forward().orCancel;
    if (mounted) setState(() => _transitioning = false);
  }

  Widget _receipt(double availableHeight) => ConstrainedBox(
    constraints: BoxConstraints(minHeight: availableHeight),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Container(
              key: const ValueKey('club-application-receipt'),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF7FF),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFD5E9FA)),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.mark_email_read_outlined,
                    size: 36,
                    color: _blue,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.accountOnly
                        ? (_needsEmail
                              ? 'Проверьте почту'
                              : 'Добро пожаловать!')
                        : 'Заявка отправлена',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: AppType.headingFamily,
                      fontSize: 27,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.accountOnly
                        ? 'Проверка нового пользователя'
                        : 'Ждите подтверждения',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    widget.accountOnly
                        ? (_needsEmail
                              ? 'Если регистрация доступна для этой почты, вы получите письмо подтверждения. После подтверждения email заявка поступит на проверку.'
                              : 'Аккаунт создан. До решения по заявке вам доступны общая лента, события, помощь и карта.')
                        : 'Ваша заявка отправлена руководителю. После рассмотрения вы получите уведомление.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.5,
                      color: _muted,
                    ),
                  ),
                  const SizedBox(height: 20),
                  DecoratedBox(
                    decoration: const BoxDecoration(
                      color: Color(0xFFDDEFFC),
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Text(
                        widget.accountOnly
                            ? (_needsEmail
                                  ? 'Ожидается подтверждение email'
                                  : 'Ожидание проверки')
                            : 'Статус: на рассмотрении',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF346D9F),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              if (_needsEmail) ...[
                Text(
                  widget.accountOnly
                      ? 'Уже есть аккаунт? Закройте это окно и нажмите «Войти».'
                      : 'Подтвердите email по ссылке из письма. Это нужно, чтобы руководитель смог принять заявку.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: _muted,
                  ),
                ),
                TextButton(
                  onPressed: _transitioning
                      ? null
                      : () => _finish(
                          ClubRegistrationResult(
                            ClubRegistrationNext.confirmation,
                            email: _submittedEmail,
                          ),
                        ),
                  child: const Text('Подтвердить email'),
                ),
                const SizedBox(height: 12),
              ],
              FilledButton(
                key: const ValueKey('club-receipt-close'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 18,
                  ),
                  backgroundColor: _blue,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                ),
                onPressed: _transitioning
                    ? null
                    : () => widget.accountOnly && !_needsEmail
                          ? _finish(
                              const ClubRegistrationResult(
                                ClubRegistrationNext.club,
                              ),
                            )
                          : Navigator.of(context).pop(),
                child: const Text(
                  'Понятно',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _reviewContents() => Padding(
    key: const ValueKey('club-review-content'),
    padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AsyncContent<AccountAccess>(
          value: ref.watch(accountAccessProvider),
          onRetry: () => ref.read(accountAccessRefreshProvider).value++,
          builder: (access) => AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 250),
            child: access.restrictedGuest
                ? RestrictedGuestCard(
                    key: ValueKey('review-${access.reviewStatus}'),
                  )
                : const Card(
                    key: ValueKey('club-review-approved'),
                    elevation: 0,
                    color: Color(0xFFEAF5EE),
                    child: Padding(
                      padding: EdgeInsets.all(22),
                      child: Column(
                        children: [
                          Icon(Icons.task_alt, color: Color(0xFF34775B)),
                          SizedBox(height: 12),
                          Text(
                            'Проверен',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF34775B),
                            ),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Доступ открыт. Теперь вы можете перейти в молодёжный клуб.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF284A39)),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: FilledButton(
            key: const ValueKey('club-review-close'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              backgroundColor: _blue,
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Понятно',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _field(
    int index,
    String label,
    IconData icon, {
    bool secret = false,
    bool visible = false,
    VoidCallback? toggle,
    String? Function(String?)? validator,
    TextInputType? keyboard,
    Iterable<String>? autofill,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      final labelMeasure = TextPainter(
        text: TextSpan(text: label, style: const TextStyle(fontSize: 17)),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final externalLabel =
          labelMeasure.width > constraints.maxWidth - (secret ? 116 : 76);
      labelMeasure.dispose();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (externalLabel)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 6),
                child: Text(
                  label,
                  style: const TextStyle(color: _muted, fontSize: 15),
                ),
              ),
            Semantics(
              label: externalLabel ? label : null,
              child: TextFormField(
                key: ValueKey('club-field-$index-$_inputRevision'),
                controller: _fields[index],
                focusNode: _focus[index],
                selectAllOnFocus: false,
                readOnly: index == 2,
                onTap: index == 2 && !_busy ? _pickDate : null,
                obscureText: secret && !visible,
                autocorrect: index < 2,
                enableSuggestions: !secret,
                autofillHints: autofill,
                keyboardType: keyboard,
                textCapitalization: index < 2
                    ? TextCapitalization.words
                    : TextCapitalization.none,
                textInputAction: index == (_recovering ? 3 : (_signIn ? 6 : 5))
                    ? TextInputAction.done
                    : TextInputAction.next,
                // Keep the browser editor alive when Enter validates the form.
                onEditingComplete: () {},
                onChanged: (_) {
                  if (_recovering && _recoveryMessage != null) {
                    setState(() => _recoveryMessage = null);
                  }
                },
                onFieldSubmitted: (_) {
                  if (_recovering) {
                    unawaited(_sendRecovery());
                  } else if (_signIn) {
                    if (index == 6) {
                      unawaited(_submitSignIn());
                    } else {
                      _focus[6].requestFocus();
                    }
                  } else if (index == 5) {
                    unawaited(_submit());
                  } else {
                    _focus[index + 1].requestFocus();
                  }
                },
                style: const TextStyle(fontSize: 17, color: _ink),
                decoration: InputDecoration(
                  labelText: externalLabel ? null : label,
                  labelStyle: const TextStyle(color: _muted),
                  floatingLabelStyle: const TextStyle(color: _muted),
                  prefixIcon: Icon(icon, color: _muted, size: 23),
                  suffixIcon: !secret
                      ? null
                      : IconButton(
                          tooltip: visible
                              ? 'Скрыть $label'
                              : 'Показать $label',
                          onPressed: toggle,
                          icon: Icon(
                            visible
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: _muted,
                            size: 22,
                          ),
                        ),
                ),
                validator: validator,
              ),
            ),
          ],
        ),
      );
    },
  );

  String? _nameError(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Заполните поле';
    return text.length > 100 ? 'Не более 100 символов' : null;
  }

  Widget _registrationForm(ThemeData theme) => Form(
    key: _form,
    autovalidateMode: _showValidationErrors
        ? AutovalidateMode.always
        : AutovalidateMode.disabled,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Добро пожаловать!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppType.headingFamily,
            fontWeight: FontWeight.w700,
            fontSize: 30,
            color: _ink,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Зарегистрируйтесь, чтобы стать частью своего прихода.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 17, height: 1.4, color: _muted),
        ),
        const SizedBox(height: 28),
        _field(
          0,
          'Имя',
          Icons.person_outline,
          validator: _nameError,
          autofill: const [AutofillHints.givenName],
        ),
        _field(
          1,
          'Фамилия',
          Icons.person_outline,
          validator: _nameError,
          autofill: const [AutofillHints.familyName],
        ),
        _field(
          2,
          'Дата рождения',
          Icons.calendar_today_outlined,
          validator: (_) => _birthDate == null ? 'Укажите дату рождения' : null,
        ),
        _field(
          3,
          'Email',
          Icons.mail_outline,
          keyboard: TextInputType.emailAddress,
          autofill: const [AutofillHints.email],
          validator: (v) =>
              RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v?.trim() ?? '')
              ? null
              : 'Введите корректный email',
        ),
        _field(
          4,
          'Пароль',
          Icons.lock_outline,
          secret: true,
          visible: _showPassword,
          toggle: () => setState(() => _showPassword = !_showPassword),
          autofill: const [AutofillHints.newPassword],
          validator: (v) =>
              (v?.length ?? 0) >= 12 ? null : 'Минимум 12 символов',
        ),
        _field(
          5,
          'Подтверждение пароля',
          Icons.lock_outline,
          secret: true,
          visible: _showRepeat,
          toggle: () => setState(() => _showRepeat = !_showRepeat),
          autofill: const [AutofillHints.newPassword],
          validator: (v) => v == _fields[4].text ? null : 'Пароли не совпадают',
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ),
        const SizedBox(height: 14),
        TextFieldTapRegion(
          child: FilledButton(
            key: const ValueKey('club-register-submit'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              backgroundColor: _blue,
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
            ),
            onPressed: _busy ? null : _submit,
            child: Row(
              children: [
                const SizedBox(width: 24),
                Expanded(
                  child: Text(
                    _busy ? 'Отправляем…' : 'Продолжить',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(Icons.arrow_forward, size: 24),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Уже есть аккаунт?',
              style: TextStyle(color: _muted, fontSize: 16),
            ),
            TextButton(
              key: const ValueKey('club-show-sign-in'),
              onPressed: _busy || _transitioning
                  ? null
                  : () => _switchForm(_ClubForm.signIn),
              child: const Text('Войти', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _loginForm(ThemeData theme) => Form(
    key: _form,
    autovalidateMode: _showValidationErrors
        ? AutovalidateMode.always
        : AutovalidateMode.disabled,
    child: Column(
      key: const ValueKey('club-sign-in-form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Войти',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppType.headingFamily,
            fontWeight: FontWeight.w700,
            fontSize: 30,
            color: _ink,
          ),
        ),
        const SizedBox(height: 28),
        _field(
          3,
          'Email',
          Icons.mail_outline,
          keyboard: TextInputType.emailAddress,
          autofill: const [AutofillHints.email],
          validator: (value) =>
              RegExp(
                r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
              ).hasMatch(value?.trim() ?? '')
              ? null
              : 'Введите корректный email',
        ),
        _field(
          6,
          'Пароль',
          Icons.lock_outline,
          secret: true,
          visible: _showLoginPassword,
          toggle: () =>
              setState(() => _showLoginPassword = !_showLoginPassword),
          autofill: const [AutofillHints.password],
          validator: (value) =>
              (value?.isNotEmpty ?? false) ? null : 'Введите пароль',
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ),
        const SizedBox(height: 14),
        TextFieldTapRegion(
          child: FilledButton(
            key: const ValueKey('club-sign-in-submit'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              backgroundColor: _blue,
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
            ),
            onPressed: _busy || _transitioning ? null : _submitSignIn,
            child: Text(
              _busy ? 'Входим…' : 'Войти',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('club-forgot-password'),
          onPressed: _busy || _transitioning
              ? null
              : () => _switchForm(_ClubForm.recovery),
          child: const Text('Забыли пароль?', style: TextStyle(fontSize: 16)),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Нет аккаунта?',
              style: TextStyle(color: _muted, fontSize: 16),
            ),
            TextButton(
              key: const ValueKey('club-show-registration'),
              onPressed: _busy || _transitioning
                  ? null
                  : () => _switchForm(_ClubForm.registration),
              child: const Text(
                'Зарегистрироваться',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _recoveryForm(ThemeData theme, EmailAuthState state) {
    final seconds = ref
        .read(emailAuthControllerProvider.notifier)
        .remainingSeconds;
    final sending = _busy || state.busy;
    return Form(
      key: _form,
      autovalidateMode: _showValidationErrors
          ? AutovalidateMode.always
          : AutovalidateMode.disabled,
      child: Column(
        key: const ValueKey('club-recovery-form'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Восстановление пароля',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppType.headingFamily,
              fontWeight: FontWeight.w700,
              fontSize: 30,
              color: _ink,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Укажите email своего аккаунта. Мы отправим ссылку для установки нового пароля.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 16, height: 1.5),
          ),
          const SizedBox(height: 28),
          _field(
            3,
            'Email',
            Icons.mail_outline,
            keyboard: TextInputType.emailAddress,
            autofill: const [AutofillHints.email],
            validator: (value) =>
                RegExp(
                  r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                ).hasMatch(value?.trim() ?? '')
                ? null
                : 'Введите корректный email',
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 12),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ),
          if (_recoveryMessage != null)
            Container(
              key: const ValueKey('club-recovery-feedback'),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF7FF),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _recoveryMessage!,
                  style: const TextStyle(
                    color: Color(0xFF346D9F),
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 14),
          TextFieldTapRegion(
            child: FilledButton(
              key: const ValueKey('club-recovery-submit'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 18,
                ),
                backgroundColor: _blue,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
              ),
              onPressed: sending || _transitioning || seconds > 0
                  ? null
                  : _sendRecovery,
              child: Text(
                sending
                    ? 'Отправляем…'
                    : seconds > 0
                    ? 'Отправить снова через $seconds с'
                    : 'Отправить ссылку',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            key: const ValueKey('club-recovery-back'),
            onPressed: _busy || _transitioning
                ? null
                : () => _switchForm(_ClubForm.signIn),
            child: const Text(
              'Вернуться ко входу',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keep the auto-disposed destination lookup alive without displaying it.
    if (!widget.accountOnly && !widget.reviewOnly)
      ref.watch(clubChoicesProvider);
    if (widget.reviewOnly) {
      ref.listen(authUserProvider, (previous, next) {
        if (next.isLoading || next.asData?.value?.id == _reviewUserId) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && ModalRoute.of(context)?.isCurrent == true) {
            Navigator.of(context).pop();
          }
        });
      });
    }
    final emailState = ref.watch(emailAuthControllerProvider);
    final theme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(seedColor: _blue).copyWith(
        primary: _blue,
        onPrimary: Colors.white,
        surface: Colors.white,
        onSurface: _ink,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF9FBFD),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 20,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(17)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: const BorderSide(color: Color(0xFFE3EAF2), width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(17),
          borderSide: const BorderSide(color: _blue, width: 1.5),
        ),
        errorMaxLines: 3,
      ),
    );
    return Theme(
      data: theme,
      child: SafeArea(
        child: Dialog(
          key: const ValueKey('club-registration-dialog'),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 16,
          ),
          insetAnimationDuration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            key: const ValueKey('club-scene-surface'),
            constraints: const BoxConstraints(maxWidth: 520),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (widget.reviewOnly) {
                  final artHeight = (constraints.maxWidth / 3)
                      .clamp(0.0, constraints.maxHeight * .28)
                      .toDouble();
                  // Shrink to the actual text. Only long content scrolls; the
                  // close button and the continuous sky remain outside it.
                  return AnimatedSize(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 280),
                    curve: Curves.easeInOutCubic,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      child: Stack(
                        children: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                height: artHeight,
                                child: const ClubWelcomeArt(
                                  key: ValueKey('club-scene-background'),
                                ),
                              ),
                              Flexible(
                                child: SingleChildScrollView(
                                  controller: _scroll,
                                  child: _reviewContents(),
                                ),
                              ),
                            ],
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: IconButton(
                              tooltip: 'Закрыть окно',
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(
                                Icons.close_rounded,
                                color: _muted,
                                size: 22,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final height = (_lockedHeight ?? constraints.maxHeight)
                    .clamp(0.0, constraints.maxHeight)
                    .toDouble();
                final artHeight = (constraints.maxWidth / 3)
                    .clamp(0.0, height * .32)
                    .toDouble();
                return SizedBox(
                  key: _sceneKey,
                  width: constraints.maxWidth,
                  height: height,
                  child: Stack(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            height: artHeight,
                            child: const ClubWelcomeArt(
                              key: ValueKey('club-scene-background'),
                            ),
                          ),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, contentConstraints) =>
                                  IgnorePointer(
                                    ignoring: _transitioning,
                                    child: FadeTransition(
                                      key: const ValueKey('club-scene-content'),
                                      opacity: _fade.drive(
                                        CurveTween(curve: Curves.easeInOut),
                                      ),
                                      child: SingleChildScrollView(
                                        controller: _scroll,
                                        keyboardDismissBehavior:
                                            ScrollViewKeyboardDismissBehavior
                                                .onDrag,
                                        child: _sent
                                            ? _receipt(
                                                contentConstraints.maxHeight,
                                              )
                                            : Padding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                      22,
                                                      8,
                                                      22,
                                                      24,
                                                    ),
                                                child: AutofillGroup(
                                                  child: _recovering
                                                      ? _recoveryForm(
                                                          theme,
                                                          emailState,
                                                        )
                                                      : _signIn
                                                      ? _loginForm(theme)
                                                      : _registrationForm(
                                                          theme,
                                                        ),
                                                ),
                                              ),
                                      ),
                                    ),
                                  ),
                            ),
                          ),
                        ],
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: IconButton(
                          tooltip: 'Закрыть регистрацию',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: _muted,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
