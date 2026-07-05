#!/usr/bin/env zsh
set -euo pipefail

swift build -c release

app=".build/release/MicStreamer.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp -f ".build/release/MicStreamer" "$app/Contents/MacOS/MicStreamer"

cat >"$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>MicStreamer</string>
  <key>CFBundleIdentifier</key>
  <string>app.micstreamer.MicStreamer</string>
  <key>CFBundleName</key>
  <string>MicStreamer</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.2</string>
  <key>NSAudioCaptureUsageDescription</key>
  <string>MicStreamer captures system audio so other people can hear what you are playing.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>MicStreamer uses your microphone only when you enable microphone mixing.</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

plutil -lint "$app/Contents/Info.plist"
codesign --force --sign - "$app"
echo "$app"
