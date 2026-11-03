# 7. Optional: Windows dual boot

Everyone's setup is different; this is what worked on the test machine (Windows 11 Pro for Workstations, build
26200, on the same disk set, booted through OpenCore, macOS is OpenCore's default entry).

## Result

macOS sleep → wake → restart into Windows → Windows shutdown → WoL: **works** (powered on in 39 s, macOS booted as
the default entry). The patched kext arms WoL on the restart into Windows; from there the Windows driver handles
its own shutdown. In S5 only the green LED blinked (10 Mbit/s, see "WOL & Shutdown Link Speed" below).

## Windows driver settings

Realtek PCIe GbE Family Controller, driver 10.79.50.1003 (2025-10-03). Device Manager → Network adapters → the
Realtek adapter → Properties:

**Power Management tab**

| Setting | Value |
| :--- | :--- |
| Allow the computer to turn off this device to save power | off |
| Allow this device to wake the computer | on |
| Only allow a magic packet to wake the computer | optional |

**Advanced tab** (English name / registry keyword / value on the test machine)

| Setting | Keyword | Value |
| :--- | :--- | :--- |
| Shutdown Wake-On-Lan | `S5WakeOnLan` | **Enabled** (required for WoL from shutdown) |
| Wake on Magic Packet | `*WakeOnMagicPacket` | **Enabled** |
| Wake on pattern match | `*WakeOnPattern` | Enabled |
| WOL & Shutdown Link Speed | `WolShutdownLinkSpeed` | 10 Mbps First |
| Wake on magic packet when system is in the S0ix power state | `*ModernStandbyWoLMagicPacket` | Disabled (not relevant on a desktop without Modern Standby) |
| Energy-Efficient Ethernet / Green Ethernet / Power Saving Mode | `*EEE`, `EnableGreenEthernet`, `PowerSavingMode` | Enabled (did not hurt) |

**Fast Startup off.** With Fast Startup, "Shut down" is a hybrid hibernation, and WoL behaves differently
(and the other OS sees a hibernated NTFS volume). Control Panel → Power Options → "Choose what the power buttons do"
→ uncheck "Turn on fast startup", or `powercfg /h off`. On the test machine `HiberbootEnabled` = 0.

Check and set from an elevated PowerShell:

```powershell
$a = Get-NetAdapter -Physical | Where-Object InterfaceDescription -like '*Realtek*'
Get-NetAdapterPowerManagement -Name $a.Name
Get-NetAdapterAdvancedProperty -Name $a.Name | Format-Table DisplayName, DisplayValue, RegistryKeyword
Set-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword S5WakeOnLan -RegistryValue 1
Set-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword '*WakeOnMagicPacket' -RegistryValue 1
(Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power').HiberbootEnabled   # 0 = Fast Startup off
```

A shutdown from the command line (`shutdown /s /t 0`) is a full shutdown unless `/hybrid` is given.

## Switching the OS remotely (how we did it)

Both directions use a one-time **BootNext**, so the default entry stays macOS.

- **macOS → Windows:** `sudo nvram 8BE4DF61-93CA-11D2-AA0D-00E098032B8C:BootNext=%00%00` (the EFI global variable
  GUID; BootNext = `Boot0000`, the Windows Boot Manager on the test machine). With OpenCore's
  `RequestBootVarRouting` the write is redirected into OpenCore's own variables, and OpenCore honors it. Writing it
  from macOS needs the SIP bit `0x40` (CSR_ALLOW_UNRESTRICTED_NVRAM) in `csr-active-config`. Then
  `sudo shutdown -r now`. Fallback without NVRAM access: `sudo bless --device /dev/<Windows ESP> --setBoot --nextonly`.
  On the test machine a small root-owned script does both, called through a NOPASSWD sudoers rule.
- **Windows → macOS:** a PowerShell script (run as administrator) enables `SeSystemEnvironmentPrivilege`, writes a
  `Boot0081` load option that points at macOS's `boot.efi` (an EFI device path: HD() node of the APFS partition +
  file path `\<Preboot volume UUID>\System\Library\CoreServices\boot.efi`) and `BootNext` = `0x0081`, both with
  `SetFirmwareEnvironmentVariableEx` under the same EFI global GUID (OpenCore's `RequestBootVarRouting` redirects
  them), then runs `shutdown /r /t 0`.

The macOS → Windows restart goes through the patched kext, so WoL stays armed for the Windows session too.
