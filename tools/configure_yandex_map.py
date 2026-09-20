#!/usr/bin/env python3
"""Add a Tiles API key to the existing local Flutter build configuration."""
from datetime import datetime
from pathlib import Path
import json
import os
import re
import shutil
import sys
import tempfile


def configure(root, key):
    root = root.resolve()
    path = root / 'config/development.json'
    if not (root / 'pubspec.yaml').is_file() or not path.is_file():
        raise ValueError('Запустите из проекта Mellon с существующим config/development.json.')
    if path.is_symlink() or root not in path.resolve().parents:
        raise ValueError('Файл настройки должен находиться внутри проекта.')
    key = key.strip()
    if not re.fullmatch(r'[A-Za-z0-9_-]{16,256}', key):
        raise ValueError('Вставьте только ключ Tiles API из кабинета Яндекса, без адреса сайта и кавычек.')
    old = path.read_bytes()
    config = json.loads(old.decode('utf-8-sig'))
    if not isinstance(config, dict):
        raise ValueError('Файл config/development.json должен содержать JSON-объект.')
    if config.get('YANDEX_TILES_API_KEY') == key:
        return False
    config['YANDEX_TILES_API_KEY'] = key
    new = (json.dumps(config, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    backup = root.parent / (root.name + '_update_backups') / (
        datetime.now().strftime('%Y%m%d_%H%M%S_%f') + '_yandex_key') / 'development.json'
    backup.parent.mkdir(parents=True, exist_ok=False)
    shutil.copy2(path, backup)
    os.chmod(backup, 0o600)
    if backup.read_bytes() != old:
        raise ValueError('Настройки изменились во время создания резервной копии.')
    fd, temporary = tempfile.mkstemp(prefix='development.json.update-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(new)
            stream.flush()
            os.fsync(stream.fileno())
        if path.read_bytes() != old:
            raise ValueError('Настройки изменились во время записи. Запустите ещё раз.')
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return True


if __name__ == '__main__':
    try:
        print('В кабинете https://developer.tech.yandex.ru/ подключите Tiles API.')
        print('Построение маршрутов не используется; нужен только ключ Tiles API.')
        value = input('Вставьте ключ и нажмите Enter: ')
        if not value.strip():
            print('Ключ не введён. Настройки не изменены.')
        else:
            changed = configure(Path.cwd(), value)
            print('Ключ сохранён.' if changed else 'Этот ключ уже сохранён.')
            print('Перезапустите Flutter. Активация ключа у Яндекса может занять до 15 минут.')
    except (OSError, ValueError, EOFError) as error:
        print('Настройка остановлена: ' + str(error), file=sys.stderr)
        sys.exit(1)
