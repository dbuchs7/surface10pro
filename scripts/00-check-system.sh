#!/usr/bin/env bash
# Read-only diagnostic report for Surface Pro 10 (for Business) on Zorin OS.
# Changes nothing on the system. Run this first and share the output before
# running any install script.
set -uo pipefail

section() { printf '\n=== %s ===\n' "$1"; }

section "OS release"
cat /etc/os-release 2>/dev/null

section "Running kernel"
uname -a

section "CPU"
lscpu 2>/dev/null | grep -E 'Model name|Vendor ID'

section "Secure Boot state"
if command -v mokutil >/dev/null 2>&1; then
    mokutil --sb-state 2>/dev/null || echo "mokutil present but query failed"
elif [ -d /sys/firmware/efi ]; then
    echo "mokutil not installed; system is UEFI. To check: sudo apt install mokutil && mokutil --sb-state"
else
    echo "System does not appear to boot via UEFI (no /sys/firmware/efi)."
fi

section "linux-surface packages already installed?"
dpkg -l 2>/dev/null | grep -iE 'linux-image-surface|linux-headers-surface|iptsd|libwacom-surface' || echo "None found."

section "linux-surface apt source configured?"
if [ -f /etc/apt/sources.list.d/linux-surface.list ]; then
    cat /etc/apt/sources.list.d/linux-surface.list
else
    echo "Not configured yet."
fi

# --- Pen / touch -----------------------------------------------------------

section "Pen/touch kernel messages (ipts / ithc)"
sudo dmesg 2>/dev/null | grep -iE 'ipts|ithc|surface_hid|hid_surface' || echo "No matches (expected before installing the surface kernel)."

section "iptsd service"
systemctl status iptsd --no-pager 2>/dev/null | head -5 || echo "iptsd not installed."

section "Input devices"
if command -v libinput >/dev/null 2>&1; then
    sudo libinput list-devices 2>/dev/null | grep -iE 'Device:|Capabilities:' | head -40
else
    echo "libinput-tools not installed (sudo apt install libinput-tools)"
fi

# --- Camera ----------------------------------------------------------------
# The Surface Pro 10 (Meteor Lake) uses an IPU6EP ISP, which IS supported by
# the mainline kernel since 6.10. The blocker is the camera sensors:
#   front IMX681 (no Linux driver), rear OV13858, IR VD55G0.
# These probes show how far the chain currently gets.

section "Camera: ISP / imaging PCI devices"
lspci -nn 2>/dev/null | grep -iE 'camera|imaging|multimedia|image process' || echo "No imaging device found via lspci."

section "Camera: kernel messages (ipu / ivsc / mei_vsc / int3472)"
sudo dmesg 2>/dev/null | grep -iE 'ipu[0-9]|ivsc|mei_vsc|int3472' || echo "No matches."

section "Camera: loaded IPU/VSC modules"
lsmod 2>/dev/null | grep -iE 'ipu|ivsc|mei_vsc|ov13858|imx' || echo "None loaded."

section "Camera: ACPI sensor/bridge devices (INT3472 etc.)"
ls /sys/bus/acpi/devices 2>/dev/null | grep -iE 'INT3472|INT3474|OVTI|SONY|IMX' || echo "No camera-related ACPI devices found."

section "Camera: V4L2 devices"
ls -l /dev/video* 2>/dev/null || echo "No /dev/video* nodes."
if command -v v4l2-ctl >/dev/null 2>&1; then
    v4l2-ctl --list-devices 2>/dev/null
else
    echo "v4l-utils not installed (sudo apt install v4l-utils)"
fi

section "Camera: libcamera detection"
if command -v cam >/dev/null 2>&1; then
    cam -l 2>&1 | head -20
else
    echo "libcamera-tools not installed (sudo apt install libcamera-tools)"
fi

section "USB devices (external webcam check)"
lsusb 2>/dev/null

printf '\nDone. Copy everything above and share it back before running scripts/10-install-pen-touch.sh.\n'
