# tarn make targets. Usage: make -f tarn.mk check | release | bench
#
# check    swiftlint on our folders, the app test suites, the hook, CLI and installer tests
# release  Tarn.app (ReleaseLocal, ad-hoc signed by Xcode, with the `tarn` CLI inside) and dist/tarn-<version>-macos.zip with its .sha256
# bench    the release Tarn.app against upstream Ghostty built from the merge base with upstream/main; writes docs/bench.md
#
# Builds run under nice and with 4 jobs: the machine is shared with other work.
# Deviation from macos/build.nu: it passes no -jobs limit, so xcodebuild is called directly.

# GNU make 3.81 (stock macOS) has no .SHELLFLAGS: pipefail goes into SHELL, so `| tail` cannot hide a failure.
SHELL    := /bin/bash -o pipefail

XCB      := nice -n 10 env -i HOME=$(HOME) PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild
PROJECT  := macos/Ghostty.xcodeproj
SYMROOT  := $(CURDIR)/macos/build
CONFIG   := ReleaseLocal
APP      := $(SYMROOT)/$(CONFIG)/Tarn.app
PLIST    := $(APP)/Contents/Info.plist
CLI      := $(APP)/Contents/MacOS/tarn
TMP      := $(CURDIR)/dist/verify
BENCH    := $(CURDIR)/dist/bench
# Xcode 27 sets ENABLE_CODE_COVERAGE for every build: the binary would count every Swift branch and
# write default.profraw into the cwd on exit. -enableCodeCoverage applies to `test` only.
NOCOV    := ENABLE_CODE_COVERAGE=NO CLANG_COVERAGE_MAPPING=NO
LSREG    :=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: check release bench

check:
	cd macos && swiftlint lint --strict Sources/Features/Tarn Tests/Tarn
	$(XCB) -project $(PROJECT) -scheme Ghostty -configuration Debug SYMROOT=$(SYMROOT) \
		-jobs 4 -skip-testing GhosttyUITests test > $(SYMROOT)/test.log 2>&1 || \
		{ grep -E "error:|failed|\*\* TEST" $(SYMROOT)/test.log | tail -40; exit 1; }
	@echo "app tests: $$(grep -c -E "Test [Cc]ase .* passed" $(SYMROOT)/test.log) passed, $$(grep -c -E "Test [Cc]ase .* failed" $(SYMROOT)/test.log) failed; log $(SYMROOT)/test.log"
	python3 -I plugin/test/hook_test.py
	python3 -I cli/test/cli_test.py
	shellcheck install.sh cli/tarn cli/test/install_test.sh
	sh cli/test/install_test.sh

release:
	@test -z "$$(git status --porcelain)" || { echo "release: the tree has changes or untracked files, commit first"; exit 1; }
	@test ! -L macos/GhosttyKit.xcframework || { echo "release: macos/GhosttyKit.xcframework must not be a link: the core is built here"; exit 1; }
	nice -n 10 zig build -Doptimize=ReleaseFast -Demit-macos-app=false -j4
	rm -r -f $(SYMROOT)/$(CONFIG)
	$(XCB) -project $(PROJECT) -scheme Ghostty -configuration $(CONFIG) SYMROOT=$(SYMROOT) \
		GHOSTTY_COMMIT=$$(git rev-parse --short HEAD) $(NOCOV) -jobs 4 build 2>&1 | tail -15
	@test -d $(APP) || { echo "release: $(APP) was not built"; exit 1; }
	@test -x $(CLI) || { echo "release: $(CLI) is missing"; exit 1; }
	@codesign --verify --strict $(CLI) || { echo "release: $(CLI) is not signed"; exit 1; }
	@test "$$(otool -l $(APP)/Contents/MacOS/ghostty | grep -c __llvm_prf)" = 0 || { echo "release: the app has coverage instrumentation"; exit 1; }
	@test "$$(plutil -extract CFBundleIdentifier raw $(PLIST))" = com.daniil4545.tarn || { echo "release: wrong CFBundleIdentifier"; exit 1; }
	@test "$$(plutil -p $(PLIST) | grep -c -e mitchellh -e SUFeedURL)" = 0 || { echo "release: Info.plist names Ghostty or sets a feed"; exit 1; }
	@v=$$(plutil -extract CFBundleShortVersionString raw $(PLIST)) && \
	  zip=dist/tarn-$$v-macos.zip && mkdir -p dist && rm -f $$zip && \
	  ditto -c -k --keepParent $(APP) $$zip && \
	  rm -r -f $(TMP) && mkdir -p $(TMP) && ditto -x -k $$zip $(TMP) && \
	  codesign --verify --deep --strict $(TMP)/Tarn.app && \
	  test -x $(TMP)/Tarn.app/Contents/MacOS/tarn && codesign --verify --strict $(TMP)/Tarn.app/Contents/MacOS/tarn && \
	  codesign -dv $(TMP)/Tarn.app 2>&1 | grep -E "Identifier|flags|Signature" && \
	  test -f $(TMP)/Tarn.app/Contents/Resources/terminfo/78/xterm-ghostty && \
	  test -f $(TMP)/Tarn.app/Contents/Resources/ghostty/shell-integration/zsh/ghostty-integration && \
	  $(TMP)/Tarn.app/Contents/MacOS/ghostty +version | head -3 && \
	  rm -r -f $(TMP) && echo "zip: $$zip" && \
	  (cd dist && shasum -a 256 tarn-$$v-macos.zip | tee tarn-$$v-macos.zip.sha256)

# The upstream app is built once per merge base from `git archive` and reused; the bench run unregisters it
# from Launch Services, so `open -a Ghostty` keeps finding the installed Ghostty.
bench:
	@test -d $(APP) || { echo "bench: $(APP) is missing, run make -f tarn.mk release first"; exit 1; }
	@git rev-parse -q --verify upstream/main > /dev/null || { echo "bench: no upstream/main, run git fetch upstream"; exit 1; }
	@base=$$(git merge-base HEAD upstream/main) && up=$(BENCH)/upstream-$$base && upapp=$$up/macos/build/ReleaseLocal/Ghostty.app && \
	  if [ ! -d $$upapp ]; then \
	    rm -r -f $$up && mkdir -p $$up && git archive $$base | tar -x -C $$up && \
	    (cd $$up && nice -n 10 zig build -Doptimize=ReleaseFast -Demit-macos-app=false -j4) && \
	    $(XCB) -project $$up/macos/Ghostty.xcodeproj -scheme Ghostty -configuration ReleaseLocal \
	      SYMROOT=$$up/macos/build $(NOCOV) -jobs 4 build 2>&1 | tail -3; \
	  fi && \
	  swiftc -O tools/bench/bench.swift -o $(BENCH)/bench && \
	  { echo "# Benchmark"; echo; \
	    echo "tarn \`$$(git rev-parse --short HEAD)\` against upstream Ghostty \`$$(git rev-parse --short $$base)\`, both ReleaseLocal."; \
	    echo "$$(date +%F), $$(sysctl -n machdep.cpu.brand_string), $$(sysctl -n hw.ncpu) cores, macOS $$(sw_vers -productVersion)."; \
	    echo "One window, one surface; runs alternate between the apps; thresholds of \`docs/spec.md\` section 7. Input latency is not measured."; echo; } > docs/bench.md && \
	  status=0 && $(BENCH)/bench $(APP) $$upapp $(BENCH)/run >> docs/bench.md || status=$$?; \
	  $(LSREG) -u $$upapp; cat docs/bench.md; exit $$status
