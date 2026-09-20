import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/access/permission_providers.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/id/new_uuid.dart';
import '../../../design_system/components/async_content.dart';
import '../../../design_system/components/content_frame.dart';
import '../../../design_system/tokens.dart';
import '../application/admin_providers.dart';
import '../domain/admin_models.dart';
import 'admin_components.dart';

class ParishEditorPage extends ConsumerWidget {
  const ParishEditorPage({this.parishId, super.key});
  final String? parishId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: Text(parishId == null ? 'Создать приход' : 'Редактировать приход'),
    ),
    body: SafeArea(
      child: AsyncContent<Set<String>>(
        preserveOnRefresh: true,
        value: ref.watch(permissionsProvider(null)),
        onRetry: () => ref.invalidate(permissionsProvider(null)),
        builder: (global) {
          if (parishId == null) {
            return global.contains('parishes.manage')
                ? const ParishEditorForm(canPublish: true)
                : const EmptyState(
                    title: 'Доступ ограничен',
                    message: 'Нет права создавать приходы.',
                  );
          }
          return AsyncContent<AdminParish?>(
            preserveOnRefresh: true,
            value: ref.watch(managedParishProvider(parishId!)),
            onRetry: () => ref.invalidate(managedParishProvider(parishId!)),
            builder: (parish) =>
                parish != null && parish.allows('parish.manage')
                ? ParishEditorForm(
                    key: ValueKey(parish.id),
                    parish: parish,
                    canPublish: global.contains('parishes.manage'),
                  )
                : const EmptyState(
                    title: 'Доступ ограничен',
                    message: 'Нет права редактировать этот приход.',
                  ),
          );
        },
      ),
    ),
  );
}

class ParishEditorForm extends ConsumerStatefulWidget {
  const ParishEditorForm({required this.canPublish, this.parish, super.key});
  final AdminParish? parish;
  final bool canPublish;
  @override
  ConsumerState<ParishEditorForm> createState() => _ParishEditorFormState();
}

class _ParishEditorFormState extends ConsumerState<ParishEditorForm> {
  final _form = GlobalKey<FormState>();
  late final String _id;
  late final DateTime? _expectedUpdatedAt;
  late final TextEditingController _name, _city, _address, _description;
  late String _joinMode;
  late bool _published;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final parish = widget.parish;
    _id = parish?.id ?? newUuid();
    _expectedUpdatedAt = parish?.updatedAt;
    _name = TextEditingController(text: parish?.name ?? '');
    _city = TextEditingController(text: parish?.cityName ?? '');
    _address = TextEditingController(text: parish?.address ?? '');
    _description = TextEditingController(text: parish?.description ?? '');
    _joinMode = parish?.joinMode ?? 'approval';
    _published = parish?.isPublished ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _address.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final repository = ref.read(adminRepositoryProvider);
    final refresh = ref.read(refreshAdminDataProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await repository.saveParish(
        ParishInput(
          id: _id,
          create: widget.parish == null,
          cityName: _city.text.trim(),
          name: _name.text.trim(),
          description: _description.text.trim(),
          address: _address.text.trim(),
          joinMode: _joinMode,
          isPublished: _published,
          expectedUpdatedAt: _expectedUpdatedAt,
        ),
      );
      refresh();
      if (!mounted) return;
      context.go('/admin/parishes/$id');
    } on Object catch (error) {
      if (mounted)
        setState(() {
          _error = userError(error);
        });
    } finally {
      if (mounted)
        setState(() {
          _busy = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: ContentFrame(
        maxWidth: AppLayout.formMaxWidth,
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Название прихода',
                ),
                maxLength: 200,
                validator: (v) => requiredText(v, 200),
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                controller: _city,
                enabled: !_busy && widget.parish == null,
                decoration: const InputDecoration(
                  labelText: 'Город',
                  hintText: 'Например, Калининград',
                ),
                maxLength: 160,
                validator: (v) => requiredText(v, 160),
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                controller: _address,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: 'Адрес'),
                maxLength: 500,
                minLines: 1,
                maxLines: 3,
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                controller: _description,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: 'О приходе'),
                minLines: 3,
                maxLines: 8,
                maxLength: 10000,
              ),
              const SizedBox(height: AppSpace.md),
              DropdownButtonFormField<String>(
                initialValue: _joinMode,
                isExpanded: true,
                itemHeight: null,
                decoration: const InputDecoration(labelText: 'Вступление'),
                items: const [
                  DropdownMenuItem(
                    value: 'approval',
                    child: Text('По одобрению'),
                  ),
                  DropdownMenuItem(value: 'open', child: Text('Свободное')),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value != null)
                          setState(() {
                            _joinMode = value;
                          });
                      },
              ),
              const SizedBox(height: AppSpace.md),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Показывать в каталоге'),
                subtitle: const Text(
                  'Опубликованный приход виден гостям приложения.',
                ),
                value: _published,
                onChanged: !_busy && widget.canPublish
                    ? (value) => setState(() {
                        _published = value;
                      })
                    : null,
              ),
              if (_error != null) AdminError(_error!),
              const SizedBox(height: AppSpace.md),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'Сохраняем…' : 'Сохранить приход'),
              ),
              const SizedBox(height: AppSpace.lg),
            ],
          ),
        ),
      ),
    ),
  );
}
