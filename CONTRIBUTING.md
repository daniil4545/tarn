# Contributing to tarn

tarn is a small fork of [Ghostty](https://ghostty.org) for working with CLI coding agents. Issues
and pull requests are welcome; please keep them small and focused.

- **Bugs and ideas:** open an issue on [daniil4545/tarn](https://github.com/daniil4545/tarn/issues).
  For a bug, give the tarn version (`tarn-vX.Y.Z`), the macOS version and the steps to reproduce.
- **Scope:** `docs/spec.md` section 1 lists what tarn does. A feature outside it needs an issue
  and a yes before code.
- **Pull requests:** branch from `dev` and open the PR into `dev`. Run `make -f tarn.mk check`
  first; `HACKING.md` covers building the Ghostty base.
- **Ghostty itself:** the Zig core is not modified here. Report core bugs to
  [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty), not to this repository.

tarn is MIT; contributions are accepted under the same license.
