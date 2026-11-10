include app.env

VERSION := $(shell cat VERSION)
SIGN_ID ?= -
COVERAGE_MIN ?= 90
ARCHS := --arch arm64
APP_DIR := build/$(APP_NAME).app

.DEFAULT_GOAL := app
.PHONY: app run zip dmg lint format test clean samples check

define INFO_PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$(APP_NAME)</string>
    <key>CFBundleDisplayName</key>
    <string>$(APP_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(BUNDLE_ID)</string>
    <key>PreviousBundleIdentifier</key>
    <string>$(PREVIOUS_BUNDLE_ID)</string>
    <key>UpdateRepository</key>
    <string>$(UPDATE_REPO)</string>
    <key>CFBundleExecutable</key>
    <string>$(APP_NAME)</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$(VERSION)</string>
    <key>CFBundleVersion</key>
    <string>$(VERSION)</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.entertainment</string>
</dict>
</plist>
endef
export INFO_PLIST

define COVERAGE_CHECK
import json, sys
minimum = float(sys.argv[1])
with open(sys.argv[2]) as f:
    data = json.load(f)
total = covered = 0
for file in data["data"][0]["files"]:
    if "/Sources/CueCore/" in file["filename"]:
        lines = file["summary"]["lines"]
        total += lines["count"]
        covered += lines["covered"]
if total == 0:
    sys.exit("coverage: no CueCore lines in the report")
pct = 100.0 * covered / total
if pct < minimum:
    sys.exit("coverage: CueCore line coverage %.1f%% is below the %g%% gate" % (pct, minimum))
print("CueCore line coverage: %.1f%% (gate %g%%)" % (pct, minimum))
endef
export COVERAGE_CHECK

app:
	swift build -c release $(ARCHS) --product CueApp
	rm -rf "$(APP_DIR)"
	mkdir -p "$(APP_DIR)/Contents/MacOS" "$(APP_DIR)/Contents/Resources"
	cp "$$(swift build -c release $(ARCHS) --product CueApp --show-bin-path)/CueApp" "$(APP_DIR)/Contents/MacOS/$(APP_NAME)"
	printf '%s\n' "$$INFO_PLIST" > "$(APP_DIR)/Contents/Info.plist"
	plutil -lint "$(APP_DIR)/Contents/Info.plist"
	# Icon Composer source to Assets.car (macOS 26) and AppIcon.icns (14, 15); absolute paths, its daemon's cwd can be stale.
	xcrun actool --compile "$(CURDIR)/$(APP_DIR)/Contents/Resources" --platform macosx --minimum-deployment-target 14.0 \
		--app-icon AppIcon --output-partial-info-plist "$(CURDIR)/build/AppIcon.plist" \
		--output-format human-readable-text --errors --warnings "$(CURDIR)/design/AppIcon.icon"
	codesign --force --options runtime --sign "$(SIGN_ID)" "$(APP_DIR)"
	codesign --verify --strict "$(APP_DIR)"

run: app
	exec "$(APP_DIR)/Contents/MacOS/$(APP_NAME)"

zip: app
	ditto -c -k --keepParent "$(APP_DIR)" "build/$(APP_NAME)-$(VERSION).zip"

# Drag-to-install disk image: the app next to a link to Applications.
dmg: app
	rm -rf build/dmg "build/$(APP_NAME)-$(VERSION).dmg"
	mkdir -p build/dmg
	ditto "$(APP_DIR)" "build/dmg/$(APP_NAME).app"
	ln -s /Applications build/dmg/Applications
	hdiutil create -quiet -volname "$(APP_NAME) $(VERSION)" -srcfolder build/dmg -fs HFS+ -format UDZO \
		"build/$(APP_NAME)-$(VERSION).dmg"
	rm -rf build/dmg

# Headless preflight with the built app, never rebuilding it: make check SHOW=<concert, movie or clip folder>.
check:
	@test -x "$(APP_DIR)/Contents/MacOS/$(APP_NAME)" || { echo "no built app at $(APP_DIR): run make app first" >&2; exit 1; }
	@"$(APP_DIR)/Contents/MacOS/$(APP_NAME)" --check "$(SHOW)"

lint:
	swift format lint --strict --recursive Sources Tests Package.swift

format:
	swift format --in-place --recursive Sources Tests Package.swift

test:
	swift test --enable-code-coverage
	python3 -c "$$COVERAGE_CHECK" "$(COVERAGE_MIN)" "$$(swift test --show-codecov-path)"

clean:
	rm -rf .build build

# Test clips, logos, movie and concert in build/samples (needs ffmpeg or nix).
samples:
	scripts/make-samples.sh build/samples
