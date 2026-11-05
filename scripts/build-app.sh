#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
APP_PATH="$PROJECT_ROOT/dist/PromptPolish.app"
if pgrep -f "$APP_PATH/Contents/MacOS/PromptPolish" >/dev/null; then
    printf 'Please quit PromptPolish before rebuilding its app bundle.\n' >&2
    exit 1
fi
swift build -c release --product PromptPolish
BINARY_DIR="$(swift build -c release --show-bin-path)"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BINARY_DIR/PromptPolish" "$APP_PATH/Contents/MacOS/PromptPolish"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
chmod +x "$APP_PATH/Contents/MacOS/PromptPolish"
plutil -lint "$APP_PATH/Contents/Info.plist"
codesign --force --sign "${PROMPTPOLISH_SIGN_IDENTITY:--}" --identifier com.kker.PromptPolish "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
printf '\nBuilt: %s\n' "$APP_PATH"
