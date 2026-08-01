APP_NAME = ClaudeUsage
BUILD_DIR = .build/release
DIST = dist/$(APP_NAME).app
INSTALL_DIR = /Applications

.PHONY: build bundle install run once clean

build:
	swift build -c release

bundle: build
	rm -rf $(DIST)
	mkdir -p $(DIST)/Contents/MacOS $(DIST)/Contents/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(DIST)/Contents/MacOS/$(APP_NAME)
	cp bundle/Info.plist $(DIST)/Contents/Info.plist
	codesign --force --deep -s - $(DIST)

install: bundle
	@pkill -x $(APP_NAME) 2>/dev/null || true
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	ditto $(DIST) "$(INSTALL_DIR)/$(APP_NAME).app"
	open "$(INSTALL_DIR)/$(APP_NAME).app"

run: bundle
	$(DIST)/Contents/MacOS/$(APP_NAME)

once:
	swift run -c release $(APP_NAME) --once

clean:
	rm -rf .build dist
