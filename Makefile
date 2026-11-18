APP_NAME := PerfectWhisper
PROJECT := $(APP_NAME).xcodeproj
CONFIG := Debug
DERIVED := .build
APP := $(DERIVED)/Build/Products/$(CONFIG)/$(APP_NAME).app
INSTALLED := /Applications/$(APP_NAME).app

.PHONY: all project build run install clean

all: build

project:
	xcodegen generate

build:
	xcodebuild -project $(PROJECT) -scheme $(APP_NAME) -configuration $(CONFIG) \
		-derivedDataPath $(DERIVED) build

run: build
	@pkill -x $(APP_NAME) 2>/dev/null || true
	open $(APP)

# Copies the built app to /Applications (so Spotlight and Login Items see it)
# and restarts it.
install: build
	@pkill -x $(APP_NAME) 2>/dev/null || true
	ditto $(APP) $(INSTALLED)
	open $(INSTALLED)

clean:
	rm -rf $(DERIVED)
