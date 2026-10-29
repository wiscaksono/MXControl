CONFIG ?= debug
APP_NAME := MXControl
APP := build/$(APP_NAME).app
DMG := build/$(APP_NAME).dmg
SNAPSHOT_DIR := build/snapshots
# Falls back to ad-hoc when no development certificate is present.
SIGNING_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null \
	| sed -n 's/.*"\(Apple Development[^"]*\)"/\1/p' | head -1)

.PHONY: build test lint format selfcheck snapshot screenshots bundle run stop dev verify release install dmg clean

build:
	swift build -c $(CONFIG)

test:
	swift test

lint:
	swiftformat --lint .
	swiftlint --quiet

format:
	swiftformat .

selfcheck:
	swift run -c $(CONFIG) $(APP_NAME) --self-check

snapshot:
	swift run -c $(CONFIG) Snapshot --out $(SNAPSHOT_DIR)

screenshots: snapshot
	./scripts/screenshots.sh

bundle: build
	SIGNING_IDENTITY="$(SIGNING_IDENTITY)" ./scripts/bundle.sh "$$(swift build -c $(CONFIG) --show-bin-path)/$(APP_NAME)" "$(APP)"

run: bundle
	open -g "$(APP)"

stop:
	@pkill -x "$(APP_NAME)" || true

# Rebuild, relaunch, repeat. Watch mode for the human; agents should use verify.
dev:
	@command -v fswatch >/dev/null 2>&1 || { echo "fswatch required: brew install fswatch"; exit 1; }
	@$(MAKE) --no-print-directory bundle
	@echo "watching Sources/, Package.swift, scripts/ (Ctrl-C to stop)"
	@fswatch -o -l 0.4 Sources Package.swift scripts/Info.plist scripts/bundle.sh | while read -r _; do \
		if $(MAKE) --no-print-directory bundle > build/dev-build.log 2>&1; then \
			pkill -x "$(APP_NAME)" >/dev/null 2>&1 || true; \
			for i in $$(seq 1 30); do \
				pgrep -x "$(APP_NAME)" >/dev/null 2>&1 || break; \
				sleep 0.1; \
			done; \
			open -g "$(APP)"; \
			printf 'reloaded %s\n' "$$(date +%H:%M:%S)"; \
		else \
			printf 'build failed %s\n' "$$(date +%H:%M:%S)"; \
			tail -n 20 build/dev-build.log; \
		fi; \
	done

verify: build test selfcheck snapshot lint

release:
	swift build -c release --arch arm64 --arch x86_64
	SIGNING_IDENTITY="$(SIGNING_IDENTITY)" ./scripts/bundle.sh "$$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$(APP_NAME)" "$(APP)"

install: release
	rm -rf "/Applications/$(APP_NAME).app"
	cp -R "$(APP)" /Applications/
	open -g "/Applications/$(APP_NAME).app"

dmg: release
	@mkdir -p build
	rm -f "$(DMG)"
	hdiutil create -volname "$(APP_NAME)" -srcfolder "$(APP)" -ov -format UDZO "$(DMG)"

clean:
	rm -rf .build build
