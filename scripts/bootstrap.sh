#!/usr/bin/env bash
set -euo pipefail
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"
command -v flutter >/dev/null || { echo 'Установите Flutter 3.47.2 и добавьте flutter в PATH.'; exit 1; }
if [[ ! -d android ]]; then
  generated_dir="$(mktemp -d)"
  trap 'rm -rf -- "$generated_dir"' EXIT
  flutter create --empty --platforms=android --org=org.moyprihod --project-name=moy_prihod --no-pub "$generated_dir/runner"
  cp -R "$generated_dir/runner/android" "$project_root/android"
  python3 scripts/configure_android.py
fi
flutter pub get
# Review and commit the generated android/ runner and pubspec.lock to your repository.
