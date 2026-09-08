SHELL := /bin/bash

APP ?= Chorus

APP_DIR = $(if $(filter Chorus,$(APP)),Hub,Providers/$(APP))
XCODEBUILD = xcodebuild -project "$(APP).xcodeproj" -scheme "$(APP)" \
	-derivedDataPath "build/$(APP)" \
	-destination 'generic/platform=macOS' -quiet

.PHONY: debug release validate bootstrap icon generate test test-hub test-kokoro-text render engine-smoke clean

# Signing is independent of Debug/Release and requires both environment values.
ifeq ($(and $(strip $(DEVELOPMENT_TEAM)),$(filter-out -,$(strip $(CODE_SIGN_IDENTITY)))),)
XCODEBUILD += CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
else
XCODEBUILD += DEVELOPMENT_TEAM="$$DEVELOPMENT_TEAM" CODE_SIGN_IDENTITY="$$CODE_SIGN_IDENTITY"
endif

debug: generate
	$(XCODEBUILD) -configuration Debug build

release: generate
	$(XCODEBUILD) -configuration Release build

validate:
	@[[ "$(APP)" =~ ^[A-Za-z][A-Za-z0-9]*$$ ]] || { echo 'APP must be an app directory name.' >&2; exit 1; }
	@test -f "$(APP_DIR)/Project.yml" || { echo 'App Project.yml not found.' >&2; exit 1; }

bootstrap: validate
	@if [[ -f "$(APP_DIR)/BuildSupport/bootstrap.sh" ]]; then bash "$(APP_DIR)/BuildSupport/bootstrap.sh"; fi

icon: validate
	@bash BuildSupport/Brand/build-icon.sh "$(APP)" "$(if $(filter Chorus,$(APP)),,$(APP))"

generate: bootstrap icon
	xcodegen generate --spec "$(APP_DIR)/Project.yml" --project-root . --project . --quiet

test-hub:
	mkdir -p build/Tests
	swiftc -swift-version 5 -strict-concurrency=complete -module-cache-path build/ModuleCache.noindex \
		Shared/*.swift Tests/Hub/main.swift -o build/Tests/chorus-hub-tests
	build/Tests/chorus-hub-tests

test-kokoro-text:
	mkdir -p build/Tests
	swiftc -swift-version 5 -strict-concurrency=complete -module-cache-path build/ModuleCache.noindex \
		Providers/Kokoro/Engine/MappedText.swift Providers/Kokoro/Engine/TextNormalizer.swift \
		Providers/Kokoro/Engine/WordTiming.swift Providers/Kokoro/Engine/SpeechAudio.swift \
		Providers/Kokoro/Engine/SSML.swift \
		Providers/Kokoro/Tests/TextContracts/main.swift -o build/Tests/kokoro-text-tests
	build/Tests/kokoro-text-tests

test: test-hub test-kokoro-text
	swift test --package-path Packages/ChorusKit --scratch-path build/Tests/ChorusKit
	find Providers Hub -type f \( -name '*.plist' -o -name '*.entitlements' \) -print0 | xargs -0 plutil -lint

render: icon
	@set -eu; mkdir -p "build/$(APP)"; \
	if [[ "$(APP)" == Chorus ]]; then \
		swiftc -swift-version 5 -D CHORUS_SNAPSHOT -module-cache-path build/ModuleCache.noindex \
			-parse-as-library Shared/*.swift Hub/*.swift Tests/Hub/RenderApp.swift -o build/Chorus/render; \
		build/Chorus/render; \
	else \
		swift run --package-path Packages/ChorusKit chorus-installer-preview \
			"$(APP_DIR)/App/Resources/Provider.json" BuildSupport/Brand/ChorusSoundwave.png "build/$(APP)"; \
	fi

engine-smoke: debug
	@set -eu; apps=("build/$(APP)/Build/Products/Debug/"*.app); \
	test "$${#apps[@]}" -eq 1 && test -d "$${apps[0]}"; \
	bash "$(APP_DIR)/BuildSupport/test-engine.sh" "$${apps[0]}"

clean: validate
	rm -rf "build/$(APP)" "dist/$(APP)" "$(APP).xcodeproj"
