# 3. The patch

[`patch/RealtekRTL8111-wol-s5.patch`](../patch/RealtekRTL8111-wol-s5.patch): 3 files, +75/−3 lines, against
[Mieze/RTL8111_driver_for_OS_X](https://github.com/Mieze/RTL8111_driver_for_OS_X) master **`a3dad34`**
("Version 3.0.0 (build 3.0.4)", 2025-12-14). It does not change the Xcode project or the version number.

## What it changes

### 1. `systemWillShutdown()`: arm WoL for power off and restart (`RealtekRTL8111.cpp`)

```cpp
bool armWoL = wolCapable && ((specifier == kIOMessageSystemWillPowerOff) ||
                             (specifier == kIOMessageSystemWillRestart));
if (armWoL) {
    wolActive = true;
    linuxData.wol_enabled = WOL_ENABLED;
    linuxData.wol_opts |= WAKE_MAGIC;
}
disable(netif);
```

- WoL is armed for a **power off** and also for a **restart**. On a restart the chip keeps ERI `0xDE` bit 0 set, so
  the next boot (macOS, or Windows in a dual boot) starts with WoL on, and the good state survives restarts.
- The test is `==`, not a bit mask: `kIOMessageSystemWillPowerOff` (`0xE0000250`) and
  `kIOMessageSystemWillRestart` (`0xE0000310`) share bits, so `kIOMessageSystemWillPowerOff & specifier` is also true
  for a restart. (The upstream outer condition, `(PowerOff | Restart) & specifier`, is fine.)
- If the interface is still up here (older macOS, or a kernel that does not call `if_down_all()`), `disable()` now
  powers the NIC down in WoL mode, as for sleep.

### 2. Re-arm when the kernel already took the interface down without WoL

```cpp
if (armWoL && !wolArmedOnDisable) {
    rtl8168_powerup_pll(&linuxData);
    switch (linuxData.mcfg) {
        case CFG_METHOD_14 ... CFG_METHOD_15:
            WriteReg8(0xD0, ReadReg8(0xD0) | BIT_6);
            break;
        case CFG_METHOD_16 ... CFG_METHOD_32:
            WriteReg8(0xD0, ReadReg8(0xD0) | BIT_6);
            WriteReg8(0xF2, ReadReg8(0xF2) | BIT_6);
            break;
        default:
            break;
    }
    rtl8168_powerdown_pll(&linuxData);
}
```

This is the actual fix. If `if_down_all()` powered the NIC down without WoL (see [02-root-cause.md](02-root-cause.md)),
the handler powers the PLL and the PHY up again, restores the two bits the non-WoL branch cleared (`0xD0` and `0xF2`
bit 6, per the same `mcfg` cases as `rtl8168_powerdown_pll()`), and powers down again, now with `wol_enabled` = 1.
That runs the WoL branch of `rtl8168_powerdown_pll()`: `rtl8168_set_hw_wol()` (ERI `0xDE` bit 0), Config2
`PMSTS_En`, low-speed advertisement, nway restart, RxConfig accept bits. The rest of `disableRTL8111()`
(`rtl8168_dsm()`, `rtl8168_nic_reset()`, `hardwareD3Para()`; `sleepRxEnable()` is empty for this chip) does not
depend on WoL, so the result is the same as if macOS had taken the interface down in WoL mode.

`wolArmedOnDisable` is set in `disableRTL8111()` (`RealtekRTL8111Hardware.cpp`) right before
`rtl8168_powerdown_pll()`:

```cpp
wolArmedOnDisable = (tp->wol_enabled == WOL_ENABLED);
```

So the re-arm runs only when it is needed. Without that condition a second power-down after a WoL power-down
restarts the link negotiation before the link partner's abilities are known (most likely `MII_LPA` is not valid
yet during the renegotiation), the driver then advertises 10/100 instead of 10 only, and the link in S5 comes up at 100 Mbit/s. That
still wakes, but it is not what the driver intends. With the condition:

| Shutdown | Link in S5 (LED on the test board) |
| :--- | :--- |
| without a sleep before it (no re-arm, same as upstream) | 10 Mbit/s (green blinking) |
| after a sleep (re-arm, the PHY was off before) | 100 Mbit/s (yellow steady + green blinking) |

### 3. Restore the MAC address, clear a stale `PME_Status`, log

After the existing `rtl8168_rar_set()` (restore the original MAC address):

```cpp
if (armWoL) {
    /* Clear a stale PME_Status (write 1 to clear), the BIOS sets PME_En. */
    ...
    IOLog("Ethernet [RealtekRTL8111]: WoL from S5 armed.\n");
}
```

`PME_En` is left to the firmware: on the test board the BIOS S5 SMI handler sets `PME_En` on every PME-capable
endpoint when "Power On By PCI-E" is enabled. The log string also lets you check that a binary contains the patch:
`grep -a "WoL from S5 armed" RealtekRTL8111.kext/Contents/MacOS/RealtekRTL8111`.

### 4. `setPowerStateWakeAction()`: clear `PME_Status` properly (`RealtekRTL8111Hardware.cpp`)

`PME_Status` is write-1-to-clear. Upstream masked it out (wrote 0), so after a WoL wake it stayed set
(`PMCSR` = `0x8008`). The patch writes 1 to clear it.

### 5. `initRTL8111()`: always WoL capable on CFG_METHOD_16–32

Upstream decided "WoL capable" from Config3/Config5 and ERI `0xDE` bit 0. That bit only says whether WoL was armed
when the chip was last powered down, so after a shutdown or restart without WoL the driver reported no WoL support
for the whole session. These chips support magic packet wakeup anyway: the patch sets `wol = true` for them, adds
`WAKE_MAGIC` to `wol_opts`, and drops the now unused ERI `0xDE` read.

## Behavior notes

- **WoL from S5 is armed whenever the driver is WoL capable.** macOS has no S5 WoL setting ("Wake for network access"
  controls sleep). To turn WoL from shutdown off, disable it in the BIOS ("Power On By PCI-E" or similar). The NIC
  keeps a link in S5, which costs a few hundred mW of standby power.
- **Restarts keep the armed state**, so WoL from S5 works after any number of macOS restarts, and after switching to
  another OS by restart (the other OS's driver takes over from there).
- **No diagnostics, no new settings.** The patched driver has the same Info.plist and properties as upstream.

## Things that do not work (tried)

- Forcing `wol_enabled` = 1 in `systemWillShutdown()` alone: `disable()` returns early, see
  [02-root-cause.md](02-root-cause.md).
- D3hot + `PME_En` at shutdown, the BIOS S3 board settings in S5: the PHY is already off.
- A user space hook at shutdown: the kernel takes the interfaces down after user space is gone.
- A workaround without a patch: sleep instead of shutdown (WoL from S3 always works). It worked for us as a stopgap in
  Home Assistant (see [08-home-assistant.md](08-home-assistant.md)).
