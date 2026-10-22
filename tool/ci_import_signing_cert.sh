#!/usr/bin/env bash
# 在 CI（GitHub Actions 的 macOS runner）里把 Developer ID 证书导入临时钥匙串，
# 并把解析出的签名身份写进 $GITHUB_ENV 供后续步骤使用。
#
# 需要的环境变量：
#   MACOS_CERT_P12_BASE64     p12 文件的 base64（本地执行：base64 -i DeveloperID.p12 | pbcopy）
#   MACOS_CERT_PASSWORD       导出 p12 时设置的密码
#   MACOS_KEYCHAIN_PASSWORD   任意随机串，仅用于临时钥匙串（可以用 openssl rand -hex 16 生成）
set -euo pipefail

: "${MACOS_CERT_P12_BASE64:?缺少 MACOS_CERT_P12_BASE64}"
: "${MACOS_CERT_PASSWORD:?缺少 MACOS_CERT_PASSWORD}"

KEYCHAIN_PASSWORD="${MACOS_KEYCHAIN_PASSWORD:-$(openssl rand -hex 16)}"
WORK_DIR="${RUNNER_TEMP:-$(mktemp -d)}"
KEYCHAIN_PATH="$WORK_DIR/signing.keychain-db"
P12_PATH="$WORK_DIR/developer-id.p12"

# GitHub secret 里的 base64 可能带换行，BSD base64 解码时会忽略空白，可以直接吃。
printf '%s' "$MACOS_CERT_P12_BASE64" | base64 --decode > "$P12_PATH"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
# 默认钥匙串空闲 5 分钟自动上锁，长构建中途上锁会让 codesign 报 errSecInternalComponent。
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

# -T 让 codesign/security 免交互访问私钥（新版 macOS 会忽略 -T，真正生效的是下面的 partition list）。
security import "$P12_PATH" -k "$KEYCHAIN_PATH" -P "$MACOS_CERT_PASSWORD" \
  -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/productbuild

# 关键一步：缺少它 codesign 会弹出钥匙串授权对话框，在无头 runner 上直接失败。
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
  -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null

# Developer ID G2 中间证书在部分镜像里缺失，best-effort 补齐，失败不影响签名。
if curl -fsSL --max-time 30 -o "$WORK_DIR/DeveloperIDG2CA.cer" \
  https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer; then
  security import "$WORK_DIR/DeveloperIDG2CA.cer" -k "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
else
  echo "::warning::未能下载 Developer ID G2 中间证书，跳过" >&2
fi

# 把临时钥匙串插进搜索列表，保留已有的钥匙串，避免影响其它步骤。
existing_keychains=""
while IFS= read -r line; do
  existing_keychains+=" $(printf '%s' "$line" | tr -d '"')"
done < <(security list-keychains -d user)
# shellcheck disable=SC2086  # 这里就是要把路径列表拆成多个参数
security list-keychains -d user -s "$KEYCHAIN_PATH" $existing_keychains

IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" \
  | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -n 1)"
if [[ -z "$IDENTITY" ]]; then
  echo "::error::临时钥匙串里没有 Developer ID Application 身份" >&2
  security find-identity -v -p codesigning "$KEYCHAIN_PATH" >&2 || true
  exit 1
fi

if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    echo "CODESIGN_IDENTITY=$IDENTITY"
    echo "KEYCHAIN_PATH=$KEYCHAIN_PATH"
  } >> "$GITHUB_ENV"
fi

echo "签名身份：$IDENTITY"
security find-identity -v -p codesigning "$KEYCHAIN_PATH" | sed 's/^/  /'
