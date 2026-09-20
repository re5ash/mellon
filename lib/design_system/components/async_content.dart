import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/errors/app_failure.dart';
import '../tokens.dart';

class AsyncContent<T> extends StatelessWidget {
  const AsyncContent({
    required this.value,
    required this.builder,
    required this.onRetry,
    this.preserveOnRefresh = false,
    this.loading,
    super.key,
  });
  final AsyncValue<T> value;
  final Widget Function(T) builder;
  final VoidCallback onRetry;
  final Widget? loading;
  // Forms can retain their local input during an explicit refresh. A changed
  // dependency (including account identity) still clears the previous child.
  final bool preserveOnRefresh;
  @override
  Widget build(BuildContext context) => value.when(
    skipLoadingOnRefresh: preserveOnRefresh,
    skipLoadingOnReload: false,
    data: builder,
    loading: () => loading ?? const Center(child: CircularProgressIndicator()),
    error: (error, stack) => Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(userError(error), textAlign: TextAlign.center),
            const SizedBox(height: AppSpace.md),
            OutlinedButton(onPressed: onRetry, child: const Text('Повторить')),
          ],
        ),
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    required this.message,
    this.icon = Icons.inbox_outlined,
    super.key,
  });
  final String title;
  final String message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: AppSpace.md),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpace.sm),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}
