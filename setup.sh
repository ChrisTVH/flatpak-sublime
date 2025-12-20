#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${ROOT_DIR}/target"

TEXT_BUNDLE="${TARGET_DIR}/sublime-text.flatpak"
MERGE_BUNDLE="${TARGET_DIR}/sublime-merge.flatpak"

TEXT_APPID="com.sublimetext.sublime_text"
MERGE_APPID="com.sublimemerge.sublime_merge"

# Install behavior: if true, install/update only if the bundle has a different commit
INSTALL_ONLY_IF_NEWER=true

log()  { printf "\033[1;36m[setup]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[setup]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[setup]\033[0m %s\n" "$*" >&2; }

check_bundle_exists() { [[ -f "$1" ]]; }
is_installed() { flatpak list --app --columns=application | grep -qx "$1"; }
ensure_script() {
  local path="$1" name="$2"
  [[ -x "$path" ]] || err "The executable $name was not found in: $path"
}

# -------- Version/commit helpers --------
get_installed_commit() {
  local appid="$1"
  flatpak info --show-commit "$appid" 2>/dev/null || true
}

get_bundle_commit() {
  local bundle="$1"
  flatpak bundle-info "$bundle" --show-commit 2>/dev/null || true
}

same_version_as_installed() {
  local bundle="$1" appid="$2"
  local installed_commit bundle_commit
  installed_commit="$(get_installed_commit "$appid")"
  bundle_commit="$(get_bundle_commit "$bundle")"
  [[ -z "$bundle_commit" ]] && { warn "Bundle has no commit; will treat as different."; return 1; }
  [[ -n "$installed_commit" && "$installed_commit" == "$bundle_commit" ]]
}


# -------- Construction --------
build_packages_normal() {
  if check_bundle_exists "$TEXT_BUNDLE" && check_bundle_exists "$MERGE_BUNDLE"; then
    log "The packages are already built. Returning to the main menu…"
    return
  fi
  ensure_script "${ROOT_DIR}/builder.sh" "builder.sh"
  log "Running builder.sh (normal build)…"
  "${ROOT_DIR}/builder.sh"
}

build_packages_force() {
  ensure_script "${ROOT_DIR}/builder.sh" "builder.sh"
  log "Forcing building anyway…"
  "${ROOT_DIR}/builder.sh"
}

build_menu() {
  echo "=== Build packages ==="
  echo "1) Normal build (respects existing bundles)"
  echo "2) Force build (always rebuilds both)"
  echo "3) Back"
  read -rp "Option: " opt
  case "$opt" in
    1) build_packages_normal ;;
    2) build_packages_force ;;
    *) return ;;
  esac
}

# -------- Installation --------
install_one() {
  local bundle="$1" appid="$2" name="$3"

  if ! check_bundle_exists "$bundle"; then
    warn "The $name bundle does not exist in target/. Build first."
    return
  fi

  if is_installed "$appid"; then
    if same_version_as_installed "$bundle" "$appid"; then
      if [[ "$INSTALL_ONLY_IF_NEWER" == true ]]; then
        log "$name is already at the same version (commit match). Skipping."
        return
      fi
      read -rp "$name is already at the same version (commit match). Reinstall anyway? (y/n): " ans
      if [[ "$ans" =~ ^[yY]$ ]]; then
        if ! flatpak install --user --noninteractive --reinstall --bundle "$bundle"; then
          err "Failed to reinstall $name. Returning to menu."
          return
        fi
        log "$name reinstalled (same commit)."
      else
        log "Skipping reinstall of $name (same version)."
      fi
      return
    fi

    # Installed but differs
    if [[ "$INSTALL_ONLY_IF_NEWER" == true ]]; then
      if ! flatpak install --user --noninteractive --reinstall --bundle "$bundle"; then
        err "Failed to update $name. Returning to menu."
        return
      fi
      log "$name updated from the bundle (newer commit)."
    else
      read -rp "$name is installed but differs from the bundle. Update from bundle? (y/n): " ans
      if [[ "$ans" =~ ^[yY]$ ]]; then
        if ! flatpak install --user --noninteractive --reinstall --bundle "$bundle"; then
          err "Failed to update $name. Returning to menu."
          return
        fi
        log "$name updated from the bundle."
      else
        log "Omitting update of $name."
      fi
    fi
  else
    # Not installed: install from local bundle
    if ! flatpak install --user --noninteractive --bundle "$bundle"; then
      err "Failed to install $name. Returning to menu."
      return
    fi
    log "$name installed."
  fi
}



toggle_install_only_if_newer() {
  if [[ "$INSTALL_ONLY_IF_NEWER" == true ]]; then
    INSTALL_ONLY_IF_NEWER=false
    log "Install behavior: Only install newer = OFF (interactive updates)"
  else
    INSTALL_ONLY_IF_NEWER=true
    log "Install behavior: Only install newer = ON (skip if same commit, auto-update if different)"
  fi
}

install_packages() {
  while true; do
    echo "=== Install packages ==="
    echo "1) Sublime Text"
    echo "2) Sublime Merge"
    echo "3) Both"
    echo "4) Toggle 'Only install newer versions' (current: ${INSTALL_ONLY_IF_NEWER})"
    echo "5) Back"
    read -rp "Option: " opt
    case "$opt" in
      1) install_one "$TEXT_BUNDLE" "$TEXT_APPID" "Sublime Text" ;;
      2) install_one "$MERGE_BUNDLE" "$MERGE_APPID" "Sublime Merge" ;;
      3)
        install_one "$TEXT_BUNDLE" "$TEXT_APPID" "Sublime Text"
        install_one "$MERGE_BUNDLE" "$MERGE_APPID" "Sublime Merge"
        ;;
      4) toggle_install_only_if_newer ;;
      5) break ;;
      *) echo "Invalid option" ;;
    esac
  done
}

# -------- Uninstallation --------
uninstall_one() {
  local appid="$1" name="$2"
  if is_installed "$appid"; then
    read -rp "Uninstall $name? (y/n): " ans
    if [[ "$ans" =~ ^[yY]$ ]]; then
      read -rp "Also delete user data for $name? (y/n): " del
      if [[ "$del" =~ ^[yY]$ ]]; then
        flatpak uninstall --user --delete-data --noninteractive "$appid"
        log "$name uninstalled and data deleted."
      else
        flatpak uninstall --user --noninteractive "$appid"
        log "$name uninstalled (data retained)."
      fi
    else
      log "Uninstallation of $name canceled."
    fi
  else
    warn "$name is not installed."
  fi
}

uninstall_packages() {
  echo "=== Uninstall packages ==="
  echo "1) Sublime Text"
  echo "2) Sublime Merge"
  echo "3) Both"
  echo "4) Back"
  read -rp "Option: " opt
  case "$opt" in
    1) uninstall_one "$TEXT_APPID" "Sublime Text" ;;
    2) uninstall_one "$MERGE_APPID" "Sublime Merge" ;;
    3)
      uninstall_one "$TEXT_APPID" "Sublime Text"
      uninstall_one "$MERGE_APPID" "Sublime Merge"
      ;;
    *) return ;;
  esac
}

# -------- Cleaning --------
clean_project() {
  ensure_script "${ROOT_DIR}/cleaner.sh" "cleaner.sh"
  log "Running cleaner.sh…"
  "${ROOT_DIR}/cleaner.sh"
}

# ========= Main menu =========
while true; do
  echo "=== Setup CLI ==="
  echo "1) Build packages"
  echo "2) Install packages"
  echo "3) Uninstall packages"
  echo "4) Clean up project"
  echo "5) Exit"
  read -rp "Option: " choice
  case "$choice" in
    1) build_menu ;;
    2) install_packages ;;
    3) uninstall_packages ;;
    4) clean_project ;;
    5) exit 0 ;;
    *) echo "Invalid option" ;;
  esac
done
