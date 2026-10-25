# Install tarn

tarn is a separate app. It installs next to Ghostty and shares Ghostty's config files. The build is ad-hoc signed, not notarized, so macOS needs one `xattr` command before the first launch.

Requirements: macOS 13 or newer, Apple silicon or Intel (one universal build).

## Install

1. Download `tarn-<version>-macos.zip` from the [releases page](https://github.com/daniil4545/tarn/releases) (tags are `tarn-vX.Y.Z`).
2. Check the checksum against the one in the release notes: `shasum -a 256 ~/Downloads/tarn-<version>-macos.zip`.
3. Unzip it and move `Tarn.app` to `/Applications`.
4. Remove the quarantine flag: `xattr -dr com.apple.quarantine /Applications/Tarn.app`. Without it macOS refuses to open an app that is not notarized.
5. Open Tarn from Launchpad or Spotlight. If macOS still blocks it, open System Settings, Privacy and Security, scroll down and press "Open Anyway".

The version in Tarn's About window is the tarn version. `ghostty +version` and `TERM_PROGRAM_VERSION` in a tab show the version of the Ghostty core tarn is based on.

## Living next to Ghostty

| Thing | Shared or separate |
|---|---|
| app, Dock icon, bundle id | separate: `Tarn.app`, `com.daniil4545.tarn` |
| macOS permissions (notifications, files, accessibility), app defaults | separate: each app asks on its own |
| Ghostty config `~/.config/ghostty/config` | shared: tarn reads it, never writes it |
| tarn overlay `~/.config/tarn/ghostty.conf` | tarn only; loaded after your Ghostty config; the Settings window writes it |
| window and tab state | separate |
| selection clipboard (`copy-on-select = clipboard`) | shared: one system-wide named pasteboard, so a selection in Ghostty changes what `paste_from_selection` pastes in Tarn |
| `keybind = global:...`, quick terminal | shared config: with both apps running, both react to the key. Quit one, or move the line into the tarn overlay and delete it from the Ghostty config |
| `macos-icon` (alternate icons) | shared config: an icon set there shows in Tarn. Put `macos-icon = official` in `~/.config/tarn/ghostty.conf` to keep tarn's own icon |

The tarn sidebar settings of a Debug build (domain `com.mitchellh.ghostty.debug`) do not carry over to the release app; set them once in Settings.

## Claude Code plugin

The plugin reports agent state (working, needs you, done) to the sidebar. It does nothing outside tarn.

1. Get the repository: `git clone --depth 1 https://github.com/daniil4545/tarn ~/tarn-plugin`.
2. Add the marketplace: `claude plugin marketplace add ~/tarn-plugin/plugin`.
3. Install the plugin: `claude plugin install tarn@tarn`.
4. Start `claude` in a Tarn tab. The tab dot turns blue while Claude works.

The marketplace file sits in `plugin/.claude-plugin/`, not at the repository root, so `claude plugin marketplace add daniil4545/tarn` does not find it; use the local path.

## zsh: completion and history (R7)

Ghostty's shell integration for zsh is on by default in Tarn. Completion and shared history need a few lines in `~/.zshrc`:

```zsh
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
setopt SHARE_HISTORY HIST_IGNORE_DUPS
HISTFILE=~/.zsh_history HISTSIZE=50000 SAVEHIST=50000
```

Check in a new Tarn tab: `whence -w compdef` prints `compdef: function`; Tab after `git ch` lists commands; the Up arrow brings back a command typed in another tab.

## First check after installing

Run through this list once. It is the acceptance list for the release.

1. Start Ghostty, then Tarn. Both windows open.
2. Cmd+Tab and the Dock show two apps with different icons and names.
3. In a Tarn tab: `echo $TERM` prints `xterm-ghostty`; `infocmp xterm-ghostty >/dev/null && echo ok` prints `ok`; `echo $GHOSTTY_RESOURCES_DIR` is a path inside `Tarn.app`.
4. The Tarn menu bar has no "Check for Updates".
5. Trigger a notification from a Tarn tab (`printf '\e]9;test\a'`): macOS asks permission for "Tarn", and the notification carries the Tarn name.
6. Ghostty's own settings and windows are as before; the Ghostty config file is unchanged (`ls -l ~/.config/ghostty/config`).
7. A font or theme line in the Ghostty config applies in Tarn too.
8. Tarn menu, "Make Tarn the Default Terminal" works if you want it (optional).

## Upgrade

The build is ad-hoc signed, so every release has a new code signature. macOS ties privacy permissions to that signature, so an upgrade may lose them.

1. Quit Tarn (Cmd+Q).
2. Replace `/Applications/Tarn.app` with the new one and run the `xattr` command again.
3. Start Tarn. If a global key (`global:` keybind) does nothing, the Accessibility permission is stale: run `tccutil reset Accessibility com.daniil4545.tarn`, or remove Tarn in System Settings, Privacy and Security, Accessibility, then start Tarn and grant it again.
4. If a tab loses access to Documents, Desktop, Downloads or other protected folders, run `tccutil reset All com.daniil4545.tarn` and grant the access again when asked.

tarn has no self-updater: it never contacts a server.

## Uninstall

Quit Tarn, delete `/Applications/Tarn.app`, and optionally `~/.config/tarn`. `claude plugin uninstall tarn@tarn` removes the plugin.
