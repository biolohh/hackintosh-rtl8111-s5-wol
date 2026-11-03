#!/bin/bash
# Build Mieze's RealtekRTL8111.kext with the S5 WoL patch and install it into OpenCore.
#
#   bash tools/build-install.sh <RTL8111_driver_for_OS_X checkout> [--no-install] [--version X.Y.Z]
#
# The checkout must have the patch applied (git apply patch/RealtekRTL8111-wol-s5.patch) and
# MacKernelSDK cloned into it (git clone https://github.com/acidanthera/MacKernelSDK).
# --version changes CURRENT_PROJECT_VERSION in the Xcode project (the kext's CFBundleVersion).
# Installing needs the EFI partition mounted (EFI=/Volumes/EFI/EFI/OC by default; diskutil list,
# then sudo diskutil mount diskXsY). The installed kext is copied first to
# EFI/OC/RealtekRTL8111.kext.backup-<old version>-<time>, outside Kexts, so OpenCore ignores it.
# Roll back: put that folder back as EFI/OC/Kexts/RealtekRTL8111.kext and restart.
set -euo pipefail

SRC=""; INSTALL=1; VERSION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --no-install) INSTALL=0 ;;
    --version) VERSION="${2:?--version needs a value}"; shift ;;
    *) SRC="$1" ;;
  esac
  shift
done
[ -n "$SRC" ] || { echo "usage: build-install.sh <RTL8111_driver_for_OS_X checkout> [--no-install] [--version X.Y.Z]"; exit 2; }
cd "$SRC"
[ -f RealtekRTL8111.xcodeproj/project.pbxproj ] || { echo "Not an RTL8111_driver_for_OS_X checkout: $SRC"; exit 1; }
[ -f MacKernelSDK/Library/x86_64/libkmod.a ] || { echo "MacKernelSDK is missing: git clone https://github.com/acidanthera/MacKernelSDK"; exit 1; }
grep -q wolArmedOnDisable RealtekRTL8111/RealtekRTL8111.hpp || { echo "The patch is not applied: git apply <this repo>/patch/RealtekRTL8111-wol-s5.patch"; exit 1; }

if [ -n "$VERSION" ]; then
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Bad version: $VERSION"; exit 1; }
  sed -i "" -E "s/CURRENT_PROJECT_VERSION = [0-9.]+;/CURRENT_PROJECT_VERSION = $VERSION;/" RealtekRTL8111.xcodeproj/project.pbxproj
fi

BUILD="$PWD/build"
OUT="$BUILD/Release/RealtekRTL8111.kext"
echo "== Build"
mkdir -p "$BUILD/Release"
# the project links libkmod.a from the build folder
cp MacKernelSDK/Library/x86_64/libkmod.a "$BUILD/Release/"
set +e
xcodebuild -project RealtekRTL8111.xcodeproj -configuration Release -arch x86_64 build \
  SYMROOT="$BUILD" > "$BUILD/build.log" 2>&1
rc=$?
set -e
grep -E ": (warning|error): |BUILD (SUCCEEDED|FAILED)" "$BUILD/build.log" || true
[ $rc -eq 0 ] || { echo "Build failed, see $BUILD/build.log"; exit 1; }
grep -aq "WoL from S5 armed" "$OUT/Contents/MacOS/RealtekRTL8111" || { echo "The patch is not in the binary"; exit 1; }
NEW=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$OUT/Contents/Info.plist")
echo "Built: $OUT (version $NEW)"
[ $INSTALL -eq 1 ] || exit 0

EFI="${EFI:-/Volumes/EFI/EFI/OC}"
KEXT="$EFI/Kexts/RealtekRTL8111.kext"
[ -d "$KEXT" ] || { echo "No $KEXT: mount the EFI partition (diskutil list; sudo diskutil mount diskXsY) or set EFI=..."; exit 1; }
OLD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$KEXT/Contents/Info.plist")
BAK="$EFI/RealtekRTL8111.kext.backup-$OLD-$(date +%Y%m%d-%H%M%S)"
echo "== Install ($OLD -> $NEW)"
sudo cp -R "$KEXT" "$BAK"
sudo rm -rf "$KEXT"
sudo cp -R "$OUT" "$KEXT"
sync
cmp "$OUT/Contents/MacOS/RealtekRTL8111" "$KEXT/Contents/MacOS/RealtekRTL8111"
echo "Backup: $BAK"
echo "Done. Restart (sudo shutdown -r now), then check: kextstat | grep -i realtek"
