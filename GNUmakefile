# tarn entry point. GNU make reads this file before Makefile, so `make lint` works while the
# upstream Makefile stays untouched (upstream merges bring it). Its targets are included below.
include Makefile

SHELL := /bin/bash -o pipefail

# Static checks only, no builds or tests. Commands and versions are those of
# .github/workflows/test.yml (zig fmt, swiftlint, typos, shellcheck) and of tarn.mk (ruff).
#
# Not run here:
# - prettier: fails on 98 tarn files (demo/js, demo/css, docs, viewer-web); tarn code is not reformatted.
# - alejandra, pinact, blueprint-compiler: need nix, a GitHub token or tools that are not installed.
# - check-translations.sh: runs `zig build update-translations`, a build.
# - typos skips the generated viewer bundles, as tarn.mk does.
lint:
	zig fmt --check --exclude .worktrees .
	cd macos && swiftlint lint --strict
	shellcheck --check-sourced --severity=warning \
		$$(find . \( -name "*.sh" -o -name "*.bash" \) -type f ! -path "./zig-out/*" ! -path "./macos/build/*" \
		! -path "./.git/*" ! -path "./.worktrees/*" | sort)
	shellcheck -e SC2015 cli/tarn
	uvx typos@1.51.1 --exclude '.worktrees' --exclude 'macos/Sources/Features/Tarn/Viewer/tarn-*'
	uvx ruff@0.17.2 check plugin/test
	uvx ruff@0.17.2 format --check plugin/test
.PHONY: lint
