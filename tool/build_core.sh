#!/usr/bin/env bash
# 构建并固定 macOS sidecar。输出 shell 变量（CORE_BIN/CORE_HASH/CORE_VERSION），
# 人类可读日志写 stderr，便于 `eval "$(tool/build_core.sh)"`。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${OUT_DIR:-$ROOT/build/core}"
CORE_REPO="${EIMMORTAL_CORE_REPO:-$ROOT/third_party/encry-immortals}"
TARGET_OS="${TARGET_OS:-darwin}"
case "${TARGET_ARCH:-$(uname -m)}" in
  arm64|aarch64) GOARCH=arm64 ;;
  x86_64|amd64) GOARCH=amd64 ;;
  *) echo "不支持的架构：${TARGET_ARCH:-$(uname -m)}" >&2; exit 2 ;;
esac

mkdir -p "$OUT_DIR"
BIN="$OUT_DIR/eimmortal"

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
  echo "构建 sidecar：repo=${CORE_REPO} version=${CORE_VERSION} os=${TARGET_OS} arch=${GOARCH}" >&2
  (
    cd "$CORE_REPO"
    CGO_ENABLED=0 GOOS="$TARGET_OS" GOARCH="$GOARCH" \
      go build -trimpath \
      -ldflags "-s -w -X main.version=$CORE_VERSION" \
      -o "$BIN" ./cmd/eimmortal
  )
fi

CORE_HASH="$(shasum -a 256 "$BIN" | awk '{print $1}')"
printf '%s\n' "$CORE_HASH" > "$OUT_DIR/eimmortal.sha256"
printf '%s\n' "$CORE_VERSION" > "$OUT_DIR/eimmortal.version"
echo "sidecar 构建完成：${BIN}" >&2
echo "sha256=${CORE_HASH} version=${CORE_VERSION}" >&2

printf 'CORE_BIN=%q\n' "$BIN"
printf 'CORE_HASH=%q\n' "$CORE_HASH"
printf 'CORE_VERSION=%q\n' "$CORE_VERSION"
