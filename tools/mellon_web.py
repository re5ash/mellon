#!/usr/bin/env python3
"""Run or build Mellon Web with the saved Yandex configuration."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import shutil
import subprocess
import sys


REVISION = 'yandex-restore-20260914'
PUBLIC_URL = 'https://eloquent-entremet-040562.netlify.app/'


def main():
    parser = argparse.ArgumentParser(description='Запуск и сборка Mellon с Яндекс Картой.')
    parser.add_argument('mode', choices=['run', 'build'])
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    source = (root / 'lib/features/map/presentation/map_tiles.dart').read_text(encoding='utf-8')
    if 'YandexTileProvider.new' not in source or 'VectorTileLayer' in source:
        raise ValueError('Исходники карты не переключены на Яндекс. Установите restore_mellon_yandex.py.')
    config_path = root / 'config/development.json'
    if not config_path.is_file():
        raise ValueError('Не найден config/development.json. Нужен ваш файл настроек приложения.')
    try:
        config = json.loads(config_path.read_text(encoding='utf-8-sig'))
    except (ValueError, UnicodeError):
        raise ValueError('Не удалось прочитать JSON в config/development.json.') from None
    key = config.get('YANDEX_TILES_API_KEY') if isinstance(config, dict) else None
    if not isinstance(key, str) or not key.strip() or any(s in key.upper() for s in ['REPLACE', 'YOUR_']):
        raise ValueError('Не указан ключ Яндекса. Выполните: python3 tools/configure_yandex_map.py')
    flutter = shutil.which('flutter')
    if flutter is None:
        local_flutter = Path.home() / 'flutter/bin/flutter'
        if local_flutter.is_file():
            flutter = str(local_flutter)
        else:
            raise ValueError('Flutter не найден. Добавьте ~/flutter/bin в PATH.')
    define = '--dart-define-from-file=config/development.json'
    stamp = root / 'build/web/mellon-map-provider.json'
    if args.mode == 'run':
        command = [flutter, 'run', '-d', 'chrome', '--profile', '--web-port=8080', define]
    else:
        # Never leave a stamp that could be mistaken for a successful new build.
        stamp.unlink(missing_ok=True)
        command = [flutter, 'build', 'web', '--release', define,
                   '--dart-define=AUTH_REDIRECT_URL=' + PUBLIC_URL]
    print('Карта: Яндекс. Используются сохранённые настройки приложения.', flush=True)
    result = subprocess.run(command, cwd=root)
    if result.returncode:
        return result.returncode
    if args.mode == 'build':
        output = root / 'build/web'
        if not (output / 'index.html').is_file() or not (output / 'main.dart.js').is_file():
            raise ValueError('Flutter завершился без ожидаемых файлов веб-сборки.')
        stamp.write_text(json.dumps({
            'provider': 'yandex', 'revision': REVISION,
            'built_at_utc': datetime.now(timezone.utc).isoformat(),
        }, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        print('Готова сборка с Яндекс Картой: ' + str(output))
        print('В Netlify откройте существующий сайт → Deploys и загрузите папку web из build.')
        print('На Mac открыть папку: open build')
        print('После публикации обновите сайт: Cmd + Shift + R.')
        print('Проверка опубликованной версии: ' + PUBLIC_URL + 'mellon-map-provider.json')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        print('Не удалось запустить: ' + str(error), file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        sys.exit(130)
