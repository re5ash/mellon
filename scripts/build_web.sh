#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname -- "${BASH_SOURCE[0]}")/.."
config_file="${1:-config/production.json}"
flutter build web --release --dart-define-from-file="$config_file"
# Serve build/web over HTTPS. Use the routing/cache rules in docs/OPERATIONS.md.
