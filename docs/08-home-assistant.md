# 8. Optional: Home Assistant

How the test machine is controlled from Home Assistant: "on" = Wake-on-LAN, "off" = a real shutdown. Adapt names,
addresses and the shutdown method to your setup. `<MAC>`, `<MAC_IP>` and `<BROADCAST>` are placeholders.

## Wake

The built-in [Wake on LAN](https://www.home-assistant.io/integrations/wake_on_lan/) integration:

```yaml
wake_on_lan:

script:
  mac_power_on:
    alias: "Mac: power on"
    mode: single
    sequence:
      # resend every 15 s for 90 s: a packet sent while the machine is still shutting down is lost
      - repeat:
          sequence:
            - action: wake_on_lan.send_magic_packet
              data:
                mac: "<MAC>"
                broadcast_address: "<BROADCAST>"     # e.g. 192.168.1.255
            - wait_template: "{{ is_state('binary_sensor.mac_online', 'on') }}"
              timeout: 15
          until:
            - condition: template
              value_template: "{{ wait.completed or repeat.index >= 6 }}"
```

## Online state

Windows (in a dual boot) blocks ping by default, so a TCP port check is more reliable:

```yaml
command_line:
  - binary_sensor:
      name: "Mac online"
      unique_id: mac_online
      command: "nc -z -w 1 <MAC_IP> 22 && echo on || echo off"
      payload_on: "on"
      payload_off: "off"
      scan_interval: 10
```

The test machine runs macOS and Windows on the same IP and MAC. Its sensor tells them apart by a port that only the
macOS side has open, and otherwise by the SSH host key on port 22 (`ssh-keyscan`, compared with `known_hosts`).

## Shut down

Over SSH, with a sudoers rule on the Mac that allows only `shutdown`:

```bash
# on the Mac
echo "$(whoami) ALL=(root) NOPASSWD: /sbin/shutdown" | sudo tee /etc/sudoers.d/ha-shutdown
sudo chmod 440 /etc/sudoers.d/ha-shutdown && sudo visudo -c
```

```yaml
shell_command:
  mac_shutdown: "ssh -i /config/.ssh/id_ed25519 -o BatchMode=yes <user>@<MAC_IP> 'sudo /sbin/shutdown -h now'"
  mac_sleep: "ssh -i /config/.ssh/id_ed25519 -o BatchMode=yes <user>@<MAC_IP> 'pmset sleepnow'"

script:
  mac_power_off:
    alias: "Mac: shut down"
    mode: single
    sequence:
      - action: shell_command.mac_shutdown
      - wait_template: "{{ is_state('binary_sensor.mac_online', 'off') }}"
        timeout: "00:02:00"
```

Put the SSH key into the HA config folder (`/config/.ssh/`), add the Mac's host key to `known_hosts`, and consider
restricting the key in the Mac's `~/.ssh/authorized_keys` (`command="…"`, `from="<HA IP>"`).

## One switch

Settings → Devices & services → Helpers → Create helper → Template → Switch:

- State: `{{ is_state('binary_sensor.mac_online', 'on') }}`
- Turn on: `script.mac_power_on`
- Turn off: `script.mac_power_off`

With a dual boot the test machine has two such switches ("macOS" and "Windows"). Turning one on wakes the machine,
waits for an OS, and if the other one came up, switches with a one-time BootNext (see
[07-windows-dual-boot.md](07-windows-dual-boot.md)).

## Without the patch: a workaround

Until the patch existed, Home Assistant avoided the bug: WoL from sleep always works, so "off" put the Mac to sleep
instead of shutting it down whenever macOS had slept since the last manual power-on. An `input_boolean` tracked that:

- on: when HA put the Mac to sleep, or when `sysctl -n kern.waketime` (over SSH, 30 s after macOS came up) showed a
  wake in this boot (`sec` > 0);
- off: when the machine had been off for at least 90 s and then came up (a manual power-on; restarts take 9–50 s).

It worked, but the machine never really powered off after a sleep. With the patch it is not needed anymore.
