APP := build/f2.8.app

.PHONY: build native debug test run diagnose dmg install clean

# Universal (Apple silicon + Intel).
build:
	@scripts/build.sh

# This Mac's architecture only — quicker while iterating.
native:
	@scripts/build.sh --native

debug:
	@scripts/build.sh --debug

# build/f2.8.dmg, ready to share.
dmg: build
	@scripts/make-dmg.sh

test: build

run: build
	open "$(APP)"

# Checks the blur engine and prints how focus resolves right now, then exits.
diagnose: build
	"$(APP)/Contents/MacOS/F28" --diagnose

# Per-user Applications folder: needs no admin rights. Override with
# `make install INSTALL_DIR=/Applications` if you can write there.
INSTALL_DIR ?= $(HOME)/Applications

install: build
	@osascript -e 'quit app id "app.f28.focus"' 2>/dev/null || true
	mkdir -p "$(INSTALL_DIR)"
	ditto "$(APP)" "$(INSTALL_DIR)/f2.8.app"
	open "$(INSTALL_DIR)/f2.8.app"

clean:
	rm -rf build
