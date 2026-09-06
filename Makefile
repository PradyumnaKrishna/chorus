# Stable public entry points; implementation details live beside the provider that owns them.
SHELL := /bin/bash
# Inert on stock macOS, which ships GNU Make 3.81; .SHELLFLAGS arrived in 3.82.
# Recipes must therefore check their own failures rather than rely on `set -e`.
.SHELLFLAGS := -eu -o pipefail -c

# ---------------------------------------------------------------------------
# Inputs. Everything below this block is derived; there is no provider table.
# ---------------------------------------------------------------------------

# A directory name under Providers/. Adding a provider means adding a directory.
PROVIDER ?= Kokoro
VERSION  ?= 0.1.0
CONFIG   ?= Release

# Signing. CHORUS_TEAM_ID selects the Apple Developer team; the app group
# container and its path on every user's Mac derive from it, so it is resolved
# once and never spelled out in the tree. Left unset for a signed build it is
# read from the keychain, which refuses to guess when several teams exist.
# Keep the identity partial: automatic signing rejects a fully qualified name.
CHORUS_TEAM_ID ?= UM9Y794Q4L
CHORUS_SIGN_IDENTITY ?= Apple Development

# CFBundleVersion must increase for every build a user could receive, which
# CFBundleShortVersionString does not: a rebuilt 0.1.0 is a distinct binary.
BUILD_NUMBER ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 1)

BUILD_DIR := build
DIST_DIR  := dist
PROJECT   := Chorus.xcodeproj

# ---------------------------------------------------------------------------
# Derived from the provider directory name.
# ---------------------------------------------------------------------------

PROVIDER_DIR := Providers/$(PROVIDER)
SCHEME       := Chorus$(PROVIDER)
APP          := $(BUILD_DIR)/Build/Products/$(CONFIG)/Chorus $(PROVIDER).app
ARCHIVE      := $(DIST_DIR)/Chorus-$(PROVIDER)-$(VERSION)

$(if $(wildcard $(PROVIDER_DIR)),,$(error No provider directory at $(PROVIDER_DIR)))

# Read by the include path in project.yml, so the generated project contains
# exactly the provider being built.
CHORUS_PROVIDER     := $(PROVIDER)
CHORUS_VERSION      := $(VERSION)
CHORUS_BUILD_NUMBER := $(BUILD_NUMBER)
export CHORUS_PROVIDER CHORUS_VERSION CHORUS_BUILD_NUMBER
export CHORUS_TEAM_ID CHORUS_SIGN_IDENTITY

# Real files, so a rebuild does not recompose the icon or rerun XcodeGen.
BOOTSTRAP_STAMP := .artifacts/$(PROVIDER)/.bootstrapped
ICON_SET        := .artifacts/$(PROVIDER)/Brand/AppIcon.xcassets/AppIcon.appiconset/Contents.json
PBXPROJ         := $(PROJECT)/project.pbxproj

# XcodeGen globs the provider's directories, so the project must be regenerated
# when a source file is added or removed -- not merely when one is edited. A
# directory's mtime changes exactly on add and remove, so depend on the tree.
PROVIDER_TREE   := $(shell find $(PROVIDER_DIR) -type d 2>/dev/null)

MODULE_CACHES := CLANG_MODULE_CACHE_PATH=/private/tmp/chorus-clang-module-cache \
                 SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/chorus-swiftpm-module-cache

XCODEBUILD = xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
             -derivedDataPath $(BUILD_DIR) -quiet \
             MARKETING_VERSION=$(VERSION) CURRENT_PROJECT_VERSION=$(BUILD_NUMBER)

.PHONY: all icon bootstrap generate build build-unsigned package test render engine-smoke clean distclean

all: build-unsigned

# ---------------------------------------------------------------------------

$(BOOTSTRAP_STAMP): $(wildcard $(PROVIDER_DIR)/BuildSupport/*.sh) \
                    $(wildcard $(PROVIDER_DIR)/BuildSupport/Dependencies/*.sh) \
                    $(wildcard $(PROVIDER_DIR)/Resources/*)
	$(PROVIDER_DIR)/BuildSupport/bootstrap.sh
	mkdir -p $(dir $@)
	touch $@

$(ICON_SET): BuildSupport/Brand/main.swift BuildSupport/Brand/ChorusSoundwave.png \
             BuildSupport/Brand/AppIconContents.json
	BuildSupport/Brand/build-icon.sh "$(PROVIDER)" "$(PROVIDER)"

$(PBXPROJ): project.yml BuildSupport/XcodeGen/Base.yml $(PROVIDER_DIR)/Project.yml \
            $(PROVIDER_TREE) $(ICON_SET) $(BOOTSTRAP_STAMP)
	xcodegen generate --quiet

bootstrap: $(BOOTSTRAP_STAMP)
icon: $(ICON_SET)
generate: $(PBXPROJ)

# The team is resolved here rather than at generate time and passed straight to
# xcodebuild, so DEVELOPMENT_TEAM -- and the CHORUS_APP_GROUP derived from it --
# resolve at build time. The generated project therefore names no team at all.
build: $(PBXPROJ)
	@team="$$(BuildSupport/team-id.sh)" || exit 1; \
	$(XCODEBUILD) DEVELOPMENT_TEAM="$$team" CODE_SIGN_IDENTITY="$(CHORUS_SIGN_IDENTITY)" build

build-unsigned: $(PBXPROJ)
	$(XCODEBUILD) CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM= build

# Distribution is intentionally based on the signed build target.
package: build
	mkdir -p $(DIST_DIR)
	ditto -c -k --keepParent "$(APP)" "$(ARCHIVE).zip"
	shasum -a 256 "$(ARCHIVE).zip" > "$(ARCHIVE).sha256"

test:
	env $(MODULE_CACHES) \
		swift test --package-path Packages/ChorusKit --scratch-path /private/tmp/chorus-kit-build
	find Providers -type f \( -name '*.plist' -o -name '*.entitlements' \) -print0 \
		| xargs -0 plutil -lint

render: build-unsigned
	env $(MODULE_CACHES) \
		swift run --package-path Packages/ChorusKit chorus-installer-preview \
			$(PROVIDER_DIR)/App/Resources/Provider.json \
			BuildSupport/Brand/ChorusSoundwave.png \
			$(BUILD_DIR)

engine-smoke: build-unsigned
	$(PROVIDER_DIR)/BuildSupport/test-engine.sh

clean:
	rm -rf $(BUILD_DIR) $(DIST_DIR) $(PROJECT)

distclean: clean
	rm -rf .artifacts .build
