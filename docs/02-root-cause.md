# 2. Root cause

Short version: **macOS takes the network interface down before the driver's shutdown handler runs, with the WoL
setting of that moment, and after every wake that setting is "off".** The driver then powers the PHY and the PLL
down, the NIC has no link in S5, and the "magic packet enabled" bit it leaves behind makes the next boot start with
WoL off again.

## The sequence, step by step

1. **Boot.** The driver reads the chip's magic packet wakeup bit (ERI register `0xDE`, bit 0) into
   `linuxData.wol_enabled` (`rtl8168_get_hw_wol()` in the Linux r8168 code the driver is built on). After a manual
   power-on the bit is 1 (chip default).

2. **Sleep.** If "Wake for network access" is on, macOS calls `setWakeOnMagicPacket(true)` before sleep, so
   `wol_enabled` = 1, and the driver's `disable()` → `disableRTL8111()` → `rtl8168_powerdown_pll()` takes the WoL
   branch: magic packet wakeup armed, PHY kept up at a low link speed. WoL from S3 works.

3. **Wake.** macOS calls `setWakeOnMagicPacket(false)`: on wake, IONetworkingFamily enables the controller with
   all wake filters off (`IOEthernetInterface`, `enableController()`). Now `wol_enabled` = 0 and stays 0 until the
   next sleep. macOS programs the WoL filter only on the sleep path; there is no S5 WoL setting in macOS.

4. **Shutdown or restart.** xnu's `reboot_kernel()` (`bsd/kern/kern_shutdown.c`) unmounts the file systems and then
   calls **`if_down_all()`** (`bsd/net/if.c`), which takes every network interface down. For this driver that is
   `disable()` → `disableRTL8111()` → `rtl8168_powerdown_pll()`, **with `wol_enabled` = 0**, so the non-WoL branch
   runs:
   - `rtl8168_phy_power_down()`,
   - `PMCH &= ~BIT_7` (PLL power down),
   - `0xD0 &= ~BIT_6`, `0xF2 &= ~BIT_6`.

   The PHY and the PLL are off.

5. **Only then** `host_reboot()` → `IOPMrootDomain::handlePlatformHaltRestart()` → the driver's
   **`systemWillShutdown()`**. Upstream calls `disable(netif)` there, but `disable()` returns at once because the
   interface is already disabled. Nothing arms WoL.

6. **In S5** the NIC has no link (dark LEDs): no magic packet can arrive.

7. **The next boot inherits it.** The WoL branch did not run, so ERI `0xDE` bit 0 stays 0, the next boot reads
   `wol_enabled` = 0, and the next shutdown powers the NIC down the same way, even without any sleep. This is why
   restarts do not help.

8. **A manual power-on repairs it.** Starting from a dark S5, the NIC gets a full power-on reset and ERI `0xDE`
   bit 0 is 1 again. (Indicator in the raw register image: byte 1 of ERI `0x1E8` is `0x00` after a power-on reset and
   `0x0a` when the chip stayed in standby, e.g. `a20a0101`.)

Two smaller driver issues make it worse:

- **WoL capability from the same bit.** For CFG_METHOD_16–32 the driver decided at init whether the chip is
  "WoL capable" from Config3/Config5 and the same ERI `0xDE` bit 0. In the inherited state above the driver reported
  no WoL support at all, so even WoL from sleep was off for that whole session.
- **`PME_Status` written with 0.** `PME_Status` in the PCI PM control register is write-1-to-clear. The driver wrote
  0 when coming back from sleep, so after a WoL wake the register stayed at `PMCSR` = `0x8008` (stale
  `PME_Status`).

## Evidence

A diagnostic build of the driver ([diagnostics/](../diagnostics)) records the WoL-relevant calls of a session and
saves them into NVRAM (`rtl-wol-trace`) at the start and the end of `systemWillShutdown()`, so they can be read after
the next boot. From the good state, a call that does what macOS does after a wake (`setWakeOnMagicPacket(false)`)
and a restart give:

```
B1/f0 E M0 D0 P0 XP00 d R Yf0
```

| Event | Meaning |
| :--- | :--- |
| `B1/f0` | boot: `wol_enabled` = 1, PMCH = `0xf0` |
| `E` | `enable()` |
| `M0` | `setWakeOnMagicPacket(false)` (what macOS does after every wake) |
| `D0` `P0` | the kernel takes the interface down with `wol_enabled` = 0; afterwards PMCH bit 7 = 0 (PLL off) |
| `XP00` | `systemWillShutdown()`: interface already disabled, `wol_enabled` = 0 |
| `d` | the driver's own `disable()` in `systemWillShutdown()` does nothing |
| `R` | the fix re-arms WoL (see [03-the-patch.md](03-the-patch.md)) |
| `Yf0` | end of the handler: PMCH = `0xf0`, PLL running again |

The same trace with a real sleep before the shutdown (diagnostic build 3.0.21, then WoL from S5 worked in 36 s):

```
B1/f0 E M1 D1 P1 S W E M0 D0 P0 XP00 d R Yf0
```

`M1 D1 P1 S` is the sleep (WoL armed, PLL kept), `W E M0` the wake, and the rest the shutdown as above.

Other measurements fit the same explanation:

- Without sleep the shutdown is fine: `wol_enabled` = 1 since the power-on.
- An RTC wake instead of WoL breaks it too: the trigger is the `setWakeOnMagicPacket(false)` after any wake, not the
  WoL event.
- Forcing D3hot + `PME_En` at shutdown, or replaying the BIOS's S3 board settings in S5, did not help: the PHY and
  the PLL were already off when those ran.
- A first attempt that forced `wol_enabled` = 1 in `systemWillShutdown()` had no effect, because it only acts through
  the driver's own `disable()`, which returns early once the interface is down.

## Sources

- xnu: `bsd/kern/kern_shutdown.c` (`reboot_kernel()`: `if_down_all()` before `host_reboot()`), `bsd/net/if.c`
  (`if_down_all()`): https://github.com/apple-oss-distributions/xnu
- IONetworkingFamily (`IOEthernetInterface::controllerWillChangePowerState()`: WoL filter only on the sleep path;
  `enableController()`: all filters off on wake; `IONetworkController::systemWillShutdown()`):
  https://github.com/apple-oss-distributions/IONetworkingFamily
- Mieze, RTL8111 driver thread (macOS supports WoL only from sleep):
  https://www.insanelymac.com/forum/topic/287161-new-driver-for-realtek-rtl8111/page/63/
- Upstream feature request for S5 WoL: https://github.com/Mieze/RTL8111_driver_for_OS_X/issues/74
