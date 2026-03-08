APP_NAME := MXControl
BUNDLE_ID := com.mxcontrol.app
BUILD_DIR := .build/release
BINARY := $(BUILD_DIR)/$(APP_NAME)
APP_BUNDLE := $(APP_NAME).app
INSTALL_DIR := /Applications
SIGNING_IDENTITY ?= -

.PHONY: build run bundle install clean

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
	@# Generate PkgInfo
	@echo "APPL????" > $(APP_BUNDLE)/Contents/PkgInfo
	@# Codesign with entitlements
	@codesign --force --sign - \
		--entitlements Sources/Entitlements.plist \
		--options runtime \
		$(APP_BUNDLE)
	@echo "Built $(APP_BUNDLE)"

install: bundle
	@cp -R $(APP_BUNDLE) $(INSTALL_DIR)/$(APP_BUNDLE)
	@echo "Installed to $(INSTALL_DIR)/$(APP_BUNDLE)"

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)
