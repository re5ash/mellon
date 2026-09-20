import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/access/account_access_provider.dart';
import '../../design_system/tokens.dart';
import 'review_hourglass.dart';

class RestrictedGuestCard extends ConsumerWidget {
  const RestrictedGuestCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(accountAccessProvider).asData?.value;
    final verified = access?.reviewed == true;
    final pending = access?.awaitingReview == true;
    final awaitingEmail = access?.reviewStatus == 'awaiting_email';
    final accent = verified ? const Color(0xFF34775B) : const Color(0xFF52799D);
    final label = verified
        ? 'Проверен'
        : awaitingEmail
        ? 'Подтвердите email'
        : pending
        ? 'Ожидание'
        : 'Гостевой доступ';
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: verified
                ? const [Color(0xFFF4FAF6), Color(0xFFEAF5EE)]
                : const [Color(0xFFF6FAFE), Color(0xFFEDF5FC)],
          ),
          border: Border.all(
            color: verified ? const Color(0xFFD7E9DF) : const Color(0xFFDDEBF6),
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                key: const ValueKey('club-review-status-badge'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .85),
                  border: Border.all(color: accent.withValues(alpha: .24)),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (pending)
                      ReviewHourglass(color: accent)
                    else
                      Icon(
                        verified
                            ? Icons.task_alt
                            : awaitingEmail
                            ? Icons.mail_outline
                            : Icons.info_outline,
                        color: accent,
                        size: 24,
                      ),
                    const SizedBox(width: 9),
                    Flexible(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: accent,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              pending
                  ? 'Заявка на проверке'
                  : verified
                  ? 'Доступ к молодёжному клубу пока не открыт'
                  : awaitingEmail
                  ? 'Проверьте почту'
                  : 'Добро пожаловать',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppType.headingFamily,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1.25,
                color: Color(0xFF263C50),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              pending
                  ? 'Мы сообщим вам о решении, когда заявку рассмотрят.'
                  : awaitingEmail
                  ? 'Откройте письмо подтверждения. После этого заявка поступит на проверку.'
                  : verified
                  ? 'Вы можете продолжать пользоваться открытыми разделами приложения.'
                  : 'Вам доступны общая лента, события, помощь и карта. Аккаунт сохранён.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Color(0xFF597188),
              ),
            ),
            if (pending) ...[
              const SizedBox(height: 14),
              const Text(
                'Пока доступны общая лента, события, помощь и карта.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: Color(0xFF71879A),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
