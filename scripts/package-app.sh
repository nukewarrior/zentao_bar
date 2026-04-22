#!/bin/sh

set -eu

if [ "$#" -ne 5 ]; then
  echo "usage: $0 <executable-path> <app-path> <version> <build-number> <build-configuration>" >&2
  exit 1
fi

EXECUTABLE_PATH="$1"
APP_DIR="$2"
VERSION="$3"
BUILD_NUMBER="$4"
BUILD_CONFIGURATION="$5"
APP_NAME="$(basename "${APP_DIR}" .app)"
EXECUTABLE_NAME="ZentaoBar"
BUNDLE_IDENTIFIER="com.codex.zentaobar.${BUILD_CONFIGURATION}"

if [ ! -f "${EXECUTABLE_PATH}" ]; then
  echo "error: executable not found at ${EXECUTABLE_PATH}" >&2
  exit 1
fi

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${EXECUTABLE_PATH}" "${APP_DIR}/Contents/MacOS/${EXECUTABLE_NAME}"
chmod +x "${APP_DIR}/Contents/MacOS/${EXECUTABLE_NAME}"

cat > "${APP_DIR}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleExecutable</key>
  <string>${EXECUTABLE_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_IDENTIFIER}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>ZentaoBuildConfiguration</key>
  <string>${BUILD_CONFIGURATION}</string>
  <key>ZentaoExecutableName</key>
  <string>${EXECUTABLE_NAME}</string>
</dict>
</plist>
EOF

printf 'APPL????' > "${APP_DIR}/Contents/PkgInfo"

echo "Packaged app bundle at ${APP_DIR}"
