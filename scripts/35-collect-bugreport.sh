#!/usr/bin/env bash
# Collects everything needed for an upstream bug report about the stylus.
#
# Read-only. The measurements are already conclusive: touch delivers thousands
# of events, the pen delivers none on any node, so the digitizer never reports
# the stylus to the kernel. This gathers the supporting evidence in one file.
set -uo pipefail

OUT="${1:-$HOME/surface-pro-10-stylus-report.txt}"

{
echo "# Surface Pro 10 for Business - stylus not reported to kernel"
echo "# Generated: $(date -Is)"
echo

echo "## System"
grep PRETTY_NAME /etc/os-release
echo "Kernel: $(uname -r)"
echo "Device: $(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown)"
echo "BIOS:   $(cat /sys/class/dmi/id/bios_version 2>/dev/null || echo unknown)"
echo

echo "## Summary"
cat <<'TXT'
Touchscreen works. The stylus (Surface Slim Pen 2, working under Windows on
the same machine) produces no input events at all.

Reading raw evdev directly from all nine quickspi-hid nodes:
  - finger:  ~2000 events on the Touchscreen node (BTN_TOUCH, ABS_X, ABS_Y)
  - stylus:  0 events on every node, including the "Stylus" node

So this is not a libinput/libwacom/desktop mapping issue - no pen reports
reach the kernel at all.

Separately, with iptsd running the digitizer dies completely: it switches the
device to raw mode, where report size exceeds the intel_quickspi DMA buffer:
  intel_quickspi: Copied 4096 bytes instead of requested 4356
  intel_quickspi: read DMA buffer failed -5
  intel_quickspi: Wait RESET_RESPONSE timeout, ret:0
  intel_quickspi: Reset touch device failed, ret = -110
Activating the pen triggers such a report. Disabling iptsd makes touch stable.
TXT
echo

echo "## quickspi / THC kernel messages"
sudo dmesg 2>/dev/null | grep -iE 'quickspi|thc|hid' | head -40
echo

echo "## Input devices"
grep -B 2 -A 6 -i quickspi /proc/bus/input/devices 2>/dev/null
echo

echo "## HID report descriptor"
# The descriptor says whether a stylus collection is declared at all.
if [ -d /sys/kernel/debug/hid ]; then
    for d in /sys/kernel/debug/hid/*045E:0C7F*; do
        [ -e "$d" ] || continue
        echo "### $(basename "$d")"
        echo "--- rdesc ---"
        sudo cat "$d/rdesc" 2>/dev/null || echo "(nicht lesbar)"
        echo
    done
else
    echo "debugfs nicht eingehängt. Mit folgendem Befehl verfügbar machen:"
    echo "  sudo mount -t debugfs none /sys/kernel/debug"
fi
echo

echo "## Modules"
lsmod | grep -iE 'quickspi|thc|hid_multitouch|hid_generic' || echo "(keine)"
echo

echo "## iptsd"
systemctl list-units 'iptsd*' --all --no-pager 2>/dev/null | head -5
pgrep -a iptsd || echo "(nicht aktiv - so soll es sein)"
} > "$OUT" 2>&1

echo "Bericht geschrieben: $OUT"
echo
echo "Enthält Hardware- und Treiberinformationen, keine persönlichen Daten."
echo "Vor dem Veröffentlichen kurz durchsehen:  less $OUT"
