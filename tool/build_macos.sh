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
echo "sidecar archs: $(lipo -archs "$CORE_BIN")" >&2
lipo -verify_arch arm64 "$CORE_BIN" || {
  echo "::error::universal sidecar is missing arm64 (archs: $(lipo -archs "$CORE_BIN"))" >&2
  exit 1
}
lipo -verify_arch x86_64 "$CORE_BIN" || {
  echo "::error::universal sidecar is missing x86_64 (archs: $(lipo -archs "$CORE_BIN"))" >&2
  exit 1
}

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
echo "app executable archs: $(lipo -archs "$MAIN_BIN")" >&2
if [[ -f "$APP_BIN" ]]; then
  echo "App.framework archs: $(lipo -archs "$APP_BIN")" >&2
fi
lipo -verify_arch arm64 "$MAIN_BIN" || {
  echo "::error::app executable is missing arm64 (archs: $(lipo -archs "$MAIN_BIN"))" >&2
  exit 1
}
lipo -verify_arch x86_64 "$MAIN_BIN" || {
  echo "::error::app executable is missing x86_64 (archs: $(lipo -archs "$MAIN_BIN"))" >&2
  exit 1
}
if [[ -f "$APP_BIN" ]]; then
  lipo -verify_arch arm64 "$APP_BIN" || {
    echo "::error::App.framework is missing arm64 (archs: $(lipo -archs "$APP_BIN"))" >&2
    exit 1
  }
  lipo -verify_arch x86_64 "$APP_BIN" || {
    echo "::error::App.framework is missing x86_64 (archs: $(lipo -archs "$APP_BIN"))" >&2
    exit 1
  }
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
