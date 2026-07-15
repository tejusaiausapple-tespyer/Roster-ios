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
brew install xcodegen
xcodegen generate
