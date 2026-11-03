# 1. Symptoms: is this your problem?

## Who is affected

- A Hackintosh with an onboard **Realtek RTL8111/8168** NIC (tested: RTL8111H, "CFG_METHOD_29" in the driver),
- running **Mieze's [RealtekRTL8111.kext](https://github.com/Mieze/RTL8111_driver_for_OS_X)** (tested: Version 3.0.0, build 3.0.4),
- with **Wake-on-LAN from shutdown (S5)** enabled in the BIOS (on ASUS boards: "Power On By PCI-E").

The bug is in the driver's shutdown path, so other macOS versions and other RTL8111/8168 chip revisions are very
likely affected the same way. Only one machine was tested; reports from other boards are welcome.

## The pattern

| What you do | WoL result |
| :--- | :--- |
| Manual power-on, use macOS, shut down | ✅ WoL powers the machine on |
| Manual power-on, restart once or more, shut down | ✅ |
| Sleep (S3), then wake by WoL | ✅ always, even when the bug is active |
| Manual power-on, **sleep once**, wake, shut down | ❌ WoL does nothing |
| The same, then restart (macOS → macOS) any number of times, shut down | ❌ still broken |
| After a failed WoL: manual power-on, shut down | ✅ fixed until the next sleep |

In short: **one sleep/wake cycle since the last manual power-on breaks WoL from shutdown, and restarts do not
repair it. Only a manual power-on (or a power cut) does.**

## How to see it

Look at the LEDs of the LAN port a few seconds after the shutdown:

- **Broken:** all LAN LEDs are dark. The NIC has no link, so no magic packet can arrive.
- **Working:** at least one LAN LED is lit or blinking (link up, packets seen).

On the test board (ASUS PRIME B550M-K) the green LED is link/activity and the yellow one means 100 Mbit/s. In the
working state without a preceding sleep only the green LED blinks: the NIC renegotiates to 10 Mbit/s for WoL, as the
driver intends. Your board may use other colors.

## Not this problem

- **WoL from shutdown never works, not even right after a manual power-on:** check the BIOS first
  ([06-bios-and-hardware.md](06-bios-and-hardware.md)): ErP/EuP/Deep Sleep must be off, "Power On By PCI-E" (or
  "Wake on LAN", "Resume by PME") on. This patch fixes only the "broken after sleep" case.
- **WoL from sleep does not work:** check "Wake for network access" (`pmset -g | grep womp` must show `womp 1`)
  and the general sleep setup ([Dortania: sleep](https://dortania.github.io/OpenCore-Post-Install/universal/sleep.html)).
- **WoL from shutdown fails only after a power cut:** after a G3 (no standby power) many boards need one manual
  power-on before WoL works again. That is BIOS behavior, not this bug.

Next: [why it happens](02-root-cause.md).
