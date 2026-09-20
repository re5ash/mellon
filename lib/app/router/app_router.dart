import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/access/account_access_provider.dart';
import '../../features/administration/presentation/admin_page.dart';
import '../../features/administration/presentation/admin_parish_page.dart';
import '../../features/administration/presentation/membership_requests_page.dart';
import '../../features/administration/presentation/parish_editor_page.dart';
import '../../features/administration/presentation/post_editor_page.dart';
import '../../features/appearance/presentation/appearance_detail_pages.dart';
import '../../features/appearance/presentation/appearance_page.dart';
import '../../features/auth/application/auth_providers.dart';
import '../../features/auth/domain/email_auth_repository.dart';
import '../../features/auth/presentation/auth_page.dart';
import '../../features/auth/presentation/email_auth_pages.dart';
import '../../features/chats/presentation/admin_chats_page.dart';
import '../../features/chats/presentation/chat_editor_page.dart';
import '../../features/chats/presentation/chat_page.dart';
import '../../features/chats/presentation/chat_route.dart';
import '../../features/chats/presentation/chats_page.dart';
import '../../features/community/club_applications_page.dart';
import '../../features/community/community_pages.dart';
import '../../features/community/join_page.dart';
import '../../features/community/managed_clubs_page.dart';
import '../../features/events/presentation/events_page.dart';
import '../../features/feed/presentation/feed_hub_page.dart';
import '../../features/feed/presentation/parish_news_page.dart';
import '../../features/help/presentation/help_page.dart';
import '../../features/map/presentation/map_page.dart';
import '../../features/membership/presentation/my_parish_page.dart';
import '../../features/notifications/presentation/notifications_page.dart';
import '../../features/parishes/presentation/parish_detail_page.dart';
import '../../features/parishes/presentation/parishes_page.dart';
import '../../features/profile/presentation/profile_details_page.dart';
import '../../features/profile/presentation/profile_page.dart';
import '../shell/app_shell.dart';
import '../shell/more_page.dart';
import 'route_access.dart';

final routerProvider = Provider.autoDispose<GoRouter>((ref) {
  final rootKey = GlobalKey<NavigatorState>();
  final refresh = ValueNotifier<int>(0);
  ref.listen(authUserProvider, (_, next) => refresh.value++);
  final router = GoRouter(
    navigatorKey: rootKey,
    initialLocation: '/feed',
    refreshListenable: refresh,
    redirect: (context, state) {
      final legacy = retiredParishDestination(state.uri.path);
      if (legacy != null)
        return legacy == '/my-youth' ? '/my-youth?choose=1' : legacy;
      final auth = ref.read(authUserProvider);
      if (auth.isLoading) return null;
      final signedIn = auth.asData?.value != null;
      final restricted =
          ref.read(accountAccessProvider).asData?.value.restrictedGuest == true;
      if (signedIn &&
          restricted &&
          (!allowedForRestrictedGuest(state.uri.path) ||
              state.uri.path == '/feed' &&
                  state.uri.queryParameters['tab'] == 'parish'))
        return '/feed';
      if (!signedIn && requiresSignIn(state.uri.path))
        return Uri(
          path: '/auth',
          queryParameters: {'from': safeDestination(state.uri.path)},
        ).toString();
      if (signedIn && state.uri.path == '/auth')
        return safeDestination(state.uri.queryParameters['from']);
      return null;
    },
    routes: [
      GoRoute(
        path: '/admin/youth-clubs',
        builder: (_, state) => const ManagedYouthPage(),
      ),
      GoRoute(
        path: '/youth-requests/:youthId',
        builder: (_, state) => ClubApplicationsPage(
          youth: state.pathParameters['youthId']!,
          requestId: state.uri.queryParameters['request'],
        ),
      ),
      GoRoute(
        path: '/profile/details',
        builder: (_, state) => const ProfileDetailsPage(),
      ),
      GoRoute(path: '/manage', redirect: (_, state) => '/admin'),
      GoRoute(
        path: '/join/:parishId',
        builder: (_, state) =>
            JoinParishPage(parish: state.pathParameters['parishId']!),
      ),
      GoRoute(path: '/', redirect: (_, state) => '/feed'),
      GoRoute(path: '/auth', builder: (_, state) => const AuthPage()),
      GoRoute(
        path: '/auth/forgot-password',
        builder: (_, state) => EmailRequestPage(
          purpose: EmailPurpose.recovery,
          initialEmail: state.extra is String ? state.extra! as String : '',
        ),
      ),
      GoRoute(
        path: '/auth/confirm',
        builder: (_, state) => EmailRequestPage(
          purpose: EmailPurpose.confirmation,
          initialEmail: state.extra is String ? state.extra! as String : '',
        ),
      ),
      GoRoute(
        path: '/auth/verify',
        builder: (_, state) => EmailLinkPage(uri: state.uri),
      ),
      GoRoute(
        path: '/auth/new-password',
        builder: (_, state) => const NewPasswordPage(),
      ),
      GoRoute(
        path: '/profile/appearance',
        builder: (_, state) => const AppearancePage(),
        routes: [
          GoRoute(
            path: 'wallpaper',
            builder: (_, state) => const ChatWallpaperPage(),
          ),
          GoRoute(
            path: 'name-color',
            builder: (_, state) => const NameColorPage(),
          ),
          GoRoute(
            path: 'night',
            builder: (_, state) => const NightAppearancePage(),
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/feed',
                builder: (_, state) =>
                    FeedHubPage(tab: state.uri.queryParameters['tab']),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/my-youth',
                builder: (_, state) => MyYouthPage(
                  embedded: true,
                  forceSelection: state.uri.queryParameters['choose'] == '1',
                ),
              ),
              GoRoute(
                path: '/my-parish',
                builder: (_, state) => const MyParishPage(),
              ),
              GoRoute(
                path: '/my-parish/news',
                builder: (_, state) => const ParishNewsPage(),
              ),
              GoRoute(
                path: '/my-parish/events',
                builder: (_, state) => const ParishEventPage(ownParish: true),
              ),
              GoRoute(
                path: '/my-parish/schedule',
                builder: (_, state) =>
                    const ParishEventPage(ownParish: true, schedule: true),
              ),
              GoRoute(
                path: '/chats',
                builder: (_, state) => const ChatsPage(),
                routes: [
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: rootKey,
                    pageBuilder: (context, state) => MellonChatScreenPage(
                      reducedMotion: MediaQuery.disableAnimationsOf(context),
                      key: state.pageKey,
                      child: ChatPage(roomId: state.pathParameters['id']!),
                    ),
                  ),
                ],
              ),
              GoRoute(path: '/more', builder: (_, state) => const MorePage()),
              GoRoute(
                path: '/parishes',
                builder: (_, state) => const ParishesPage(),
                routes: [
                  GoRoute(
                    path: ':id',
                    parentNavigatorKey: rootKey,
                    builder: (_, state) =>
                        ParishDetailPage(id: state.pathParameters['id']!),
                  ),
                ],
              ),
              GoRoute(
                path: '/events',
                builder: (_, state) => const ParishEventPage(),
              ),
              GoRoute(
                path: '/help',
                builder: (_, state) => const HelpRequestPage(),
              ),
              GoRoute(
                path: '/notifications',
                builder: (_, state) => const NotificationsPage(),
              ),
              GoRoute(
                path: '/profile',
                builder: (_, state) => const ProfilePage(),
              ),
              GoRoute(
                path: '/admin',
                builder: (_, state) => const AdminPage(),
                routes: [
                  GoRoute(
                    path: 'parishes/new',
                    parentNavigatorKey: rootKey,
                    builder: (_, state) => const ParishEditorPage(),
                  ),
                  GoRoute(
                    path: 'parishes/:parishId',
                    parentNavigatorKey: rootKey,
                    builder: (_, state) => AdminParishPage(
                      parishId: state.pathParameters['parishId']!,
                    ),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        parentNavigatorKey: rootKey,
                        builder: (_, state) => ParishEditorPage(
                          parishId: state.pathParameters['parishId']!,
                        ),
                      ),
                      GoRoute(
                        path: 'requests',
                        parentNavigatorKey: rootKey,
                        builder: (_, state) => MembershipRequestsPage(
                          parishId: state.pathParameters['parishId']!,
                        ),
                      ),
                      GoRoute(
                        path: 'chats',
                        parentNavigatorKey: rootKey,
                        builder: (_, state) => AdminChatsPage(
                          parishId: state.pathParameters['parishId']!,
                        ),
                        routes: [
                          GoRoute(
                            path: 'new',
                            parentNavigatorKey: rootKey,
                            builder: (_, state) => ChatEditorPage(
                              parishId: state.pathParameters['parishId']!,
                            ),
                          ),
                          GoRoute(
                            path: ':roomId',
                            parentNavigatorKey: rootKey,
                            builder: (_, state) => ChatEditorPage(
                              parishId: state.pathParameters['parishId']!,
                              roomId: state.pathParameters['roomId']!,
                            ),
                          ),
                        ],
                      ),
                      GoRoute(
                        path: 'posts/new',
                        parentNavigatorKey: rootKey,
                        builder: (_, state) => PostEditorPage(
                          parishId: state.pathParameters['parishId']!,
                        ),
                      ),
                      GoRoute(
                        path: 'posts/:postId',
                        parentNavigatorKey: rootKey,
                        builder: (_, state) => PostEditorPage(
                          parishId: state.pathParameters['parishId']!,
                          postId: state.pathParameters['postId']!,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/map',
                builder: (_, state) => MapPage(
                  parishId: state.uri.queryParameters['parish'],
                  focusRequest: state.uri.queryParameters['focus'],
                ),
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Страница не найдена')),
      body: Center(
        child: FilledButton(
          onPressed: () => context.go('/feed'),
          child: const Text('Открыть ленту'),
        ),
      ),
    ),
  );
  bool disposed = false;
  ref.listen(accountAccessProvider, (previous, next) {
    // Only this access flag affects redirects. Repeated successful polling
    // must not reparse the current route or disturb its scroll position.
    if (previous?.asData?.value.restrictedGuest ==
        next.asData?.value.restrictedGuest)
      return;
    refresh.value++;
    if (next.asData?.value.restrictedGuest == true &&
        previous?.asData?.value.restrictedGuest != true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (disposed) return;
        rootKey.currentState?.popUntil((route) => route.isFirst);
        router.go('/feed');
      });
    }
  });
  ref.onDispose(() {
    disposed = true;
    router.dispose();
    refresh.dispose();
  });
  return router;
});
