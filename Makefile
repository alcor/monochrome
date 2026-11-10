# make project   Monochrome.xcodeproj from project.yml (XcodeGen: brew install xcodegen)
# make build     Release build into build/
# make install   build into ~/Applications/Monochrome.app and open it; the app installs the rest
#                itself at launch (helper/Install.swift)
# make test      the extension's and host's tests (needs a build for the host ones)
# make release VERSION=1.1   version into project.yml and manifest.json, a Developer ID build notarized by
#                Apple (Xcode signs with the team's cloud-managed certificate and submits it; needs Xcode signed in
#                to an account on team TVA9Z8LD95 that may use Developer ID), dist/Monochrome-app-1.1.zip, appcast.xml; prints the publishing commands
DERIVED := build
APP     := $(DERIVED)/Build/Products/Release/Monochrome.app
INSTALLED := $(HOME)/Applications/Monochrome.app
SPARKLE_BIN := $(DERIVED)/SourcePackages/artifacts/sparkle/Sparkle/bin
ARCHIVE := $(DERIVED)/Monochrome.xcarchive
NOTARIZED := $(DERIVED)/notarized/Monochrome.app
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: project build install run test pack release clean

project:
	xcodegen generate --quiet

build: project
	xcodebuild -project Monochrome.xcodeproj -scheme Monochrome -configuration Release -destination "generic/platform=macOS" \
	  -derivedDataPath $(DERIVED) -allowProvisioningUpdates -quiet build
	@test -d "$(APP)"

# By process, not by bundle id: "tell application id ... to quit" resolves the id to the newest bundle,
# the one just built, and launches that copy to quit it.
# Built in place, with Xcode's install action into $(HOME)/Applications, not copied from build/:
# xcodebuild registers every app it builds with LaunchServices (Swift Build does it for any macOS app,
# with no setting to stop it), and while macOS knows two copies of the Safari app extension Safari keeps
# whichever it took last and refuses the other ("other version in use"), so the app's messages to Safari
# fail. Built here there is one copy. The app keeps running its old code until the pkill; a second pkill
# stops any copy the Safari extension started (by bundle id) in between.
install: project
	xcodebuild -project Monochrome.xcodeproj -scheme Monochrome -configuration Release -destination "generic/platform=macOS" \
	  -derivedDataPath $(DERIVED) -allowProvisioningUpdates -quiet DSTROOT="$(HOME)" INSTALL_PATH=/Applications install
	@test -d "$(INSTALLED)"
	$(LSREGISTER) -u "$(APP)" 2>/dev/null || true
	pkill -x Monochrome 2>/dev/null || true
	sleep 0.5
	pkill -x Monochrome 2>/dev/null || true
	open "$(INSTALLED)"
	@echo "installed: $(INSTALLED) (allow it under System Settings → Privacy & Security → Accessibility if asked)"

# The build as it is, registering the host only: no login item, Dock tile, default browser or App Shortcuts.
run: build
	open "$(APP)" --args --portable

test:
	npm test

pack:
	store/pack.sh

release:
	@test -n "$(VERSION)" || { echo "usage: make release VERSION=1.1"; exit 1; }
	sed -i '' 's/^    MARKETING_VERSION: ".*"/    MARKETING_VERSION: "$(VERSION)"/; s/^    CURRENT_PROJECT_VERSION: ".*"/    CURRENT_PROJECT_VERSION: "$(VERSION)"/' project.yml
	python3 -c "import json; m = json.load(open('manifest.json')); m['version'] = '$(VERSION)'; f = open('manifest.json', 'w'); json.dump(m, f, ensure_ascii=False, indent=2); f.write('\n')"
	$(MAKE) project
	rm -rf "$(ARCHIVE)" $(DERIVED)/upload $(DERIVED)/notarized
	xcodebuild -project Monochrome.xcodeproj -scheme Monochrome -configuration Release -destination "generic/platform=macOS" \
	  -derivedDataPath $(DERIVED) -archivePath "$(ARCHIVE)" -allowProvisioningUpdates -quiet archive
	xcodebuild -exportArchive -archivePath "$(ARCHIVE)" -exportOptionsPlist ExportOptions.plist \
	  -exportPath $(DERIVED)/upload -allowProvisioningUpdates -quiet
	@echo "waiting for the notary service"
	until xcodebuild -exportNotarizedApp -archivePath "$(ARCHIVE)" -exportPath $(DERIVED)/notarized \
	    -allowProvisioningUpdates >/dev/null 2>&1; do sleep 15; done
	xcrun stapler validate "$(NOTARIZED)"
	# The archive's and the export's copies are registered too; see install for why only one may be.
	for app in "$(ARCHIVE)/Products/Applications/Monochrome.app" "$(DERIVED)/upload/Monochrome.app" "$(NOTARIZED)" \
	    "$(DERIVED)/Build/Intermediates.noindex/ArchiveIntermediates/Monochrome/InstallationBuildProductsLocation/Applications/Monochrome.app"; do \
	  $(LSREGISTER) -u "$$PWD/$$app" 2>/dev/null || true; done
	spctl --assess --type execute "$(NOTARIZED)"
	mkdir -p dist
	rm -f dist/Monochrome-app-$(VERSION).zip
	ditto -c -k --sequesterRsrc --keepParent "$(NOTARIZED)" dist/Monochrome-app-$(VERSION).zip
	"$(SPARKLE_BIN)/generate_appcast" --download-url-prefix "https://github.com/arfct/monochrome/releases/download/v$(VERSION)/" \
	  --link https://github.com/arfct/monochrome/releases -o appcast.xml dist
	# generate_appcast gives every zip in dist/ the new release's prefix; each goes back to its own release.
	python3 -I -c "import re; s = open('appcast.xml').read(); open('appcast.xml', 'w').write(re.sub(r'download/v[^/]+/Monochrome-app-([0-9.]+)\.zip', r'download/v\1/Monochrome-app-\1.zip', s))"
	@echo
	@echo "built dist/Monochrome-app-$(VERSION).zip and appcast.xml. To publish:"
	@echo "  gh release create v$(VERSION) dist/Monochrome-app-$(VERSION).zip --title \"Monochrome $(VERSION)\" --notes \"...\""
	@echo "  git commit -am \"Release $(VERSION)\" && git push"
	@echo "The app reads the appcast on main, so the release must exist before that push lands."

clean:
	rm -rf $(DERIVED) Monochrome.xcodeproj
