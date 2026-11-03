# 11. How it was found (history)

The work was done with an AI coding agent (Claude Code), over SSH on the Hackintosh, with the machine's owner doing
the physical part: watching the LAN LEDs, pressing the power button when WoL failed, switching the PSU off. Total:
about two and a half days, 2026-11-01 to 2026-11-03.

## Timeline

1. **The symptom.** Home Assistant could not power the Hackintosh on after a shutdown, but only sometimes. The
   pattern: after any sleep since the last manual power-on ([01-symptoms.md](01-symptoms.md)).
2. **First driver patches** (local builds 3.0.5–3.0.8):
   - 3.0.5: `PME_En` + D3 at shutdown, as for sleep. Not enough.
   - 3.0.6: force `wol_enabled` and `WAKE_MAGIC` at shutdown. No effect (later understood: `disable()` returns
     early).
   - 3.0.7: write-1-to-clear `PME_Status` (it was stuck at `0x8008`). Kept.
   - 3.0.8: always WoL capable on RTL8168. Kept; it fixed sessions without any WoL after a restart (for example
     after switching from Windows).
   - Stopgap in Home Assistant: sleep instead of shutdown after a macOS sleep ([08-home-assistant.md](08-home-assistant.md)).
3. **Firmware investigation** (3.0.9–3.0.17: root-only register access in the driver): ACPI tables, BIOS 4101 SMM
   reverse engineering, full register snapshots of the good and the broken state, S5 LED tests with the owner. All
   in [10-ruled-out.md](10-ruled-out.md). Key results: the S3 cycle itself is the trigger (an RTC wake breaks it
   too); in S0 the only difference is the magic packet bit; in the broken S5 the NIC has no link.
4. **The turn** (3.0.18–3.0.21, one night): keeping the NIC in D0 during sleep changed nothing, so the problem was
   not the sleep itself but something after it. Apple's IONetworkingFamily source showed that macOS turns WoL off
   after every wake. 3.0.19 added the re-arm in `systemWillShutdown()` and fixed restarts after a sleep without a
   manual power-on. 3.0.21 added the NVRAM event trace, which showed the exact order: the interface goes down with
   WoL off **before** `systemWillShutdown()` runs. xnu's `reboot_kernel()` → `if_down_all()` confirmed it
   ([02-root-cause.md](02-root-cause.md)).
5. **The final patch**: the fix without diagnostics, explicit `specifier ==` (the local diagnostic patch had a bit
   mask test that also matched restarts, which turned out to be desirable), and in 3.0.22 the re-arm only when needed
   (keeps the 10 Mbit/s link in S5 when no sleep came before).
6. **Tests with the owner** (morning of 2026-11-03): WoL from S5 after a sleep with 3.0.21 and 3.0.22, without a
   sleep, through Home Assistant, and after switching to Windows ([05-testing.md](05-testing.md)). The Home
   Assistant stopgap was removed.

## Lessons

- **Trace before you guess.** Many hours went into firmware theories. A 480-byte event log written to NVRAM at
  shutdown found the cause in one restart.
- **Read the OS source.** The decisive facts (WoL off after every wake, `if_down_all()` before the shutdown handler)
  are in Apple's open source (xnu, IONetworkingFamily).
- **A cheap visible signal helps.** The LAN LED in S5 (dark or lit) separated "the NIC is off" from "the wake path
  is broken" without any tools.
- **Restarts are not neutral.** The broken state was carried across restarts by a single bit in the NIC, which made
  the bug look random.
