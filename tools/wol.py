#!/usr/bin/env python3
"""Send a Wake-on-LAN magic packet.

    python3 wol.py <MAC> [broadcast address]      e.g.  python3 wol.py 00:11:22:33:44:55 192.168.1.255

The packet goes to UDP ports 9 and 7 of the broadcast address (default 255.255.255.255).
Use the broadcast address of your subnet if the default one does not reach the machine."""
import re
import socket
import sys

if len(sys.argv) < 2 or not re.fullmatch(r'([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}', sys.argv[1]):
    sys.exit(__doc__)
mac = bytes.fromhex(re.sub('[:-]', '', sys.argv[1]))
bcast = sys.argv[2] if len(sys.argv) > 2 else '255.255.255.255'
pkt = b'\xff' * 6 + mac * 16
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
for port in (9, 7):
    s.sendto(pkt, (bcast, port))
print(f'magic packet sent to {bcast} (UDP 9 and 7)')
