#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
if [[ "$#" -gt 0 ]]; then
  shift
fi
APP_ARGS=("$@")
APP_NAME="SimpleLime"
BUNDLE_ID="com.whitehappypony.SimpleLime"
MIN_SYSTEM_VERSION="14.0"
APP_VERSION="0.5.0"
APP_BUILD="1"
APP_DESCRIPTION="Scratch-first text editor for temporary notes, Markdown, and code."

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON="$ROOT_DIR/Resources/AppIcon.icns"
APP_CLI="$ROOT_DIR/Resources/simplelime"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/clang-module-cache}"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

running_app_pids() {
  pgrep -x "$APP_NAME" 2>/dev/null || true
}

wait_for_app_exit() {
  local timeout_seconds="$1"
  local max_attempts=$((timeout_seconds * 5))
  local attempts=0

  while [[ -n "$(running_app_pids)" && "$attempts" -lt "$max_attempts" ]]; do
    sleep 0.2
    attempts=$((attempts + 1))
  done

  [[ -z "$(running_app_pids)" ]]
}

stop_app() {
  local pids
  pids="$(running_app_pids)"
  [[ -z "$pids" ]] && return 0

  echo "Stopping existing $APP_NAME process before launching the fresh build..."
  pkill -TERM -x "$APP_NAME" >/dev/null 2>&1 || true
  if wait_for_app_exit 20; then
    return 0
  fi

  echo "Existing $APP_NAME process did not exit after SIGTERM; forcing it to quit..."
  pkill -KILL -x "$APP_NAME" >/dev/null 2>&1 || true
  if wait_for_app_exit 10; then
    return 0
  fi

  echo "Could not stop existing $APP_NAME process: $(running_app_pids)" >&2
  return 1
}

stage_app_bundle() {
  swift build --disable-sandbox
  BUILD_BINARY="$(swift build --disable-sandbox --show-bin-path)/$APP_NAME"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_RESOURCES"
  cp "$BUILD_BINARY" "$APP_BINARY"
  chmod +x "$APP_BINARY"

  if [[ -f "$APP_ICON" ]]; then
    cp "$APP_ICON" "$APP_RESOURCES/AppIcon.icns"
  fi

  if [[ -f "$APP_CLI" ]]; then
    cp "$APP_CLI" "$APP_RESOURCES/simplelime"
    chmod +x "$APP_RESOURCES/simplelime"
  fi

  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>
      <string>Document</string>
      <key>CFBundleTypeRole</key>
      <string>Editor</string>
      <key>LSHandlerRank</key>
      <string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.text</string>
        <string>public.plain-text</string>
        <string>public.source-code</string>
        <string>public.json</string>
        <string>public.xml</string>
        <string>public.shell-script</string>
        <string>public.comma-separated-values-text</string>
        <string>public.tab-separated-values-text</string>
        <string>public.image</string>
        <string>com.adobe.pdf</string>
        <string>public.data</string>
        <string>net.daringfireball.markdown</string>
      </array>
    </dict>
  </array>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>SimpleLime Collaboration Link</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>simplelime</string>
      </array>
    </dict>
  </array>
  <key>CFBundleGetInfoString</key>
  <string>$APP_NAME $APP_VERSION - $APP_DESCRIPTION</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>LSSupportsOpeningDocumentsInPlace</key>
  <true/>
  <key>NSBonjourServices</key>
  <array>
    <string>_simplelime._tcp</string>
  </array>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSLocalNetworkUsageDescription</key>
  <string>SimpleLime uses the local network to find trusted devices and exchange notes between your Macs.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>SimpleLime uses the microphone when you start Voice Scribe to append dictated transcripts to your notes.</string>
  <key>NSAudioCaptureUsageDescription</key>
  <string>SimpleLime captures system audio when you choose system audio or meeting audio in Voice Scribe.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>SimpleLime uses speech recognition when you start Voice Scribe to transcribe your microphone input.</string>
  <key>NSHumanReadableCopyright</key>
  <string>$APP_DESCRIPTION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
}

open_app() {
  if [[ "${#APP_ARGS[@]}" -eq 0 ]]; then
    /usr/bin/open -n "$APP_BUNDLE"
  else
    /usr/bin/open -n "$APP_BUNDLE" --args "${APP_ARGS[@]}"
  fi
}

warn_running_app() {
  local pids
  pids="$(running_app_pids)"
  if [[ -n "$pids" ]]; then
    echo "Warning: $APP_NAME is already running. This mode only builds $APP_BUNDLE."
    echo "Running PID(s): ${pids//$'\n'/, }"
    echo "Run '$0 run' or relaunch the app manually to use the fresh build."
  fi
}

case "$MODE" in
  --build-only|build-only|stage)
    stage_app_bundle
    echo "Built $APP_BUNDLE"
    warn_running_app
    ;;
  run)
    stop_app
    stage_app_bundle
    open_app
    ;;
  --debug|debug)
    stop_app
    stage_app_bundle
    lldb -- "$APP_BINARY" "${APP_ARGS[@]}"
    ;;
  --logs|logs)
    stop_app
    stage_app_bundle
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    stop_app
    stage_app_bundle
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    stop_app
    stage_app_bundle
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--build-only|--debug|--logs|--telemetry|--verify] [--safe-mode] [file ...]" >&2
    exit 2
    ;;
esac
