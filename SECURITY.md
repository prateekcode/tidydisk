# Security policy

TidyDisk deletes files, so a bug here can cost someone their data. Reports are welcome and taken seriously.

## Supported versions

Only the latest release gets fixes. Check [Releases](https://github.com/prateekcode/tidydisk/releases) for the current version and update before reporting, in case it is already fixed.

| Version | Supported |
|:--|:--|
| Latest release | Yes |
| Anything older | No, please update |

## What counts

Anything that could delete, move or expose files beyond what the app shows the user. For example:

- a cleaner, an uninstall or a "Move to Trash" that removes something that was not listed or ticked
- a path that escapes its intended folder (through a symlink, `..`, or an unusual file name) and reaches other data
- a command TidyDisk runs (`du`, `find`, `npm`, `docker`, `git`, `curl` and the like) that can be made to run something else, for instance through a crafted folder or project name
- the GitHub token (kept in the macOS Keychain) or any file content, path or name leaving the Mac without the user asking for it
- the weekly scan's LaunchAgent being usable to run something other than TidyDisk
- anything sent over the network that the README's privacy section does not describe

Ordinary bugs (a wrong size, a crash, a cleaner that finds nothing) are not security problems: please use the [bug report form](https://github.com/prateekcode/tidydisk/issues/new?template=bug_report.yml).

## How to report

Please do not open a public issue for a security problem.

- **Preferred:** GitHub's private vulnerability reporting. On the repository, open the **Security** tab and choose **Report a vulnerability** ([direct link](https://github.com/prateekcode/tidydisk/security/advisories/new)).
- **Or by email:** riekapps@gmail.com, with "TidyDisk security" in the subject.

It helps to include the TidyDisk version, the macOS version, the steps to reproduce on a throwaway folder, and what was removed or exposed.

## What to expect

TidyDisk is maintained by a small indie studio. Reports are handled on a best-effort basis: you will get an acknowledgement, an honest read on whether it is a problem, and a fix in the next release when it is. There is no bug bounty. If you would like credit in the release notes, say so in the report.
