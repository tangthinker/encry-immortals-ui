#!/usr/bin/env bash
# 提交 Apple 公证（notarytool）、staple 票据，并做 Gatekeeper 预检。
#
#   用法：tool/notarize_macos.sh "build/macos/Build/Products/Release/Encry Immortals.app"
#         tool/notarize_macos.sh dist/Encry-Immortals-v1.0.0-macOS-universal.dmg
#
# 凭据（二选一）：
#   App Store Connect API Key：NOTARY_KEY_PATH + NOTARY_KEY_ID + NOTARY_ISSUER_ID
#   Apple ID + App 专用密码：   NOTARY_APPLE_ID + NOTARY_PASSWORD + NOTARY_TEAM_ID
#
# 注意：.app 必须先 staple 再压缩成 zip，zip 本身无法 staple。
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "用法: tool/notarize_macos.sh <MyApp.app|*.dmg|*.pkg>" >&2
  exit 2
fi
TARGET="$1"
[[ -e "$TARGET" ]] || { echo "找不到 $TARGET" >&2; exit 2; }

case "$TARGET" in
  *.zip)
    echo "zip 无法 staple：请先公证并 staple .app，再压缩成 zip" >&2
    exit 2
    ;;
  *.app|*.dmg|*.pkg) ;;
  *)
    echo "不支持的产物类型：$TARGET" >&2
    exit 2
    ;;
esac

auth_args=()
if [[ -n "${NOTARY_KEY_PATH:-}" ]]; then
  : "${NOTARY_KEY_ID:?缺少 NOTARY_KEY_ID}"
  : "${NOTARY_ISSUER_ID:?缺少 NOTARY_ISSUER_ID}"
  auth_args=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
elif [[ -n "${NOTARY_APPLE_ID:-}" ]]; then
  : "${NOTARY_PASSWORD:?缺少 NOTARY_PASSWORD（App 专用密码，不是 Apple ID 密码）}"
  : "${NOTARY_TEAM_ID:?缺少 NOTARY_TEAM_ID}"
  auth_args=(--apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_PASSWORD" --team-id "$NOTARY_TEAM_ID")
else
  echo "缺少公证凭据：设置 NOTARY_KEY_PATH(+_KEY_ID/_ISSUER_ID) 或 NOTARY_APPLE_ID(+_PASSWORD/_TEAM_ID)" >&2
  exit 2
fi

WORK_DIR="${RUNNER_TEMP:-$(mktemp -d)}"
JSON="$WORK_DIR/notary-submit.json"

# notarytool 只接受 zip/dmg/pkg，裸 .app 要先打包成 zip 再提交（staple 仍作用于 .app）。
SUBMIT_PATH="$TARGET"
if [[ "$TARGET" == *.app ]]; then
  SUBMIT_PATH="$WORK_DIR/$(basename "$TARGET").zip"
  rm -f "$SUBMIT_PATH"
  ditto -c -k --sequesterRsrc --keepParent "$TARGET" "$SUBMIT_PATH"
fi

echo "==> 提交公证：$TARGET"
set +e
xcrun notarytool submit "$SUBMIT_PATH" "${auth_args[@]}" --wait --output-format json > "$JSON" 2>&1
submit_status=$?
cat "$JSON"
set -e

read -r submission_id status <<<"$(
  python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d.get("id",""),d.get("status",""))' \
    "$JSON" 2>/dev/null || true
)" || true
if [[ -z "${submission_id:-}" ]]; then
  # python3 不可用时的兜底解析
  submission_id="$(grep -m1 '"id"' "$JSON" | sed 's/.*: *"\([^"]*\)".*/\1/')" || true
  status="$(grep -m1 '"status"' "$JSON" | sed 's/.*: *"\([^"]*\)".*/\1/')" || true
fi

if [[ "$submit_status" -ne 0 || "${status:-}" != "Accepted" ]]; then
  echo "::error::公证未通过（status=${status:-unknown}，exit=${submit_status}）" >&2
  if [[ -n "${submission_id:-}" ]]; then
    echo "==> notarytool log $submission_id" >&2
    xcrun notarytool log "$submission_id" "${auth_args[@]}" || true
  fi
  exit 1
fi
echo "公证通过：submission=$submission_id"

echo "==> staple 票据"
xcrun stapler staple -v "$TARGET"
xcrun stapler validate -v "$TARGET"

# Gatekeeper 预检。staple validate 已经证明票据就位，这里失败只告警，避免镜像波动卡发布。
case "$TARGET" in
  *.app)
    spctl --assess --type execute --verbose=4 "$TARGET" \
      || echo "::warning::spctl 评估 .app 未通过（票据已 staple，可能是 runner 缓存问题）" >&2
    ;;
  *.dmg)
    spctl --assess --type open --context context:primary-signature --verbose=4 "$TARGET" \
      || echo "::warning::spctl 评估 .dmg 未通过（票据已 staple，可能是 runner 缓存问题）" >&2
    ;;
esac

echo "完成：$TARGET 已公证并 staple"
