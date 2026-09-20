import 'package:flutter/material.dart';

import '../domain/publication_icon.dart';

class PublicationFields extends StatelessWidget {
  const PublicationFields({
    required this.published,
    required this.icon,
    required this.manual,
    required this.onPublished,
    required this.onIcon,
    this.enabled = true,
    super.key,
  });
  final bool published, manual, enabled;
  final PublicationIcon icon;
  final ValueChanged<bool> onPublished;
  final ValueChanged<String?> onIcon;

  Future<void> _choose(BuildContext context) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Тематическая иконка'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: const Text('Автоматически'),
                  onPressed: () => Navigator.pop(context, 'auto'),
                ),
                for (final item in publicationIcons)
                  ActionChip(
                    avatar: Icon(item.icon, size: 20),
                    label: Text(item.label),
                    onPressed: () => Navigator.pop(context, item.id),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
    if (context.mounted && choice != null)
      onIcon(choice == 'auto' ? null : choice);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 16),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon.icon),
        title: Text(icon.label),
        subtitle: Text(manual ? 'Выбрано вручную' : 'Подобрано автоматически'),
        trailing: TextButton(
          onPressed: enabled ? () => _choose(context) : null,
          child: const Text('Сменить'),
        ),
      ),
      const SizedBox(height: 8),
      Text('Публикация', style: Theme.of(context).textTheme.titleSmall),
      SwitchListTile.adaptive(
        key: const ValueKey('publish-to-general-feed'),
        contentPadding: EdgeInsets.zero,
        value: published,
        onChanged: enabled ? onPublished : null,
        title: const Text('Опубликовать в общей ленте'),
        subtitle: const Text('Запись также появится в общей ленте'),
      ),
    ],
  );
}
