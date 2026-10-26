# Benchmark

tarn `361df3ff4` against upstream Ghostty `48dde97e0`, both ReleaseLocal.
2026-10-25, Apple M4, 10 cores, macOS 26.6.2.
One window, one surface; runs alternate between the apps; thresholds of `docs/spec.md` section 7. Input latency is not measured.

| Metric | tarn | upstream | Difference | Within threshold |
| --- | --- | --- | --- | --- |
| Startup, ms (median of 10) | 247.92 | 231.03 | +7.3% | no |
| Idle CPU, % (mean of 60 s) | 0.36 | 0.35 | +0.00 pp | yes |
| Memory RSS, MB (median of 5) | 115.17 | 112.16 | +2.7% | yes |
| Memory footprint, MB (median of 5) | 125.75 | 123.67 | +1.7% | yes |
| cat 100 MB, s (median of 5) | 0.32 | 0.30 | +6.6% | no |

## Startup investigation (T-149, hotfix 1.0.1)

Not a `make -f tarn.mk bench` result: the table above is the 1.0.0 run and the next `make bench` rewrites this file, so move this section if it is still needed. Startup only, ReleaseLocal builds of `361df3ff4` plus the hotfix tree, upstream at `48dde97e0`, one shared ReleaseFast core, launch to first window (window list), alternating runs, Apple M4.

| Finding | Evidence |
| --- | --- |
| The SwiftUI sidebar is not the main cost | removing `SidebarLayout` and `ViewerLayout` from the window moved the median by about 3 ms of a 10 to 14 ms gap |
| Measured gap is noisy | the same binaries gave a gap of +7% to +14% in three sessions, and a build of the same source differed by up to 8 ms; in a fourth session tarn ran faster than upstream. A 5% threshold (about 7 ms) is under this noise on a shared machine |
| Cost found by profile | `window.tabGroup` of a lone window in `WorkspaceRegistry.bookGroups` (about 2 ms real), the card popover built at start, lazy stacks |
| Not done | `make -f tarn.mk bench` itself: the tree is dirty and the xcframework is a link (`release` refuses both), and the benchmark needs an unlocked screen (a locked session never gives the app a window) |

Next step: run `make -f tarn.mk release` and `bench` from a clean checkout on an idle, unlocked machine, with more than 10 startup rounds.

