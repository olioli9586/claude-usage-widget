APP_NAME = ClaudeUsage
BUILD_DIR = .build/release
DIST = dist/$(APP_NAME).app
INSTALL_DIR = /Applications

# Command Line Tools ship swift-testing outside the default search paths (and
# without its Foundation cross-import overlay), so point swift at it there.
# With full Xcode selected, plain `swift test` works.
CLT_FRAMEWORKS = /Library/Developer/CommandLineTools/Library/Developer/Frameworks
ifeq ($(shell xcode-select -p 2>/dev/null),/Library/Developer/CommandLineTools)
TEST_FLAGS = -Xswiftc -F -Xswiftc $(CLT_FRAMEWORKS) \
	-Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
	-Xlinker -rpath -Xlinker $(CLT_FRAMEWORKS)
endif

.PHONY: build bundle install run once test clean

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

test:
	swift test $(TEST_FLAGS)

clean:
	rm -rf .build dist
