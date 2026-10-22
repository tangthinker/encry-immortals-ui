# macOS Developer ID 签名与公证（CI 版）

发布流水线在 GitHub Actions 上跑，签名材料不进仓库，全部通过 Actions Secrets 注入。
未配置 `MACOS_CERT_P12_BASE64` 时，工作流自动退回原来的 ad-hoc 签名流程，不会失败。

## 1. 申请证书（只做一次，在本地 Mac 上）

1. 钥匙串访问 → 证书助理 → **从证书颁发机构请求证书** → 存储到磁盘，得到 `CertificateSigningRequest.certSigningRequest`。
   - 这一步在哪台机器做都行，但**私钥只存在于这台机器的钥匙串**里，后面的 `.p12` 必须在这台机器导出。
2. 打开 <https://developer.apple.com/account/resources/certificates/add>：
   - 证书类型选 **Developer ID Application**（分发 `.app`/`.dmg`/`.zip`；只有 `.pkg` 才需要另外一张 Developer ID Installer）。
   - 中间证书选 **G2 Sub-CA (Xcode 11.4.1 or later)**。
   - `Choose File` 上传第 1 步生成的 CSR，下载 `.cer` 并双击安装。
3. 打开钥匙串访问 → 登录 → **我的证书**，找到 `Developer ID Application: 你的名字 (TEAMID)`：
   - 确认它下面挂着私钥（能展开）。
   - 右键 → 导出 → `.p12`，设置一个强密码（就是后面的 `MACOS_CERT_PASSWORD`）。
4. 转成 base64 放进 secret：

   ```bash
   base64 -i DeveloperID.p12 | pbcopy
   ```

## 2. 创建公证用的 App Store Connect API Key

<https://appstoreconnect.apple.com> → 用户和访问 → 集成 → **App Store Connect API** → 团队密钥 → 生成密钥：

- 角色选 **Developer** 即可（不需要 Admin）。
- `.p8` **只能下载一次**，务必当场保存。
- 记下 **Key ID** 和页面顶部的 **Issuer ID**。

> 也可以用 Apple ID + App 专用密码（`NOTARY_APPLE_ID` / `NOTARY_PASSWORD` / `NOTARY_TEAM_ID`），
> 但 API Key 不随密码轮换失效，更适合 CI，`tool/notarize_macos.sh` 两种都支持。

## 3. 配置 GitHub Secrets

仓库 → Settings → Secrets and variables → Actions → New repository secret：

| Secret | 内容 |
| --- | --- |
| `MACOS_CERT_P12_BASE64` | `base64 -i DeveloperID.p12 \| pbcopy` 的结果 |
| `MACOS_CERT_PASSWORD` | 导出 p12 时设置的密码 |
| `MACOS_KEYCHAIN_PASSWORD` | 随便一个随机串，`openssl rand -hex 16` 生成，仅用于 CI 临时钥匙串 |
| `NOTARY_KEY_P8_BASE64` | `base64 -i AuthKey_XXXX.p8 \| pbcopy` 的结果 |
| `NOTARY_KEY_ID` | API Key 的 Key ID（10 位） |
| `NOTARY_ISSUER_ID` | App Store Connect 的 Issuer ID（UUID 形式） |

只要 `MACOS_CERT_P12_BASE64` 存在，`Release` 工作流就会自动切换为签名 + 公证模式。

## 4. 流水线做了什么

`tool/ci_import_signing_cert.sh`（构建前）：

1. 解码 p12，建一个临时钥匙串并导入身份；
2. `security set-key-partition-list` 授权 `codesign` 免交互访问私钥（缺这步在无头环境必报 `errSecInternalComponent`）；
3. 把解析出的 `Developer ID Application: ...` 身份写进 `$GITHUB_ENV` 的 `CODESIGN_IDENTITY`。

`tool/build_macos.sh`（构建）：

- `CODESIGN_IDENTITY` 非空时，先由内向外把 `Contents/Frameworks/` 里的 framework 全部换成 Developer ID 签名（Xcode 模板写死了 `CODE_SIGN_IDENTITY = "-"`，不换签内层代码公证必被拒），
- 再带 `--options runtime --timestamp --entitlements macos/Runner/Release.entitlements` 重签整个 `.app`。

`tool/notarize_macos.sh`（打包）：

1. 把 `.app` 压成 zip 提交 `notarytool --wait`，通过后 `stapler staple` 到 `.app`；
2. 用 stapled 的 `.app` 生成 zip 和 dmg，dmg 单独签 Developer ID；
3. 提交 dmg 公证 → staple → `spctl` 预检。

顺序很关键：**ticket 必须先 staple 进 `.app` 再压缩**，否则用户解压后拿到的 app 里没有票据。

## 5. 本地复现

```bash
export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
./tool/build_macos.sh

export NOTARY_KEY_PATH=~/private/AuthKey_XXXX.p8
export NOTARY_KEY_ID=XXXXXXXXXX
export NOTARY_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
./tool/notarize_macos.sh "build/macos/Build/Products/Release/Encry Immortals.app"
```

## 6. 常见失败

| 报错 | 原因与处理 |
| --- | --- |
| `errSecInternalComponent` | 漏了 `security set-key-partition-list`，或钥匙串自动上锁 |
| `code object is not signed at all` / `not signed with a valid Developer ID` | 内层 framework 还是 ad-hoc，检查 `sign_nested` 是否执行 |
| `The executable does not have the hardened runtime enabled` | 某个嵌套二进制没带 `--options runtime` |
| `The signature does not include a secure timestamp` | 漏 `--timestamp`，或 CI 出网被拦 |
| `Invalid` 且日志提示 `is not in a standard location` | `Contents/Resources/bin/` 里的 sidecar 位置不被认可，可移到 `Contents/MacOS/` 或 `Contents/Frameworks/` |
| 公证通过但 Gatekeeper 仍拦截 | `.app` 未 staple 就压缩；或用户机器离线 |

公证失败时工作流会打印 `notarytool log`，里面有逐条 issue，改完重跑即可。

## 7. 证书轮换

Developer ID Application 有效期 5 年。到期前重新走第 1 步，只替换 `MACOS_CERT_P12_BASE64` 和
`MACOS_CERT_PASSWORD` 两个 secret，代码不用改。吊销旧证书后，已发布的旧版本仍可运行，只是不能再出新签名。
