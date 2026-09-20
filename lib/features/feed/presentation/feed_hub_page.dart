import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/access/account_access_provider.dart';
import '../../../design_system/components/content_frame.dart';
import '../../../design_system/tokens.dart';
import '../../auth/application/auth_providers.dart';
import '../../community/community_pages.dart';
import '../../events/presentation/events_page.dart';
import '../../help/presentation/help_page.dart';
import 'feed_page.dart';

const feedTabs = ['general', 'parish', 'events', 'help'];

class FeedHubPage extends ConsumerWidget {
  const FeedHubPage({this.tab, super.key});
  final String? tab;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider);
    final access = ref.watch(accountAccessProvider);
    final publicOnly =
        user.asData?.value == null ||
        access.asData?.value == null ||
        access.asData?.value.restrictedGuest == true;
    return _FeedHubContent(
      key: ValueKey('${user.asData?.value?.id}:$publicOnly'),
      tab: tab,
      publicOnly: publicOnly,
    );
  }
}

class _FeedHubContent extends ConsumerStatefulWidget {
  const _FeedHubContent({required this.publicOnly, this.tab, super.key});
  final String? tab;
  final bool publicOnly;
  @override
  ConsumerState<_FeedHubContent> createState() => _FeedHubPageState();
}

class _FeedHubPageState extends ConsumerState<_FeedHubContent>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<String> get visibleTabs =>
      widget.publicOnly ? const ['general', 'events', 'help'] : feedTabs;
  int _index(String? value) {
    final index = visibleTabs.indexOf(value ?? 'general');
    return index < 0 ? 0 : index;
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: visibleTabs.length,
      vsync: this,
      initialIndex: _index(widget.tab),
    );
    _tabs.addListener(_tabChanged);
  }

  void _tabChanged() {
    if (GoRouter.of(context).routeInformationProvider.value.uri.path ==
            '/feed' &&
        !_tabs.indexIsChanging &&
        _tabs.index != _index(widget.tab)) {
      context.replace('/feed?tab=${visibleTabs[_tabs.index]}');
    }
  }

  @override
  void didUpdateWidget(_FeedHubContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tab != oldWidget.tab && _tabs.index != _index(widget.tab)) {
      _tabs.animateTo(_index(widget.tab));
    }
  }

  @override
  void dispose() {
    _tabs.removeListener(_tabChanged);
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final userId = ref.watch(authUserProvider).asData?.value?.id;
    return Column(
      children: [
        ContentFrame(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scroll =
                  constraints.maxWidth < 440 ||
                  MediaQuery.textScalerOf(context).scale(14) > 19;
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(40),
                ),
                child: TabBar(
                  controller: _tabs,
                  isScrollable: scroll,
                  tabAlignment: scroll ? TabAlignment.start : TabAlignment.fill,
                  dividerHeight: 0,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(40),
                  ),
                  labelColor: colors.onPrimary,
                  unselectedLabelColor: colors.onSurfaceVariant,
                  tabs: [
                    const Tab(text: 'Общая'),
                    if (!widget.publicOnly) const Tab(text: 'Клубы'),
                    const Tab(text: 'События'),
                    const Tab(text: 'Помощь'),
                  ],
                ),
              );
            },
          ),
        ),
        if (MediaQuery.sizeOf(context).height >= 600)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Text(
              'Листайте между разделами',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              FeedPage(key: ValueKey('general-$userId')),
              if (!widget.publicOnly)
                MyYouthPage(
                  key: ValueKey('clubs-news-$userId'),
                  embedded: true,
                  newsOnly: true,
                ),
              ParishEventPage(key: ValueKey('events-$userId')),
              HelpRequestPage(key: ValueKey('help-$userId')),
            ],
          ),
        ),
      ],
    );
  }
}
