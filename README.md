<p align="center">
  <img src="docs/assets/app-icon.png" width="112" alt="Encry Immortals app icon">
</p>

<h1 align="center">Encry Immortals</h1>

<p align="center">
  <strong>Local-first, encrypted, incremental backups for macOS and Windows.</strong><br>
  <sub>No account. No cloud lock-in. No master password on disk.</sub>
</p>

<p align="center">
  <a href="README.zh-CN.md">简体中文</a> · <strong>English</strong>
</p>

<p align="center">
  <a href="https://github.com/tangthinker/encry-immortals-ui/releases"><img alt="Release" src="https://img.shields.io/github/v/release/tangthinker/encry-immortals-ui?label=release&color=B08A3E"></a>
  <a href="https://github.com/tangthinker/encry-immortals-ui/actions/workflows/release.yml"><img alt="Release workflow" src="https://github.com/tangthinker/encry-immortals-ui/actions/workflows/release.yml/badge.svg"></a>
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.47.5-02569B?logo=flutter&logoColor=white">
  <img alt="Go" src="https://img.shields.io/badge/Go-1.27-00ADD8?logo=go&logoColor=white">
  <img alt="Tests" src="https://img.shields.io/badge/tests-102-2F7D63">
  <img alt="Platforms" src="https://img.shields.io/badge/platform-macOS%20%7C%20Windows-10161A">
</p>

> [!NOTE]
> **Status: MVP, actively developed.** Latest release `v0.4.2` ships a **universal macOS build** (`x86_64 + arm64`),
> a dedicated **Apple Silicon build**, a **Windows x64 installer + portable zip**, and **multiple isolated workspaces**.
> The macOS builds are Developer ID signed, notarized by Apple, and stapled; Windows is CI-built but still needs physical-host validation and Authenticode signing before wider distribution.

---

**Contents:** [Why](#why-encry-immortals) · [Screens](#a-quick-look) · [Features](#what-it-does) · [Architecture](#architecture) · [Security](#security-model) · [Download](#download--install) · [Build](#build-from-source) · [Roadmap](#roadmap--known-limitations)

## Why Encry Immortals?

Most backup tools ask you to trust an account, a sync provider, or a proprietary blob format.
Encry Immortals takes a different route:

- **A local vault, sealed by a chain.** Every backup produces a verifiable commit; every restore starts with a `doctor --chain` preflight.
- **A separate Go sidecar, not a black box.** The UI speaks a typed, documented JSON contract to the `eimmortal` binary. The CLI exposes the same core operations the GUI uses.
- **No password storage.** The master password is sent through `stdin`, kept in memory, and cleared on lock/quit.
- **A desktop app, not a web dashboard.** Native menus, keyboard shortcuts, resizable windows, and a UI that works offline.

The result is a small, inspectable backup workstation for people who want their archive to outlive a service.

## A quick look

<table>
  <tr>
    <td width="50%" align="center">
      <img src="docs/assets/m1-dashboard-light.jpg" alt="Dashboard in light mode"><br>
      <sub><b>Dashboard</b> · light · chain health, latest commit, storage facts</sub>
    </td>
    <td width="50%" align="center">
      <img src="docs/assets/m1-dashboard.jpg" alt="Dashboard in dark mode"><br>
      <sub><b>Dashboard</b> · dark · the same facts, same hierarchy</sub>
    </td>
  </tr>
  <tr>
    <td width="50%" align="center">
      <img src="docs/assets/m1-onboarding-light.jpg" alt="Onboarding: create or join a vault"><br>
      <sub><b>Onboarding</b> · create a new vault or join an existing TargetDir</sub>
    </td>
    <td width="50%" align="center">
      <img src="docs/assets/m1-onboarding-params-light.jpg" alt="Backup parameters during onboarding"><br>
      <sub><b>Parameter studio</b> · normal and advanced settings before the first command</sub>
    </td>
  </tr>
  <tr>
    <td width="50%" align="center">
      <img src="docs/assets/m1-settings-schedule-light.jpg" alt="Scheduled backups settings"><br>
      <sub><b>Scheduled backups</b> · daily, weekly, monthly or fixed interval</sub>
    </td>
    <td width="50%" align="center">
      <img src="docs/assets/m1-backup.jpg" alt="Backup progress and logs"><br>
      <sub><b>Backup</b> · dry runs, live progress, logs and lock recovery</sub>
    </td>
  </tr>
</table>

More screens: **[unlock](docs/assets/m1-unlock.jpg)** · **[history](docs/assets/m1-history.jpg)** · **[restore](docs/assets/m1-restore.jpg)** · **[verify](docs/assets/m1-verify.jpg)** · **[settings](docs/assets/m1-settings-light.jpg)** · **[advanced parameters](docs/assets/m1-settings-params-light.jpg)**

## What it does

| Area | What you get |
|---|---|
| **Workspaces** | Create, import and switch multiple workspaces; each owns its own `profile.json`, `config.toml` and local vault. Existing single-workspace installs migrate automatically. |
| **Vault lifecycle** | Create a new vault or join an existing TargetDir with an Armor Key. Choose storage, compression, scan and integrity parameters before the first command. |
| **Incremental backups** | Scan → chunk → zstd → encrypt → pack. Dry-run preview, live progress/logs, truncation notice, continue-later and `--break-lock` recovery. |
| **Continuous backup** | When a run hits `session_max_mib`, keep **Continue** for one more run or choose **Keep backing up until complete**; it repeats safely with stop and no-progress guards. |
| **History & restore** | Commit log, change detail, file tree at a chosen `seq`; restore with a hard `doctor --chain` preflight, missing-pack detection and overwrite policy. |
| **Integrity** | `verify --sample N` / `--deep`, chain doctor, PASS/WARN/FAIL states, missing/corrupt/sample-failure reporting. |
| **Parameter studio** | The implemented sidecar parameters in one place: pack/slice/small-file sizes, zstd level, excludes, staging directory, xattr policy, hardlinks and on-change strategy. New workspaces default to a **50 GB** per-session limit; existing workspaces keep their explicit value. |
| **Scheduled backups** | Daily, weekly or monthly at a local time, or every N minutes/hours/days. Plans persist; due runs execute while the app is open and unlocked. |
| **Native desktop UX** | Native menu bar, `⌘1–5` / `⌘⇧B` / `⌘⇧R` / `⌘,` shortcuts, content-based window titles, sidebar lock, settings tab and a persisted light/system/dark theme. |
| **App protection** | Single-instance file lock, serial command queue, close guards during a running command, and sidecar SHA-256 verification in release builds. |

## Architecture

<p align="center">
  <img src="docs/assets/architecture.png" alt="Encry Immortals architecture: Flutter UI, Go sidecar, control plane and TargetDir" width="100%">
</p>

```text
Flutter screens
  → AppController / VaultSession
  → CommandQueue (one sidecar at a time)
  → eimmortal Go sidecar
  → TargetDir (ciphertext + metadata)  +  app-private control plane
```

- The UI never edits vault files directly. Every operation goes through the sidecar and its typed JSON response.
- The sidecar reads `config.toml` (0600 on POSIX); the GUI owns that file and writes only implemented parameters.
- The app data root keeps `workspaces.json`; each workspace has its own `profile.json`, `config.toml` and control plane (`vault.meta`, `state.db`, `journal`). The TargetDir contains only encrypted data and metadata.
- The core is pinned as the `third_party/encry-immortals` submodule at `v0.1.5`.
- Release trust chain: sign the sidecar → compute SHA-256 → pin it at build time → verify the hash before launch and on every unlock.

## Security model

| Boundary | Rule |
|---|---|
| **Master password** | Only through sidecar `stdin`. Never in argv, environment variables, temp files, logs or analytics. Held in memory only; lock/quit clears it. |
| **Armor Key** | Displayed only when explicitly exported, after password re-verification. It is not written to logs. |
| **Control plane** | App-private directory, POSIX `0600` files. `config.toml` contains no secrets. |
| **TargetDir** | Ciphertext and metadata only. Removing the local profile never deletes the TargetDir or its history. |
| **Sidecar integrity** | Release builds pin the signed sidecar SHA-256 and verify it before execution. Debug builds use the Xcode-injected ad-hoc sidecar. |
| **Restore gate** | `doctor --chain` is a hard preflight. A failing chain is never silently ignored. |
| **Scheduled runs** | The scheduler never stores or asks for the password. If the vault is locked at the scheduled time, it waits and catches up after unlock. |

> [!IMPORTANT]
> macOS builds are **Developer ID signed, notarized by Apple, and stapled** — download and launch directly, no Gatekeeper workaround needed.
> Signing and notarization run in CI; the setup is documented in [docs/macos-signing.md](docs/macos-signing.md).

## Scheduled backups, honestly

Encry Immortals runs an **in-app scheduler**:

- Daily at a chosen `HH:mm`
- Weekly on a chosen weekday and time
- Monthly on a chosen day (short months use their last day) and time
- Every N minutes / hours / days (5 minutes to 30 days)

Plans and their `nextRunAt` / `lastRunAt` / `lastError` are stored in the vault profile.

The app **must be running and unlocked** for a scheduled backup to execute. The master password is never persisted, so the scheduler cannot unlock a vault by itself. If the app is locked at the due time, it catches up once after unlock; if the app is fully quit, it runs on the next launch after unlock if the plan is overdue. This is intentionally an in-app scheduler, not launchd/Task Scheduler.

## Download & install

**macOS universal** — latest release (`x86_64 + arm64`):

- [`Encry-Immortals-v0.4.2-macOS-universal.dmg`](https://github.com/tangthinker/encry-immortals-ui/releases/download/v0.4.2/Encry-Immortals-v0.4.2-macOS-universal.dmg)
- [`Encry-Immortals-v0.4.2-macOS-universal.zip`](https://github.com/tangthinker/encry-immortals-ui/releases/download/v0.4.2/Encry-Immortals-v0.4.2-macOS-universal.zip)

**macOS arm64** — dedicated Apple Silicon build:

- [`Encry-Immortals-v0.4.2-macOS-arm64.dmg`](https://github.com/tangthinker/encry-immortals-ui/releases/download/v0.4.2/Encry-Immortals-v0.4.2-macOS-arm64.dmg)
- [`Encry-Immortals-v0.4.2-macOS-arm64.zip`](https://github.com/tangthinker/encry-immortals-ui/releases/download/v0.4.2/Encry-Immortals-v0.4.2-macOS-arm64.zip)

Open either DMG, drag **Encry Immortals** to Applications, and launch it. Both builds are Developer ID signed, notarized by Apple, and stapled.

**Windows x64** — latest release:

- [`Encry-Immortals-0.4.2-Windows-x64.exe`](https://github.com/tangthinker/encry-immortals-ui/releases/download/v0.4.2/Encry-Immortals-0.4.2-Windows-x64.exe) — Inno Setup installer (per-user, no admin required)
- [`Encry-Immortals-0.4.2-Windows-x64-portable.zip`](https://github.com/tangthinker/encry-immortals-ui/releases/download/v0.4.2/Encry-Immortals-0.4.2-Windows-x64-portable.zip) — portable build

The Windows artifacts are **unsigned**; Authenticode and physical Windows testing are still roadmap items.

## Build from source

### Prerequisites

- Flutter `3.47.5` / Dart `3.13.4`
- Xcode + Command Line Tools (macOS)
- Go `1.27+` (the debug/release sidecar build)
- Git submodules

### Run

```bash
git clone --recurse-submodules https://github.com/tangthinker/encry-immortals-ui.git
cd encry-immortals-ui
flutter --no-version-check pub get
flutter --no-version-check run -d macos
```

The Xcode **Debug/Profile Sidecar** phase builds the sidecar from the pinned submodule and copies it into the app bundle. No `EIMMORTAL_CORE_PATH` export is needed for a normal `flutter run`.

### Build a release

```bash
./tool/build_macos.sh
dart run tool/verify_bundle.dart \
  "build/macos/Build/Products/Release/Encry Immortals.app" \
  "$(cat build/core/eimmortal.sha256)"
# integrity: verified
```

The release script signs the sidecar before hashing, copies it into `Contents/Resources/bin/eimmortal`, signs the app and verifies the bundled hash.

### Test

```bash
flutter --no-version-check analyze
flutter --no-version-check test                     # 102 unit/widget tests, 5 integration skipped
RUN_CORE_INTEGRATION=1 \
EIMMORTAL_CORE_PATH=/path/to/eimmortal \
  flutter --no-version-check test test/integration
```

## Release automation

Pushing a `v*` tag triggers [`.github/workflows/release.yml`](.github/workflows/release.yml):

1. Check out the repo and the pinned core submodule.
2. Install Flutter `3.47.5` and Go `1.27.1`.
3. Run `flutter analyze` and the test suite.
4. Build the sidecar, sign it, pin its hash and build the macOS app.
5. Verify and package both the universal and arm64 macOS `.zip` + `.dmg`.
6. Build Windows x64, verify the sidecar hash, create the Inno Setup installer and portable zip.
7. Publish universal, arm64 and Windows artifacts to GitHub Releases.

Windows artifacts are produced in CI but remain unsigned until Authenticode is wired up.

## Project layout

```text
lib/
  app/                         screens, widgets, theme, controller, workspace switcher
  core/                        sidecar gateway, models, queue, profile, workspace store, settings
assets/icon/                   icon SVG sources + 1024px masters
tool/                          core/app builds, bundle verification, icon tooling
macos/ · windows/              native runners and assets
docs/                          architecture notes, contract, devlog, screenshots
third_party/encry-immortals/   pinned Go core submodule (v0.1.5)
```

Deeper reading:

- [Technical selection](docs/tech-selection.md)
- [Client ↔ sidecar contract](docs/integration-contract.md)
- [Development log](docs/devlog.md)
- [Icon design notes](assets/icon/README.md)
- [macOS signing and notarization](docs/macos-signing.md)
- [Changelog](CHANGELOG.md)

## Design notes

The icon is a brass wax seal pressed onto a paper inlay. The infinity mark stands for permanence and the backup chain; the scalloped edge, paper grain and letterpress shadow are all vector geometry. There are no gradients, glow effects, letters or literal keys.

The app follows the same restraint: flat ink/brass/paper surfaces, system typography, Menlo for paths and hashes, and a light theme by default. A **Reduce Motion** preference is respected by the screen transition, and the palette passes WCAG AA contrast tests in both appearances.

<p align="center">
  <img src="docs/assets/app-icon-preview.jpg" alt="App icon across macOS and Windows surfaces" width="720">
</p>

## Roadmap / known limitations

- [ ] Validate Windows packaging, GUI-subsystem stdio, `LockFileEx` control locks and Authenticode signing.
- [x] Developer ID signing + notarization + stapling; universal Apple Silicon / Intel release.
- [ ] Optional OS-level scheduling (launchd / Task Scheduler) with an explicit Keychain opt-in, so a backup can run while the app is closed.
- [ ] Idle auto-lock and startup recovery for interrupted operations.
- [ ] Multi-vault support and paginated snapshot browsing.
- [x] In-app daily / weekly / monthly / interval scheduling.
- [x] Full parameter studio, light/dark/system themes, native menu bar and the new seal icon.

## Contributing

Issues and pull requests are welcome. Before opening a PR:

1. Run `flutter --no-version-check analyze` and `flutter --no-version-check test`.
2. Keep the client ↔ sidecar contract intact; see [docs/integration-contract.md](docs/integration-contract.md).
3. Never commit passwords, Armor Keys, decrypted fixtures or machine-specific absolute paths.
4. Add a devlog entry for behavior changes that affect the app or packaging.

## License

No license has been declared yet. Until a license is added, the source is all rights reserved; please open an issue before redistribution or reuse.

## Acknowledgements

Built on top of [encry-immortals](https://github.com/tangthinker/encry-immortals), Flutter, Go, and the Apple Human Interface Guidelines. The seal, gradient-free palette and icon were designed for this project rather than sourced from a template.
