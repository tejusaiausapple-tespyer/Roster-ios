#!/bin/sh
# Xcode Cloud runs this right after cloning, before any build step, with the
# working directory set to ci_scripts/ itself — not the repo root.
set -e

cd "$CI_PRIMARY_REPOSITORY_PATH"

# 1. GoogleService-Info.plist is gitignored (real Firebase credentials, never
#    committed) — decode it from the GOOGLE_SERVICE_INFO_PLIST_BASE64 secret
#    env var set in the workflow's Environment tab. This MUST happen before
#    `xcodegen generate` below: the resource entry for this file in
#    project.yml is `optional: true`, which means XcodeGen only wires it into
#    the app's Copy Bundle Resources phase if the file already exists on disk
#    at generate time. Generate first and this silently produces a project
#    that never bundles the plist at all — no error, just a build that fails
#    later with "Could not get GOOGLE_APP_ID in Google Services file".
if [ -z "$GOOGLE_SERVICE_INFO_PLIST_BASE64" ]; then
  echo "error: GOOGLE_SERVICE_INFO_PLIST_BASE64 is not set on this workflow's Environment tab." >&2
  exit 1
fi
echo "$GOOGLE_SERVICE_INFO_PLIST_BASE64" | base64 --decode > "$CI_PRIMARY_REPOSITORY_PATH/Rosterra/Resources/GoogleService-Info.plist"

# 2. The .xcodeproj is gitignored (generated from project.yml) — Xcode Cloud's
#    clone doesn't have one, so build it here, after the plist above exists.
#    Homebrew is preinstalled on Xcode Cloud, but `brew install` normally
#    triggers an implicit `brew update` first (fetching the whole formula
#    index over the network) — that step is a well-known flaky point on
#    ephemeral CI runners (I/O errors, HTTP failures). Skip it and retry the
#    install itself a couple of times before giving up.
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
xcodegen_installed=0
for attempt in 1 2 3; do
  if brew install xcodegen; then
    xcodegen_installed=1
    break
  fi
  echo "warning: brew install xcodegen failed (attempt $attempt/3), retrying..." >&2
  sleep 5
done
if [ "$xcodegen_installed" -ne 1 ]; then
  echo "error: brew install xcodegen failed after 3 attempts." >&2
  exit 1
fi
xcodegen generate

# 3. Xcode Cloud disables automatic SPM resolution and requires a
#    Package.resolved to already exist at
#    Rosterra.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
#    before it will build. Since the .xcodeproj above is freshly generated on
#    every single run (never committed), that file never exists yet — resolve
#    explicitly here so it's in place before Xcode Cloud's own build phase.
xcodebuild -resolvePackageDependencies -project Rosterra.xcodeproj -scheme Rosterra
