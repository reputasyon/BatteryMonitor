#!/bin/bash
set -e

echo "Building Battery Monitor..."
swift build -c release

APP="BatteryMonitor.app"
echo "Creating $APP bundle..."

mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp .build/release/BatteryMonitor "$APP/Contents/MacOS/BatteryMonitor"

# Generate icon if not exists
if [ ! -f "$APP/Contents/Resources/AppIcon.icns" ]; then
    echo "Generating app icon..."
    swift create_icon.swift
    iconutil -c icns /tmp/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
fi

echo ""
echo "Build complete: $APP"
echo ""
echo "Install:"
echo "  cp -r $APP /Applications/"
echo ""
echo "Run:"
echo "  open /Applications/BatteryMonitor.app"
