import 'package:supabase_flutter/supabase_flutter.dart';

class AppFailure implements Exception {
  const AppFailure(this.message);
  final String message;
}

String userError(Object error) {
  if (error is AppFailure) return error.message;
  if (error is AuthException) {
    return switch (error.code) {
      'over_email_send_rate_limit' =>
        'Достигнут лимит отправки писем. Проверьте входящие и спам. Повторите попытку позже.',
      'over_request_rate_limit' =>
        'Слишком много попыток. Подождите и попробуйте снова.',
      'email_address_not_authorized' =>
        'Отправка писем на этот адрес пока не настроена. Обратитесь к администратору приложения.',
      'email_address_invalid' => 'Проверьте адрес электронной почты.',
      'email_not_confirmed' =>
        'Подтвердите почту: откройте письмо или нажмите «Подтвердить почту» и введите код.',
      'invalid_credentials' => 'Неверная почта или пароль.',
      'weak_password' =>
        'Пароль не отвечает требованиям. Используйте более длинный и сложный пароль.',
      'user_already_exists' => 'Аккаунт уже существует. Попробуйте войти.',
      'otp_expired' || 'otp_disabled' =>
        'Код или ссылка недействительны, уже использованы или срок действия истёк. Запросите новое письмо.',
      'same_password' => 'Новый пароль должен отличаться от старого.',
      'session_not_found' || 'session_expired' || 'refresh_token_not_found' =>
        'Сеанс завершён. Войдите снова или запросите новое письмо для восстановления.',
      'reauthentication_needed' || 'reauthentication_not_valid' =>
        'Нужно подтвердить доступ заново. Запросите новое письмо для восстановления.',
      'email_provider_disabled' =>
        'Вход по почте отключён. Обратитесь к администратору.',
      'signup_disabled' => 'Регистрация временно недоступна.',
      _ =>
        'Не удалось выполнить действие. Проверьте соединение и повторите попытку.',
    };
  }
  if (error is PostgrestException) {
    return switch (error.message) {
      'role_edit_conflict' =>
        'Права уже изменены в другом окне. Ваш выбор сохранён на экране. Загрузите актуальные права перед повторным редактированием.',
      'role_request_conflict' =>
        'Этот запрос уже использован. Загрузите актуальные права.',
      'review_required' =>
        'Сначала рассмотрите заявку пользователя в разделе заявок клуба.',
      'email_confirmation_required' => 'Участник должен подтвердить email.',
      'request_already_reviewed' => 'Заявка уже рассмотрена. Обновите список.',
      'club_profile_required' =>
        'Перед подачей заявки заполните имя, фамилию и дату рождения в разделе «Настройки → Профиль».',
      'club_unavailable' => 'Клуб больше не принимает заявки. Выберите другой.',
      'invalid_phone' => 'Проверьте номер телефона.',
      'invalid_map_point' => 'Выберите корректную точку события на карте.',
      'invalid_avatar' =>
        'Не удалось сохранить фото. Выберите изображение ещё раз.',
      'last_super_admin' =>
        'Нельзя снять роль у последнего суперадминистратора.',
      'protected_role' =>
        'Встроенную роль изменить нельзя. Создайте отдельную роль.',
      'active_youth_membership_required' =>
        'Сначала добавьте пользователя в молодёжку.',
      'active_membership_required' =>
        'Пользователь должен быть действующим участником прихода.',
      'message_unavailable' => 'Сообщение больше недоступно.',
      'membership_already_exists' =>
        'Сначала выйдите из текущего прихода или отмените заявку.',
      'membership_banned' =>
        'Вступление в этот приход ограничено администратором.',
      'message_rate_limited' => 'Подождите немного перед следующим сообщением.',
      'profile_edit_conflict' =>
        'Профиль изменён в другом окне. Ваш ввод сохранён на экране. Нажмите «Загрузить сохранённое», чтобы получить актуальные данные.',
      'invalid_birth_date' =>
        'Укажите дату рождения с 01.01.1900 до сегодняшнего дня.',
      'invalid_profile' =>
        'Проверьте поля профиля: отображаемое имя обязательно, каждое имя — не более 100 символов.',
      'profile_unavailable' =>
        'Профиль недоступен. Попробуйте выйти из аккаунта и войти снова.',
      'edit_conflict' =>
        'Запись уже изменена. Вернитесь к списку, обновите его и откройте запись заново.',
      'invalid_membership_transition' =>
        'Заявка уже обработана или её статус изменился. Обновите список.',
      'invalid_parish' ||
      'invalid_city' ||
      'invalid_post' ||
      'invalid_content' ||
      'invalid_role' ||
      'invalid_permissions' ||
      'invalid_settings' ||
      'invalid_youth' ||
      'invalid_chat' => 'Проверьте заполнение полей и длину текста.',
      'parish_unavailable' ||
      'post_unavailable' ||
      'chat_unavailable' => 'Запись больше недоступна. Обновите список.',
      _ =>
        error.code == '23505'
            ? 'Такая запись уже существует.'
            : error.code == '42501'
            ? 'Нет доступа к этому действию.'
            : 'Не удалось сохранить изменения. Попробуйте ещё раз.',
    };
  }
  return 'Не удалось выполнить действие. Проверьте соединение и повторите попытку.';
}
