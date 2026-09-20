# Запуск, Web/PWA и эксплуатация

## Окружения и зависимости

- Flutter 3.47.2 указан как целевой SDK; пакетные версии закреплены в pubspec.yaml по просмотренным страницам pub.dev. Они ещё не разрешались Flutter pub в среде создания.
- Прямые версии: flutter_riverpod 3.4.3, go_router 18.0.1, supabase_flutter 2.17.2, shared_preferences 2.5.5. Transitive lock появится только после успешного `flutter pub get`.
- dev/staging/prod — разные Supabase-проекты, разные redirect allowlists и config JSON. Секретов в config Flutter быть не должно.
- Android runner создаётся штатным Flutter SDK через `scripts/bootstrap.sh`; SHA/Gradle wrapper не имитировались вручную.
- Приложение не опубликовано и не зарегистрировано в магазинах. `org.moyprihod` — технический namespace-заполнитель; перед выпуском закрепить свой applicationId и подпись.

## Supabase

Для локальной разработки `supabase start` / `supabase db reset` выполняются из корня. Для staging создать отдельный проект, связать его Supabase CLI и после проверки target применить `supabase db push`. Не применять этот фундамент поверх чужой существующей базы: миграции рассчитаны на новый проект и меняют default grants.

В Dashboard оставить exposed API schema только `public`; не добавлять `app_private`. Убедиться, что Realtime включён, publication содержит только перечисленные пять таблиц. Указать точные адреса Auth redirect для каждого окружения. Email-подтверждение включено; локальное письмо доступно в локальном почтовом интерфейсе Supabase. Production требует настроенного SMTP.

Создать первого супер-администратора отдельной процедурой из ACCESS_CONTROL.md. Не помещать initial admin UUID в Flutter и не использовать правило «первый зарегистрированный».

## Web и iPhone

```bash
bash scripts/build_web.sh config/production.json
```

Результат в `build/web` размещается на HTTPS-хостинге с SPA fallback на `index.html`. Сейчас go_router использует стандартную URL-стратегию Flutter Web с hash-путями; переход на чистые path URLs — отдельный осознанный шаг вместе с rewrite и Auth callback-проверками. Во всех случаях проверить прямые ссылки, refresh и вход по письму.

В Safari пользователь открывает опубликованный HTTPS-адрес → «Поделиться» → «На экран Домой». Manifest задаёт standalone и иконки, apple-touch-icon — иконку iPhone. Это веб-приложение, не iOS IPA. Правильная установка и поведение должны быть проверены на физическом устройстве.

Flutter поддерживает мобильный Safari, однако совместимость конкретного приложения требует тестирования. Flutter больше не генерирует service worker по умолчанию; здесь добавлен собственный маленький worker для страницы отсутствия соединения. Он не кэширует Auth/API-запросы или содержимое приложения. См. [Flutter Web FAQ](https://docs.flutter.dev/platform-integration/web/faq).

**Офлайн:** при отсутствии сети отображается offline.html. Полная работа ленты/чатов без интернета не реализована. В кэше Service Worker нет main.dart.js, приватных материалов или сообщений; старые backend-данные из него не выдаются.

**Push:** iPhone Web Push требует поддерживаемой версии iOS и установки на главный экран; разрешение должно запрашиваться после явного действия пользователя. Это отдельная функция, не следствие наличия manifest. См. [WebKit о Web Push](https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/). Фоновое постоянно активное WebSocket-соединение на iPhone не предполагается.

### Правила хостинга

- HTTPS, SPA fallback, правильные MIME для js/wasm/json.
- `index.html`, `flutter_bootstrap.js`, `main.dart.js`, `manifest.json`, `sw.js`: `Cache-Control: no-cache` или короткое управляемое время жизни.
- Нефингерпринтованные ассеты не объявлять `immutable`; для длительного кэша внедрить versioned build paths.
- `sw.js` не должен подменяться fallback HTML. Service worker scope соответствует base href.
- При развёртывании под `/app/` использовать `flutter build web --base-href=/app/ ...`, проверить manifest scope, SW, и Auth redirects.
- Настроить CSP по фактической сборке Flutter/Supabase; не копировать неподходящую CSP, блокирующую renderer/worker. Не подключать непроверенные скрипты к origin приложения.

## Матрица проверки устройства

| Проверка | Что проверить |
|---|---|
| 320/390/430 px | Нет горизонтального переполнения, формы прокручиваются |
| Планшет/desktop | Rail только при достаточной ширине/высоте, читаемая длина строки |
| Landscape | Нижняя навигация/контент доступны на коротком экране |
| Шрифт 180–200% | Текст, кнопки, поля без потери смысла |
| Safari keyboard | Поле и действие доступны, закрытие клавиатуры не ломает viewport |
| iPhone standalone | safe-area, status bar, возврат из фона, восстановление сессии |
| Авторизация | Email callback из браузера и приложения, истёкшая ссылка, logout |
| Потеря сети | Понятная ошибка, повтор, отсутствие дубликатов сообщения при retry |
| Отзыв прав | Запрос после отзыва отклонён, UI очищается после обновления |
| Темы | Light/dark/system, повторный запуск и системное изменение темы |

## Realtime и уведомления

Postgres Changes используется у chat_messages и notifications. Ленты сейчас обновляются вручную/при возврате приложения; включение таблиц в publication не создаёт frontend-подписку автоматически. Realtime должен работать вместе с SELECT/RLS; см. [Supabase Postgres Changes](https://supabase.com/docs/guides/realtime/postgres-changes).

Перед production проверить потерю соединения, reconnect, пропуски событий, повторную выборку и смену членства. При высокой нагрузке сравнить Postgres Changes и Broadcast; не считать текущую подписку масштабированием до любых объёмов без измерений.

Outbox создаёт одну запись на уведомление. Delivery worker, блокировки/lease, retries с backoff, дедупликация и удаление недействительных подписок ещё не реализованы. Создание уведомлений доверенным producer также требует следующего этапа. Не выдавать клиенту INSERT на notifications или прямой доступ к push_subscriptions.

## Выпуск и эксплуатация

Проверить analyze/tests/build, воспроизводимую сборку с зафиксированным lock, RLS через настоящий PostgREST, несколько параллельных заявок одного пользователя, reconnect и реальные устройства. Перед production определить правила хранения/удаления данных, настроить резервные копии и проверить восстановление, метрики ошибок/задержек и аудит управления без токенов/контактов/тел сообщений в логах.
