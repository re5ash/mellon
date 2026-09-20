import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/id/new_uuid.dart';
import '../../../design_system/components/async_content.dart';
import '../../../design_system/components/content_frame.dart';
import '../../../design_system/tokens.dart';
import '../application/admin_providers.dart';
import '../domain/admin_models.dart';
import 'admin_components.dart';

class PostEditorPage extends ConsumerWidget {
  const PostEditorPage({required this.parishId, this.postId, super.key});
  final String parishId;
  final String? postId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: Text(
        postId == null ? 'Создать публикацию' : 'Редактировать публикацию',
      ),
    ),
    body: SafeArea(
      child: AsyncContent<AdminParish?>(
        preserveOnRefresh: true,
        value: ref.watch(managedParishProvider(parishId)),
        onRetry: () => ref.invalidate(managedParishProvider(parishId)),
        builder: (parish) {
          if (parish == null || !parish.allows('posts.manage')) {
            return const EmptyState(
              title: 'Доступ ограничен',
              message: 'Нет права управлять публикациями этого прихода.',
            );
          }
          if (postId == null)
            return PostEditorForm(parishId: parishId, parishName: parish.name);
          final request = (parishId: parishId, postId: postId!);
          return AsyncContent<AdminPost?>(
            preserveOnRefresh: true,
            value: ref.watch(adminPostProvider(request)),
            onRetry: () => ref.invalidate(adminPostProvider(request)),
            builder: (post) => post == null
                ? const EmptyState(
                    title: 'Публикация недоступна',
                    message: 'Вернитесь к списку публикаций.',
                  )
                : PostEditorForm(
                    key: ValueKey(post.id),
                    parishId: parishId,
                    parishName: parish.name,
                    post: post,
                  ),
          );
        },
      ),
    ),
  );
}

class PostEditorForm extends ConsumerStatefulWidget {
  const PostEditorForm({
    required this.parishId,
    required this.parishName,
    this.post,
    super.key,
  });
  final String parishId, parishName;
  final AdminPost? post;
  @override
  ConsumerState<PostEditorForm> createState() => _PostEditorFormState();
}

class _PostEditorFormState extends ConsumerState<PostEditorForm> {
  final _form = GlobalKey<FormState>();
  late final String _id;
  late final DateTime? _expectedUpdatedAt;
  late final TextEditingController _title, _body;
  late String _visibility, _status;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final post = widget.post;
    _id = post?.id ?? newUuid();
    _expectedUpdatedAt = post?.updatedAt;
    _title = TextEditingController(text: post?.title ?? '');
    _body = TextEditingController(text: post?.body ?? '');
    _visibility = post?.visibility ?? 'parish';
    _status = post?.status ?? 'draft';
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
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
      await repository.savePost(
        PostInput(
          id: _id,
          parishId: widget.parishId,
          create: widget.post == null,
          title: _title.text.trim(),
          body: _body.text.trim(),
          visibility: _visibility,
          status: _status,
          expectedUpdatedAt: _expectedUpdatedAt,
        ),
      );
      refresh();
      if (!mounted) return;
      context.go('/admin/parishes/${widget.parishId}');
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
              Text(
                widget.parishName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpace.lg),
              TextFormField(
                controller: _title,
                enabled: !_busy,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Заголовок'),
                validator: (v) => requiredText(v, 200),
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                controller: _body,
                enabled: !_busy,
                minLines: 5,
                maxLines: 16,
                maxLength: 30000,
                decoration: const InputDecoration(
                  labelText: 'Текст публикации',
                ),
              ),
              const SizedBox(height: AppSpace.md),
              DropdownButtonFormField<String>(
                initialValue: _visibility,
                isExpanded: true,
                itemHeight: null,
                decoration: const InputDecoration(labelText: 'Кому доступна'),
                items: const [
                  DropdownMenuItem(
                    value: 'parish',
                    child: Text('Только приход'),
                  ),
                  DropdownMenuItem(value: 'public', child: Text('Общая лента')),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value != null)
                          setState(() {
                            _visibility = value;
                          });
                      },
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                _visibility == 'public'
                    ? 'После публикации запись смогут читать гости, если приход опубликован в каталоге.'
                    : 'Запись предназначена для участников этого прихода и его уполномоченных администраторов.',
              ),
              const SizedBox(height: AppSpace.md),
              DropdownButtonFormField<String>(
                initialValue: _status,
                isExpanded: true,
                itemHeight: null,
                decoration: const InputDecoration(labelText: 'Статус'),
                items: const [
                  DropdownMenuItem(value: 'draft', child: Text('Черновик')),
                  DropdownMenuItem(
                    value: 'published',
                    child: Text('Опубликовано'),
                  ),
                  DropdownMenuItem(value: 'archived', child: Text('Архив')),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value != null)
                          setState(() {
                            _status = value;
                          });
                      },
              ),
              if (_error != null) AdminError(_error!),
              const SizedBox(height: AppSpace.lg),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(
                  _busy
                      ? 'Сохраняем…'
                      : _status == 'published'
                      ? 'Опубликовать'
                      : 'Сохранить',
                ),
              ),
              const SizedBox(height: AppSpace.lg),
            ],
          ),
        ),
      ),
    ),
  );
}
