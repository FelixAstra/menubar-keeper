NAME    := MenuBarKeeper
VERSION := $(shell tr -d '[:space:]' < VERSION)

.DEFAULT_GOAL := help

.PHONY: help build native install run dmg icon cert clean verify

help: ## Show this help
	@echo "$(NAME) $(VERSION)"
	@echo
	@grep -E '^[a-zA-Z_-]+:.*## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

build: ## Build a universal binary (arm64 + x86_64)
	@./Scripts/build.sh

native: ## Build for this machine only (faster)
	@./Scripts/build.sh --native

install: ## Build, install into /Applications and launch
	@./Scripts/build.sh --install

run: ## Launch the installed app
	@open /Applications/$(NAME).app

dmg: ## Build and package a distributable disk image
	@./Scripts/package-dmg.sh --build

icon: ## Regenerate the .icns from the source artwork
	@python3 Scripts/make-app-icon.py

cert: ## Create the local self-signed signing certificate (once)
	@./Scripts/make-signing-cert.sh

verify: ## Report the code signature of the installed app
	@codesign --verify --strict --verbose=2 /Applications/$(NAME).app
	@codesign -dr - /Applications/$(NAME).app 2>&1 | tail -1

clean: ## Remove build output
	@rm -rf build
	@echo "Cleaned build/"
