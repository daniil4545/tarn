# Plan: S8 release, tarn 1.0.0 as its own app

Status: draft for spec review, branch `s8-release` (from `main` e63d8ee11, includes PR #4).
Canon: `docs/spec.md` principles 3 and 4, section 12 (tags `tarn-vX.Y.Z`), section 13 (S0 row); `.claude/CLAUDE.md`.

## 1. Goal and scope

- Goal: `tarn` installs next to Ghostty as a separate app and works as the main terminal.
- User decisions (2026-10-25): ad-hoc signed zip in a GitHub Release, the user removes quarantine with `xattr`; no notarization, no paid account. tarn shares Ghostty's config; its own overlay is `~/.config/tarn/ghostty.conf` (PR #4). The Zig core `src/` stays untouched.
- In: identity, updater off, icon, `tarn.mk` (`check`, `release`), `docs/install.md`, README Install section, one Release build verified.
- Out: tags, the GitHub Release, notarization, `bench`, any change in `src/`.

## 2. Ghostty first: what is reused

| Need | Ghostty has | Use |
|---|---|---|
| App name and bundle id | `PRODUCT_NAME`, `PRODUCT_BUNDLE_IDENTIFIER`, `INFOPLIST_KEY_CFBundleDisplayName` per configuration, `macos/Ghostty.xcodeproj/project.pbxproj` | change these settings, no new mechanism |
| Version | `MARKETING_VERSION` in pbxproj (`:580`, `:977`, `:1032`); upstream CI patches it with PlistBuddy (`release-tip.yml:624-626`) | set `MARKETING_VERSION = 1.0.0` in the build setting; no PlistBuddy step |
| Update off | `SUEnableAutomaticChecks=false` already in `Ghostty-Info.plist:108`, honored at `AppDelegate.swift:841-843` | add manual path only (section 5) |
| Icon | asset catalog name in `ASSETCATALOG_COMPILER_APPICON_NAME = Ghostty` (`:538`, `:936`, `:991`), built from `images/Ghostty.icon` (pbxproj `:80,:390`); in-app image set `AppIconImage` | replace by an app icon set in `macos/Assets.xcassets` (section 6) |

## 3. Name decision

Ghostty names the product `Ghostty.app` (capital), the executable `ghostty` (`EXECUTABLE_NAME = ghostty`, pbxproj `:551,:950,:1004`) and the CLI `ghostty`. tarn follows the same split: bundle `Tarn.app`.

Decision: **`Tarn.app`**, display name `Tarn`, executable stays `ghostty`.
- Why capital: macOS apps are capitalized (Finder, Dock, Cmd+Tab, menu bar show the file name); Ghostty does the same. The prose name in docs stays lowercase `tarn`.
- Why the executable stays `ghostty` (not `tarn`): the `tarn` CLI of the attention stage (S7) may sit in `Contents/MacOS` or `Resources`; APFS is case-insensitive, so `MacOS/Tarn` and `MacOS/tarn` would be one name. Keeping `ghostty` also keeps `TEST_HOST` and the core's `ghostty +action` CLI path valid. Cost: `ps` shows `ghostty`; Dock, Cmd+Tab and Activity Monitor show the bundle name `Tarn`.
- Swift module stays `Ghostty`: `PRODUCT_MODULE_NAME = Ghostty` is set explicitly, because `PRODUCT_NAME = Tarn` would rename the module and break `MainMenu.xib:15` (`customModule="Ghostty"`) and `@testable import Ghostty`.
- Target and scheme names stay `Ghostty` (`build.nu:7` and the shared scheme keep working); only `BuildableName` in `Ghostty.xcscheme:18,76,106` and `TEST_HOST` (pbxproj `:766,:789,:812`) change to `Tarn.app`.

## 4. Identity: every use found

Bundle ids (pbxproj). New ids: `com.daniil4545.tarn` (Release, ReleaseLocal), `com.daniil4545.tarn.debug` (Debug).

| Where | Now | Decision |
|---|---|---|
| pbxproj `:582`, `:1034` | `com.mitchellh.ghostty` | change to `com.daniil4545.tarn` |
| pbxproj `:979` | `com.mitchellh.ghostty.debug` | `com.daniil4545.tarn.debug` |
| pbxproj `:676,:705,:734` | `com.mitchellh.ghostty-dock-tile` | `com.daniil4545.tarn-dock-tile` |
| pbxproj `:758,:782,:805` | `com.mitchellh.GhosttyTests` | `com.daniil4545.tarn.tests` |
| pbxproj `:601,:624,:647` | `com.mitchellh.GhosttyUITests` | `com.daniil4545.tarn.uitests` |
| pbxproj `:555,:953,:1008` display name `Ghostty`, `Ghostty[DEBUG]` | user sees in Dock, menus, Services | `Tarn`, `Tarn[DEBUG]` |
| pbxproj `:669,:698,:727` `Ghostty Dock Tile Plugin` | plugin display name | `Tarn Dock Tile Plugin` |
| pbxproj `:557-573`, `:955-970`, `:1010-1025` usage strings "A program running within Ghostty would like..." (3 configs x 15) | shown in macOS permission prompts | replace `Ghostty` with `Tarn` (scripted, `git diff --stat` after) |
| pbxproj `:580,:977,:1032` `MARKETING_VERSION = 0.1` | About window, `CFBundleShortVersionString` | `1.0.0` for the app target only |
| `DockTilePlugin.swift:13,15` `UserDefaults(suiteName: "com.mitchellh.ghostty[.debug]")` | the plugin runs inside the Dock process and reads the app's defaults by bundle id; unchanged it would read the installed Ghostty's custom-icon choice | change to `com.daniil4545.tarn[.debug]` (clash with Ghostty) |
| `Ghostty-Info.plist:115` and `SurfaceView+Transferable.swift:41` UTI `com.mitchellh.ghosttySurfaceId` (exported type) | two apps would export one type id; Launch Services keeps one | `com.daniil4545.tarn.surfaceId` in both places (clash with Ghostty) |
| `MainMenu.xib:80,82,84,115,127,145,533` menu titles `Ghostty`, `About Ghostty`, `Make Ghostty the Default Terminal`, `Hide Ghostty`, `Quit Ghostty`, `Ghostty Help` | seen daily | `Tarn` in each title |
| `AppDelegate.swift:1044-1046` `showHelp` opens `ghostty.org/docs` | Help menu | open `https://github.com/daniil4545/tarn#readme` |
| `AboutView.swift:6-7,81-82` GitHub and docs URLs, title `Ghostty`, tagline | About window | title `Tarn`, tagline from README, URLs to `daniil4545/tarn`; commit link base follows `githubURL` |
| `AppDelegate.swift:567,1393,1427,538`; `UntrustedURLAlert.swift:39`; `IntentPermission.swift:48`; `GhosttyIntentError.swift:8,10`; `ErrorView.swift:13`; `main.swift:16` | alert texts naming Ghostty | `Tarn` |
| `TitlebarTabsVenturaTerminalWindow.swift:545`, `TitlebarTabsTahoeTerminalWindow.swift:284` title `👻 Ghostty` | placeholder window title | `Tarn` |
| `ViewerHost.swift:207` comment with `com.mitchellh.ghostty` | log filter hint | `com.daniil4545.tarn` |

Left unchanged:

| Where | Why |
|---|---|
| `GhosttyPackage.swift:9,12,291-403` notification names and categories `com.mitchellh.ghostty.*` | in-process names or per-app scopes (`UNUserNotificationCenter` is per bundle); no cross-app effect |
| `QuickTerminalWindow.swift:18`, `TerminalWindow.swift:769-773`, `BaseTerminalController.swift:1739`, `Fullscreen.swift:456-457`, `Notification+AppIcon.swift:7`, `IntentPermission.swift:47` ids | in-process identifiers |
| `NSPasteboard+Extension.swift:32` named pasteboard `com.mitchellh.ghostty.selection` | shared with Ghostty on purpose-free: both apps share the selection clipboard; harmless, and it matches the shared config; change if the user dislikes it |
| `Ghostty.sdef` (names, codes `Ghst`) and `OSAScriptingDefinition` | AppleScript targets an app by name or bundle id; the dictionary title shows only in Script Editor |
| `Ghostty-Info.plist` `LSEnvironment GHOSTTY_MAC_LAUNCH_SOURCE`, `GhosttyBuild`, `GhosttyCommit` keys | read by the core and About; keys are not user-visible |
| `TERM_PROGRAM=ghostty`, `TERM=xterm-ghostty`, `ghostty` resources dir | core behavior; shell integration and terminfo depend on them |
| `AppDelegate`/`TarnSettings.swift:145` "Ghostty Config..." | names the config file the user shares with Ghostty; correct |

Consequences of the unchanged Zig `bundle_id = "com.mitchellh.ghostty"` (`src/build_config.zig:58`):

| Core use | Effect for tarn |
|---|---|
| config search `~/Library/Application Support/com.mitchellh.ghostty/config` and `~/.config/ghostty/config` | shared with Ghostty: the intended decision |
| cache dir `~/Library/Caches/com.mitchellh.ghostty` (`src/os/macos.zig:145`) | shared with Ghostty; the cache holds regenerable data |
| core `os_log` subsystem (`src/main_ghostty.zig:185`) | core logs appear under `com.mitchellh.ghostty`, Swift logs under `com.daniil4545.tarn`; filter by both when debugging |

Two apps with one config share `keybind = global:...` and `quick-terminal` bindings: running both at once means both react (documented in the install guide).

New insertion points go into `docs/architecture.md` section 9 as rows 30 onward (rows 14-18 may be taken by other branches): one row per file group (pbxproj and scheme, xib menu titles, About and alert texts, dock tile suite and UTI, updater, help URL).

## 5. Updater off

Sparkle is a package dependency and stays (removing it touches the project graph and every upstream merge). The feed is the risk: `UpdateDelegate.swift:11-14` returns Ghostty's appcast URLs. Smallest set:

1. `UpdateDelegate.swift:5-15` `feedURLString` returns `nil`: no feed, so a check can never find a Ghostty build.
2. `AppDelegate.swift:233` `updateController.startUpdater()` removed: the updater never starts.
3. `UpdateController.swift:62` `checkForUpdates()` returns at the top: the `check_for_updates` key action (`Ghostty.App.swift:744`) cannot reach an unstarted updater.
4. `AppDelegate.swift:1175` area: `menuCheckForUpdates?.isHidden = true` (outlet at `:23`, xib item `MainMenu.xib:90`). The menu item stays in the xib to keep the outlet valid.

`SUEnableAutomaticChecks=false` (`Ghostty-Info.plist:108`) stays. `SUPublicEDKey` (`:110`) is left; with no feed it is inert.

## 6. Icon

- Source: logo A, `git show origin/s6-presentation:docs/assets/logo.svg` and `docs/assets/logo-1024.png` (1024 square). No `rsvg-convert` or ImageMagick here; `sips` and `iconutil` exist, so sizes come from the 1024 PNG with `sips -z`.
- New `macos/Assets.xcassets/AppIcon.appiconset/` (macOS sizes 16, 32, 128, 256, 512 at 1x and 2x) and `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` in the three configurations. `images/Ghostty.icon` is removed from the Resources phase (pbxproj `:19,:390`) and from the group (`:80,:184`); the folder `images/Ghostty.icon` stays on disk (upstream file).
- The in-app `AppIconImage.imageset` (256/512/1024 PNG: Settings, error view, dock fallback before macOS 26, `DockTilePlugin.swift:63`) gets the same logo, so no Ghostty ghost shows anywhere by default.
- Left: the alternate and custom icon sets (`Alternate Icons`, `Custom Icon`, option `macos-icon`) stay Ghostty-made; the default is `official` = ours. They are the user's opt-in choice.
- Risk: the 1024 PNG already has rounded corners (tile `rx=56` of 256). macOS 26 applies its own mask to catalog icons; a pre-rounded PNG may show a double edge. Check the built icon file by eye; if it looks wrong, ask for a square source.

## 7. Packaging: `tarn.mk`

New root file (the S0 row names it, it does not exist yet; `bench` is not part of this stage).

| Target | Steps |
|---|---|
| `check` | `swiftlint lint --strict Sources/Features/Tarn Tests/Tarn` in `macos/`; `xcodebuild test` of the Tarn suites (Debug, 4 jobs, nice, skip UI tests); `python3 -I plugin/test/hook_test.py` |
| `release` | `xcodebuild -configuration Release -jobs 4 SYMROOT=macos/build` under `nice -n 10` with the same clean `env -i` as `macos/build.nu`; `codesign --force --deep -s - --preserve-metadata=entitlements`; `codesign --verify`; `ditto -c -k --keepParent Tarn.app dist/tarn-<version>-macos.zip`; print `shasum -a 256` |

- `<version>` is read from the built Info.plist, so the file name cannot differ from the app.
- `dist/` goes into `.gitignore`.
- Release config: upstream `Release` uses `Ghostty.entitlements` (privacy entitlements, no sandbox), signing identity `-` already set (`:996`). `--deep` re-signing drops entitlements unless preserved; hence `--preserve-metadata`.
- The Zig core comes from `macos/GhosttyKit.xcframework`, built outside this stage. Its optimization mode decides runtime speed; the build is not rebuilt here. I record which mode the xcframework has in the report.

## 8. Install guide and README

`docs/install.md`: download and unzip; move to `/Applications`; `xattr -dr com.apple.quarantine /Applications/Tarn.app`; first launch (right-click Open fallback); coexistence with Ghostty (separate bundle id and settings, shared config, overlay `~/.config/tarn/ghostty.conf`, shared global key binds); Claude Code plugin (the real marketplace command is checked against `claude plugin --help`, local form `claude plugin marketplace add <repo>/plugin` then `claude plugin install tarn@tarn`); zsh setup for R7 (no guide exists; each line checked in a clean `zsh -f`); uninstall. README gets a short `Install` section and drops "still builds as `Ghostty.app`".

## 9. Verification (run, with output)

1. `make -f tarn.mk release` once, under the global lock.
2. `defaults read .../Contents/Info.plist CFBundleIdentifier` is `com.daniil4545.tarn`; `CFBundleShortVersionString` is `1.0.0`; `CFBundleName`/display name `Tarn`.
3. Icon file in `Contents/Resources`; `codesign -dv --verbose=4` shows ad-hoc; `codesign --verify --deep --strict`; entitlements present.
4. Zip exists, `unzip -l` shows `Tarn.app/`, sha256 printed.
5. `make -f tarn.mk check` once.
6. Not done by me: install into `/Applications`, launch. The report says so.

## 10. Risks

| Risk | Mitigation |
| --- | --- |
| `PRODUCT_NAME=Tarn` breaks module or test host | explicit `PRODUCT_MODULE_NAME`; run the Tarn tests once |
| Release build needs the Sparkle package offline | Debug resolved it; if it fails, report |
| Shared selection pasteboard and global key binds with Ghostty | documented |
| S7 edits `project.pbxproj` and `AppDelegate.swift` | small commits, single-line settings; conflicts go to the main window |
| Pre-rounded icon PNG shows a double edge on macOS 26 | check by eye, ask for a square source |
