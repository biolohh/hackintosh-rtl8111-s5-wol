# 4. Build and install

Two ways: the **prebuilt kext** from the [Releases](../../../releases) page, or **build it yourself** (needs Xcode).
Either way, keep a backup of your current kext and know how to put it back (see "Roll back" below) before you
restart.

Tested with: macOS 26.2 (25C56), Xcode 26.4 (17E192), MacKernelSDK `3f75008`, OpenCore 1.0.8, upstream `a3dad34`.

## A. Prebuilt kext

1. Download `RealtekRTL8111-*-wol-s5.zip` from the latest release and compare its SHA-256 with the release notes:
   `shasum -a 256 RealtekRTL8111-*-wol-s5.zip`.
2. Unzip it. Check that it is the patched one:
   `grep -a "WoL from S5 armed" RealtekRTL8111.kext/Contents/MacOS/RealtekRTL8111` (must print a match).
3. Continue with "Install" below.

The prebuilt kext carries version **3.0.22** in its Info.plist: that is a local build number (upstream build 3.0.4 +
this patch), not an upstream release. It is the build that was tested, with the debug symbol table removed
(`strip -S`, so it does not contain the build machine's paths; the code section is identical) and signed ad hoc
(`codesign -s -`), like a local Xcode build.

## B. Build from source

```bash
git clone https://github.com/Mieze/RTL8111_driver_for_OS_X.git
cd RTL8111_driver_for_OS_X
git checkout a3dad34                # or stay on master if the patch still applies
git clone https://github.com/acidanthera/MacKernelSDK.git
curl -LO https://raw.githubusercontent.com/biolohh/hackintosh-rtl8111-s5-wol/main/patch/RealtekRTL8111-wol-s5.patch
git apply --check RealtekRTL8111-wol-s5.patch && git apply RealtekRTL8111-wol-s5.patch
```

`git apply` may warn about trailing whitespace: the driver's own style keeps the indentation on empty lines, and the
patch follows it. The warnings are harmless.

Then either use the script from this repository (it builds, checks the binary, and with no `--no-install` also
installs with a backup):

```bash
bash /path/to/hackintosh-rtl8111-s5-wol/tools/build-install.sh . --no-install
```

or build by hand:

```bash
mkdir -p build/Release
cp MacKernelSDK/Library/x86_64/libkmod.a build/Release/      # the project links it from the build folder
xcodebuild -project RealtekRTL8111.xcodeproj -configuration Release -arch x86_64 build SYMROOT="$PWD/build"
grep -a "WoL from S5 armed" build/Release/RealtekRTL8111.kext/Contents/MacOS/RealtekRTL8111
```

The build prints a few static analyzer warnings ("Value stored to … is never read"); they come from upstream code.

To give your build its own version number (so `kextstat` shows which one is loaded), pass `--version 3.0.22` (or
any `X.Y.Z`) to the script, or edit `CURRENT_PROJECT_VERSION` in `RealtekRTL8111.xcodeproj/project.pbxproj`.

## Install

1. Mount the EFI partition that OpenCore boots from: `diskutil list` (look for the EFI partition of the boot disk),
   then `sudo diskutil mount diskXsY`. It appears at `/Volumes/EFI`.
2. Back up the current kext **outside** `Kexts` (OpenCore loads only what `config.plist` lists, so a folder in `OC`
   is ignored):
   ```bash
   sudo cp -R /Volumes/EFI/EFI/OC/Kexts/RealtekRTL8111.kext /Volumes/EFI/EFI/OC/RealtekRTL8111.kext.backup-$(date +%Y%m%d)
   ```
3. Replace it:
   ```bash
   sudo rm -rf /Volumes/EFI/EFI/OC/Kexts/RealtekRTL8111.kext
   sudo cp -R build/Release/RealtekRTL8111.kext /Volumes/EFI/EFI/OC/Kexts/
   sync
   cmp build/Release/RealtekRTL8111.kext/Contents/MacOS/RealtekRTL8111 /Volumes/EFI/EFI/OC/Kexts/RealtekRTL8111.kext/Contents/MacOS/RealtekRTL8111
   ```
   `tools/build-install.sh <checkout>` does steps 2–3 for you.
4. `config.plist` needs no change if `RealtekRTL8111.kext` is already in Kernel → Add (BundlePath
   `RealtekRTL8111.kext`, ExecutablePath `Contents/MacOS/RealtekRTL8111`, PlistPath `Contents/Info.plist`).
5. Restart: `sudo shutdown -r now`. Then `kextstat | grep -i realtek` shows the loaded version, and the network
   should work as before.

The restart that loads the new kext is still handled by the old one. That does not matter: the new kext re-arms WoL
at its first shutdown or restart, whatever state it started in.

## Roll back

Put the backup back and restart:

```bash
sudo rm -rf /Volumes/EFI/EFI/OC/Kexts/RealtekRTL8111.kext
sudo cp -R /Volumes/EFI/EFI/OC/RealtekRTL8111.kext.backup-<date> /Volumes/EFI/EFI/OC/Kexts/RealtekRTL8111.kext
sync && sudo shutdown -r now
```

If macOS does not boot at all, the EFI partition can also be edited from Windows, Linux or the OpenCore shell.

## Later upstream releases

The patch replaces the kext with a modified build. A new upstream release would overwrite it: re-apply the patch to
the new source (`git apply --3way` helps if the context moved) or check whether upstream fixed it
([upstream issue #98](https://github.com/Mieze/RTL8111_driver_for_OS_X/issues/98)).
