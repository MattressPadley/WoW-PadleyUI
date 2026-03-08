#!/bin/bash
#
# PadleyUI Release Script
# Creates a GitHub release with a WowUp-compatible addon zip.
#
# Usage: ./release.sh [version]
#   version  - e.g. 0.0.2 (optional, reads from TOC if omitted)
#
# Requires: git, gh (GitHub CLI), zip

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
git ls-files --cached | grep -v -E '^\.(git|claude)' | grep -v -E '^(release\.sh|CLAUDE\.md)' | while read -r f; do
    dir=$(dirname "$f")
    mkdir -p "${RELEASE_DIR}/${ADDON_NAME}/${dir}"
    cp "$f" "${RELEASE_DIR}/${ADDON_NAME}/${f}"
done

# Create the zip from the release dir so the top-level folder is PadleyUI/
(cd "$RELEASE_DIR" && zip -r "../${RELEASE_DIR}/${ZIP_NAME}" "${ADDON_NAME}")

echo "==> Created ${RELEASE_DIR}/${ZIP_NAME}"

# --- Tag and push ---
git tag -a "$TAG" -m "Release ${TAG}"
git push origin main --tags

echo "==> Pushed tag ${TAG}"

# --- Create GitHub release ---
gh release create "$TAG" \
    "${RELEASE_DIR}/${ZIP_NAME}" \
    --title "${ADDON_NAME} ${TAG}" \
    --generate-notes

echo ""
echo "==> Done! Release URL:"
gh release view "$TAG" --json url -q '.url'
