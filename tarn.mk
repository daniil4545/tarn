# tarn make targets. Usage: make -f tarn.mk check | release
#
# check    swiftlint on our folders, the app test suites, the hook contract test
# release  Tarn.app (ReleaseLocal, ad-hoc signed by Xcode) and dist/tarn-<version>-macos.zip
#
# Builds run under nice and with 4 jobs: the machine is shared with other work.
# Deviation from macos/build.nu: it passes no -jobs limit, so xcodebuild is called directly.

SHELL    := /bin/bash
.SHELLFLAGS := -o pipefail -c

XCB      := nice -n 10 env -i HOME=$(HOME) PATH=/usr/bin:/bin:/usr/sbin:/sbin xcodebuild
PROJECT  := macos/Ghostty.xcodeproj
SYMROOT  := $(CURDIR)/macos/build
CONFIG   := ReleaseLocal
APP      := $(SYMROOT)/$(CONFIG)/Tarn.app
PLIST    := $(APP)/Contents/Info.plist
TMP      := $(CURDIR)/dist/verify

.PHONY: check release

check:
	cd macos && swiftlint lint --strict Sources/Features/Tarn Tests/Tarn
	$(XCB) -project $(PROJECT) -scheme Ghostty -configuration Debug SYMROOT=$(SYMROOT) \
		-jobs 4 -skip-testing GhosttyUITests test 2>&1 | tail -30
	python3 -I plugin/test/hook_test.py

release:
	@test -z "$$(git status --porcelain --untracked-files=no)" || { echo "release: tracked files are modified, commit first"; exit 1; }
	@test -d macos/GhosttyKit.xcframework -a ! -L macos/GhosttyKit.xcframework || { echo "release: macos/GhosttyKit.xcframework must be built here, not linked"; exit 1; }
	nice -n 10 zig build -Doptimize=ReleaseFast -Demit-macos-app=false -j4
	rm -r -f $(SYMROOT)/$(CONFIG)
	$(XCB) -project $(PROJECT) -scheme Ghostty -configuration $(CONFIG) SYMROOT=$(SYMROOT) \
		GHOSTTY_COMMIT=$$(git rev-parse --short HEAD) -jobs 4 build 2>&1 | tail -15
	@test -d $(APP) || { echo "release: $(APP) was not built"; exit 1; }
	@v=$$(plutil -extract CFBundleShortVersionString raw $(PLIST)) && \
	  zip=dist/tarn-$$v-macos.zip && mkdir -p dist && rm -f $$zip && \
	  ditto -c -k --keepParent $(APP) $$zip && \
	  rm -r -f $(TMP) && mkdir -p $(TMP) && ditto -x -k $$zip $(TMP) && \
	  codesign --verify --deep --strict $(TMP)/Tarn.app && \
	  codesign -dv $(TMP)/Tarn.app 2>&1 | grep -E "Identifier|flags|Signature" && \
	  test -f $(TMP)/Tarn.app/Contents/Resources/terminfo/78/xterm-ghostty && \
	  test -f $(TMP)/Tarn.app/Contents/Resources/ghostty/shell-integration/zsh/ghostty-integration && \
	  $(TMP)/Tarn.app/Contents/MacOS/ghostty +version | head -3 && \
	  rm -r -f $(TMP) && echo "zip: $$zip" && shasum -a 256 $$zip
