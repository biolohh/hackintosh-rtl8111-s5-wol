# 10. What it was not (measured)

Before the cause was found in the driver, the investigation went through the firmware. These were measured on the
test machine and ruled out; they may save time on other boards.

## Firmware and board

- **BIOS GPE/PME arming, Super I/O wake path.** The LAN wake does not come through the PCIe GPE or the Super I/O's
  RI#/wake logic: the wake reason is a power button event (`PWRB`), and the SIO event registers are empty after a WoL
  wake (see [06-bios-and-hardware.md](06-bios-and-hardware.md)).
- **Deep S5.** ErP is off; the SIO's Deep S5 enable (LDN 16 CR 30 bit 0) is 0.
- **D3hot + `PME_En` at shutdown** (as the driver does for sleep): LEDs still dark in S5.
- **The BIOS's S3 board settings applied in S5** (the S3 SMI handler drives a GPIO low, changes SIO wake bits and the
  3VSB switch; replayed before S5): LEDs still dark.
- **Traces of the S3 cycle on the board**: the DSDT `BLNK` power LED blink state and the SIO power-loss flag do not
  matter when entering S5. All other FCH, CMOS, BIOS RAM and chipset GPIO registers were identical in the good and
  the broken state.
- **D3hot during sleep**: WoL from S3 also works with the NIC kept in D0 + `PME_En` during sleep, and the state
  after it is broken the same way.

## The NIC in S0

A full register comparison of the good and the broken state in S0 (MMIO, ERI `0x000–0x3FF`, MAC OCP, PHY OCP, EPHY,
PCI config space) showed only one reliable difference: the magic packet wakeup bit (ERI `0xDE` bit 0), which the
driver reads into `wol_enabled`. The few MAC OCP / PHY OCP differences (`0xC0BC` bit 7, `0xE006` bit 13,
`0xA20C`/`0xA20E` bit 0, `0xA710` bit 15) are most likely leftovers of the non-WoL power-down before the reset.

## ACPI (the test machine's own tables)

- FADT: PM1a_EVT `0x800`, PM1a_CNT `0x804`, GPE0 `0x820`, `PCI_EXP_WAK` = 1, fixed power button; reset register: SMI
  port `0xB2` (`0xBE`).
- LAN device: `\_SB.PCI0.GPP1.PT02.PT29.RLAN`, `_PRW` = `GPRW(0x08, 0x04)` (GPE 0x08, wake from S4 at most per
  ACPI, but the board wakes from S5 through the power button path).
- `_PTS` → `SPTS`: for S3/S5 `SLPS = 1`, for S5 `PWDE = 1` (PMIO `0xBB` bit 6), `BLNK = 0`; `_WAK` → `SWAK`/`SIOW`.

## BIOS 4101 SMM (reverse engineered with UEFIExtract, IFRExtractor-RS and objdump)

| Module | S3 entry | S5 entry (and power button) |
| :--- | :--- | :--- |
| `AsusApmSmi` | clears GPE3 status; if the Realtek LAN is enabled: SIO LDN A CR EE bit 5 (RI wake), clears LDN 11 CR E2 bit 1 and CR E1 bit 2 | re-reads Setup; if "Power On By PCI(-E)": clears GPE0_STS, **walks PCI: clears `PME_Status`, sets `PME_En` on every D3cold-PME-capable endpoint** (the NIC too), GPE0_EN \|= `0x110104` + bit 3, `PWDE` = 1, `PCIEXP_WAKE_DIS` = 0, SIO RI bits; RTC wake |
| `AsusEupSmi` (ErP) | LDN 12 CR E2 bit 3 = 0 (USB power stays) | ErP off → Deep S5 disabled (LDN 16 CR 30 bit 0 = 0); USB power in S5 only with PS/2 wake, "USB power delivery in S5" or CMOS `0x60` bit 0 |
| `ProjectSMI` | SIO CR 2C bits 6–5 = 00 (pin 71: 3VSBSW#), LDN A CR E4 bit 4, **GP77 output low**, LDN 7 CR EC bit 7, power LED 1 Hz | nothing |
| `SleepSmi` | restart: CF9 (ToggleAllPwrGood logic); a separate "S3 + 3 s RTC wake" path | |

POST: `AsusOnBoardDeviceDxe` makes SIO GP36 (the LAN enable line) an input when the onboard LAN is enabled.

The firmware does everything needed for WoL from S5. It cannot help if the driver has already powered the NIC's PHY
and PLL down, which is what the driver did after a sleep.
