BIN := .build/release/ieum-cli
APP_NAME := Ieum
APP := .build/app/$(APP_NAME).app
ENTITLEMENTS := Resources/entitlements.plist

# Developer ID release (see `make app-release`):
#   SIGN_IDENTITY  e.g. "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE a keychain profile created with `xcrun notarytool store-credentials`
SIGN_IDENTITY ?=
NOTARY_PROFILE ?=

.PHONY: build sign test clean app app-bundle app-release dmg bench

build:
	swift build -c release --arch arm64
	$(MAKE) sign

sign:
	codesign --force --sign - --entitlements $(ENTITLEMENTS) $(BIN)

test:
	swift test

# Assemble the unsigned .app bundle from the release build.
app-bundle:
	swift build -c release --arch arm64 --product Ieum
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp .build/release/Ieum "$(APP)/Contents/MacOS/Ieum"
	cp Resources/App/Info.plist "$(APP)/Contents/Info.plist"
	cp Resources/App/AppIcon.icns "$(APP)/Contents/Resources/AppIcon.icns"

# Local build: ad-hoc signed with hardened runtime. Runs on this Mac only.
app: app-bundle
	codesign --force --options runtime --sign - --entitlements $(ENTITLEMENTS) "$(APP)"
	codesign --verify --strict --verbose=2 "$(APP)"

# Distributable build: Developer ID signature, notarization, stapling, Gatekeeper check.
app-release: app-bundle
	@test -n "$(SIGN_IDENTITY)" || { echo "Set SIGN_IDENTITY to your Developer ID Application identity."; exit 1; }
	@test -n "$(NOTARY_PROFILE)" || { echo "Set NOTARY_PROFILE to a notarytool keychain profile."; exit 1; }
	codesign --force --options runtime --timestamp --sign "$(SIGN_IDENTITY)" --entitlements $(ENTITLEMENTS) "$(APP)"
	codesign --verify --strict --verbose=2 "$(APP)"
	ditto -c -k --keepParent "$(APP)" ".build/app/$(APP_NAME).zip"
	xcrun notarytool submit ".build/app/$(APP_NAME).zip" --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(APP)"
	spctl --assess --type execute --verbose=2 "$(APP)"

# Disk image of the app that is already in .build/app (run `make app-release` first for a notarized app).
# Does NOT rebuild the app, so the notarization ticket stapled to it is kept.
# With SIGN_IDENTITY the .dmg is signed; with SIGN_IDENTITY and NOTARY_PROFILE it is also notarized and stapled.
DMG := .build/app/Ieum.dmg
dmg:
	@test -d "$(APP)" || { echo "Build the app first: make app-release (or make app)."; exit 1; }
	rm -rf .build/app/dmg-root "$(DMG)"
	mkdir -p .build/app/dmg-root
	cp -R "$(APP)" .build/app/dmg-root/
	ln -s /Applications .build/app/dmg-root/Applications
	hdiutil create -volname "$(APP_NAME)" -srcfolder .build/app/dmg-root -ov -format UDZO "$(DMG)"
	rm -rf .build/app/dmg-root
	@if [ -n "$(SIGN_IDENTITY)" ]; then \
		codesign --force --timestamp --sign "$(SIGN_IDENTITY)" "$(DMG)"; \
		if [ -n "$(NOTARY_PROFILE)" ]; then \
			xcrun notarytool submit "$(DMG)" --keychain-profile "$(NOTARY_PROFILE)" --wait && \
			xcrun stapler staple "$(DMG)" && \
			spctl --assess --type open --context context:primary-signature --verbose=2 "$(DMG)"; \
		fi; \
	else echo "Unsigned .dmg (set SIGN_IDENTITY and NOTARY_PROFILE for a distributable one)."; fi
	@echo "Created $(DMG)"

# Repeatable latency / accuracy / cost measurements. Usage: make bench LABEL=v0.2.0 [BASELINE=v0.1.0-baseline]
LABEL ?= current
bench:
	swift build -c release --arch arm64 --product ieum-bench
	BASELINE=$(BASELINE) Benchmarks/run.sh $(LABEL)

clean:
	swift package clean
	rm -rf .build
