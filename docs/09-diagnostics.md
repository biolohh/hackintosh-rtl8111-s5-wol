# 9. Optional: diagnostics and troubleshooting

## Quick checks (no special build needed)

```bash
kextstat | grep -i realtek                                   # which RealtekRTL8111 is loaded
grep -a "WoL from S5 armed" /Volumes/EFI/EFI/OC/Kexts/RealtekRTL8111.kext/Contents/MacOS/RealtekRTL8111   # patched?
pmset -g | grep womp                                         # 1 = "Wake for network access" (WoL from sleep)
pmset -g log | grep -E " (Sleep|Wake) " | tail -5            # sleep/wake history and wake reasons
pmset -g assertions                                          # what prevents sleep
pmset -g sched                                               # scheduled wake/power-on events
ioreg -r -c RTL8111 -l -w0 | head -60                        # driver properties
log show --last 10m --predicate 'eventMessage CONTAINS "RealtekRTL8111"' --style compact   # driver log lines
```

(In zsh, `log` is a builtin; use `/usr/bin/log` in scripts.)

## Troubleshooting

| Observation | Likely cause | What to check |
| :--- | :--- | :--- |
| LEDs dark after shutdown, even right after a manual power-on | BIOS: ErP/Deep S5 on, LAN wake off, or the board cuts LAN standby power | [06-bios-and-hardware.md](06-bios-and-hardware.md) |
| LEDs dark after shutdown only after a sleep | the patched kext is not loaded | `kextstat`, the `grep -a` check above, the right EFI partition |
| LEDs lit in S5 but no wake | magic packet does not arrive or wake is not enabled in the BIOS | MAC address, broadcast address (try the subnet broadcast), the packet sent too early (resend after the machine is fully off), "Power On By PCI-E" |
| WoL works from S5 but not from sleep | macOS sleep setup | `womp 1`, [Dortania: sleep](https://dortania.github.io/OpenCore-Post-Install/universal/sleep.html) |
| The machine does not sleep at all | an assertion | `pmset -g assertions`; on the test machine a Broadcom Bluetooth USB hub (`BRCM20702 Hub`) once got stuck in a reset loop and kept `com.apple.pci.hostBridge.preventSleep` alive; a 10 s power cut fixed it |
| WoL fails after a power cut | normal on many boards | one manual power-on first |

## The research build (diagnostic kext)

[`diagnostics/`](../diagnostics) has the driver build used to find the cause (version 3.0.21). It contains an
earlier form of the fix plus diagnostics. **Use it only for debugging, not as your daily driver**: it gives root a
way to read physical memory, I/O ports and NIC registers and to write a few whitelisted registers, through the
driver.

What it adds:

- **Event trace**, kept in memory (`ioreg -l -w0 -r -c RTL8111 | grep '"WoLDiag-trace"'`) and written to NVRAM at the
  start and the end of `systemWillShutdown()`, so the previous shutdown or restart can be read after the next boot:
  `nvram rtl-wol-trace`. Events:

  | Event | Meaning |
  | :--- | :--- |
  | `B<wol_enabled>/<PMCH>` | boot |
  | `E` / `e` | `enable()` (`e`: already enabled) |
  | `D<wol_enabled>` + `P<PMCH bit 7>` | `disable()`; `P0` = PLL powered down |
  | `d` | `disable()` that did nothing (interface already down) |
  | `M1` / `M0` | `setWakeOnMagicPacket(true/false)` |
  | `S` / `W` | sleep / wake |
  | `X<P\|R><isEnabled><wol_enabled>` | `systemWillShutdown()` for power off / restart |
  | `R` | the re-arm ran |
  | `Y<PMCH>` | end of `systemWillShutdown()` |

  The buffer is 480 bytes; events after it is full are lost.

  Good shutdown without a sleep: `B1/f0 E D1 P1 XP01 d R Yf0` (this build always re-arms).
  The bug path, fixed: `B1/f0 E M1 D1 P1 S W E M0 D0 P0 XP00 d R Yf0`.

- **`WoLDiag-*` ioreg properties**: the WoL state at boot (`WoLDiag-boot`), on request (`WoLDiag-nic`), and results.
  `wol_enabled=1` is the good state, `0` the state the bug leaves after a wake. Do not confuse the boot value with the
  current one.
- **`wolpeek`** ([`diagnostics/wolpeek.c`](../diagnostics/wolpeek.c)): sends a command to the driver and prints the
  result. Build: `clang -O2 -framework IOKit -framework CoreFoundation -o wolpeek wolpeek.c`. Use: `sudo ./wolpeek
  "<command>"`. Commands (names of at most 7 characters; results of the `w…` commands go to `WoLDiag-outcmd`):
  - read: `phys|mmio|mmio8 <addr> <len>`, `io8|io16|io32 <port> <len>`, `nic`, `nicregs`, `eri`, `erihi`
    (ERI `0x200–0x3FF`), `nicocp`, `ocpall` (MAC OCP `0xC000–0xEFFE`), `ocphi` (`0xF000–0xFFFE`), `phyocp`
    (PHY OCP `0xA000–0xBFFE`), `nicphy` (MII 0x00–0x0F), `nicephy` (EPHY), `rawboot`/`rawwake` (raw NIC state at boot
    and at wake, before the driver set it up), `sio <LDN>`, `rsio <LDN<<8|CR>`;
  - write (limited): `wmmio` (FCH `0xFED80000–0xFED81FFF`, ECAM), `wio8|16|32` (`0x800–0x8FF`), `wpmcsr 0 <value>`,
    `wsio`, `wocp`/`wpocp <reg> <value>`, `wolarm 0 1`, `wsleep 0 <0|1>` (1: stay in D0 + `PME_En` for sleep),
    `wwomp 0 <0|1>` (call `setWakeOnMagicPacket()` like macOS does), `wtrace 0 0` (write the trace to NVRAM now);
  - `s5run "<command>;…"`: run commands at the next shutdown, after WoL is armed.
- **`wolsnap.sh`**: one snapshot of everything WoL-related (ACPI PM1/GPE0, FCH registers, CMOS, chipset GPIO, PCIe
  config of the NIC and its bridges, NIC MMIO/ERI/OCP/PHY, raw boot/wake images, Super I/O). **The addresses are for
  the test board** (AMD B550, NCT6798D, the NIC's bus position); adjust them. Compare two snapshots with
  `python3 diagnostics/wsdiff.py A.txt B.txt` (`--all` also shows known noise). Snapshots contain the NIC's MAC
  address: mask it before sharing.

Build it like the final patch ([04-build-and-install.md](04-build-and-install.md)), with
`diagnostics/RealtekRTL8111-wol-diag-3.0.21.patch` instead (it also sets the version to 3.0.21).

## What to collect for a bug report

- macOS version, board and BIOS version, NIC (`ioreg -r -c RTL8111 -l -w0 | grep -E '"(model|IOModel|Chipset)"'`,
  e.g. `IOModel` = `RTL8168H/8111H`, `Chipset` = 29), kext version;
- the BIOS settings from [06-bios-and-hardware.md](06-bios-and-hardware.md);
- the results of the tests in [05-testing.md](05-testing.md), with the LED state in S5;
- with the research build: `nvram rtl-wol-trace` after the failing shutdown, and `ioreg -l -w0 -r -c RTL8111 | grep
  WoLDiag`.
