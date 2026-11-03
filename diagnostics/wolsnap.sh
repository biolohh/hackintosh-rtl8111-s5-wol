#!/bin/bash
# wolsnap.sh: full WoL-related register snapshot (S5 WoL investigation; MMIO, ECAM and SIO addresses are for an ASUS PRIME B550M-K, adjust them for your board), one "name hex" line per region.
# Needs the locally patched RealtekRTL8111.kext (3.0.10+) and wolpeek (WOLPEEK=path). Run: sudo bash ./wolsnap.sh > snap.txt
P=${WOLPEEK:-./wolpeek}
r() { printf '%s ' "$1"; "$P" "$2" | xxd -p | tr -d '\n'; echo; }
r pm1 "io16 0x800 4"; r pm1cnt "io16 0x804 2"; r gpe0 "io32 0x820 8"
r fch_smi_pmio_pmio2 "mmio 0xfed80200 0x300"; r fch_biosram "mmio8 0xfed80500 0x100"; r fch_acpi "mmio 0xfed80800 0x100"
r cmos_0e_ff "mmio8 0xfed8060e 0xf2"
r pt_gpio "mmio 0xfec30000 0x40"
r fch_iomux "mmio 0xfed80d00 0x100"; r fch_misc "mmio 0xfed80e00 0x100"; r fch_gpio "mmio 0xfed81500 0x400"; r fch_aoac "mmio 0xfed81e00 0x100"
r pci_nic_0a_00_0 "mmio 0xf0a00000 0x1000"; r pci_pt29_03_09_0 "mmio 0xf0348000 0x1000"; r pci_pt02_02_00_0 "mmio 0xf0200000 0x1000"
r pci_gpp1_00_01_2 "mmio 0xf000a000 0x1000"; r pci_smbus_00_14_0 "mmio 0xf00a0000 0x100"; r pci_lpc_00_14_3 "mmio 0xf00a3000 0x100"
r nicregs nicregs; r nic_eri eri; r nic_ocp nicocp; r nic_phy nicphy; r nic_ephy nicephy; r nic_ocpall ocpall; r nic_phyocp phyocp
# 3.0.18+: ERI 0x200-0x3FF, MAC OCP 0xF000-0xFFFE, and the raw NIC state at boot/wake before the driver set it up
r nic_erihi erihi; r nic_ocphi ocphi; r raw_boot rawboot; r raw_wake rawwake
for l in 0x03 0x07 0x08 0x09 0x0a 0x0b 0x0d 0x0e 0x0f 0x11 0x12 0x14 0x15 0x16 0x17 0x18; do r "sio_ldn_$l" "sio $l"; done
echo "nic $("$P" nic)"
echo "times $(sysctl -n kern.boottime kern.waketime kern.sleeptime | tr '\n' ' ')"
