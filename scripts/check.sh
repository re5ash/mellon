#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname -- "${BASH_SOURCE[0]}")/.."
flutter pub get
dart format lib test
flutter analyze --fatal-infos
flutter test
python3 scripts/check_structure.py
