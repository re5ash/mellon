import 'package:flutter/material.dart';

import 'chat_appearance.dart';
import 'chat_icon_badge.dart';

Future<String?> showChatIconPicker(
  BuildContext context, {
  required String selected,
  required String title,
  String description = '',
  String seed = '',
}) => showDialog<String>(
  context: context,
  builder: (_) => ChatIconPicker(
    selected: selected,
    title: title,
    description: description,
    seed: seed,
  ),
);

class ChatIconPicker extends StatefulWidget {
  const ChatIconPicker({
    required this.selected,
    required this.title,
    this.description = '',
    this.seed = '',
    super.key,
  });
  final String selected, title, description, seed;
  @override
  State<ChatIconPicker> createState() => _ChatIconPickerState();
}

class _ChatIconPickerState extends State<ChatIconPicker> {
  late String _selected = widget.selected;
  String? _group;
  int _motion = 0;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final items = ChatAppearance.library
        .where((i) => _group == null || i.group == _group)
        .toList();
    final style = ChatAppearance.resolve(
      _selected,
      title: widget.title,
      description: widget.description,
      seed: widget.seed,
    );
    return AlertDialog(
      title: const Text('Тематическая иконка'),
      contentPadding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      content: SizedBox(
        width: 560,
        height: (MediaQuery.sizeOf(context).height * .62)
            .clamp(240, 620)
            .toDouble(),
        child: Column(
          children: [
            Row(
              children: [
                ChatIconBadge(
                  iconKey: _selected,
                  title: widget.title,
                  description: widget.description,
                  seed: widget.seed,
                  size: 64,
                  motionToken: _motion,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    _selected == 'auto'
                        ? 'Автоматически · ${style.topic}'
                        : style.label,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ChoiceChip(
              label: const Text('Автоматически'),
              avatar: const Icon(Icons.auto_awesome_rounded),
              selected: _selected == 'auto',
              onSelected: (_) => setState(() {
                _selected = 'auto';
                _motion++;
              }),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final group in [null, ...ChatAppearance.groups])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(group ?? 'Все'),
                        selected: _group == group,
                        onSelected: (_) => setState(() => _group = group),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => GridView.builder(
                  key: ValueKey(_group),
                  itemCount: items.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: box.maxWidth < 330 ? 3 : 5,
                    mainAxisExtent: 100,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                  ),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final selected =
                        (ChatAppearance.aliases[_selected] ?? _selected) ==
                        item.key;
                    return Semantics(
                      selected: selected,
                      button: true,
                      label: item.label,
                      child: InkWell(
                        key: ValueKey('chat-icon-${item.key}'),
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => setState(() {
                          _selected = item.key;
                          _motion++;
                        }),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: selected
                                ? colors.primaryContainer.withValues(alpha: .4)
                                : null,
                            border: Border.all(
                              color: selected
                                  ? colors.primary
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ChatIconBadge(iconKey: item.key),
                              const SizedBox(height: 6),
                              Text(
                                item.topic,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          key: const ValueKey('apply-chat-icon'),
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('Применить'),
        ),
      ],
    );
  }
}
