# Research build (diagnostics only)

The driver build used to find the cause, kept for anyone who wants to debug WoL on other hardware.
**Not for daily use**: it lets root read physical memory, I/O ports and NIC registers, and write a few whitelisted
registers, through the driver.

| File | What it is |
| :--- | :--- |
| `RealtekRTL8111-wol-diag-3.0.21.patch` | against upstream `a3dad34`: an earlier form of the fix (re-arm in `systemWillShutdown()`, always), the NVRAM event trace, `WoLDiag-*` ioreg properties, the root-only command interface; sets the version to 3.0.21 |
| `wolpeek.c` | command line client for that interface |
| `wolsnap.sh` | full register snapshot (addresses for the test board: AMD B550, NCT6798D) |
| `wsdiff.py` | compares two snapshots, skips known noise |

How to use them, the trace format and the command list: [docs/09-diagnostics.md](../docs/09-diagnostics.md).
For the fix itself use [`patch/RealtekRTL8111-wol-s5.patch`](../patch/RealtekRTL8111-wol-s5.patch).
