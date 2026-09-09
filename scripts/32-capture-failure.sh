#!/usr/bin/env bash
# Captures system state right after the digitizer has died.
#
# Read-only. Run this AS SOON AS touch/stylus stop responding - the kernel log
# around the moment of failure is the point of the exercise.
set -uo pipefail

OUT="${1:-$HOME/digitizer-failure-$(date +%H%M%S).txt}"

{
echo "# Digitizer-Ausfall - Zustandsaufnahme"
echo "# Zeit:   $(date -Is)"
echo "# Kernel: $(uname -r)"
echo

echo "=== Kernel-Log, letzte 80 Zeilen (mit Zeitstempel) ==="
sudo dmesg -T 2>/dev/null | tail -80

echo
echo "=== Auffälligkeiten: Fehler, Resets, Timeouts ==="
sudo dmesg -T 2>/dev/null \
    | grep -iE 'quickspi|thc|ithc|ipts|hid|stylus|pen|reset|timeout|fail|error|i2c_designware|spi' \
    | tail -50

echo
echo "=== Digitizer-Module ==="
lsmod 2>/dev/null | grep -iE 'quickspi|thc|ithc|ipts|hid' || echo "(keine)"

echo
echo "=== Existieren die Eingabegeräte noch? ==="
grep -iE 'Name=.*(stylus|touchscreen|IPTSD|quickspi)' /proc/bus/input/devices 2>/dev/null \
    || echo "(keine passenden Geräte mehr vorhanden!)"

echo
echo "=== hidraw-Geräte ==="
ls -l /sys/class/hidraw/ 2>/dev/null || echo "(keine)"

echo
echo "=== iptsd-Zustand (sollte abgeschaltet sein) ==="
systemctl list-units 'iptsd*' --all --no-pager 2>/dev/null | head -8
pgrep -a iptsd 2>/dev/null || echo "(kein iptsd-Prozess - gut)"

echo
echo "=== Stift per Bluetooth verbunden? ==="
if command -v bluetoothctl >/dev/null 2>&1; then
    bluetoothctl devices Connected 2>/dev/null || bluetoothctl devices 2>/dev/null | head -10
else
    echo "(bluetoothctl nicht verfügbar)"
fi

echo
echo "=== THC/QuickSPI PCI-Gerät ==="
lspci -nnk 2>/dev/null | grep -iA 3 'serial bus\|signal processing\|touch' | head -30
} > "$OUT" 2>&1

echo "Zustand gesichert in: $OUT"
echo
echo "Die wichtigsten Zeilen:"
grep -iE 'reset|timeout|fail|error' "$OUT" | tail -15 | sed 's/^/    /' \
    || echo "    (keine offensichtlichen Fehlermeldungen gefunden)"
echo
echo "Bitte die ganze Datei teilen:  cat $OUT"
