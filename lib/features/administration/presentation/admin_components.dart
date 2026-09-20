import 'package:flutter/material.dart';

import '../../../design_system/tokens.dart';

class AdminPager extends StatelessWidget {
  const AdminPager({required this.page, this.previous, this.next, super.key});
  final int page;
  final VoidCallback? previous, next;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
    child: Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton(onPressed: previous, child: const Text('Назад')),
        Text('Страница $page'),
        OutlinedButton(onPressed: next, child: const Text('Далее')),
      ],
    ),
  );
}

class AdminError extends StatelessWidget {
  const AdminError(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
    child: Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    ),
  );
}

String postStatusLabel(String status) => switch (status) {
  'published' => 'Опубликовано',
  'archived' => 'В архиве',
  _ => 'Черновик',
};

String? requiredText(String? value, int maximum) {
  if (value == null || value.trim().isEmpty) return 'Заполните поле';
  if (value.trim().length > maximum) return 'Не больше $maximum символов';
  return null;
}
