# Contributing to TidyDisk

Thanks for looking. TidyDisk is a small native Mac app, and most useful contributions are small too: a cache it does not know about yet, an AI tool that is missing, a wrong size, a clearer label.

Two things make it easy to help:

- **Cleaners are data.** A new cleaner is one entry in a catalog, not a new code path.
- **You can see every screen without clicking.** `--shot` renders any tab to a PNG.

Not sure whether something is wanted? Open a [discussion](https://github.com/prateekcode/tidydisk/discussions) or a [cleaner request](https://github.com/prateekcode/tidydisk/issues/new?template=cleaner_request.yml) first. Everyone taking part is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).

## Build and run

You need macOS 14 or later and Apple's Swift toolchain (Xcode, or the command line tools from `xcode-select --install`). There is no Xcode project: the app is a plain Swift package.

```sh
git clone https://github.com/prateekcode/tidydisk.git
cd tidydisk

swift build              # quick compile check
./build.sh               # release build, assembled and ad-hoc signed as TidyDisk.app
open TidyDisk.app
./build.sh --install     # the same, then copied to /Applications
```

`./build.sh` builds a universal binary (Apple Silicon and Intel). If that step fails with only the command line tools installed, install Xcode, or use `swift build` for the compile check. `./build.sh --release` signs and notarizes with the maintainer's Developer ID; you do not need it, and pull requests should not change it.

Releases are built with Swift 6.4 in Swift 5 language mode (`swift-tools-version:5.9`, no dependencies). If your toolchain is older and something does not compile, say so in the pull request rather than raising the tools version.

To open the code in Xcode, use File, Open on the folder; Xcode reads `Package.swift` directly.

## Project layout

```
Package.swift                 one executable target, macOS 14, no dependencies
build.sh                      builds the binary and assembles TidyDisk.app
Scripts/                      Info.plist and the app icon generator
Sources/TidyDisk/
  TidyDiskApp.swift           entry point: window, menu bar item, headless modes
  AppState.swift              UI state on the main actor; owns the stores
  Models/                     CleanupTask (what a cleaner is), Catalog (the cleaners), AppTab
  Engine/                     the work: sizing, cleaning, disk walk, apps, AI tools, system readings
  Stores/                     one ObservableObject per tab (Disk, Apps, AI, Monitor)
  UI/Theme.swift              every colour, font and metric
  UI/Components/              the shared kit: Page, panel, Badge, Meter, KitButton and so on
  UI/Screens/                 one file per tab, composed from the kit
web/                          the landing page at tidydisk.riekapps.com
```

The README's "How it works" section has the diagram and a line on each engine file.

## Add a cleaner

This is the most common contribution. A cleaner is a `CleanupTask` (`Models/CleanupTask.swift`) added in `Catalog.build()` (`Models/Catalog.swift`). The engine and the UI pick it up from there; nothing else needs to change.

### 1. Pick how it cleans

`TaskKind` says what happens on scan and on clean:

| Kind | Use it when |
|:--|:--|
| `.directoryContents([paths])` | A cache folder can simply be emptied. The folder itself is kept. |
| `.commands(scanPaths:commands:)` | The tool has its own cleanup command. `scanPaths` are only measured; the commands do the cleaning. A command is skipped when its tool is not installed. |
| `.allButNewest(parent:)` | Versioned sibling folders where the newest must stay (old Android NDKs). |
| `.projectSweep(dirNames:)` | Folders with these names inside every project found on the Mac. |
| `.appCacheSweep(root:subpaths:exclude:)` | The same cache subfolders inside every app's folder under `root`. |
| `.findAndRemove(root:dirNames:)` | Folders with these names anywhere under one root. |

Prefer the tool's own command where one exists (`npm cache clean`, `brew cleanup`), instead of deleting its internals.

### 2. Pick the risk group

| Tier | Shown as | Meaning | Selection |
|:--|:--|:--|:--|
| `.safe` | Safe to clean | Rebuilt by the system or app when needed | Ticked for the user after a scan |
| `.aggressive` | Review before cleaning | Comes back on demand, but re-downloading or re-indexing takes time | Never ticked for the user |
| `.nuclear` | Handle with care | Needs a reinstall before the project runs again | Never ticked for the user |

When in doubt, choose the more careful group. A cleaner that is wrongly in Safe gets run by people who never read its name.

**The rule that matters most:** a `CleanupTask` deletes permanently. That is only acceptable for data the owning tool regenerates by itself. Anything that is not regenerated (documents, archives, downloaded models, chat history, settings) must go to the Trash through `Engine.trashFile`, the way Large Files, Duplicates, Apps and AI do, and must never be a catalog cleaner.

### 3. Add the entry

Inside `Catalog.build()` you have four helpers: `exists(path)`, `existing([paths])` (keeps the ones that exist), `hasTool("name")` and `add(...)`. Every entry is wrapped in a probe, so a Mac without the tool never sees the cleaner.

A folder that can be emptied, shaped like the CocoaPods entry:

```swift
if exists(home + "/Library/Caches/org.carthage.CarthageKit") {
    add("carthage", "Carthage cache", "Downloaded dependencies and build products",
        "shippingbox.fill", .devCaches, .safe,
        .directoryContents([home + "/Library/Caches/org.carthage.CarthageKit"]))
}
```

A tool with its own cleanup command, shaped like the Homebrew entry:

```swift
if hasTool("go") {
    add("go-modcache", "Go module cache", "Re-downloaded on the next go build",
        "shippingbox.fill", .devCaches, .aggressive,
        .commands(scanPaths: existing([home + "/go/pkg/mod"]),
                  commands: [["go", "clean", "-modcache"]]))
}
```

The arguments to `add` are, in order:

1. `id`: short, lowercase, unique, and stable. Do not rename an existing one.
2. `name`: what the row is called, in the user's words ("Gradle caches", not "gradle-cache-dir").
3. `detail`: one line saying what it is or what happens after cleaning.
4. `icon`: an SF Symbol name.
5. `category`: a `TaskCategory` (`.devCaches`, `.xcode`, `.system`, `.appCaches`, `.docker`, `.nuclear`).
6. `tier`: the risk group from step 2.
7. `kind`: from step 1.

Put the entry in the block for its tier (`// ---- Safe ----`, `// ---- Aggressive ----`, `// ---- Nuclear ----`).

Things to know:

- Tools are looked up on a fixed `PATH` (`Engine.toolPATH`: Homebrew, `/usr/local/bin` and the system folders). A tool that lives elsewhere is not found.
- Stay inside the user's home folder unless there is a clear reason, and say what the reason is in the pull request.
- Do not probe or read `~/Library/Containers`, `~/Library/Group Containers` or `~/Library/Mobile Documents` for a new cleaner. See the safety rules below.

### 4. Try it

1. `./build.sh`, open the app, run a scan. Scanning only measures.
2. Compare the reported size with `du -sh <path>`.
3. Before cleaning real data, point your entry at a scratch folder you made (for example `home + "/tidydisk-scratch/cache"` with a few files copied in), clean, and read the Log screen: every action writes a `[done]`, `[skip]` or `[fail]` line. Put the real path back before you commit.
4. Clean the real folder, then run the tool once and confirm it rebuilds what it needs.

## Add an AI tool

The AI tab is driven by `AICatalog.tools` in `Engine/AICatalog.swift`. Adding a tool is adding one `AITool` entry. This is the existing entry for Jan:

```swift
AITool(id: "jan", name: "Jan", symbol: "hand.wave",
       apps: ["Jan.app"], ports: [1337],
       sources: [
           .each(.models, in: "~/jan/models"),
           .each(.models, in: "~/Library/Application Support/Jan/data/models"),
           .each(.models, in: "~/Library/Application Support/Jan/data/llamacpp/models"),
           .rest(.appData, "Threads and settings", of: "~/jan"),
       ] + electronApp("~/Library/Application Support/Jan", data: "Threads and settings")),
```

**How its processes are recognised** (for "Running now", memory, CPU and ports). Fill in whichever apply:

- `apps`: app bundle names. Gives the icon, and matches any process running from inside the bundle.
- `binaries`: executable names, matched exactly and case-sensitively (`"ollama"`).
- `pathHints`: substrings of an executable's path (`"/.lmstudio/"`).
- `commandHints`: lowercase substrings of an interpreter's command line, for tools run by `node` or `python` (`"@google/gemini-cli"`).
- `ports`: default ports of its local server.
- `symbol`: an SF Symbol, shown when the app itself is not installed.

**Where its data lives.** Each `AISource` has a kind and a shape. Paths start with `~/`, and the last path component may end in `*` to match by prefix.

| Kind | What it is | How freely it is offered |
|:--|:--|:--|
| `.models` | Downloaded weights | The only kind "older than 90 days" selects |
| `.cache` | Rebuilt or re-downloaded by the tool | Selectable |
| `.appData` | Chats, sessions, settings | Only ever ticked by hand |

| Shape | Result |
|:--|:--|
| `.paths(kind, "Name", [paths])` | One row made of every listed path that exists |
| `.each(kind, in: dir, prefix:, suffix:, depth:)` | One row per entry `depth` levels below `dir` (a model per folder or file) |
| `.rest(kind, "Name", of: dir)` | One row for whatever in `dir` no other source claims |
| `.ollama(dir)` | An Ollama model store, with blobs shared between models counted once |

`electronApp(root, caches:, data:)` is a helper for Electron and VS Code based apps: it adds the usual cache folders as one cache row and the rest of the support folder as app data.

Things to get right:

- **When unsure, it is `.appData`.** A folder that holds chat history is not a cache, even if it is called `tmp` (see the Gemini CLI entry).
- **Order matters.** The first tool that matches a process wins, which is why Claude Code sits before Claude. Put a more specific tool above the one that contains it.
- **Never list a shared folder as a path** (`~/Library/Caches`, `~/.cache`, `~/Documents`). `isSafeToTrash` refuses them, and the row would fail.
- Everything in the AI tab goes to the Trash. Do not add a delete path.
- Sources inside folders macOS guards are skipped by the catalog itself when Full Disk Access is off. You do not need to add a check, but do not work around it either.

Check the paths on a Mac where the tool is installed and has been used. Say in the pull request which version you looked at.

## UI rules

The look is fixed, so screens stay consistent and reviews stay short.

- **Colours, fonts and spacing come from `Theme`** (`UI/Theme.swift`). No `Color(red:…)`, hex values or magic paddings in a screen.
- **Screens are composed from the kit** in `UI/Components/Components.swift`: `Page`, `PageHeader`, `IconTile`, `SectionLabel`, `Rule`, `Badge`, `Meter`, `StackedBar`, `LegendItem`, `Flow`, `Sparkline`, `KitButton`, `CheckBox`, `Segmented`, `StatTile`, `NavRow`, `EmptyState`, `BusyLabel`. Screens do not draw their own cards, buttons, badges or bars.
- **One card style:** `.panel()`, a flat surface with a hairline border. No gradients, glows, shadows or accent-coloured borders.
- **Purple is the only accent** (`Theme.accent`). The signal colours (`green`, `amber`, `red` and the rest) carry meaning: risk groups, status, chart series. They are not decoration.
- **Text:** `Font.display(size)` for titles and big numbers, `Font.label` for uppercase section labels, the system font otherwise.
- Need something the kit does not have? Add it to `Components.swift` as a small reusable view with a one-line doc comment, then use it. Do not build it inside the screen.
- Wording is plain and short: say what happens ("Moved to the Trash"), not how it is implemented.

## Safety rules

A pull request that breaks one of these will not be merged, however useful the rest is.

1. **Scanning stays read-only.** A scan measures. Nothing is removed, moved or changed until the user presses a button that says so.
2. **Regenerated data may be deleted; everything else goes to the Trash.** See "Add a cleaner", step 2.
3. **Never tick a risky thing for the user.** Only Safe cleaners with something to reclaim are pre-selected.
4. **Respect the folders macOS guards.** Do not read `~/Library/Containers`, `~/Library/Group Containers` or `~/Library/Mobile Documents` unless Full Disk Access is on (`Engine.hasFullDiskAccess()`). Even a `stat` inside them can raise a system prompt. Skip them and report them as skipped, as `DiskWalker` and `AICatalog` do.
5. **Stay in the user's home folder.** Do not delete outside it without a clear reason, stated in the pull request.
6. **Keep the guard rails:** project sweeps never touch the global `~/.gradle`, "all but newest" always keeps the newest, TidyDisk and Apple's apps cannot be uninstalled from the Apps tab.
7. **No network calls**, with two exceptions: a feature the user starts (such as Push to GitHub or the speed test), and the anonymous usage statistics, which are off unless the user switches them on in Settings. Statistics never carry file names, paths or folder names.
8. **Log what you did.** Every removal writes a `[done]`, `[trash]`, `[skip]` or `[fail]` line to the activity log.
9. **Test on a throwaway folder first.** Never try a new removal path on data you care about.

## Check a UI change

`--shot` opens the app on one tab, waits, writes the window to a PNG and quits. It needs no Screen Recording permission.

```sh
./build.sh
TidyDisk.app/Contents/MacOS/TidyDisk --shot clean /tmp/clean.png 3 --scan --machine-name "MacBook Air"
```

- Tabs: `overview`, `disk`, `clean`, `largeFiles`, `apps`, `projects`, `ai`, `monitor`, `duplicates`, `settings`, `log`.
- The number is how many seconds to wait before the picture (default 3).
- `--scan` runs a real scan first, so the screen has data. It is read-only.
- `--machine-name "MacBook Air"` replaces your Mac's name in the picture. Use it for anything you attach.
- `--disk-mode overview|map|folders|types` picks the Disk tab's view.

Two more read-only helpers:

```sh
TidyDisk.app/Contents/MacOS/TidyDisk --measure            # where the space goes, as text
TidyDisk.app/Contents/MacOS/TidyDisk --measure ~/Library  # one folder's children by size
```

Screenshots show real folder, app and project names from your Mac. Look at the PNG before you attach it.

## Open a pull request

- One change per pull request. A new cleaner and a refactor are two pull requests.
- Fork, branch from `main`, and open the pull request against `main`. The build check must pass.
- Fill in the template. What a reviewer needs:
  - what changed and why, in a sentence or two
  - your macOS version and chip
  - **for a cleaner or AI tool:** the paths, the size TidyDisk reports next to `du -sh`, the Log lines from a clean, and why you chose the risk group
  - **for a UI change:** a `--shot` PNG of each changed tab, before and after if it is a visual change
- Add a line to `CHANGELOG.md` under Unreleased when a user would notice the change.
- There is no automated test suite yet. Tests for pure functions are welcome (see the ideas below).

### Code style

- Match the file you are in: four spaces, doc comments (`///`) that say why, not what.
- Reuse before you add. If two screens need the same view or helper, it belongs in the kit or in `Engine`.
- No new dependencies. The package has none, and that is deliberate.
- Slow work (`du`, `find`, any `Process`) runs off the main actor.

### Commit messages

Plain sentences that say what changed, as in `git log`. An area prefix is fine when it helps. No ticket numbers or type prefixes are required.

```
Add Carthage cache to the Safe cleaners
build.sh: read the products folder from SwiftPM (moved to .build/out on Swift 6.4)
AI tab: count Ollama blobs shared between models once
```

For a larger change, add a short body with one line per part.

## Good first issues

Each of these is small, self-contained and can be checked against the code today.

1. **Python caches.** The catalog has no Python entry: add pip (`~/Library/Caches/pip`, or `pip cache purge`), and look at uv and Poetry.
2. **Rust.** `Cargo.toml` already marks a folder as a project, but there is no cleaner for `~/.cargo/registry` and `~/.cargo/git`, and `target` is not among the project build folders.
3. **Go.** `go.mod` is a project marker too, yet nothing cleans the module cache (`go clean -modcache`).
4. **Bun and Deno.** The package-manager cleaner covers npm, pnpm and yarn only.
5. **Tools installed with a version manager.** `Engine.toolPATH` is a fixed list, so npm from nvm, fnm, Volta, asdf or mise is not found and its cache is never offered.
6. **More AI tools.** `AICatalog.tools` has 20 entries. Missing ones include Continue, opencode, Msty and Open WebUI: add one you actually use, with paths checked on your Mac.
7. **Copy the log.** The Log screen lets you select one line at a time; a "Copy all" button would make bug reports much easier.
8. **First unit tests.** There is no test target. `Engine.allButNewestDirs`, `AICatalog.releasedBlobs`, `AICatalog.isSafeToTrash` and `AILiveSampler.mcpServer` are pure functions that decide what gets removed or shown, and are a good place to start.

If you pick one, comment on the issue (or open one) so two people do not do the same work.

## Reporting a security problem

Do not open a public issue. See [SECURITY.md](SECURITY.md).

## Licence

TidyDisk is [MIT licensed](LICENSE). By contributing, you agree that your contribution is released under the same licence.
