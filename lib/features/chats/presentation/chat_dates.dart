const _weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
const _months = [
  'января',
  'февраля',
  'марта',
  'апреля',
  'мая',
  'июня',
  'июля',
  'августа',
  'сентября',
  'октября',
  'ноября',
  'декабря',
];

String chatClock(DateTime value) {
  final date = value.toLocal();
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

bool sameChatDay(DateTime a, DateTime b) {
  final first = a.toLocal(), second = b.toLocal();
  return first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}

int _daysAgo(DateTime date, DateTime now) => DateTime.utc(
  now.year,
  now.month,
  now.day,
).difference(DateTime.utc(date.year, date.month, date.day)).inDays;

String chatListTimestamp(DateTime? value, {DateTime? now}) {
  if (value == null) return '';
  final date = value.toLocal(), today = (now ?? DateTime.now()).toLocal();
  final days = _daysAgo(date, today);
  if (days == 0) return chatClock(date);
  if (days == 1) return 'Вчера';
  if (days > 1 && days < 7) return _weekdays[date.weekday - 1];
  return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}'
      '${date.year == today.year ? '' : '.${date.year}'}';
}

String chatDayLabel(DateTime value, {DateTime? now}) {
  final date = value.toLocal(), today = (now ?? DateTime.now()).toLocal();
  final days = _daysAgo(date, today);
  if (days == 0) return 'Сегодня';
  if (days == 1) return 'Вчера';
  return '${date.day} ${_months[date.month - 1]}'
      '${date.year == today.year ? '' : ' ${date.year}'}';
}
