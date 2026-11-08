# make project   Monochrome.xcodeproj from project.yml (XcodeGen: brew install xcodegen)
# make build     Release build into build/
# make install   build, then replace ~/Applications/Monochrome.app and open it; the app installs the rest
#                itself at launch (helper/Install.swift)
# make test      the extension's and host's tests (needs a build for the host ones)
# make release VERSION=1.1   version into project.yml and manifest.json, build, dist/Monochrome-app-1.1.zip,
#                appcast.xml; prints the publishing commands
DERIVED := build
APP     := $(DERIVED)/Build/Products/Release/Monochrome.app
INSTALLED := $(HOME)/Applications/Monochrome.app
SPARKLE_BIN := $(DERIVED)/SourcePackages/artifacts/sparkle/Sparkle/bin

.PHONY: project build install run test pack release clean

project:
	xcodegen generate --quiet

build: project
	xcodebuild -project Monochrome.xcodeproj -scheme Monochrome -configuration Release \
	  -derivedDataPath $(DERIVED) -allowProvisioningUpdates -quiet build
	@test -d "$(APP)"

# By process, not by bundle id: "tell application id ... to quit" resolves the id to the newest bundle,
# the one just built, and launches that copy to quit it.
install: build
	pkill -x Monochrome 2>/dev/null || true
	sleep 0.5
	mkdir -p "$(HOME)/Applications"
	rm -rf "$(INSTALLED)"
	ditto "$(APP)" "$(INSTALLED)"
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
	$(MAKE) build
	mkdir -p dist
	rm -f dist/Monochrome-app-$(VERSION).zip
	ditto -c -k --keepParent "$(APP)" dist/Monochrome-app-$(VERSION).zip
	"$(SPARKLE_BIN)/generate_appcast" --download-url-prefix "https://github.com/arfct/monochrome/releases/download/v$(VERSION)/" \
	  --link https://github.com/arfct/monochrome/releases -o appcast.xml dist
	@echo
	@echo "built dist/Monochrome-app-$(VERSION).zip and appcast.xml. To publish:"
	@echo "  gh release create v$(VERSION) dist/Monochrome-app-$(VERSION).zip --title \"Monochrome $(VERSION)\" --notes \"...\""
	@echo "  git commit -am \"Release $(VERSION)\" && git push"
	@echo "The app reads the appcast on main, so the release must exist before that push lands."

clean:
	rm -rf $(DERIVED) Monochrome.xcodeproj
