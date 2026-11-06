#!/bin/sh
# Xcode Cloud: generate Goodsky.xcodeproj from project.yml before the build starts.
set -eu
brew install xcodegen
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate
