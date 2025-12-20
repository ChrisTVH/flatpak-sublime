#!/usr/bin/env bash
set -euo pipefail

# ========= Config =========
TEXT_URL="https://download.sublimetext.com/sublime_text_build_4200_x64.tar.xz"
MERGE_URL="https://download.sublimetext.com/sublime_merge_build_2121_x64.tar.xz"

# Optional checksums (leave empty to skip verification)
TEXT_SHA256="36f69c551ad18ee46002be4d9c523fe545d93b67fea67beea731e724044b469f"
MERGE_SHA256="c96aeb9437b90bdd0431055da443569c651171511dc4994591a9447cfa73b734"

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

# ========= Logging & errors =========
log() { printf "\033[1;36m[builder]\033[0m %s\n" "$*"; }
err() { printf "\033[1;31m[error]\033[0m %s\n" "$*" >&2; }
trap 'err "Failed at: ${BASH_COMMAND:-unknown}. Check the previous step."' ERR

require_cmd() {
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || { err "Missing required command: $c"; exit 1; }
  done
}

# Add sha256sum because it's used in verification
require_cmd curl tar rsync flatpak flatpak-builder find sha256sum gzip

check_files_ready() {
  local dir="$1" bin="$2"
  [[ -x "${dir}/${bin}" ]]
}

verify_checksum_if_set() {
  local file="$1" expected="$2"
  if [[ -n "${expected}" ]]; then
    echo "${expected}  ${file}" | sha256sum -c - || { err "Checksum verification failed for ${file}"; exit 1; }
  fi
}

# Extract a deterministic topdir from an unpacked tarball root
sync_extracted_contents() {
  local src_root="$1" dst_dir="$2" app_name="$3"

  local topdir_name
  topdir_name="$(find "$src_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort | head -n1)"
  [[ -n "${topdir_name:-}" ]] || { err "No extracted root directory found for ${app_name} in ${src_root}"; exit 1; }
  local topdir="${src_root}/${topdir_name}"

  # Remove upstream .desktop if present
  find "$topdir" -type f -name "${app_name}.desktop" -exec rm -f {} +

  # Copy ONLY inner contents (not the root folder), normalize basic perms
  rsync -a --delete --chmod=u+rwX,go+rX "${topdir}/" "${dst_dir}/"

  # Ensure main binary is executable
  [[ -x "${dst_dir}/${app_name}" ]] || { chmod +x "${dst_dir}/${app_name}" || { err "Missing exec bit on ${app_name}"; exit 1; }; }
}

download_and_prepare() {
  local url="$1" out_tar="$2" build_dir="$3" files_dir="$4" app_name="$5" checksum="$6"

  log "Downloading ${app_name}…"
  curl -fL "${url}" -o "${out_tar}"
  verify_checksum_if_set "${out_tar}" "${checksum}"

  log "Extracting ${app_name}…"
  mkdir -p "${build_dir}"
  tar -xJf "${out_tar}" -C "${build_dir}"

  log "Syncing ${app_name} contents…"
  sync_extracted_contents "${build_dir}" "${files_dir}" "${app_name}"
}

# ========= AppStream metainfo generation =========
# Derive build number (version) from URL pattern "...build_####..."
extract_build_version() {
  local url="$1"
  local build
  build="$(printf "%s" "$url" | grep -oE 'build_[0-9]+' | grep -oE '[0-9]+' )" || true
  printf "%s" "${build:-unknown}"
}

write_metainfo() {
  local files_dir="$1" app_id="$2" desktop_id="$3" name="$4" summary="$5" homepage="$6" version="$7" categories_csv="$8" binary="$9" description_para="${10}"

  local outdir="${files_dir}/share/app-info/xmls"
  local outfile="${outdir}/${app_id}.metainfo.xml"
  local today
  today="$(date +%F)"

  mkdir -p "${outdir}"

  cat > "${outfile}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<component type="desktop-application">
  <id>${app_id}</id>
  <name>${name}</name>
  <summary>${summary}</summary>
  <description>
    <p>${description_para}</p>
  </description>
  <launchable type="desktop-id">${desktop_id}</launchable>
  <metadata_license>CC0-1.0</metadata_license>
  <project_license>Proprietary</project_license>
  <url type="homepage">${homepage}</url>
  <provides>
    <binary>${binary}</binary>
  </provides>
  <categories>
$(printf "%s" "${categories_csv}" | tr ',' '\n' | sed 's/^/    <category>/' | sed 's/$/<\/category>/')
  </categories>
  <releases>
    <release version="${version}" date="${today}"/>
  </releases>
</component>
EOF

  log "Metainfo written: ${outfile}"
}

generate_appstream() {
  # Sublime Text
  local text_version
  text_version="$(extract_build_version "${TEXT_URL}")"
  write_metainfo \
    "${TEXT_FILES_DIR}" \
    "${TEXT_APPID}" \
    "com.sublimetext.sublime_text.desktop" \
    "Sublime Text" \
    "Sophisticated text editor for code, markup and prose" \
    "https://www.sublimetext.com/" \
    "${text_version}" \
    "Development,Utility,TextEditor" \
    "sublime_text" \
    "Sublime Text is a fast, powerful editor with a rich ecosystem of packages."

  # Sublime Merge
  local merge_version
  merge_version="$(extract_build_version "${MERGE_URL}")"
  write_metainfo \
    "${MERGE_FILES_DIR}" \
    "${MERGE_APPID}" \
    "com.sublimemerge.sublime_merge.desktop" \
    "Sublime Merge" \
    "Sublime Merge is a Git client, from the makers of Sublime Text" \
    "https://www.sublimemerge.com/" \
    "${merge_version}" \
    "Development,RevisionControl" \
    "sublime_merge" \
    "Sublime Merge is a fast, intuitive Git client from the creators of Sublime Text."
}

# ========= AppStream sanity & alias (.xml.gz) =========
assert_metainfo_present() {
  local files_dir="$1" app_id="$2"
  local path="${files_dir}/share/app-info/xmls/${app_id}.metainfo.xml"
  [[ -f "$path" ]] || { err "Missing AppStream metainfo: ${path}"; exit 1; }
  log "AppStream present: ${path}"
}

# Create the compressed alias expected by exporter: app-id.xml.gz (from app-id.metainfo.xml)
make_appstream_gz_alias() {
  local files_dir="$1" app_id="$2"
  local src="${files_dir}/share/app-info/xmls/${app_id}.metainfo.xml"
  local dst="${files_dir}/share/app-info/xmls/${app_id}.xml.gz"
  [[ -f "$src" ]] || { err "Cannot compress: source not found ${src}"; exit 1; }
  gzip -9c "$src" > "$dst" || { err "Failed to create ${dst}"; exit 1; }
  log "AppStream gz alias created: ${dst}"
}

# Optionally validate XML if xmllint is available (non-fatal if missing)
validate_metainfo_xml() {
  local files_dir="$1" app_id="$2"
  local path="${files_dir}/share/app-info/xmls/${app_id}.metainfo.xml"
  if command -v xmllint >/dev/null 2>&1; then
    xmllint --noout "$path" || { err "Invalid XML in ${path}"; exit 1; }
    log "XML validated: ${path}"
  else
    log "xmllint not found; skipping XML validation for ${path}"
  fi
}

# ========= Clean & prep =========
log "Preparing structure and preliminary cleaning…"
mkdir -p "${TARGET_DIR}"
rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"

mkdir -p "${TEXT_FILES_DIR}" "${MERGE_FILES_DIR}"

# ========= Download & Extract if needed =========
if check_files_ready "${TEXT_FILES_DIR}" "sublime_text"; then
  log "Sublime Text already present in files/, skipping download and extraction."
else
  download_and_prepare \
    "${TEXT_URL}" \
    "${TMP_DIR}/sublime_text.tar.xz" \
    "${TMP_DIR}/sublime_text_build" \
    "${TEXT_FILES_DIR}" \
    "sublime_text" \
    "${TEXT_SHA256}"
fi

if check_files_ready "${MERGE_FILES_DIR}" "sublime_merge"; then
  log "Sublime Merge already present in files/, skipping download and extraction."
else
  download_and_prepare \
    "${MERGE_URL}" \
    "${TMP_DIR}/sublime_merge.tar.xz" \
    "${TMP_DIR}/sublime_merge_build" \
    "${MERGE_FILES_DIR}" \
    "sublime_merge" \
    "${MERGE_SHA256}"
fi

# ========= Generate AppStream metainfo =========
log "Generating AppStream metainfo…"
generate_appstream

# Sanity: ensure metainfo exists and is valid
assert_metainfo_present "${TEXT_FILES_DIR}" "${TEXT_APPID}"
assert_metainfo_present "${MERGE_FILES_DIR}" "${MERGE_APPID}"
validate_metainfo_xml "${TEXT_FILES_DIR}" "${TEXT_APPID}"
validate_metainfo_xml "${MERGE_FILES_DIR}" "${MERGE_APPID}"

# Create the .xml.gz aliases expected by flatpak export
make_appstream_gz_alias "${TEXT_FILES_DIR}" "${TEXT_APPID}"
make_appstream_gz_alias "${MERGE_FILES_DIR}" "${MERGE_APPID}"

# ========= Build (force-clean) =========
log "Building Flatpak Sublime Text…"
flatpak-builder \
  --repo="${TEXT_REPO_DIR}" \
  --force-clean \
  --disable-rofiles-fuse \
  "${TEXT_BUILD_DIR}" \
  "${TEXT_MANIFEST}"

log "Building Flatpak Sublime Merge…"
flatpak-builder \
  --repo="${MERGE_REPO_DIR}" \
  --force-clean \
  --disable-rofiles-fuse \
  "${MERGE_BUILD_DIR}" \
  "${MERGE_MANIFEST}"

# ========= Bundle export =========
log "Exporting bundles to target/…"
flatpak build-bundle "${TEXT_REPO_DIR}" "${TARGET_DIR}/sublime-text.flatpak" "${TEXT_APPID}"
flatpak build-bundle "${MERGE_REPO_DIR}" "${TARGET_DIR}/sublime-merge.flatpak" "${MERGE_APPID}"

# ========= Final clean (optional) =========
rm -rf "${TMP_DIR}"

log "Building complete. Bundles ready in: ${TARGET_DIR}"
