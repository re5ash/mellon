import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moy_prihod/core/errors/app_failure.dart';
import 'package:moy_prihod/core/images/photo_cache.dart';
import 'package:moy_prihod/design_system/components/record_card.dart';
import 'package:moy_prihod/features/auth/application/auth_providers.dart';
import 'package:moy_prihod/features/auth/domain/app_user.dart';
import 'package:moy_prihod/features/events/application/events_providers.dart';
import 'package:moy_prihod/features/events/domain/event.dart';
import 'package:moy_prihod/features/events/domain/events_repository.dart';
import 'package:moy_prihod/features/events/presentation/events_page.dart';
import 'package:moy_prihod/features/feed/data/publication_photo_cache.dart';
import 'package:moy_prihod/features/feed/presentation/publication_photo.dart';
import 'package:moy_prihod/features/membership/application/membership_providers.dart';
import 'package:moy_prihod/features/membership/domain/membership.dart';

ParishEvent event(int index, {String? title}) => ParishEvent(
  id: 'event-$index',
  title: title ?? 'Встреча $index',
  description: index == 0
      ? List.filled(12, 'Встречаемся в клубе после службы.').join(' ')
      : 'Приглашаем на встречу клуба.',
  photoPath: index == 0 ? 'event/photo.png' : null,
);

class PendingEvents implements ParishEventRepository {
  List<ParishEvent> rows = List.generate(20, event);
  Completer<List<ParishEvent>>? pending;
  int reads = 0;
  @override
  Future<List<ParishEvent>> list({String? parishId}) async {
    reads++;
    return pending == null ? rows : await pending!.future;
  }
}

class EventFixture {
  final repository = PendingEvents();
  final cache = PhotoCache();
  final users = StreamController<AppUser?>.broadcast();
  late ProviderContainer container;
  int photoLoads = 0;

  Future<void> dispose() async {
    cache.dispose();
    await users.close();
  }
}

Future<EventFixture> mountEvents(
  WidgetTester tester, {
  bool ownParish = false,
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final fixture = EventFixture();
  final image = fixture.cache.put(
    'event/photo.png',
    MemoryImage(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGN49eHzfwAJYgPNIyeaqwAAAABJRU5ErkJggg==',
      ),
    ),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await fixture.dispose();
  });
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        authUserProvider.overrideWith((ref) async* {
          yield const AppUser('actor');
          yield* fixture.users.stream;
        }),
        currentMembershipProvider.overrideWith(
          (ref) async => const Membership(
            id: 'membership',
            parishId: 'parish',
            status: 'active',
          ),
        ),
        eventsRepositoryProvider.overrideWithValue(fixture.repository),
        publicationPhotoCacheProvider.overrideWithValue(fixture.cache),
        publicationPhotoImageProvider('event/photo.png').overrideWith((
          ref,
        ) async {
          fixture.photoLoads++;
          return image;
        }),
      ],
      child: MaterialApp(
        home: Scaffold(body: ParishEventPage(ownParish: ownParish)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  fixture.container = ProviderScope.containerOf(
    tester.element(find.byType(ParishEventPage)),
  );
  return fixture;
}

void main() {
  for (final ownParish in [false, true]) {
    for (final width in [390.0, 1000.0]) {
      testWidgets(
        'repeated refresh keeps decoded photo, expansion and scroll: $ownParish/$width',
        (tester) async {
          final fixture = await mountEvents(
            tester,
            ownParish: ownParish,
            width: width,
          );
          await tester.tap(find.text('Подробнее').first);
          await tester.pumpAndSettle();
          final scroll = tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position;
          scroll.jumpTo(32);
          await tester.pump();
          final photo = find.byType(PublicationPhoto);
          final photoElement = tester.element(photo);
          final imageState = tester.state(find.byType(Image));
          final photoRect = tester.getRect(photo);
          final offset = scroll.pixels;
          final loads = fixture.photoLoads;
          final provider = ownParish ? myParishEventsProvider : eventsProvider;

          for (var refresh = 0; refresh < 4; refresh++) {
            final next = Completer<List<ParishEvent>>();
            fixture.repository.pending = next;
            fixture.container.invalidate(provider);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 250));
            expect(find.byType(CircularProgressIndicator), findsNothing);
            expect(tester.element(photo), same(photoElement));
            expect(tester.state(find.byType(Image)), same(imageState));
            expect(tester.getRect(photo), photoRect);
            expect(scroll.pixels, offset);
            expect(find.text('Свернуть'), findsOneWidget);
            next.complete(List.generate(20, event));
            await tester.pumpAndSettle();
            expect(tester.element(photo), same(photoElement));
            expect(tester.state(find.byType(Image)), same(imageState));
            expect(tester.getRect(photo), photoRect);
            expect(scroll.pixels, offset);
            expect(fixture.photoLoads, loads);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'inserting another event preserves expanded card identity; edits and deletes still apply',
    (tester) async {
      final fixture = await mountEvents(tester);
      final card = find.widgetWithText(RecordCard, 'Встреча 0');
      final state = tester.state(card);
      await tester.tap(find.text('Подробнее').first);
      await tester.pumpAndSettle();
      fixture.repository.rows = [
        event(99),
        event(0, title: 'Обновлённая встреча'),
      ];
      fixture.container.invalidate(eventsProvider);
      await tester.pumpAndSettle();
      expect(
        tester.state(find.widgetWithText(RecordCard, 'Обновлённая встреча')),
        same(state),
      );
      expect(find.text('Свернуть'), findsOneWidget);
      fixture.repository.rows = [];
      fixture.container.invalidate(eventsProvider);
      await tester.pumpAndSettle();
      expect(find.byType(PublicationPhoto), findsNothing);
      expect(find.byType(RecordCard), findsNothing);
      expect(find.text('Пока нет событий'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an auth notification for the same user does not rebuild the list request',
    (tester) async {
      final fixture = await mountEvents(tester);
      final reads = fixture.repository.reads;
      fixture.users.add(const AppUser('actor'));
      await tester.pumpAndSettle();
      expect(fixture.repository.reads, reads);
      expect(find.byType(PublicationPhoto), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('access error clears previous event photos', (tester) async {
    final fixture = await mountEvents(tester);
    final next = Completer<List<ParishEvent>>();
    fixture.repository.pending = next;
    fixture.container.invalidate(eventsProvider);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(PublicationPhoto), findsOneWidget);
    next.completeError(const AppFailure('Доступ к событиям отозван.'));
    await tester.pumpAndSettle();
    expect(find.byType(PublicationPhoto), findsNothing);
    expect(find.text('Доступ к событиям отозван.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'account switch clears photos and ignores the old pending response',
    (tester) async {
      final fixture = await mountEvents(tester);
      final oldResponse = Completer<List<ParishEvent>>();
      fixture.repository.pending = oldResponse;
      fixture.container.invalidate(eventsProvider);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final newResponse = Completer<List<ParishEvent>>();
      fixture.repository.pending = newResponse;
      fixture.users.add(const AppUser('other-actor'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(PublicationPhoto), findsNothing);
      oldResponse.complete([event(0)]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(PublicationPhoto), findsNothing);
      newResponse.complete([]);
      await tester.pumpAndSettle();
      expect(find.text('Пока нет событий'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
