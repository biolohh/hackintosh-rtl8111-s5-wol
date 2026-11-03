# Hackintosh: Wake-on-LAN from shutdown breaks after sleep (Realtek RTL8111/8168)

On a Hackintosh with a Realtek RTL8111/8168 NIC and [Mieze's RealtekRTL8111.kext](https://github.com/Mieze/RTL8111_driver_for_OS_X),
Wake-on-LAN from shutdown (S5) stops working as soon as macOS has slept once, and restarts do not bring it back:
only a manual power-on does. This repository explains why (traced and confirmed against the xnu source), and fixes it
with a small driver patch (+75/−3 lines), a prebuilt kext, test results, and optional notes for BIOS settings,
Windows dual boot and Home Assistant.

**Status:** fixed and tested on one machine (ASUS PRIME B550M-K, RTL8111H, macOS 26.2, OpenCore 1.0.8). Reports from
other boards are welcome. Upstream report: [Mieze/RTL8111_driver_for_OS_X#98](https://github.com/Mieze/RTL8111_driver_for_OS_X/issues/98).

## Fix it with your AI agent (copy and paste)

If you use an AI coding agent on your Hackintosh (Claude Code, Codex, Cursor, …), copy the whole block below into
it. It tells the agent where everything is and what it must ask you first. You only need to do the physical part:
look at the LAN port LEDs, and send the magic packet from another device (phone app, router, or `tools/wol.py` on
another computer).

```text
Help me fix Wake-on-LAN from shutdown (S5) on my Hackintosh. The fix is a small patch for Mieze's
RealtekRTL8111.kext, documented in https://github.com/biolohh/hackintosh-rtl8111-s5-wol
Before you do anything, read these files from that repository (raw files:
https://raw.githubusercontent.com/biolohh/hackintosh-rtl8111-s5-wol/main/<path>):
README.md, docs/01-symptoms.md, docs/04-build-and-install.md, docs/05-testing.md, docs/06-bios-and-hardware.md.

Rules:
- Explain each step before you do it and show me the output.
- Ask me before every restart, shutdown or sleep, before writing to the EFI partition, and before any sudo command.
- Before replacing the kext, back up the current one outside EFI/OC/Kexts and tell me the backup path. Never delete it.
- Do not change config.plist or BIOS settings yourself. If something needs to change there, tell me what and why.
- If anything differs from what the docs expect (another driver, another NIC, the patch does not apply), stop and ask.
- You run on this Mac, so every restart or shutdown ends your session. Keep your progress in ~/wol-fix-progress.md,
  and before each restart tell me what comes next, so I can paste this prompt again and say "continue".

Steps:
1. Check that the fix applies to this machine:
   - sw_vers; kextstat | grep -i realtek   (expect com.insanelymac.RealtekRTL8111)
   - the NIC is a Realtek RTL8111/8168: ioreg -r -c RTL8111 -l -w0 | grep -E '"(model|IOModel|Chipset)"'
   - find and mount the EFI partition that OpenCore boots from (diskutil list; sudo diskutil mount diskXsY), then
     look at /Volumes/EFI/EFI/OC/Kexts/RealtekRTL8111.kext and its CFBundleVersion.
2. Ask me whether my symptom matches docs/01-symptoms.md (WoL from shutdown works after a manual power-on, but not
   after the Mac has slept). If WoL from shutdown never works, go through the BIOS settings in
   docs/06-bios-and-hardware.md with me first: the patch cannot fix that case.
3. Get the patched kext, either
   a) prebuilt: the zip from the latest release on https://github.com/biolohh/hackintosh-rtl8111-s5-wol/releases,
      and check its SHA-256 against the release notes; or
   b) build it (needs Xcode): "B. Build from source" in docs/04-build-and-install.md (clone upstream, check out
      a3dad34, clone MacKernelSDK into it, git apply --check and git apply the patch, then
      tools/build-install.sh <checkout> --no-install).
   Check: grep -a "WoL from S5 armed" RealtekRTL8111.kext/Contents/MacOS/RealtekRTL8111 must print a match.
4. After my OK: back up and install it as in "Install" in docs/04-build-and-install.md (or tools/build-install.sh
   without --no-install), and cmp the installed binary with the new one.
5. After my OK: restart. Then check kextstat | grep -i realtek and that the network works.
6. Go through the tests in docs/05-testing.md with me. Tell me my MAC address (ifconfig) so I can send the magic
   packet from another device. The important one is test 2: sleep, wake, shut down, WoL.
7. If test 2 fails: tell me how to roll back ("Roll back" in docs/04-build-and-install.md) and collect what
   docs/09-diagnostics.md lists for a bug report.
Finish with a short summary: what was installed, where the backup is, and the test results.
```

## The problem in one minute

| | WoL from shutdown |
| :--- | :--- |
| manual power-on → … → shutdown | ✅ works |
| manual power-on → **sleep once** → wake → shutdown | ❌ nothing happens, LAN LEDs dark |
| … then any number of restarts → shutdown | ❌ still broken |
| manual power-on again | ✅ fixed until the next sleep |

Why: after every wake macOS switches WoL off in the driver (`setWakeOnMagicPacket(false)`), and at shutdown the
kernel takes the network interface down (`if_down_all()`) **before** the driver's `systemWillShutdown()` runs. The
driver powers the NIC's PHY and PLL down without WoL, and by the time `systemWillShutdown()` could arm WoL, the
interface is already down and nothing happens. A bit left behind in the NIC makes the next boot start with WoL off
too, so restarts carry the broken state along. Details: [docs/02-root-cause.md](docs/02-root-cause.md).

## The fix in one minute

In `systemWillShutdown()`, for a power off and a restart: arm WoL, and if the kernel already took the interface down
without WoL, power the PLL and the PHY up again and power them down in WoL mode. Plus three small fixes: the driver is
always WoL capable on these chips, `PME_Status` is cleared correctly (write 1), and a stale `PME_Status` is cleared
before S5. Details: [docs/03-the-patch.md](docs/03-the-patch.md).

## Install (manual)

- **Prebuilt:** download the zip from [Releases](../../releases), check the SHA-256, put `RealtekRTL8111.kext` into
  `EFI/OC/Kexts` (keep a backup of the old one), restart.
- **From source:**
  ```bash
  git clone https://github.com/Mieze/RTL8111_driver_for_OS_X.git && cd RTL8111_driver_for_OS_X
  git checkout a3dad34
  git clone https://github.com/acidanthera/MacKernelSDK.git
  git apply /path/to/hackintosh-rtl8111-s5-wol/patch/RealtekRTL8111-wol-s5.patch
  bash /path/to/hackintosh-rtl8111-s5-wol/tools/build-install.sh .      # builds, backs up, installs (EFI mounted)
  ```

Step by step, with rollback: [docs/04-build-and-install.md](docs/04-build-and-install.md).

## Tested on

| | |
| :--- | :--- |
| Board | ASUS PRIME B550M-K, BIOS 4101, Ryzen 5 5600X |
| NIC | Realtek RTL8111H (CFG_METHOD_29) |
| macOS | 26.2 (25C56), OpenCore 1.0.8, SMBIOS MacPro7,1 |
| Driver | RealtekRTL8111 Version 3.0.0 (build 3.0.4, upstream `a3dad34`) + this patch |
| Results | WoL from S5 after a sleep: 31–36 s to the first ping; without a sleep: 45 s; after switching to Windows and shutting down there: 39 s; from Home Assistant: 33 s ([docs/05-testing.md](docs/05-testing.md)) |

## Documentation

| File | Contents |
| :--- | :--- |
| [docs/01-symptoms.md](docs/01-symptoms.md) | Is this your problem? Pattern, LEDs, look-alikes |
| [docs/02-root-cause.md](docs/02-root-cause.md) | Why it happens, step by step, with the trace evidence and sources |
| [docs/03-the-patch.md](docs/03-the-patch.md) | Every change of the patch explained, behavior notes |
| [docs/04-build-and-install.md](docs/04-build-and-install.md) | Prebuilt or build from source, install, roll back |
| [docs/05-testing.md](docs/05-testing.md) | Test procedure, pitfalls, full results |
| [docs/06-bios-and-hardware.md](docs/06-bios-and-hardware.md) | BIOS settings, how the wake works on the test board, other hardware |
| [docs/07-windows-dual-boot.md](docs/07-windows-dual-boot.md) | Optional: Windows driver settings, Fast Startup, switching OS by BootNext |
| [docs/08-home-assistant.md](docs/08-home-assistant.md) | Optional: power on/off from Home Assistant, the old workaround |
| [docs/09-diagnostics.md](docs/09-diagnostics.md) | Optional: quick checks, troubleshooting table, the research build |
| [docs/10-ruled-out.md](docs/10-ruled-out.md) | What it was not: firmware, ACPI, BIOS SMM findings |
| [docs/11-history.md](docs/11-history.md) | How it was found, and lessons |

## Repository layout

```
patch/        the fix (git apply against upstream a3dad34)
tools/        build-install.sh (build + backup + install), wol.py (send a magic packet)
docs/         the documentation above
diagnostics/  the research build: trace, register access, snapshots (debugging only)
```

## Credits

- [Mieze](https://github.com/Mieze) for RealtekRTL8111.kext (and the r8168 port it is based on, from Realtek's Linux
  driver).
- [acidanthera](https://github.com/acidanthera) for OpenCore and MacKernelSDK.
- Apple's open source releases of [xnu](https://github.com/apple-oss-distributions/xnu) and
  [IONetworkingFamily](https://github.com/apple-oss-distributions/IONetworkingFamily), which showed the cause.
- Investigated and written with [Claude Code](https://claude.com/claude-code); tested on real hardware by
  [@biolohh](https://github.com/biolohh).

## License

GPL-2.0-or-later, like the driver the patch applies to (see [LICENSE](LICENSE)).
