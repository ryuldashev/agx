# agterm tasks — a thin front door over scripts/*.sh (the scripts stay the source of truth).
# Run `make` (or `make help`) to list targets.

INSTALL_DIR := /Applications
RELEASE_APP := build/DerivedData/Build/Products/Release/agx.app

.DEFAULT_GOAL := help
.PHONY: help prep generate build run release deploy test test-app lint dist clean gc sync-reader

help: ## list targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-9s\033[0m %s\n", $$1, $$2}'

prep: ## build libghostty + ghostty resources (one-time, idempotent)
	./scripts/setup.sh

generate: prep ## regenerate agterm.xcodeproj from project.yml
	xcodegen generate

build: generate ## debug build, no launch
	xcodebuild -project agterm.xcodeproj -scheme agterm -configuration Debug \
	  -derivedDataPath build/DerivedData build

run: ## debug build + launch (scripts/run.sh)
	./scripts/run.sh

release: ## release build, no launch (scripts/build.sh)
	./scripts/build.sh

deploy: release ## release build + swap into /Applications (refuses an unmerged branch; AGTERM_DEPLOY_PREVIEW=1 overrides)
	@./scripts/deploy-guard.sh
	rm -rf "$(INSTALL_DIR)/agx.app.new" "$(INSTALL_DIR)/agx.app.old"
	cp -R "$(RELEASE_APP)" "$(INSTALL_DIR)/agx.app.new"
	[ -d "$(INSTALL_DIR)/agx.app" ] && mv "$(INSTALL_DIR)/agx.app" "$(INSTALL_DIR)/agx.app.old" || true
	mv "$(INSTALL_DIR)/agx.app.new" "$(INSTALL_DIR)/agx.app"
	@echo "installed $(INSTALL_DIR)/agx.app (running instance keeps agx.app.old until the next deploy)"
	@./scripts/gc.sh || true

test: ## host-free agtermCore unit tests (scripts/test.sh)
	./scripts/test.sh

test-app: ## application-hosted AppKit unit tests (scripts/test-app.sh)
	./scripts/test-app.sh

lint: ## swiftlint over the tree (strict — warnings fail too)
	swiftlint lint --strict --quiet

dist: ## signed + notarized DMG — usage: make dist VERSION=x.y.z [PUBLISH=1]
	@test -n "$(VERSION)" || { echo "usage: make dist VERSION=x.y.z [PUBLISH=1]" >&2; exit 1; }
	./scripts/release.sh $(VERSION) $(if $(PUBLISH),--publish,)

sync-reader: ## copy the reader page from ~/mmee/reader/web into agterm/Resources/reader
	cp ~/mmee/reader/web/index.html ~/mmee/reader/web/app.js ~/mmee/reader/web/reader.css ~/mmee/reader/web/*.min.js agterm/Resources/reader/

clean: ## remove build artifacts (build/)
	rm -rf build

gc: ## remove merged Claude worktrees, drop build output of idle ones (scripts/gc.sh; AGTERM_GC_DAYS=3)
	./scripts/gc.sh
