SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

APP_NAME := Foil
BUNDLE_ID := com.neonwatty.Foil
SCHEME := Foil
CONFIG := Debug
LOCAL_SIGN_IDENTITY := Foil Local Code Signing
LOCAL_SIGN_KEYCHAIN := $(HOME)/Library/Keychains/foil-codesign.keychain-db
LOCAL_SIGN_KEYCHAIN_PASSWORD ?= foil-local-codesign
DEFAULT_SIGN_IDENTITY := $(shell security find-identity -p codesigning "$(LOCAL_SIGN_KEYCHAIN)" 2>/dev/null | grep -q '"$(LOCAL_SIGN_IDENTITY)"' && echo "$(LOCAL_SIGN_IDENTITY)" || echo "-")
SIGN_IDENTITY ?= $(DEFAULT_SIGN_IDENTITY)
DEVELOPMENT_TEAM ?=

ifeq ($(SIGN_IDENTITY),-)
SIGNING_FLAGS := CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=NO
else ifeq ($(SIGN_IDENTITY),$(LOCAL_SIGN_IDENTITY))
SIGNING_FLAGS := CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM) CODE_SIGN_STYLE=Manual ENABLE_HARDENED_RUNTIME=NO
else
SIGNING_FLAGS := CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM) CODE_SIGN_STYLE=Manual
endif

BUILD_DIR := $(shell xcodebuild -scheme $(SCHEME) -configuration $(CONFIG) -destination 'platform=macOS' -showBuildSettings 2>/dev/null | grep -m1 BUILT_PRODUCTS_DIR | awk '{print $$NF}')
APP_PATH := $(BUILD_DIR)/$(APP_NAME).app
APP_MARKETING_VERSION := $(shell sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' Foil.xcodeproj/project.pbxproj | head -1)
APP_BUILD_VERSION := $(shell sed -n 's/.*CURRENT_PROJECT_VERSION = \([^;]*\);.*/\1/p' Foil.xcodeproj/project.pbxproj | head -1)
LIVE_GROQ_TEST_CLASS := FoilTests/LiveGroqIntegrationTests
DEFAULT_UNIT_TEST_FILTERS := -only-testing:FoilTests -skip-testing:$(LIVE_GROQ_TEST_CLASS)

.PHONY: setup-local-signing setup-release-secrets prepare-release enable-xctest-developer-mode build build-warnings-as-errors unlock-local-signing-keychain run start stop restart install uninstall clean test test-ui test-ui-diagnostics test-provider-qa test-provider-qa-live test-live-groq test-live-transcription-e2e-cli test-local-transcription-e2e test-microphone-live test-cross-app test-app-smoke test-paste-real test-queued-paste-compatibility test-queued-paste-compatibility-browser test-queued-paste-compatibility-cross-app qa-paste prepare-local-permissions-qa prepare-local-permissions-qa-check guide-installed-permissions-qa test-local-permissions-qa-script test-cleanup-quality qa qa-ci qa-local

setup-local-signing:
	LOCAL_SIGN_KEYCHAIN_PASSWORD="$(LOCAL_SIGN_KEYCHAIN_PASSWORD)" scripts/setup-local-signing.sh

setup-release-secrets:
	scripts/set-release-secrets.sh

prepare-release:
	@if [ -z "$(VERSION)" ] || [ -z "$(BUILD)" ] || [ -z "$(NOTES)" ]; then \
		echo "Usage: make prepare-release VERSION=1.12.1 BUILD=33 NOTES=/path/to/release-notes.md" >&2; \
		exit 2; \
	fi
	scripts/prepare-release.sh "$(VERSION)" "$(BUILD)" "$(NOTES)"

enable-xctest-developer-mode:
	sudo DevToolsSecurity -enable
	@if ! id -Gn "$$USER" | tr ' ' '\n' | grep -qx '_developer'; then \
		sudo dseditgroup -o edit -a "$$USER" -t user _developer; \
	fi

unlock-local-signing-keychain:
	@if [ "$(SIGN_IDENTITY)" = "$(LOCAL_SIGN_IDENTITY)" ] && [ -f "$(LOCAL_SIGN_KEYCHAIN)" ]; then \
		security unlock-keychain -p "$(LOCAL_SIGN_KEYCHAIN_PASSWORD)" "$(LOCAL_SIGN_KEYCHAIN)"; \
	fi

build: unlock-local-signing-keychain
	@if [ -d "$(APP_PATH)" ]; then find "$(APP_PATH)" -name '*.cstemp*' -delete; fi
	@tmp=$$(mktemp); \
	xcodebuild -scheme $(SCHEME) -configuration $(CONFIG) -destination 'platform=macOS' $(SIGNING_FLAGS) build >"$$tmp" 2>&1; \
	status=$$?; tail -3 "$$tmp"; \
	if ! grep -q '\*\* BUILD SUCCEEDED \*\*' "$$tmp"; then status=1; fi; \
	rm -f "$$tmp"; exit $$status

build-warnings-as-errors:
	@tmp=$$(mktemp); \
	xcodebuild build -scheme $(SCHEME) -configuration $(CONFIG) -destination 'platform=macOS' OTHER_SWIFT_FLAGS='-warnings-as-errors' >"$$tmp" 2>&1; \
	status=$$?; tail -3 "$$tmp"; \
	if ! grep -q '\*\* BUILD SUCCEEDED \*\*' "$$tmp"; then status=1; fi; \
	rm -f "$$tmp"; exit $$status

run:
	@identity=$$(security find-identity -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application: Mean Weasel LLC (B3A6AN2HA4)\)".*/\1/p' | head -1); \
	if [ -z "$$identity" ]; then \
		$(MAKE) setup-local-signing; \
		identity="$(LOCAL_SIGN_IDENTITY)"; \
	fi; \
	$(MAKE) install SIGN_IDENTITY="$$identity" DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)"
	open /Applications/$(APP_NAME).app

start:
	@open /Applications/$(APP_NAME).app 2>/dev/null || open $(APP_PATH) 2>/dev/null || echo "Run 'make install' or 'make build' first"

stop:
	@pkill -x $(APP_NAME) 2>/dev/null && echo "Stopped" || echo "Not running"

restart: stop
	@sleep 0.5
	@open /Applications/$(APP_NAME).app 2>/dev/null || open $(APP_PATH)

install: build
	-@pkill -x $(APP_NAME) 2>/dev/null; sleep 0.5
	rm -rf /Applications/$(APP_NAME).app
	cp -R $(APP_PATH) /Applications/$(APP_NAME).app
	@echo "Installed to /Applications/$(APP_NAME).app"

uninstall:
	-@pkill -x $(APP_NAME) 2>/dev/null
	rm -rf /Applications/$(APP_NAME).app
	@echo "Removed /Applications/$(APP_NAME).app"

test:
	@tmp=$$(mktemp); \
	RUN_LIVE_GROQ_TESTS=0 xcodebuild test -scheme $(SCHEME) -configuration $(CONFIG) -destination 'platform=macOS' $(DEFAULT_UNIT_TEST_FILTERS) >"$$tmp" 2>&1; \
	status=$$?; tail -5 "$$tmp"; \
	if ! grep -q '\*\* TEST SUCCEEDED \*\*' "$$tmp"; then status=1; fi; \
	rm -f "$$tmp"; exit $$status

test-ui:
	@echo "WARNING: make test-ui runs macOS XCUITests in the active desktop session."
	@echo "It can take focus, open windows, and drive UI interactions. Run it on a separate machine or when this Mac is idle."
	@sleep 3
	-@pkill -x $(APP_NAME) 2>/dev/null; sleep 0.5
	@tmp=$$(mktemp); \
	xcodebuild test -scheme $(SCHEME) -configuration $(CONFIG) -destination 'platform=macOS' -only-testing:FoilUITests >"$$tmp" 2>&1; \
	status=$$?; tail -5 "$$tmp"; \
	if ! grep -q '\*\* TEST SUCCEEDED \*\*' "$$tmp"; then status=1; fi; \
	rm -f "$$tmp"; exit $$status

test-ui-diagnostics:
	@echo "WARNING: make test-ui-diagnostics runs the full macOS XCUITest suite."
	@echo "It is intended for idle desktops or dedicated CI runners and preserves diagnostics on failure."
	FULL_UI_TIMEOUT_SECONDS="$${FULL_UI_TIMEOUT_SECONDS:-1200}" \
	RESULT_BUNDLE_PATH="$${RESULT_BUNDLE_PATH:-FullUITestResults.xcresult}" \
	LOG_PATH="$${LOG_PATH:-full-ui-diagnostics.log}" \
	SCHEME="$(SCHEME)" CONFIG="$(CONFIG)" scripts/run-full-ui-diagnostics.sh

test-provider-qa:
	@tmp=$$(mktemp); \
	xcodebuild test -scheme $(SCHEME) -configuration $(CONFIG) -destination 'platform=macOS' \
		-parallel-testing-enabled NO -maximum-concurrent-test-device-destinations 1 -enableCodeCoverage NO \
		-only-testing:FoilUITests/FoilUITests/testProviderQADefaultsToGroqPreset \
		-only-testing:FoilUITests/FoilUITests/testProviderQALocalWhisperPresetShowsExpectedSettings \
		-only-testing:FoilUITests/FoilUITests/testProviderQALocalWhisperCanBeSelectedFromDefaultSettings \
		-only-testing:FoilUITests/FoilUITests/testProviderQALocalWhisperSetupHelperShowsModelCommands \
		-only-testing:FoilUITests/FoilUITests/testProviderQALocalWhisperSelectionPersistsAcrossRelaunch \
		-only-testing:FoilUITests/FoilUITests/testProviderQAInvalidCustomBaseURLShowsValidationStatus \
		-only-testing:FoilUITests/FoilUITests/testProviderQACustomProviderPersistsAcrossRelaunch >"$$tmp" 2>&1; \
	status=$$?; tail -8 "$$tmp"; \
	if ! grep -q '\*\* TEST SUCCEEDED \*\*' "$$tmp"; then status=1; fi; \
	rm -f "$$tmp"; exit $$status

test-provider-qa-live:
	SCHEME="$(SCHEME)" CONFIG="$(CONFIG)" scripts/run-live-groq-provider-qa-xcuitest.sh

test-live-groq:
	@if [[ -z "$${GROQ_API_KEY:-}" ]]; then \
		echo "ERROR: GROQ_API_KEY is required for make test-live-groq"; \
		exit 2; \
	fi; \
	old_run=$$(launchctl getenv RUN_LIVE_GROQ_TESTS || true); \
	old_key=$$(launchctl getenv GROQ_API_KEY || true); \
	restore_live_groq_env() { \
		if [[ -n "$$old_run" ]]; then launchctl setenv RUN_LIVE_GROQ_TESTS "$$old_run"; else launchctl unsetenv RUN_LIVE_GROQ_TESTS; fi; \
		if [[ -n "$$old_key" ]]; then launchctl setenv GROQ_API_KEY "$$old_key"; else launchctl unsetenv GROQ_API_KEY; fi; \
	}; \
	trap restore_live_groq_env EXIT; \
	launchctl setenv RUN_LIVE_GROQ_TESTS 1; \
	launchctl setenv GROQ_API_KEY "$$GROQ_API_KEY"; \
	RUN_LIVE_GROQ_TESTS=1 xcodebuild test -scheme $(SCHEME) -configuration $(CONFIG) -destination 'platform=macOS' -only-testing:$(LIVE_GROQ_TEST_CLASS)

test-live-transcription-e2e-cli:
	CONFIG="$(CONFIG)" scripts/run-live-transcription-e2e-cli.sh

test-local-transcription-e2e:
	SCHEME="$(SCHEME)" CONFIG="$(CONFIG)" scripts/run-local-transcription-e2e-xcuitest.sh

test-microphone-live:
	RUN_LIVE_MICROPHONE_TESTS=1 SCHEME="$(SCHEME)" CONFIG="$(CONFIG)" scripts/run-live-microphone-qa.sh

test-cross-app:
	swift tests/test_async_paste.swift
	swift tests/test_skylight_paste.swift
	swift tests/test_cross_app_async_paste.swift

test-app-smoke:
	swift tests/test_app_mock_async_paste.swift

test-paste-real: install
	swift tests/test_app_mock_async_paste.swift

test-queued-paste-compatibility:
	scripts/run-queued-paste-compatibility-smoke.sh

test-queued-paste-compatibility-browser:
	scripts/run-queued-paste-compatibility-smoke.sh --include-browser

test-queued-paste-compatibility-cross-app:
	scripts/run-queued-paste-compatibility-smoke.sh --include-browser --include-cross-app

qa-paste: test-paste-real

prepare-local-permissions-qa:
	scripts/prepare-local-permissions-qa.sh

prepare-local-permissions-qa-check:
	scripts/prepare-local-permissions-qa.sh --check

guide-installed-permissions-qa:
	EXPECTED_VERSION="$(APP_MARKETING_VERSION)" EXPECTED_BUILD="$(APP_BUILD_VERSION)" scripts/prepare-local-permissions-qa.sh --guide-installed

test-local-permissions-qa-script:
	scripts/test-prepare-local-permissions-qa.sh

test-cleanup-quality:
	swift tests/test_cleanup_quality.swift

qa-ci:
	@echo "=== Warnings-as-errors build ==="
	$(MAKE) build-warnings-as-errors
	@echo ""
	@echo "=== Unit tests ==="
	$(MAKE) test
	@echo ""
	@echo "=== UI feedback tests ==="
	$(MAKE) test-ui

qa-local: install
	@echo "=== Installed app smoke test ==="
	$(MAKE) test-paste-real
	@echo ""
	@echo "=== Desktop paste integration tests ==="
	$(MAKE) test-cross-app
	@echo ""
	@echo "Run 'make test-cleanup-quality' separately when a local Groq API key is configured."

qa:
	@echo "=== Unit tests ==="
	RUN_LIVE_GROQ_TESTS=0 xcodebuild test -scheme $(SCHEME) -configuration $(CONFIG) -destination 'platform=macOS' -skip-testing:$(LIVE_GROQ_TEST_CLASS) 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)"
	@echo ""
	@echo "=== Async paste integration test ==="
	-@pkill -x $(APP_NAME) 2>/dev/null; pkill -x Foil 2>/dev/null; sleep 0.5
	swift tests/test_async_paste.swift
	@echo ""
	@echo "=== SkyLight background paste test ==="
	swift tests/test_skylight_paste.swift

clean:
	xcodebuild -scheme $(SCHEME) clean 2>&1 | tail -3
