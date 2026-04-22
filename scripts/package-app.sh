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
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
ICON_SOURCE="${PROJECT_ROOT}/assets/zentao_icon.png"
ICON_NAME="AppIcon"
ICONSET_DIR="${APP_DIR}/Contents/Resources/${ICON_NAME}.iconset"
ICON_PATH="${APP_DIR}/Contents/Resources/${ICON_NAME}.icns"
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

if [ -f "${ICON_SOURCE}" ]; then
  mkdir -p "${ICONSET_DIR}"

  generate_icon() {
    SIZE="$1"
    OUTPUT_NAME="$2"
    sips -s format png -z "${SIZE}" "${SIZE}" "${ICON_SOURCE}" --out "${ICONSET_DIR}/${OUTPUT_NAME}" >/dev/null
  }

  generate_icon 16 icon_16x16.png
  generate_icon 32 icon_16x16@2x.png
  generate_icon 32 icon_32x32.png
  generate_icon 64 icon_32x32@2x.png
  generate_icon 128 icon_128x128.png
  generate_icon 256 icon_128x128@2x.png
  generate_icon 256 icon_256x256.png
  generate_icon 512 icon_256x256@2x.png
  generate_icon 512 icon_512x512.png
  generate_icon 1024 icon_512x512@2x.png

  iconutil -c icns "${ICONSET_DIR}" -o "${ICON_PATH}"
  rm -rf "${ICONSET_DIR}"
fi

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
  <key>CFBundleIconFile</key>
  <string>${ICON_NAME}</string>
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
