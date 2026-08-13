#!/bin/sh
# Copies a read-only snapshot of LifeCue sources + project.pbxproj into the
# LifeCueTests bundle so source-scanning XCTests can run on physical devices
# (where Mac SRCROOT / #filePath are not readable).
set -euo pipefail

if [ -z "${TARGET_BUILD_DIR:-}" ] || [ -z "${FULL_PRODUCT_NAME:-}" ] || [ -z "${SRCROOT:-}" ]; then
  echo "error: TARGET_BUILD_DIR, FULL_PRODUCT_NAME, and SRCROOT must be set" >&2
  exit 1
fi

DEST="${TARGET_BUILD_DIR}/${FULL_PRODUCT_NAME}/LifeCueRepoRoot"
rm -rf "${DEST}"
mkdir -p "${DEST}/LifeCue.xcodeproj" "${DEST}/LifeCue" "${DEST}/LifeCueTests"

# Swift sources only (preserve relative layout under LifeCue/ and LifeCueTests/).
rsync -a --delete \
  --include='*/' \
  --include='*.swift' \
  --exclude='*' \
  "${SRCROOT}/LifeCue/" "${DEST}/LifeCue/"

rsync -a --delete \
  --include='*/' \
  --include='*.swift' \
  --exclude='*' \
  "${SRCROOT}/LifeCueTests/" "${DEST}/LifeCueTests/"

cp "${SRCROOT}/LifeCue.xcodeproj/project.pbxproj" \
  "${DEST}/LifeCue.xcodeproj/project.pbxproj"

echo "Copied LifeCue repo snapshot for tests → ${DEST}"
