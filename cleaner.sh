#!/usr/bin/env bash
set -euo pipefail

log() { printf "\033[1;35m[cleaner]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[cleaner]\033[0m %s\n" "$*"; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Utilities
exists_dir() { [[ -d "$1" ]]; }
has_content() { exists_dir "$1" && find "$1" -mindepth 1 -print -quit >/dev/null; }

# 1) Remove .flatpak-builder from root
if exists_dir "${ROOT_DIR}/.flatpak-builder"; then
  log "Removing .flatpak-builder from the project root…"
  rm -rf "${ROOT_DIR}/.flatpak-builder"
else
  warn "There is no .flatpak-builder in the project root; nothing to remove."
fi

# 2) Clear contents of target/
TARGET_DIR="${ROOT_DIR}/target"
if exists_dir "${TARGET_DIR}"; then
  if has_content "${TARGET_DIR}"; then
    log "Emptying content from target/…"
    rm -rf "${TARGET_DIR}/"*
  else
    warn "target/ is empty; nothing to clean up."
  fi
else
  warn "The target/ folder does not exist; creating base structure…"
  mkdir -p "${TARGET_DIR}"
fi

# 3) Clear contents of main/sublime-merge/files/
MERGE_FILES_DIR="${ROOT_DIR}/main/sublime-merge/files"
if exists_dir "${MERGE_FILES_DIR}"; then
  if has_content "${MERGE_FILES_DIR}"; then
    log "Emptying contents of main/sublime-merge/files/…"
    rm -rf "${MERGE_FILES_DIR}/"*
  else
    warn "main/sublime-merge/files/ is empty; nothing to clean up."
  fi
else
  warn "main/sublime-merge/files/ does not exist; creating base structure…"
  mkdir -p "${MERGE_FILES_DIR}"
fi

# 4) Clear contents of main/sublime-text/files/
TEXT_FILES_DIR="${ROOT_DIR}/main/sublime-text/files"
if exists_dir "${TEXT_FILES_DIR}"; then
  if has_content "${TEXT_FILES_DIR}"; then
    log "Emptying contents of main/sublime-text/files/…"
    rm -rf "${TEXT_FILES_DIR}/"*
  else
    warn "main/sublime-text/files/ is empty; nothing to clean up."
  fi
else
  warn "There is no main/sublime-text/files/; creating base structure…"
  mkdir -p "${TEXT_FILES_DIR}"
fi

# 5) Delete build-dir and Sublime Merge repo
MERGE_BUILD_DIR="${ROOT_DIR}/main/sublime-merge/build-dir"
MERGE_REPO_DIR="${ROOT_DIR}/main/sublime-merge/repo"

if exists_dir "${MERGE_BUILD_DIR}"; then
  log "Removing main/sublime-merge/build-dir…"
  rm -rf "${MERGE_BUILD_DIR}"
else
  warn "There is no main/sublime-merge/build-dir; nothing to delete."
fi

if exists_dir "${MERGE_REPO_DIR}"; then
  log "Removing main/sublime-merge/repo…"
  rm -rf "${MERGE_REPO_DIR}"
else
  warn "There is no main/sublime-merge/repo; nothing to delete."
fi

# 6) Delete build-dir and Sublime Text repo
TEXT_BUILD_DIR="${ROOT_DIR}/main/sublime-text/build-dir"
TEXT_REPO_DIR="${ROOT_DIR}/main/sublime-text/repo"

if exists_dir "${TEXT_BUILD_DIR}"; then
  log "Removing main/sublime-text/build-dir…"
  rm -rf "${TEXT_BUILD_DIR}"
else
  warn "There is no main/sublime-text/build-dir; nothing to delete."
fi

if exists_dir "${TEXT_REPO_DIR}"; then
  log "Removing main/sublime-text/repo…"
  rm -rf "${TEXT_REPO_DIR}"
else
  warn "There is no main/sublime-text/repo; nothing to delete."
fi

log "Project cleaned and restored to its original condition."
