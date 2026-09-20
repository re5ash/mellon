import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design_system/components/club_backdrop.dart';
import '../../design_system/components/content_frame.dart';
import '../../design_system/components/navigation_content_insets.dart';
import '../../design_system/mellon_theme.dart';
import '../auth/application/auth_providers.dart';

class CommunityScaffold extends ConsumerStatefulWidget {
  const CommunityScaffold({
    required this.title,
    required this.children,
    this.actions,
    this.maxWidth = 820,
    this.protectSession = true,
    this.embedded = false,
    this.clubBackground = false,
    super.key,
  });
  final double maxWidth;
  final bool protectSession;
  final bool embedded;
  final bool clubBackground;
  final String title;
  final List<Widget> children;
  final List<Widget>? actions;
  @override
  ConsumerState<CommunityScaffold> createState() => _CommunityScaffoldState();
}

class _CommunityScaffoldState extends ConsumerState<CommunityScaffold> {
  String? _actor;
  bool _bound = false;
  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authUserProvider);
    final current = auth.asData?.value?.id;
    if (!_bound && !auth.isLoading) {
      _actor = current;
      _bound = true;
    }
    final changed = widget.protectSession && _bound && current != _actor;
    final body = SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: NavigationContentInsets.of(context)),
        child: ContentFrame(
          maxWidth: widget.maxWidth,
          padding: widget.clubBackground && MellonThemeStyle.of(context).enabled
              ? EdgeInsets.symmetric(
                  horizontal: MellonThemeStyle.of(context).pageInset,
                  vertical: 10,
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: changed
                ? const [
                    Text(
                      'Аккаунт изменился. Закройте этот экран и откройте его заново.',
                    ),
                  ]
                : widget.children,
          ),
        ),
      ),
    );
    final decoratedBody = widget.clubBackground
        ? ClubScreenBackground(child: body)
        : body;
    if (widget.embedded) return decoratedBody;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: changed ? null : widget.actions,
      ),
      body: decoratedBody,
    );
  }
}

class CommunityTile extends StatelessWidget {
  const CommunityTile({
    required this.title,
    required this.icon,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.color,
    super.key,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.primary;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: tint),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(subtitle!),
                    ],
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else if (onTap != null)
                const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String body,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Подтвердить'),
          ),
        ],
      ),
    ) ??
    false;
Future<void> openCommunity(BuildContext context, Widget page) =>
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));
