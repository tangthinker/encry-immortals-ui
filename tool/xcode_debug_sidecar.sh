#!/usr/bin/env bash
# Xcode Debug build phase: put a runnable sidecar inside the .app so plain
# `flutter run -d macos` works without exporting EIMMORTAL_CORE_PATH.
# Release is handled by tool/build_macos.sh (sign + SHA-256 pinning).
set -euo pipefail

if [[ "${CONFIGURATION:-}" != "Debug" && "${CONFIGURATION:-}" != "Profile" ]]; then
  exit 0
fi

REPO_ROOT="$(cd "${PROJECT_DIR:?}/.." && pwd)"
DEST_DIR="${BUILT_PRODUCTS_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}/bin"
DEST="$DEST_DIR/eimmortal"
CORE_REPO="$REPO_ROOT/third_party/encry-immortals"
CACHED="$REPO_ROOT/build/core/eimmortal"

mkdir -p "$DEST_DIR"

SOURCE=""
if [[ -n "${EIMMORTAL_CORE_PATH:-}" ]]; then
  if [[ ! -x "$EIMMORTAL_CORE_PATH" ]]; then
    echo "error: EIMMORTAL_CORE_PATH 不是可执行文件：${EIMMORTAL_CORE_PATH}" >&2
    exit 1
  fi
  SOURCE="$EIMMORTAL_CORE_PATH"
  echo "note: 使用 EIMMORTAL_CORE_PATH 的 sidecar" >&2
elif [[ -d "$CORE_REPO/cmd/eimmortal" ]] && command -v go >/dev/null 2>&1; then
  VERSION="$(git -C "$CORE_REPO" describe --tags --always --dirty 2>/dev/null || echo 0.0.0-dev)"
  GOARCH_VALUE="$(go env GOARCH)"
  BUILD_DIR="${DERIVED_FILE_DIR:-$REPO_ROOT/build/core}"
  mkdir -p "$BUILD_DIR"
  SOURCE="$BUILD_DIR/eimmortal-debug"
  echo "note: 从 third_party 构建 sidecar（${VERSION} / ${GOARCH_VALUE}）" >&2
  (
    cd "$CORE_REPO"
    CGO_ENABLED=0 GOOS=darwin GOARCH="$GOARCH_VALUE" \
      go build -trimpath \
      -ldflags "-s -w -X main.version=$VERSION" \
      -o "$SOURCE" ./cmd/eimmortal
  )
elif [[ -x "$CACHED" ]]; then
  SOURCE="$CACHED"
  echo "note: 使用已构建的 sidecar：${CACHED}" >&2
else
  echo "error: 找不到 sidecar。执行 ./tool/build_core.sh，或初始化 third_party submodule 并安装 Go。" >&2
  exit 1
fi

cp "$SOURCE" "$DEST"
chmod 755 "$DEST"
# Debug 使用 ad-hoc 签名；Release 由工具脚本统一签名并固定哈希。
if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$DEST" >/dev/null 2>&1 || true
fi
echo "note: 已注入 sidecar 到 $(basename "$DEST_DIR")/bin/eimmortal" >&2
