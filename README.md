# 🫧 TidyDisk

**Free disk cleaner for Mac developers.** Reclaims the gigabytes hiding in Xcode DerivedData, node_modules, simulators, package-manager caches and forgotten projects — safely, with everything reviewed before it's touched.

**Website & download:** [tidydisk.riekapps.com](https://tidydisk.riekapps.com)

- 100% on-device — nothing leaves your Mac, no account, no telemetry
- Native SwiftUI, universal binary (Apple Silicon + Intel), a few MB on disk
- Notarized by Apple

## Install

**Homebrew:**

```sh
brew install --cask prateek-apk/tap/tidydisk
```

**Or manually:** download the zip from [tidydisk.riekapps.com](https://tidydisk.riekapps.com), unzip, drag `TidyDisk.app` to Applications.

Requires macOS 14 (Sonoma) or later.

## What it cleans

TidyDisk probes your Mac at launch and only shows what's actually there:

- **Smart Scan** — Xcode DerivedData & caches, CocoaPods, npm/pnpm/yarn, Gradle, Homebrew, SwiftPM, Docker, simulator runtimes, old device-support folders, app caches, Trash, and more
- **Space Lens → Projects** — finds every dev project on your Mac (via `.git`, `package.json`, `pubspec.yaml`, `*.xcodeproj`, …) and cleans their build artifacts (`node_modules`, `build`, `.dart_tool`, `Pods`, `.gradle`); can also push a project to a private GitHub repo or archive it to iCloud before you delete it
- **Large Files** — everything over 200 MB in your home folder
- **Duplicates** — identical files in Downloads & Desktop, newest copy kept
- **Menu bar** — free space at a glance, one-click scan, optional weekly scan with a notification

Three risk tiers keep it safe: **safe** caches are pre-selected, **aggressive** and **nuclear** (e.g. all node_modules) always need an explicit opt-in. File deletions go to Trash where possible.

## Build from source

Pure SwiftPM — no Xcode project needed:

```sh
./build.sh            # build + ad-hoc sign TidyDisk.app
./build.sh --install  # also copy to /Applications
```

The task catalog lives in `Sources/TidyDisk/Models/Catalog.swift` — add a `CleanupTask` there to extend the app.

## Notes

- Emptying Trash and reading some app containers needs **Full Disk Access** (System Settings → Privacy & Security). Without it those items report 0 and are skipped.
- The weekly scan is a LaunchAgent running `TidyDisk --scan-notify` headless; its plist points at the app's executable, so re-toggle it if you move the app.

## License

[MIT](LICENSE) © RiekApps
