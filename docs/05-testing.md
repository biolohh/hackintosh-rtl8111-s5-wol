# 5. Testing

You need a second device on the same LAN to send the magic packet: [`tools/wol.py`](../tools/wol.py) (Python 3, any
OS), a phone app, your router, or Home Assistant.

```bash
networksetup -listallhardwareports           # find the Ethernet device, e.g. en0
ifconfig en0 | awk '/ether/ {print $2}'      # its MAC address
python3 tools/wol.py <MAC> <broadcast address of your LAN, e.g. 192.168.1.255>   # on the other device
```

## Test procedure

Do the tests in this order after installing the patched kext and restarting once. For each shutdown, look at the
LAN port LEDs about 15 s and 60 s after the machine went off, wait a minute or two, then send the magic packet.

| # | Steps | Expected |
| :--- | :--- | :--- |
| 1 | no sleep since boot → `sudo shutdown -h now` → WoL | LEDs lit in S5; the machine powers on (30–60 s to the login screen or ping) |
| 2 | `pmset sleepnow` → wait until it sleeps → wake it (WoL or keyboard) → `sudo shutdown -h now` → WoL | LEDs lit in S5; powers on. **This is the case the patch fixes.** |
| 3 | sleep → wake → `sudo shutdown -r now` → after the boot `sudo shutdown -h now` → WoL | powers on (the restart kept WoL armed) |
| 4 | optional: like 2, but shut down from the Apple menu | same as 2 (same kernel path) |
| 5 | optional: dual boot, see [07-windows-dual-boot.md](07-windows-dual-boot.md) | |

If test 2 fails, see [09-diagnostics.md](09-diagnostics.md).

## Pitfalls

- **Send the packet when the machine is completely off.** A packet sent during the shutdown is lost. Home Assistant
  in our setup resends every 15 s for 90 s.
- **Do not schedule an RTC wake for the test sleep** (`pmset relative wake …`): an RTC power-on would look like a
  successful WoL. `pmset -g sched` lists scheduled events.
- **Something may block sleep.** `pmset -g assertions` shows who prevents it. During our tests a Bluetooth USB hub in a
  reset loop kept `com.apple.pci.hostBridge.preventSleep` asserted; only a power cut cleared it.
- **WoL from sleep** needs "Wake for network access" (`pmset -g | grep womp` → `womp 1`). On the test board the wake
  reason after a WoL wake from S3 is `PWRB` (`pmset -g log | grep "Wake from"`): the NIC's WAKE# line goes to the
  power button logic.

## Results on the test machine

ASUS PRIME B550M-K, BIOS 4101, RTL8111H, macOS 26.2, OpenCore 1.0.8 (details:
[06-bios-and-hardware.md](06-bios-and-hardware.md)). "3.0.21" is the diagnostic build, "3.0.22" the final patch.
Times are from sending the magic packet to the first ping reply.

| Path | Unpatched (upstream 3.0.4 and early local builds) | Patched |
| :--- | :--- | :--- |
| power-on → shutdown → WoL | ✅ | not separately tested (same code path as the next row) |
| power-on → restart → shutdown → WoL | ✅ 35 s | ✅ 45 s (3.0.22, 10 Mbit/s link in S5) |
| power-on → **sleep → wake → shutdown** → WoL | ❌ LEDs dark | ✅ 36 s (3.0.21), 31 s (3.0.22) |
| power-on → sleep → wake → restart → shutdown → WoL | ❌ | ✅ (restart keeps WoL armed, checked with the trace) |
| sleep → WoL (from S3) | ✅ 5–24 s, even in the broken state | ✅ 4–8 s |
| after a failed WoL: manual power-on → shutdown → WoL | ✅ | ✅ |
| sleep → wake → restart into Windows → Windows shutdown → WoL | not tested | ✅ 39 s (3.0.22) |
| Home Assistant: sleep → wake → "off" (real shutdown) → "on" (WoL) | | ✅ 33 s (3.0.22) |

LED patterns in S5 on this board (green = link/activity, yellow = 100 Mbit/s):

| State | LEDs |
| :--- | :--- |
| broken (unpatched, after a sleep) | dark |
| patched, no sleep before the shutdown | green blinking (10 Mbit/s) |
| patched, after a sleep (re-armed) | yellow steady + green blinking (100 Mbit/s) |
| Windows shutdown ("WOL & Shutdown Link Speed" = "10 Mbps First") | green blinking |

Raw NIC registers after a WoL boot from S5 (diagnostic build): ERI `0x1E8` = `a20a0101` (the chip stayed in
standby, no power-on reset), ERI `0xDE` = `0x1f` (magic packet bit set), PMCH = `0xf0`.
