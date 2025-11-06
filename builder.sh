#!/usr/bin/env bash
set -euo pipefail

# ========= Config =========
TEXT_URL="https://download.sublimetext.com/sublime_text_build_4200_x64.tar.xz"
MERGE_URL="https://download.sublimetext.com/sublime_merge_build_2112_x64.tar.xz"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${ROOT_DIR}/target"
TMP_DIR="${TARGET_DIR}/.tmp"

TEXT_MAIN_DIR="${ROOT_DIR}/main/sublime-text"
MERGE_MAIN_DIR="${ROOT_DIR}/main/sublime-merge"

TEXT_FILES_DIR="${TEXT_MAIN_DIR}/files"
MERGE_FILES_DIR="${MERGE_MAIN_DIR}/files"

TEXT_BUILD_DIR="${TEXT_MAIN_DIR}/build-dir"
MERGE_BUILD_DIR="${MERGE_MAIN_DIR}/build-dir"

TEXT_REPO_DIR="${TEXT_MAIN_DIR}/repo"
MERGE_REPO_DIR="${MERGE_MAIN_DIR}/repo"

TEXT_MANIFEST="${TEXT_MAIN_DIR}/sublime-text.json"
MERGE_MANIFEST="${MERGE_MAIN_DIR}/sublime-merge.json"

TEXT_APPID="com.sublimetext.sublime_text"
MERGE_APPID="com.sublimemerge.sublime_merge"

check_files_ready() {
  local dir="$1" bin="$2"
  [[ -x "${dir}/${bin}" ]]
}

log() { printf "\033[1;36m[builder]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[error]\033[0m %s\n" "$*" >&2; }
trap 'err "Error during build. Check the last step executed."' ERR

require_cmd() {
  for c in "$@"; do command -v "$c" >/dev/null 2>&1 || err "Missing required command: $c"; done
}
require_cmd curl tar rsync flatpak flatpak-builder find

sync_extracted_contents() {
  local src_root="$1" dst_dir="$2" app_name="$3"

  local topdir
  topdir="$(find "$src_root" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  if [[ -z "${topdir:-}" ]]; then
    err "No extracted root directory found for ${app_name} in ${src_root}"
  fi

  # Remove .desktop upstream if it exists
  find "$topdir" -type f -name "${app_name}.desktop" -exec rm -f {} +

  # Copy ONLY the internal content (not the root folder)
  rsync -a --delete "${topdir}/" "${dst_dir}/"
}

# ========= Clean & prep =========
log "Preparing structure and preliminary cleaning..."
mkdir -p "${TARGET_DIR}"
rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"

mkdir -p "${TEXT_FILES_DIR}" "${MERGE_FILES_DIR}"

# ========= Download & Extract if needed =========
if check_files_ready "${TEXT_FILES_DIR}" "sublime_text"; then
  log "Sublime Text already present in files/, skipping download and extraction."
else
  log "Downloading and preparing Sublime Text..."
  curl -fL "${TEXT_URL}" -o "${TMP_DIR}/sublime_text.tar.xz"
  mkdir -p "${TMP_DIR}/sublime_text_build"
  tar -xJf "${TMP_DIR}/sublime_text.tar.xz" -C "${TMP_DIR}/sublime_text_build"
  sync_extracted_contents "${TMP_DIR}/sublime_text_build" "${TEXT_FILES_DIR}" "sublime_text"
fi

if check_files_ready "${MERGE_FILES_DIR}" "sublime_merge"; then
  log "Sublime Merge already present in files/, skipping download and extraction."
else
  log "Downloading and preparing Sublime Merge..."
  curl -fL "${MERGE_URL}" -o "${TMP_DIR}/sublime_merge.tar.xz"
  mkdir -p "${TMP_DIR}/sublime_merge_build"
  tar -xJf "${TMP_DIR}/sublime_merge.tar.xz" -C "${TMP_DIR}/sublime_merge_build"
  sync_extracted_contents "${TMP_DIR}/sublime_merge_build" "${MERGE_FILES_DIR}" "sublime_merge"
fi

# ========= Build (force-clean) =========
log "Building Flatpak Sublime Text..."
flatpak-builder \
  --repo="${TEXT_REPO_DIR}" \
  --force-clean \
  --disable-rofiles-fuse \
  "${TEXT_BUILD_DIR}" \
  "${TEXT_MANIFEST}"

log "Building Flatpak Sublime Merge..."
flatpak-builder \
  --repo="${MERGE_REPO_DIR}" \
  --force-clean \
  --disable-rofiles-fuse \
  "${MERGE_BUILD_DIR}" \
  "${MERGE_MANIFEST}"

# ========= Bundle export =========
log "Exporting bundles to target/..."
flatpak build-bundle "${TEXT_REPO_DIR}" "${TARGET_DIR}/sublime-text.flatpak" "${TEXT_APPID}"
flatpak build-bundle "${MERGE_REPO_DIR}" "${TARGET_DIR}/sublime-merge.flatpak" "${MERGE_APPID}"

# ========= Final clean (optional) =========
rm -rf "${TMP_DIR}"

log "Building complete. Bundles ready in: ${TARGET_DIR}"
