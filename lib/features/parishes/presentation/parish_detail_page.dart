import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/components/async_content.dart';
import '../../../design_system/components/content_frame.dart';
import '../../../design_system/tokens.dart';
import '../../auth/application/auth_providers.dart';
import '../application/parish_providers.dart';

class ParishDetailPage extends ConsumerStatefulWidget {
  const ParishDetailPage({required this.id, super.key});
  final String id;
  @override
  ConsumerState<ParishDetailPage> createState() => _ParishDetailPageState();
}

class _ParishDetailPageState extends ConsumerState<ParishDetailPage> {
  Future<void> _request() async {
    if (ref.read(authUserProvider).asData?.value == null) {
      await context.push<void>('/auth?from=/join/${widget.id}');
      return;
    }
    await context.push<void>('/join/${widget.id}');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Приход')),
    body: SafeArea(
      child: AsyncContent(
        value: ref.watch(parishProvider(widget.id)),
        onRetry: () => ref.invalidate(parishProvider(widget.id)),
        builder: (parish) => SingleChildScrollView(
          child: ContentFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  parish.name,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: AppSpace.md),
                Text(parish.address),
                const SizedBox(height: AppSpace.md),
                Text(parish.description),
                const SizedBox(height: AppSpace.lg),
                FilledButton(
                  onPressed: _request,
                  child: const Text('Присоединиться'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
