#!/bin/bash
#
# PadleyUI Release Script
# Creates a GitHub release with a WowUp-compatible addon zip.
#
# Usage: ./release.sh [version]
#   version  - e.g. 0.0.2 (optional, reads from TOC if omitted)
#
# Requires: git, gh (GitHub CLI), powershell

set -euo pipefail

ADDON_NAME="PadleyUI"
TOC_FILE="${ADDON_NAME}.toc"
RELEASE_DIR="release"

# --- Determine version ---
if [ -n "${1:-}" ]; then
    VERSION="$1"
    # Update the TOC file with the new version
    sed -i "s/^## Version: .*/## Version: ${VERSION}/" "$TOC_FILE"
    echo "Updated ${TOC_FILE} version to ${VERSION}"
else
    VERSION=$(sed -n 's/^## Version: //p' "$TOC_FILE" | tr -d '\r')
    if [ -z "$VERSION" ]; then
        echo "Error: could not read version from ${TOC_FILE}" >&2
        exit 1
    fi
fi

TAG="v${VERSION}"
ZIP_NAME="${ADDON_NAME}-${VERSION}.zip"

echo "==> Releasing ${ADDON_NAME} ${TAG}"

# --- Ensure working tree is clean ---
if [ -n "$(git status --porcelain -- ':!release/')" ]; then
    echo ""
    echo "Uncommitted changes detected. Commit them before releasing."
    git status --short -- ':!release/'
    exit 1
fi

# --- Check tag doesn't already exist ---
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Error: tag ${TAG} already exists" >&2
    exit 1
fi

# --- Build zip ---
echo "==> Building ${ZIP_NAME}"
rm -rf "$RELEASE_DIR"
mkdir -p "${RELEASE_DIR}/${ADDON_NAME}"

# Copy addon files (everything tracked by git, excluding dev files)
git ls-files --cached | grep -v -E '^\.(git|claude)' | grep -v -E '^(release\.sh|build-zip\.ps1|CLAUDE\.md)' | while read -r f; do
    dir=$(dirname "$f")
    mkdir -p "${RELEASE_DIR}/${ADDON_NAME}/${dir}"
    cp "$f" "${RELEASE_DIR}/${ADDON_NAME}/${f}"
done

# Create the zip with forward-slash paths (ZIP spec requirement)
ABS_RELEASE=$(cd "$RELEASE_DIR" && pwd -W 2>/dev/null || pwd)
powershell -NoProfile -ExecutionPolicy Bypass -File build-zip.ps1 \
    -SourceDir "$ABS_RELEASE" -AddonName "$ADDON_NAME" -ZipPath "${ABS_RELEASE}\\${ZIP_NAME}"

# Generate release.json for WowUp
INTERFACE=$(sed -n 's/^## Interface: //p' "$TOC_FILE" | tr -d '\r')
cat > "${RELEASE_DIR}/release.json" <<RJSON
{
  "releases": [
    {
      "name": "${ADDON_NAME} ${TAG}",
      "version": "${VERSION}",
      "filename": "${ZIP_NAME}",
      "nolib": false,
      "metadata": [
        {
          "flavor": "mainline",
          "interface": ${INTERFACE}
        }
      ]
    }
  ]
}
RJSON

echo "==> Created ${RELEASE_DIR}/${ZIP_NAME}"
echo "==> Created ${RELEASE_DIR}/release.json"

# --- Tag and push ---
git tag -a "$TAG" -m "Release ${TAG}"
git push origin main --tags

echo "==> Pushed tag ${TAG}"

# --- Create GitHub release ---
gh release create "$TAG" \
    "${RELEASE_DIR}/${ZIP_NAME}" \
    "${RELEASE_DIR}/release.json" \
    --title "${ADDON_NAME} ${TAG}" \
    --generate-notes

echo ""
echo "==> Done! Release URL:"
gh release view "$TAG" --json url -q '.url'
