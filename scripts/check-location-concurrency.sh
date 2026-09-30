#!/bin/bash
# Compile the production service against a controllable CoreLocation boundary.
# This is a standalone concurrency check, not an iOS build or hardware GPS test.
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
check_dir="$(mktemp -d /tmp/roster-location-check.XXXXXX)"
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc -emit-module -emit-library -module-name CoreLocation \
  "$script_dir/location-service-checks/CoreLocation.swift" \
  -o "$check_dir/libCoreLocation.dylib"
xcrun swiftc -I "$check_dir" -L "$check_dir" -lCoreLocation \
  "$script_dir/../Rosterra/Services/LocationService.swift" \
  "$script_dir/location-service-checks/Check.swift" -o "$check_dir/check"
DYLD_LIBRARY_PATH="$check_dir" "$check_dir/check"
