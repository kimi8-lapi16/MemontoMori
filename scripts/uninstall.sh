#!/usr/bin/env bash
set -euo pipefail

# MemontoMori アンインストーラ
#
# 既定ではアプリ本体と設定（環境設定・キャッシュ・保存状態）だけを削除し、
# 作成したメモ（サンドボックス内 Documents の .md 等）はそのまま残します。
# 再インストールすれば残したメモがそのまま読み込まれます。
#
# Usage:
#   scripts/uninstall.sh              アプリと設定を削除（メモは残す。確認プロンプトあり）
#   scripts/uninstall.sh --yes        確認なしで実行（メモは残す）
#   scripts/uninstall.sh --purge      メモとサンドボックスコンテナごと完全削除（要確認）
#   scripts/uninstall.sh --artifacts  リポジトリ内のビルド生成物 (./build, ./dist) も削除
#
# フラグは併用可能。--purge は元に戻せないため --yes を付けても最終確認を求めます。

APP_NAME="MemontoMori"
BUNDLE_ID="kimi8-lapi16.MemontoMori"
INSTALL_PATH="/Applications/${APP_NAME}.app"
CONTAINER="${HOME}/Library/Containers/${BUNDLE_ID}"

# サンドボックスコンテナ内のメモ保存先（既定では削除しない）。
MEMO_DIR="${CONTAINER}/Data/Documents/${APP_NAME}"
CONTAINER_LIB="${CONTAINER}/Data/Library"

ASSUME_YES=0
PURGE=0
CLEAN_ARTIFACTS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes|-y) ASSUME_YES=1; shift ;;
    --purge) PURGE=1; shift ;;
    --artifacts) CLEAN_ARTIFACTS=1; shift ;;
    -h|--help) sed -n '3,18p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

# メモを残さず消す設定（環境設定・キャッシュ・保存状態）。サンドボックス内と
# 非サンドボックス（過去に非サンドボックスでビルドした場合の保険）両方をカバー。
SETTINGS_PATHS=(
  "${CONTAINER_LIB}/Preferences/${BUNDLE_ID}.plist"
  "${CONTAINER_LIB}/Caches"
  "${CONTAINER_LIB}/Saved Application State"
  "${CONTAINER_LIB}/HTTPStorages"
  "${HOME}/Library/Preferences/${BUNDLE_ID}.plist"
  "${HOME}/Library/Saved Application State/${BUNDLE_ID}.savedState"
  "${HOME}/Library/Caches/${BUNDLE_ID}"
  "${HOME}/Library/HTTPStorages/${BUNDLE_ID}"
)

echo "==> ${APP_NAME} のアンインストールを開始します"
echo

echo "削除対象:"
[[ -e "${INSTALL_PATH}" ]] && echo "  - アプリ本体: ${INSTALL_PATH}"
for p in "${SETTINGS_PATHS[@]}"; do
  [[ -e "${p}" ]] && echo "  - 設定/キャッシュ: ${p}"
done
[[ "${PURGE}" -eq 1 ]] && [[ -e "${CONTAINER}" ]] && echo "  - サンドボックスコンテナ一式（メモを含む）: ${CONTAINER}"
[[ "${CLEAN_ARTIFACTS}" -eq 1 ]] && echo "  - ビルド生成物: ./build, ./dist"
echo

# メモの扱いを表示。
has_memos=0
if [[ -d "${MEMO_DIR}" ]] && [[ -n "$(ls -A "${MEMO_DIR}" 2>/dev/null)" ]]; then
  has_memos=1
fi

if [[ "${has_memos}" -eq 1 ]]; then
  if [[ "${PURGE}" -eq 1 ]]; then
    echo "⚠️  --purge が指定されています。次のメモも完全に削除されます（元に戻せません）:"
    echo "     ${MEMO_DIR}"
  else
    echo "✅ メモは削除しません。次の場所にそのまま残します:"
    echo "     ${MEMO_DIR}"
  fi
  echo
fi

# 確認プロンプト（--yes でスキップ。ただし --purge かつメモありは必ず確認）。
if [[ "${ASSUME_YES}" -eq 0 ]] || { [[ "${PURGE}" -eq 1 ]] && [[ "${has_memos}" -eq 1 ]]; }; then
  read -r -p "続行しますか? [y/N] " reply
  case "${reply}" in
    y|Y|yes|YES) ;;
    *) echo "中止しました。"; exit 0 ;;
  esac
fi

echo
echo "==> 起動中のインスタンスを終了..."
osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
# メニューバーアプリなので念のため残プロセスも落とす。
pkill -x "${APP_NAME}" >/dev/null 2>&1 || true
sleep 1

if [[ -e "${INSTALL_PATH}" ]]; then
  echo "==> アプリ本体を削除: ${INSTALL_PATH}"
  rm -rf "${INSTALL_PATH}"
fi

for p in "${SETTINGS_PATHS[@]}"; do
  if [[ -e "${p}" ]]; then
    echo "==> 削除: ${p}"
    rm -rf "${p}"
  fi
done

# 設定キャッシュを確実に無効化（サンドボックスでも保険として）。
defaults delete "${BUNDLE_ID}" >/dev/null 2>&1 || true

if [[ "${PURGE}" -eq 1 ]] && [[ -e "${CONTAINER}" ]]; then
  echo "==> サンドボックスコンテナを削除（メモを含む）: ${CONTAINER}"
  rm -rf "${CONTAINER}"
fi

if [[ "${CLEAN_ARTIFACTS}" -eq 1 ]]; then
  cd "$(dirname "$0")/.."
  echo "==> ビルド生成物を削除: ./build, ./dist"
  rm -rf ./build ./dist
fi

echo
echo "==> 完了しました。"
if [[ "${has_memos}" -eq 1 ]] && [[ "${PURGE}" -eq 0 ]]; then
  echo "    メモは削除せず残しています: ${MEMO_DIR}"
fi
