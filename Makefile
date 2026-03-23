APP_NAME := MXControl
BUNDLE_ID := com.mxcontrol.app
BUILD_DIR := .build/release
BINARY := $(BUILD_DIR)/$(APP_NAME)
APP_BUNDLE := $(APP_NAME).app
INSTALL_DIR := /Applications
SIGNING_IDENTITY ?= Apple Development: wwicaksono96@gmail.com (UYQPA4SKQ3)

.PHONY: build run bundle install deploy dmg clean

build:
	swift build -c release

run:
	swift run

debug:
	swift build
	.build/debug/$(APP_NAME)

bundle: build
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp $(BINARY) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	@cp Sources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	@cp Sources/Resources/logi-logo.png $(APP_BUNDLE)/Contents/Resources/logi-logo.png
	@cp Sources/Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	@# Generate PkgInfo
	@echo "APPL????" > $(APP_BUNDLE)/Contents/PkgInfo
	@# Codesign (override SIGNING_IDENTITY for dev cert, defaults to ad-hoc)
	@codesign --force --sign "$(SIGNING_IDENTITY)" \
		--entitlements Sources/Entitlements.plist \
		--options runtime \
		$(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE)"

install: bundle
	@cp -R $(APP_BUNDLE) $(INSTALL_DIR)/$(APP_BUNDLE)
	@echo "Installed to $(INSTALL_DIR)/$(APP_BUNDLE)"

deploy: bundle
	@echo "Deploying $(APP_NAME)..."
	@-killall $(APP_NAME) 2>/dev/null && sleep 1 || true
	@rm -rf $(INSTALL_DIR)/$(APP_BUNDLE)
	@cp -R $(APP_BUNDLE) $(INSTALL_DIR)/$(APP_BUNDLE)
	@open $(INSTALL_DIR)/$(APP_BUNDLE)
	@echo "Deployed and launched $(APP_NAME)"

dmg: bundle
	@rm -f $(APP_NAME).dmg
	@hdiutil create -volname "$(APP_NAME)" \
		-srcfolder $(APP_BUNDLE) \
		-ov -format UDZO \
		$(APP_NAME).dmg
	@echo "Created $(APP_NAME).dmg"

clean:
	swift package clean
	rm -rf $(APP_BUNDLE) $(APP_NAME).dmg
