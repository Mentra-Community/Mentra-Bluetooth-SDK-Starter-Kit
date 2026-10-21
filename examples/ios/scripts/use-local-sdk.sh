#!/usr/bin/env bash
# Points MentraExample.xcodeproj at the local SDK package in
# MENTRA_BLUETOOTH_SDK_PACKAGE_PATH instead of the published Swift package.
# This edits the committed project; `git checkout MentraExample.xcodeproj` reverts it.
set -euo pipefail

# Defaults to the MentraOS checkout next to this repository (../mentraos).
sdk_path="${MENTRA_BLUETOOTH_SDK_PACKAGE_PATH:-$(dirname "$0")/../../../../mentraos/mobile/modules/bluetooth-sdk}"
sdk_path="$(cd "$sdk_path" && pwd)"
test -f "$sdk_path/Package.swift"

project="$(dirname "$0")/../MentraExample.xcodeproj/project.pbxproj"
SDK_PATH="$sdk_path" perl -0pi -e '
  s|isa = XCRemoteSwiftPackageReference;\s*repositoryURL = "[^"]*mentra-bluetooth-sdk-ios[^"]*";\s*requirement = \{[^}]*\};|isa = XCLocalSwiftPackageReference;\n\t\t\trelativePath = "$ENV{SDK_PATH}";|
  or die "$ARGV does not reference the published Bluetooth SDK package; git checkout it first.\n";
' "$project"
echo "MentraExample now builds MentraBluetoothSDK from $sdk_path"
