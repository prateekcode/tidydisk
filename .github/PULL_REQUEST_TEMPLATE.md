<!-- Thanks for the pull request. CONTRIBUTING.md has the detail behind each box. -->

## What this changes

<!-- One or two plain sentences. Link the issue if there is one: "Closes #12". -->

## How I checked it

<!-- What you ran and on what: macOS version, chip, real folder or a throwaway one. -->

## Checklist

- [ ] `swift build -c release` passes, and `./build.sh` produces an app that opens
- [ ] Scanning is still read-only: nothing is removed before the user presses a button
- [ ] Anything the owning tool does not regenerate goes to the Trash, not `removeItem`
- [ ] New cleaner or AI tool: tried on a throwaway copy first, sizes compared with `du -sh`, and the risk group is explained above
- [ ] No reads of `~/Library/Containers`, `Group Containers` or `Mobile Documents` unless Full Disk Access is on
- [ ] No new network calls (or: the call only happens when the user starts the feature, and it is described above)
- [ ] UI change: built from `Theme` tokens and the kit in `UI/Components`, no new card styles or colours
- [ ] UI change: a `--shot` PNG of each changed tab is attached (taken with `--machine-name "MacBook Air"`)
- [ ] `CHANGELOG.md` has a line under Unreleased if a user would notice the change
