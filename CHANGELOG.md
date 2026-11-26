# Changelog

All notable changes to TidyDisk are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions are `major.minor`, as shown in the app and on the [Releases](https://github.com/prateekcode/tidydisk/releases) page.

## [Unreleased]

## [2.1] - 2026-11-26

### Added

- A full Settings screen.
- Anonymous usage statistics, off by default. Nothing is sent unless you switch them on in Settings, and they never include file names, paths or folder names.
- Project documentation for contributors: `CONTRIBUTING.md`, `SECURITY.md`, a code of conduct, issue forms, a pull request template and a build check on every pull request.

### Changed

- Overview fills large windows instead of leaving empty space.

## [2.0] - 2026-11-26

The app moved from a sidebar with a scan, review, done flow to tabs you can open in any order, on a flat dark design with purple as the only accent.

### Added

- **Overview** tab: free space, what can be cleared in each of the three risk groups, and live CPU, memory, network and battery.
- **Disk** tab: where the space went by location, as a treemap, by folder with drill-down, and by file type. One pass over about 2 million files takes around 8 seconds, and the result is kept between launches.
- **Large Files** tab: every file over a size you pick, moved to the Trash when you say so.
- **Apps** tab: installed apps with the files they keep in `~/Library`, uninstall to the Trash, and leftovers of apps that were already removed.
- **AI** tab: what Claude, ChatGPT, Ollama, LM Studio, Cursor and other AI tools use in disk, memory and CPU, with their MCP servers and local ports. Items go to the Trash only.
- **Monitor** tab: CPU, GPU, memory, disk, network, battery, uptime, top processes and a speed test.
- `TidyDisk --measure [folder]` prints the disk breakdown without opening the app.
- `TidyDisk --shot <tab> <png>` renders a tab to an image, for checking a screen without Screen Recording permission.
- The last scan and the lifetime "cleaned" counter persist across launches.

### Changed

- **Clean** shows the three risk groups with tick boxes, replacing the scan, review, done flow.
- The sidebar is replaced by a top tab bar. Projects, Duplicates, Settings and Log moved onto the same shared design kit (`UI/Theme.swift`, `UI/Components/Components.swift`).
- The free space in the menu bar updates by itself every 5 seconds. It used to refresh only when the panel was opened or after a clean.
- `build.sh` asks SwiftPM where the build products are (the folder moved in Swift 6.4) and names the release zip from `Info.plist`.

## [1.1] - 2026-07-25

### Added

- A Settings screen.
- Push to GitHub with a personal access token, kept in the macOS Keychain. Repositories are created through the GitHub REST API and pushed over HTTPS.
- Backup destinations: a "Test access" check that triggers the macOS permission prompt, and an Add Folder picker.

### Changed

- Push to GitHub no longer requires the `gh` CLI. It is still used when no token is set.
- Archive and push failures show as alerts instead of only appearing in the log.

## [1.0] - 2026-07-24

First public release.

### Added

- Smart scan that adapts to the Mac: a cleaner appears only when its tool, app or folder exists (Xcode, npm, pnpm, yarn, CocoaPods, Gradle, Docker, Homebrew, SwiftPM and more).
- Three risk groups: Safe to clean is pre-selected, Review before cleaning and Handle with care need an explicit opt-in.
- Project discovery across the Mac, with cleaning of build artifacts (`node_modules`, `build`, `.dart_tool`, `Pods`, `.gradle`), push to a private GitHub repository and archive to iCloud.
- Large file and duplicate finders.
- Menu bar item with free space, a one-click scan and an optional weekly scan with a notification.
- Homebrew cask: `brew install --cask prateekcode/tap/tidydisk`.

[Unreleased]: https://github.com/prateekcode/tidydisk/compare/v2.0...HEAD
[2.0]: https://github.com/prateekcode/tidydisk/compare/v1.1...v2.0
[1.1]: https://github.com/prateekcode/tidydisk/compare/v1.0...v1.1
[1.0]: https://github.com/prateekcode/tidydisk/releases/tag/v1.0
