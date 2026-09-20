import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../design_system/components/async_content.dart';
import '../../../design_system/components/content_frame.dart';
import '../../../design_system/tokens.dart';
import '../application/parish_providers.dart';

class ParishesPage extends ConsumerStatefulWidget {
  const ParishesPage({super.key});
  @override
  ConsumerState<ParishesPage> createState() => _ParishesPageState();
}

class _ParishesPageState extends ConsumerState<ParishesPage> {
  String _query = '';
  Timer? _debounce;
  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ContentFrame(
    child: Column(
      children: [
        TextField(
          decoration: const InputDecoration(
            labelText: 'Найти приход',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) {
            _debounce?.cancel();
            _debounce = Timer(
              const Duration(milliseconds: 300),
              () => setState(() => _query = value),
            );
          },
        ),
        const SizedBox(height: AppSpace.md),
        Expanded(
          child: AsyncContent(
            value: ref.watch(parishListProvider(_query)),
            onRetry: () => ref.invalidate(parishListProvider(_query)),
            builder: (parishes) => parishes.isEmpty
                ? const EmptyState(
                    title: 'Приходы не найдены',
                    message: 'Попробуйте изменить запрос.',
                  )
                : ListView.separated(
                    itemCount: parishes.length,
                    separatorBuilder: (_, i) =>
                        const SizedBox(height: AppSpace.sm),
                    itemBuilder: (context, i) {
                      final parish = parishes[i];
                      return Card(
                        child: ListTile(
                          isThreeLine: parish.address.isNotEmpty,
                          leading: const Icon(Icons.church_outlined),
                          title: Text(parish.name),
                          subtitle: Text(parish.address),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/parishes/${parish.id}'),
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
