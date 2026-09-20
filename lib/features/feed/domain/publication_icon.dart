import 'package:flutter/material.dart';

class PublicationIcon {
  const PublicationIcon(this.id, this.label, this.group, this.icon);
  final String id, label, group;
  final IconData icon;
}

// Stable IDs are stored in the event; IconData stays constant for tree shaking.
const publicationIcons = <PublicationIcon>[
  PublicationIcon(
    'help_hands',
    'Помощь',
    'Помощь',
    Icons.volunteer_activism_outlined,
  ),
  PublicationIcon('help_heart', 'Поддержка', 'Помощь', Icons.favorite_border),
  PublicationIcon(
    'help_gift',
    'Пожертвование',
    'Помощь',
    Icons.redeem_outlined,
  ),
  PublicationIcon('faith_church', 'Храм', 'Праздник', Icons.church_outlined),
  PublicationIcon(
    'faith_candle',
    'Свеча',
    'Праздник',
    Icons.local_fire_department_outlined,
  ),
  PublicationIcon(
    'faith_bell',
    'Колокол',
    'Праздник',
    Icons.notifications_none,
  ),
  PublicationIcon('people_group', 'Молодёжь', 'Встреча', Icons.groups_outlined),
  PublicationIcon('people_chat', 'Беседа', 'Встреча', Icons.forum_outlined),
  PublicationIcon('people_meeting', 'Встреча', 'Встреча', Icons.people_outline),
  PublicationIcon('sport_ball', 'Футбол', 'Спорт', Icons.sports_soccer),
  PublicationIcon('sport_run', 'Бег', 'Спорт', Icons.directions_run),
  PublicationIcon('sport_bike', 'Велосипед', 'Спорт', Icons.directions_bike),
  PublicationIcon(
    'trip_bus',
    'Поездка',
    'Поездка',
    Icons.directions_bus_outlined,
  ),
  PublicationIcon('trip_route', 'Маршрут', 'Поездка', Icons.route_outlined),
  PublicationIcon('trip_boat', 'Сплав', 'Поездка', Icons.kayaking),
  PublicationIcon('learn_book', 'Книга', 'Обучение', Icons.menu_book_outlined),
  PublicationIcon(
    'learn_school',
    'Обучение',
    'Обучение',
    Icons.school_outlined,
  ),
  PublicationIcon(
    'learn_lecture',
    'Лекция',
    'Обучение',
    Icons.auto_stories_outlined,
  ),
  PublicationIcon('event_calendar', 'Событие', 'Событие', Icons.event_outlined),
  PublicationIcon(
    'event_date',
    'Расписание',
    'Событие',
    Icons.calendar_month_outlined,
  ),
];

PublicationIcon? publicationIconById(String? id) {
  for (final item in publicationIcons) {
    if (item.id == id) return item;
  }
  return null;
}

PublicationIcon suggestPublicationIcon(
  String title,
  String body, {
  String seed = '',
}) {
  final text = '$title $body'.toLowerCase().replaceAll('ё', 'е');
  // Specific activities take precedence over generic words such as «встреча».
  final group = switch (text) {
    _
        when RegExp(
          r'помощ|помочь|пожертв|благотвор|нужда|поддерж|сбор (вещ|средств|денег|продукт)|волонтер',
        ).hasMatch(text) =>
      'Помощь',
    _
        when RegExp(
          r'футбол|волейбол|баскетбол|спорт|пробеж|велосипед|турнир|трениров',
        ).hasMatch(text) =>
      'Спорт',
    _
        when RegExp(
          r'поезд|паломни|экскурс|сплав|поход|путешеств|маршрут',
        ).hasMatch(text) =>
      'Поездка',
    _
        when RegExp(
          r'лекци|обуч|урок|книг|мастер.класс|семинар|изуч',
        ).hasMatch(text) =>
      'Обучение',
    _
        when RegExp(
          r'праздник|рождеств|пасх|богослуж|литург|молеб|всенощ|причаст|исповед',
        ).hasMatch(text) =>
      'Праздник',
    _
        when RegExp(
          r'встреч|молодеж|общени|бесед|знакомств|групп',
        ).hasMatch(text) =>
      'Встреча',
    _ => 'Событие',
  };
  final options = publicationIcons
      .where((item) => item.group == group)
      .toList();
  // Unlike String.hashCode this stays identical after reload and across devices.
  var hash = 0;
  for (final code in (seed.isEmpty ? text : seed).codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  return options[hash % options.length];
}
