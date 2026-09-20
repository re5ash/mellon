#!/usr/bin/env python3
"""Build and package Mellon's web startup without changing backend data."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

REVISION = 'mellon-fast-start-v1'
PUBLIC_URL = 'https://eloquent-entremet-040562.netlify.app/'


def package(output, worker_template, defer_emoji=True, *, configure_headers=True):
    output = Path(output)
    # This directory belongs exclusively to this packaging step.
    old = output / 'mellon-static'
    if old.is_symlink():
        raise ValueError('mellon-static не должен быть символической ссылкой.')
    if old.exists():
        shutil.rmtree(old)
    manifest_path = output / 'assets/FontManifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    emoji_bytes = 0
    if defer_emoji:
        emoji_path = output / 'assets/assets/fonts/NotoColorEmoji.ttf'
        if not emoji_path.is_file():
            raise ValueError('Не найден полный шрифт эмодзи; упаковка остановлена.')
        emoji_bytes = emoji_path.stat().st_size
        # Preserve the complete font as an asset; only its automatic eager load
        # is removed. Dart FontLoader installs it after the first Flutter frame.
        manifest = [item for item in manifest if item.get('family') != 'MellonEmoji']
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False), encoding='utf-8')
    html = (output / 'index.html').read_text(encoding='utf-8')
    if 'name="mellon-build"' in html:
        raise ValueError('Эта папка уже упакована. Сначала выполните новую Flutter-сборку.')
    if not re.search(r'<base\s+href=[\"\x27]/[\"\x27]', html):
        raise ValueError('Для этой сборки нужен стандартный base href="/".')
    bootstrap = output / 'flutter_bootstrap.js'
    if 'MELLON_FAST_START_V1' not in bootstrap.read_text(encoding='utf-8'):
        raise ValueError('Не установлен новый flutter_bootstrap.js.')
    required = ['main.dart.js', 'flutter_bootstrap.js', 'mellon_startup.js',
                'canvaskit/canvaskit.js', 'canvaskit/canvaskit.wasm']
    for rel in required:
        if not (output / rel).is_file():
            raise ValueError('Не найден файл сборки: ' + rel)
    # Keep root files for existing clients and native Flutter asset paths.
    # Version all code, renderer and bundled assets used by the new document.
    paths = sorted(p for p in output.rglob('*') if p.is_file() and (
        p.relative_to(output).parts[0] in ('assets', 'canvaskit') or
        (p.parent == output and p.suffix in ('.js', '.wasm') and
         p.name not in ('sw.js', 'flutter_service_worker.js'))
    ))
    digest = hashlib.sha256(REVISION.encode() + html.encode() + worker_template.encode())
    for p in paths:
        digest.update(p.relative_to(output).as_posix().encode())
        digest.update(p.read_bytes())
    version = digest.hexdigest()[:16]
    prefix = 'mellon-static/' + version + '/'
    for p in paths:
        dest = output / prefix / p.relative_to(output)
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(p.read_bytes())
    # Rewrite only local scripts; retain auth URL handling, badge CSS and the
    # iPhone gesture guard. Never change Supabase or Yandex settings.
    def script_source(match):
        name = match.group(2)
        if name.startswith(('http:', 'https:', '//', '/')):
            return match.group(0)
        if not (output / prefix / name.split('?', 1)[0]).is_file():
            return match.group(0)
        if name.startswith('mellon_chat_gestures.js?v='):
            name = 'mellon_chat_gestures.js'
        return match.group(1) + prefix + name + match.group(3)
    html = re.sub(r'(<script\b[^>]*\bsrc=")(.*?)(")', script_source, html)
    hints = ('<meta name="mellon-build" content="' + version + '">\n'
             '  <link rel="preload" as="script" href="' + prefix + 'main.dart.js">\n')
    html = html.replace('</head>', '  ' + hints + '</head>', 1)
    core = list(required)
    if (output / 'mellon_chat_gestures.js').is_file():
        core.append('mellon_chat_gestures.js')
    for name in ['FontManifest.json', 'AssetManifest.bin', 'AssetManifest.bin.json', 'AssetManifest.json']:
        if (output / 'assets' / name).is_file():
            core.append('assets/' + name)
    for family in manifest:
        for font in family.get('fonts', []):
            path = 'assets/' + font['asset']
            if not (output / path).is_file():
                raise ValueError('В манифесте указан отсутствующий шрифт: ' + path)
            core.append(path)
    release = {'id': version, 'prefix': prefix, 'core': sorted(set(core))}
    worker = worker_template.replace('__MELLON_RELEASE__', json.dumps(release))
    (output / 'sw.js').write_text(worker, encoding='utf-8')
    # Local preview supplies its own HTTP headers. Preserve the project's
    # Netlify rules unchanged when packaging solely for a local launch.
    if configure_headers:
        headers_path = output / '_headers'
        headers = headers_path.read_text(encoding='utf-8') if headers_path.exists() else ''
        if re.search(r'^\s*Cache-Control:', headers, re.I | re.M):
            raise ValueError('В _headers уже настроен Cache-Control. Нужна проверка совместимости перед публикацией.')
        headers += ('\n# Mellon: only content-versioned public assets are immutable.\n'
                    '/mellon-static/*\n  Cache-Control: public, max-age=31536000, immutable\n'
                    '/sw.js\n  Cache-Control: no-cache\n'
                    '/index.html\n  Cache-Control: no-cache\n'
                    '/\n  Cache-Control: no-cache\n')
        headers_path.write_text(headers, encoding='utf-8')
    # Publish the new entry point only once all referenced resources exist.
    (output / 'index.html').write_text(html, encoding='utf-8')
    report = {'revision': REVISION, 'build': version,
              'emoji_deferred_bytes': emoji_bytes, 'renderer': 'local-canvaskit',
              'cache': 'versioned-public-app-files-only'}
    (output / 'mellon-startup.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    return report


def main():
    root = Path(__file__).resolve().parents[1]
    if not (root / 'config/development.json').is_file():
        raise ValueError('Не найден config/development.json с настройками приложения.')
    flutter = shutil.which('flutter')
    if not flutter:
        candidate = Path.home() / 'flutter/bin/flutter'
        if not candidate.is_file():
            raise ValueError('Flutter не найден. Добавьте ~/flutter/bin в PATH.')
        flutter = str(candidate)
    output = root / 'build/web'
    (output / 'mellon-startup.json').unlink(missing_ok=True)
    defer = (root / 'assets/fonts/NotoColorEmoji.ttf').is_file()
    command = [flutter, 'build', 'web', '--release',
               '--dart-define-from-file=config/development.json',
               '--dart-define=AUTH_REDIRECT_URL=' + PUBLIC_URL,
               '--dart-define=MELLON_DEFER_EMOJI=' + str(defer).lower()]
    print('Собираем Mellon с вашими сохранёнными настройками…', flush=True)
    result = subprocess.run(command, cwd=root)
    if result.returncode:
        return result.returncode
    template = (root / 'tools/mellon_fast_sw.js').read_text(encoding='utf-8')
    report = package(output, template, defer)
    print('Готово: ' + str(output))
    print('Сборка: ' + report['build'])
    print('После первого экрана загружается шрифт эмодзи: %.1f МБ.' % (report['emoji_deferred_bytes'] / 1e6))
    print('SQL не требуется. Загрузите ВСЮ папку build/web в Deploys существующего сайта Netlify.')
    print('Открыть папку: open build')
    print('Проверка публикации: ' + PUBLIC_URL + 'mellon-startup.json')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError) as error:
        print('Сборка не подготовлена к публикации: ' + str(error), file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        sys.exit(130)
