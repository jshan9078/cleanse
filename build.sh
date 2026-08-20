#!/bin/zsh
# Builds Cleanse.app from main.swift. Run: ./build.sh
set -e
cd "$(dirname "$0")"

APP="Cleanse.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -parse-as-library -o "$APP/Contents/MacOS/Cleanse" main.swift
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Built $APP — launch with: open $APP"
