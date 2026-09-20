import 'package:flutter/material.dart';

import 'emoji_catalog.dart';

class ChatEmojiPicker extends StatefulWidget {
  const ChatEmojiPicker({
    required this.onSelected,
    required this.onClose,
    super.key,
  });
  final ValueChanged<String> onSelected;
  final VoidCallback onClose;

  @override
  State<ChatEmojiPicker> createState() => _ChatEmojiPickerState();
}

class _ChatEmojiPickerState extends State<ChatEmojiPicker> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  int _group = 0;

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {});
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase().replaceAll('ё', 'е');
    final emojis = query.isEmpty
        ? chatEmojiGroups[_group].emojis
        : chatEmojiGroups
              .expand((group) => group.emojis)
              .where((emoji) {
                final words = '${emoji.value} ${emoji.keywords}'.replaceAll(
                  'ё',
                  'е',
                );
                return query.split(RegExp(r'\s+')).every(words.contains);
              })
              .toList(growable: false);
    final colors = Theme.of(context).colorScheme;
    return Padding(
      key: const ValueKey('chat-emoji-picker'),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('emoji-search'),
                  controller: _search,
                  onChanged: (_) => _refresh(),
                  decoration: const InputDecoration(
                    hintText: 'Найти эмодзи',
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 20),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Закрыть эмодзи',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
          SizedBox(
            height: 46,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: chatEmojiGroups.length,
              itemBuilder: (context, index) {
                final group = chatEmojiGroups[index];
                return Tooltip(
                  message: group.title,
                  child: Semantics(
                    label: group.title,
                    button: true,
                    selected: query.isEmpty && index == _group,
                    child: InkWell(
                      key: ValueKey('emoji-category-$index'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        _group = index;
                        _search.clear();
                        _refresh();
                      },
                      child: Container(
                        width: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: query.isEmpty && index == _group
                              ? colors.primaryContainer
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          group.icon,
                          textScaler: TextScaler.noScaling,
                          style: const TextStyle(
                            fontFamily: 'MellonEmoji',
                            fontSize: 23,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: Text(
                query.isEmpty
                    ? chatEmojiGroups[_group].title
                    : 'Найдено: ${emojis.length}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),
          Expanded(
            child: emojis.isEmpty
                ? const Center(child: Text('Эмодзи не найдены'))
                : LayoutBuilder(
                    builder: (context, constraints) => GridView.builder(
                      key: const ValueKey('emoji-grid'),
                      controller: _scroll,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: (constraints.maxWidth / 44)
                            .floor()
                            .clamp(1, 10),
                        mainAxisExtent: 44,
                      ),
                      itemCount: emojis.length,
                      itemBuilder: (context, index) {
                        final emoji = emojis[index];
                        return Tooltip(
                          message: emoji.label,
                          child: Semantics(
                            label: emoji.label,
                            button: true,
                            child: InkWell(
                              key: ValueKey('emoji-${emoji.value}'),
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => widget.onSelected(emoji.value),
                              child: Center(
                                child: Text(
                                  emoji.value,
                                  textScaler: TextScaler.noScaling,
                                  style: const TextStyle(
                                    fontFamily: 'MellonEmoji',
                                    fontSize: 28,
                                  ),
                                ),
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
    );
  }
}
