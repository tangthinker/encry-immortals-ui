#!/usr/bin/env bash
# 构建本地 macOS release app，并把固定哈希的 sidecar 放进 bundle。
# 这是 ad-hoc 签名版本；对外分发需要 Developer ID + notarization。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDENTITY="${CODESIGN_IDENTITY:--}"
# A release must run on both Apple Silicon and Intel. The Flutter app is
# already universal; the Go sidecar must be merged explicitly.
export TARGET_ARCH="${TARGET_ARCH:-universal}"
eval "$("$ROOT/tool/build_core.sh")"
SIDECAR_ARCHS="$(lipo -archs "$CORE_BIN")"
echo "sidecar archs: ${SIDECAR_ARCHS}" >&2
if [[ " $SIDECAR_ARCHS " != *" arm64 "* || " $SIDECAR_ARCHS " != *" x86_64 "* ]]; then
  echo "::error::universal sidecar is missing an architecture (archs: ${SIDECAR_ARCHS})" >&2
  exit 1
fi

sign_code() {
  if [[ "$IDENTITY" == "-" ]]; then
    codesign --force --sign - "$1"
  else
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$1"
  fi
}

# codesign 会改写 Mach-O，必须在签名之后计算 SHA-256，否则运行时校验必然失败。
sign_code "$CORE_BIN" >/dev/null 2>&1
CORE_HASH="$(shasum -a 256 "$CORE_BIN" | awk '{print $1}')"
printf '%s\n' "$CORE_HASH" > "$ROOT/build/core/eimmortal.sha256"
echo "已签名 sidecar，最终 sha256=${CORE_HASH}" >&2

APP="$ROOT/build/macos/Build/Products/Release/Encry Immortals.app"
echo "构建 Flutter release（universal，core sha256=${CORE_HASH}）…" >&2
(
  cd "$ROOT"
  flutter --no-version-check build macos --release \
    --dart-define=EIMMORTAL_CORE_SHA256="${CORE_HASH}"
)

mkdir -p "$APP/Contents/Resources/bin"
cp "${CORE_BIN}" "$APP/Contents/Resources/bin/eimmortal"
chmod 755 "$APP/Contents/Resources/bin/eimmortal"
printf '%s\n%s\n' "$CORE_VERSION" "$CORE_HASH" \
  > "$APP/Contents/Resources/core-build.txt"

# sidecar 在复制前已经签好；复制不会改变哈希。再签整个 app。
sign_code "$APP"
codesign --verify --deep --strict "$APP"
MAIN_BIN="$APP/Contents/MacOS/Encry Immortals"
APP_BIN="$APP/Contents/Frameworks/App.framework/Versions/A/App"
APP_ARCHS="$(lipo -archs "$MAIN_BIN")"
echo "app executable archs: ${APP_ARCHS}" >&2
if [[ " $APP_ARCHS " != *" arm64 "* || " $APP_ARCHS " != *" x86_64 "* ]]; then
  echo "::error::app executable is missing an architecture (archs: ${APP_ARCHS})" >&2
  exit 1
fi
if [[ -f "$APP_BIN" ]]; then
  APP_FRAMEWORK_ARCHS="$(lipo -archs "$APP_BIN")"
  echo "App.framework archs: ${APP_FRAMEWORK_ARCHS}" >&2
  if [[ " $APP_FRAMEWORK_ARCHS " != *" arm64 "* || " $APP_FRAMEWORK_ARCHS " != *" x86_64 "* ]]; then
    echo "::error::App.framework is missing an architecture (archs: ${APP_FRAMEWORK_ARCHS})" >&2
    exit 1
  fi
fi
BUNDLED_HASH="$(shasum -a 256 "$APP/Contents/Resources/bin/eimmortal" | awk '{print $1}')"
if [[ "$BUNDLED_HASH" != "$CORE_HASH" ]]; then
  echo "bundle 内 sidecar 哈希与构建期常量不一致：$BUNDLED_HASH != $CORE_HASH" >&2
  exit 1
fi

echo "release app: $APP" >&2
echo "core version: ${CORE_VERSION}" >&2
echo "core sha256:  ${CORE_HASH}" >&2
echo "bundle verify:" >&2
codesign --verify --deep --strict --verbose=1 "$APP" 2>&1 | sed 's/^/  /' >&2
echo "提示：默认 ad-hoc 签名（CODESIGN_IDENTITY=-）；分发需 Developer ID、hardened runtime 与 notarytool。" >&2
