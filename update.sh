#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="MemontoMori"
PROJECT="MenuMemoApp.xcodeproj"
SCHEME="MenuMemoApp"
DERIVED="./build"
RELEASE_APP="${DERIVED}/Build/Products/Release/${APP_NAME}.app"
INSTALL_PATH="/Applications/${APP_NAME}.app"

echo "==> Building ${APP_NAME} (Release)..."
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

echo "==> Quitting existing instance (if any)..."
osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
sleep 1

echo "==> Installing to ${INSTALL_PATH}..."
rm -rf "${INSTALL_PATH}"
cp -R "${RELEASE_APP}" "${INSTALL_PATH}"

echo "==> Launching ${APP_NAME}..."
open -a "${APP_NAME}"

echo "Done."
