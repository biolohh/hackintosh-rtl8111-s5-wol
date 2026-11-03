# 6. BIOS and hardware

## Test machine

| | |
| :--- | :--- |
| Board | ASUS PRIME B550M-K, BIOS 4101 (AMI, 2025-10-16) |
| CPU / chipset | Ryzen 5 5600X (FCH in the CPU), B550 (Promontory) |
| NIC | Realtek RTL8111H (driver: CFG_METHOD_29), PCI subsystem `1043:8677`, behind the chipset |
| Super I/O | Nuvoton NCT6798D |
| macOS | 26.2 (25C56), SMBIOS MacPro7,1 |
| Bootloader | OpenCore 1.0.8 |
| Driver | Mieze RealtekRTL8111.kext, Version 3.0.0 (build 3.0.4) + this patch |
| Other OS | Windows 11 (dual boot through OpenCore) |

## BIOS settings that matter

On this ASUS board (Advanced → APM Configuration):

| Setting | Value | Why |
| :--- | :--- | :--- |
| Power On By PCI-E | **Enabled** | required for WoL from S5 on this board; the S5 SMI handler then also sets `PME_En` on the PME-capable endpoints and enables the board's wake routing |
| ErP Ready | **Disabled** | with ErP the board enters Deep S5 and cuts standby power to the NIC |
| Restore AC Power Loss | any | not involved |
| Onboard LAN (Advanced → Onboard Devices) | Enabled | |

Other vendors use other names: "Wake on LAN", "Resume by PCI-E/PME", "Power On By PME", "LAN Wake Up"; and for the
power saving mode that must be off: "ErP", "EuP", "Deep Sleep", "Deep S5", "Low power S5".

Check the BIOS part first: **WoL from shutdown must work right after a manual power-on** (before any macOS sleep).
If it does not, the patch cannot help; the problem is in the BIOS settings or the board.

## How the wake works on this board (measured)

- **The LAN wake is a power button event.** macOS reports `PWRB` (+ `SWUS SWDS M2_2`) as the wake reason after a WoL
  wake from S3, and `RTC0` after an RTC wake. The LAN's ACPI `_PRW` (GPE 0x08) never shows up: the NIC's WAKE#
  (LANWAKEB) is wired to the power button line (PWR_BTN#), not to a PCIe GPE.
- **Not through the Super I/O logic.** After a WoL wake the SIO event registers are empty.
- **Consequence:** with the BIOS settings above, WoL from S5 works if, and only if, the NIC is powered, has a link
  and has magic packet wakeup armed in S5. The wake itself does not depend on the BIOS's GPE/PME arming for the
  onboard LAN: the power button event is accepted in S5 anyway. That is why the problem could be fixed entirely in
  the driver.

## Things that are specific to the board

- The BIOS's S5 SMI handler (`AsusApmSmi`, reverse engineered from BIOS 4101) walks the PCI bus when "Power On By
  PCI-E" is on: clears `PME_Status`, sets `PME_En` on every D3cold-PME-capable endpoint (the NIC too), enables the
  wake GPEs and `PWDE`. Other boards may need the OS to set `PME_En`; the patch leaves it to the firmware.
- With ErP disabled, "Deep S5" is off (SIO LDN 16 CR 30 bit 0 = 0) and the NIC keeps standby power.
- After a power cut (G3) the board needs one manual power-on before WoL from S5 works again. That is normal for many
  boards.

## Notes for other hardware

- **Other RTL8111/8168 revisions:** the re-arm uses the same `mcfg` cases as the driver's own
  `rtl8168_powerdown_pll()`, so it should behave the same on every revision the driver supports. Only CFG_METHOD_29
  was tested.
- **Other NICs (Intel, RTL8125):** Mieze's IntelMausi and LucyRTL8125 drivers have the same structure
  (`systemWillShutdown()` → `disable()`), and macOS behaves the same for every driver (WoL off after wake,
  `if_down_all()` before the shutdown handler). The same idea (re-arm in `systemWillShutdown()` when the interface
  went down without WoL) likely applies there, but it is not part of this patch and was not tested. See
  https://github.com/Mieze/IntelMausiEthernet/issues/17 and https://github.com/Mieze/LucyRTL8125Ethernet/issues/17.
