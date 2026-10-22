#!/usr/bin/env bash
# 构建 macOS release app，并把固定哈希的 sidecar 放进 bundle。
# 默认 ad-hoc 签名；设置 CODESIGN_IDENTITY 时改用 Developer ID（hardened runtime + 时间戳），
# 之后用 tool/notarize_macos.sh 提交公证。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDENTITY="${CODESIGN_IDENTITY:--}"
# A release must run on both Apple Silicon and Intel. The Flutter app is
# already universal; the Go sidecar must be merged explicitly.
export TARGET_ARCH="${TARGET_ARCH:-universal}"
case "$TARGET_ARCH" in
  universal) REQUIRED_ARCHS="arm64 x86_64" ;;
  arm64|aarch64) REQUIRED_ARCHS="arm64" ;;
  x86_64|amd64) REQUIRED_ARCHS="x86_64" ;;
  *)
    echo "不支持的 TARGET_ARCH：$TARGET_ARCH（支持 universal/arm64/x86_64）" >&2
    exit 2
    ;;
esac

require_archs() {
  local path="$1" label="$2"
  shift 2
  local archs required
  archs="$(lipo -archs "$path")"
  echo "${label} archs: ${archs}" >&2
  for required in "$@"; do
    if [[ " $archs " != *" $required "* ]]; then
      echo "::error::${label} is missing ${required} (archs: ${archs})" >&2
      return 1
    fi
  done
}

eval "$("$ROOT/tool/build_core.sh")"
require_archs "$CORE_BIN" "sidecar" $REQUIRED_ARCHS

sign_code() {
  if [[ "$IDENTITY" == "-" ]]; then
    codesign --force --sign - "$1"
  else
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$1"
  fi
}

# Xcode 模板把 CODE_SIGN_IDENTITY 固定成了 "-"，所以 flutter build 产出的
# App.framework / FlutterMacOS.framework 都是 ad-hoc 签名。只重签外层 .app 的话，
# notarytool 会因为内层代码不是 Developer ID 签名而拒绝，必须自内向外逐个换签。
sign_nested() {
  local app="$1" item
  local frameworks="$app/Contents/Frameworks"
  [[ -d "$frameworks" ]] || return 0
  while IFS= read -r -d '' item; do
    echo "重签：${item##*/Frameworks/}" >&2
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$item"
  done < <(find "$frameworks" -depth -mindepth 1 \
             \( -name '*.framework' -o -name '*.dylib' -o -name '*.app' \) -print0)
}

# codesign 会改写 Mach-O，必须在签名之后计算 SHA-256，否则运行时校验必然失败。
sign_code "$CORE_BIN" >/dev/null 2>&1
CORE_HASH="$(shasum -a 256 "$CORE_BIN" | awk '{print $1}')"
printf '%s\n' "$CORE_HASH" > "$ROOT/build/core/eimmortal.sha256"
echo "已签名 sidecar，最终 sha256=${CORE_HASH}" >&2

APP="$ROOT/build/macos/Build/Products/Release/Encry Immortals.app"
# 同一工作区先构建 arm64 再构建 universal 时，Xcode 可能复用上次的 main binary。
# 删掉旧 app 强制重新链接，确保当前 TARGET_ARCH 与主可执行文件一致。
rm -rf "$APP"
echo "构建 Flutter release（target=${TARGET_ARCH}，core sha256=${CORE_HASH}）…" >&2
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

# arm64 变体把主可执行文件裁成单架构；App.framework 保留 universal 不影响 arm64 启动。
if [[ "$TARGET_ARCH" == "arm64" ]]; then
  THIN_MAIN="$APP/Contents/MacOS/Encry Immortals"
  if lipo -archs "$THIN_MAIN" | grep -qw x86_64; then
    rm -f "${THIN_MAIN}.arm64"
    lipo -thin arm64 "$THIN_MAIN" -output "${THIN_MAIN}.arm64"
    mv "${THIN_MAIN}.arm64" "$THIN_MAIN"
    echo "arm64 app executable thinned to: $(lipo -archs "$THIN_MAIN")" >&2
  fi
fi

# sidecar 在复制前已经签好；复制不会改变哈希。再签整个 app。
if [[ "$IDENTITY" == "-" ]]; then
  sign_code "$APP"
else
  sign_nested "$APP"
  # 显式带上 entitlements：--force 重签会连带替换掉旧签名里的 entitlements。
  codesign --force --options runtime --timestamp \
    --entitlements "$ROOT/macos/Runner/Release.entitlements" \
    --sign "$IDENTITY" "$APP"
fi
codesign --verify --deep --strict "$APP"
MAIN_BIN="$APP/Contents/MacOS/Encry Immortals"
APP_BIN="$APP/Contents/Frameworks/App.framework/Versions/A/App"
require_archs "$MAIN_BIN" "app executable" $REQUIRED_ARCHS
if [[ -f "$APP_BIN" ]]; then
  require_archs "$APP_BIN" "App.framework" $REQUIRED_ARCHS
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
if [[ "$IDENTITY" == "-" ]]; then
  echo "提示：当前为 ad-hoc 签名；对外分发请设置 CODESIGN_IDENTITY 后运行 tool/notarize_macos.sh。" >&2
else
  echo "提示：已用 Developer ID 签名，下一步运行 tool/notarize_macos.sh 提交公证。" >&2
fi
