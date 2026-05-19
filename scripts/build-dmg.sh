#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   scripts/build-dmg.sh                Build a DMG into ./dist
#   scripts/build-dmg.sh --install      Build, then install to /Applications and launch
#   scripts/build-dmg.sh --version 1.2.3   Override version string in DMG filename

cd "$(dirname "$0")/.."

APP_NAME="MemontoMori"
PROJECT="MemontoMori.xcodeproj"
SCHEME="MemontoMori"
DERIVED="./build"
RELEASE_APP="${DERIVED}/Build/Products/Release/${APP_NAME}.app"
DIST_DIR="./dist"
INSTALL_PATH="/Applications/${APP_NAME}.app"

INSTALL=0
VERSION_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) INSTALL=1; shift ;;
    --version) VERSION_OVERRIDE="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '3,8p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -n "${VERSION_OVERRIDE}" ]]; then
  VERSION="${VERSION_OVERRIDE}"
else
  VERSION="$(grep -m1 -E 'MARKETING_VERSION = ' "${PROJECT}/project.pbxproj" \
    | sed -E 's/.*MARKETING_VERSION = ([^;]+);.*/\1/' | tr -d ' ')"
  VERSION="${VERSION:-0.0.0}"
fi

echo "==> Building ${APP_NAME} ${VERSION} (Release)..."
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -derivedDataPath "${DERIVED}" \
  -quiet \
  build

if [[ ! -d "${RELEASE_APP}" ]]; then
  echo "Error: build output not found at ${RELEASE_APP}" >&2
  exit 1
fi

echo "==> Ad-hoc signing..."
codesign --force --deep --sign - "${RELEASE_APP}"

echo "==> Staging DMG contents..."
mkdir -p "${DIST_DIR}"
STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT
cp -R "${RELEASE_APP}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"

DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
rm -f "${DMG_PATH}"

echo "==> Creating ${DMG_PATH}..."
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGE}" \
  -ov \
  -fs HFS+ \
  -format UDZO \
  "${DMG_PATH}" >/dev/null

echo "==> Done: ${DMG_PATH}"

if [[ "${INSTALL}" -eq 1 ]]; then
  echo "==> Quitting existing instance (if any)..."
  osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
  sleep 1
  echo "==> Installing to ${INSTALL_PATH}..."
  rm -rf "${INSTALL_PATH}"
  cp -R "${RELEASE_APP}" "${INSTALL_PATH}"
  echo "==> Launching ${APP_NAME}..."
  open -a "${APP_NAME}"
fi
