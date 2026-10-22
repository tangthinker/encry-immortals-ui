#!/usr/bin/env bash
# 构建并固定 sidecar。输出 shell 变量（CORE_BIN/CORE_HASH/CORE_VERSION），
# 人类可读日志写 stderr，便于 `eval "$(tool/build_core.sh)"`。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT/build/core}"
CORE_REPO="${EIMMORTAL_CORE_REPO:-$ROOT/third_party/encry-immortals}"
TARGET_OS="${TARGET_OS:-darwin}"
TARGET_ARCH="${TARGET_ARCH:-$(uname -m)}"

BUILD_UNIVERSAL=0
case "$TARGET_ARCH" in
  arm64|aarch64) GOARCH=arm64 ;;
  x86_64|amd64) GOARCH=amd64 ;;
  universal)
    BUILD_UNIVERSAL=1
    GOARCH=arm64
    ;;
  *)
    echo "不支持的架构：$TARGET_ARCH" >&2
    exit 2
    ;;
esac

mkdir -p "$OUT_DIR"
BIN="$OUT_DIR/eimmortal"

build_one() {
  local goarch="$1"
  local output="$2"
  (
    cd "$CORE_REPO"
    CGO_ENABLED=0 GOOS="$TARGET_OS" GOARCH="$goarch" \
      go build -trimpath \
      -ldflags "-s -w -X main.version=$CORE_VERSION" \
      -o "$output" ./cmd/eimmortal
  )
}

if [[ -n "${EIMMORTAL_CORE_BIN:-}" ]]; then
  if [[ ! -x "$EIMMORTAL_CORE_BIN" ]]; then
    echo "EIMMORTAL_CORE_BIN 不可执行：$EIMMORTAL_CORE_BIN" >&2
    exit 2
  fi
  cp "$EIMMORTAL_CORE_BIN" "$BIN"
  chmod 755 "$BIN"
  CORE_VERSION="$("$BIN" version | awk '{print $2}')"
  echo "使用现有 sidecar：${EIMMORTAL_CORE_BIN}（${CORE_VERSION}）" >&2
else
  if [[ ! -d "$CORE_REPO" ]]; then
    echo "找不到核心仓库：$CORE_REPO" >&2
    echo "设置 EIMMORTAL_CORE_REPO，或把固定 tag 的核心仓库放到 third_party/encry-immortals。" >&2
    exit 2
  fi
  CORE_VERSION="$(git -C "$CORE_REPO" describe --tags --always --dirty 2>/dev/null || echo 0.0.0-dev)"
  if [[ "$BUILD_UNIVERSAL" == 1 ]]; then
    if [[ "$TARGET_OS" != "darwin" ]]; then
      echo "universal sidecar 只支持 macOS（TARGET_OS=darwin）。" >&2
      exit 2
    fi
    command -v lipo >/dev/null 2>&1 || {
      echo "缺少 lipo，无法合并 universal sidecar。" >&2
      exit 2
    }
    echo "构建 universal sidecar：repo=${CORE_REPO} version=${CORE_VERSION} os=${TARGET_OS} arch=arm64+x86_64" >&2
    ARM_BIN="$OUT_DIR/eimmortal-arm64"
    AMD_BIN="$OUT_DIR/eimmortal-amd64"
    build_one arm64 "$ARM_BIN"
    build_one amd64 "$AMD_BIN"
    lipo -create -output "$BIN" "$ARM_BIN" "$AMD_BIN"
    ARCHS="$(lipo -archs "$BIN")"
    echo "universal sidecar archs: ${ARCHS}" >&2
    if [[ " $ARCHS " != *" arm64 "* || " $ARCHS " != *" x86_64 "* ]]; then
      echo "::error::universal sidecar is missing an architecture (archs: ${ARCHS})" >&2
      exit 1
    fi
    rm -f "$ARM_BIN" "$AMD_BIN"
    chmod 755 "$BIN"
  else
    echo "构建 sidecar：repo=${CORE_REPO} version=${CORE_VERSION} os=${TARGET_OS} arch=${GOARCH}" >&2
    build_one "$GOARCH" "$BIN"
    chmod 755 "$BIN"
  fi
fi

CORE_HASH="$(shasum -a 256 "$BIN" | awk '{print $1}')"
printf '%s\n' "$CORE_HASH" > "$OUT_DIR/eimmortal.sha256"
printf '%s\n' "$CORE_VERSION" > "$OUT_DIR/eimmortal.version"
echo "sidecar 构建完成：${BIN}" >&2
echo "sha256=${CORE_HASH} version=${CORE_VERSION}" >&2
lipo -info "$BIN" >&2 || true

printf 'CORE_BIN=%q\n' "$BIN"
printf 'CORE_HASH=%q\n' "$CORE_HASH"
printf 'CORE_VERSION=%q\n' "$CORE_VERSION"
