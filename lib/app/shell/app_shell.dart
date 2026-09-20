import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/access/account_access_provider.dart';
import '../../core/access/permission_providers.dart';
import '../../core/config/app_branding.dart';
import '../../design_system/appearance_settings.dart';
import '../../design_system/components/mellon_theme_backdrop.dart';
import '../../design_system/components/navigation_content_insets.dart';
import '../../design_system/mellon_theme.dart';
import '../../design_system/parish_menu_theme.dart';
import '../../design_system/theme_controller.dart';
import '../../design_system/tokens.dart';
import '../../features/auth/application/auth_providers.dart';
import '../../features/auth/presentation/club_registration_dialog.dart';
import '../../features/chats/application/chat_providers.dart';
import '../../features/community/club_directory_repository.dart';
import '../../features/community/community_repository.dart';
import '../../features/events/application/events_providers.dart';
import '../../features/feed/application/feed_providers.dart';
import '../../features/help/application/help_providers.dart';
import '../../features/membership/application/membership_providers.dart';
import '../../features/notifications/application/notification_providers.dart';
import '../../features/notifications/presentation/notification_bell.dart';
import 'account_menu.dart';
import 'club_navigation_bar.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.shell, super.key});
  final StatefulNavigationShell shell;
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  static const destinations = ClubNavigationBar.destinations;
  bool _openingClub = false;
  bool _shellCanPop = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(accountAccessRefreshProvider).value++;
      ref.invalidate(currentMembershipProvider);
      ref.invalidate(myYouthProvider);
      ref.invalidate(clubDirectoryProvider);
      ref.invalidate(clubWorkspacesProvider);
      ref.invalidate(managedClubsProvider);
      ref.invalidate(scopePermissionsProvider);
      ref.invalidate(appConfigurationProvider);
      ref.invalidate(permissionsProvider);
      ref.invalidate(feedPageProvider);
      ref.invalidate(chatMessagesProvider);
      ref.invalidate(chatRoomsProvider);
      ref.invalidate(chatRoomProvider);
      ref.invalidate(notificationsProvider);
      ref.invalidate(eventsProvider);
      ref.invalidate(myParishEventsProvider);
      ref.invalidate(helpProvider);
      ref.invalidate(myParishHelpProvider);
    }
  }

  Future<void> _select(int index) async {
    if (index == 1) {
      if (_openingClub) return;
      _openingClub = true;
      try {
        // Wait for the restored session before deciding whether this is a guest.
        final user = await ref.read(authUserProvider.future);
        if (!mounted) return;
        if (user == null) {
          await openClubRegistration(context);
        } else {
          final access = await ref.read(accountAccessProvider.future);
          if (!mounted ||
              ref.read(authUserProvider).asData?.value?.id != user.id) {
            return;
          }
          if (access.restrictedGuest) {
            await openClubRegistration(context, reviewOnly: true);
          } else {
            widget.shell.goBranch(1, initialLocation: true);
          }
        }
      } on Object {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Не удалось проверить вход. Попробуйте ещё раз.'),
            ),
          );
        }
      } finally {
        _openingClub = false;
      }
      return;
    }
    widget.shell.goBranch(
      index,
      initialLocation: index == widget.shell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: widget.shell.currentIndex == 1
        ? ParishMenuTheme.from(Theme.of(context))
        : Theme.of(context),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= AppLayout.railBreakpoint &&
            constraints.maxHeight >= 560;
        const branches = [0, 1, 2];
        final design = MellonThemeStyle.of(context);
        final themedClub = widget.shell.currentIndex == 1 && design.enabled;
        return MellonThemeBackdrop(
          enabled:
              themedClub &&
              ref.watch(appearanceControllerProvider).clubBackground ==
                  ClubBackground.current,
          child: Scaffold(
            backgroundColor: themedClub ? Colors.transparent : null,
            extendBody: !wide,
            appBar: AppBar(
              backgroundColor: themedClub ? Colors.transparent : null,
              surfaceTintColor: themedClub ? Colors.transparent : null,
              scrolledUnderElevation: themedClub ? 0 : null,
              foregroundColor:
                  themedClub &&
                      design.classical &&
                      Theme.of(context).brightness == Brightness.light
                  ? Colors.white
                  : null,
              titleTextStyle: themedClub && design.classical
                  ? Theme.of(context).appBarTheme.titleTextStyle
                        ?.copyWith(color: Colors.white)
                  : null,
              centerTitle: !(themedClub && design.classical),
              title: Text(
                widget.shell.currentIndex == 0
                    ? 'Лента'
                    : widget.shell.currentIndex == 2
                    ? 'Карта'
                    : appDisplayName(
                        ref
                            .watch(appConfigurationProvider)
                            .asData
                            ?.value['app_name'],
                      ),
              ),
              // Push/pop inside a shell branch need not rebuild the shell itself.
              // Observe the router so the leading action follows the actual stack.
              leading: ListenableBuilder(
                listenable: GoRouter.of(context).routerDelegate,
                builder: (context, child) {
                  // A root chat temporarily covers this route. Keep the shell's
                  // own leading action stable throughout entry and edge-back.
                  if (ModalRoute.isCurrentOf(context) ?? true) {
                    _shellCanPop = context.canPop();
                  }
                  return _shellCanPop
                      ? BackButton(onPressed: () => context.pop())
                      : widget.shell.currentIndex == 1
                      ? const Icon(Icons.church_outlined)
                      : const NotificationBell();
                },
              ),
              actions: [
                if (widget.shell.currentIndex == 1) const NotificationBell(),
                AccountMenu(parishStyle: widget.shell.currentIndex == 1),
              ],
            ),
            body: SafeArea(
              bottom: wide,
              child: Row(
                children: [
                  if (wide)
                    NavigationRail(
                      extended:
                          constraints.maxWidth >=
                          AppLayout.extendedRailBreakpoint,
                      selectedIndex:
                          branches.contains(widget.shell.currentIndex)
                          ? branches.indexOf(widget.shell.currentIndex)
                          : 0,
                      onDestinationSelected: (index) =>
                          _select(branches[index]),
                      labelType:
                          constraints.maxWidth >=
                              AppLayout.extendedRailBreakpoint
                          ? NavigationRailLabelType.none
                          : NavigationRailLabelType.all,
                      destinations: branches
                          .map((index) => destinations[index])
                          .map(
                            (d) => NavigationRailDestination(
                              icon: Icon(d.icon),
                              label: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 170,
                                ),
                                child: Text(
                                  d.label,
                                  textAlign: TextAlign.center,
                                  softWrap: true,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final bottom = wide
                            ? 0.0
                            : MediaQuery.paddingOf(context).bottom;
                        return NavigationContentInsets(
                          bottom: bottom,
                          child: widget.shell,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: wide
                ? null
                : ClubNavigationBar(
                    selectedIndex: widget.shell.currentIndex,
                    onSelected: _select,
                  ),
          ),
        );
      },
    ),
  );
}
