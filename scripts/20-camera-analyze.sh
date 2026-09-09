#!/usr/bin/env bash
# Staged camera diagnostic for Surface Pro 10 (Meteor Lake / IPU6EP).
#
# Read-only. Walks the camera driver chain stage by stage and reports where
# it breaks, so the next step is a decision rather than a guess.
#
# The chain:
#   [1] IPU6 ISP  →  [2] IVSC/MEI  →  [3] INT3472 bridge  →  [4] sensor driver
#   →  [5] media graph / V4L2  →  [6] libcamera
set -uo pipefail

STAGE_OK=0   # highest stage reached

section() { printf '\n\033[1m=== [%s] %s ===\033[0m\n' "$1" "$2"; }
note()    { printf '    %s\n' "$1"; }
ok()      { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()     { printf '  \033[31m✗\033[0m %s\n' "$1"; }
warn()    { printf '  \033[33m!\033[0m %s\n' "$1"; }

DMESG=$(sudo dmesg 2>/dev/null || echo "")
if [ -z "$DMESG" ]; then
    warn "dmesg konnte nicht gelesen werden - Skript ggf. mit sudo erneut ausführen."
fi

# --- Stage 1: IPU6 ISP -----------------------------------------------------
section 1 "IPU6 ISP (Bildprozessor)"
if lspci -nn 2>/dev/null | grep -iqE 'image process|imaging unit|\[8086:[0-9a-f]{4}\].*(camera|imaging)'; then
    ok "IPU-PCI-Gerät gefunden:"
    lspci -nn | grep -iE 'image process|imaging unit|camera|imaging' | sed 's/^/      /'
    STAGE_OK=1
else
    bad "Kein IPU-PCI-Gerät sichtbar."
    note "Erwartet wird ein Intel 'Image Processing Unit' Eintrag."
fi

if lsmod 2>/dev/null | grep -qE '^intel_ipu6'; then
    ok "IPU6-Kernelmodule geladen:"
    lsmod | grep -E '^intel_ipu6|^ipu6' | sed 's/^/      /'
    STAGE_OK=1
else
    bad "Keine intel_ipu6-Module geladen."
    note "Ab Kernel 6.10 sollte intel_ipu6 / intel_ipu6_isys mainline vorhanden sein."
    note "Prüfen: modinfo intel_ipu6"
fi

echo "$DMESG" | grep -iE 'ipu6|ipu-bridge' | tail -15 | sed 's/^/      /'

# --- Stage 2: IVSC / MEI ---------------------------------------------------
section 2 "IVSC / MEI (Sensor-Stromversorgung und CSI-Bridge)"
if lsmod 2>/dev/null | grep -qE 'mei_vsc|ivsc'; then
    ok "VSC-Module geladen:"
    lsmod | grep -E 'mei_vsc|ivsc' | sed 's/^/      /'
    [ "$STAGE_OK" -ge 1 ] && STAGE_OK=2
else
    warn "Keine mei_vsc/ivsc-Module geladen."
    note "Ohne ivsc-ace/ivsc-csi wird der Sensor nicht eingeschaltet."
    note "Nicht jedes Gerät nutzt IVSC - kein Ausschlusskriterium."
fi
echo "$DMESG" | grep -iE 'mei_vsc|ivsc' | tail -10 | sed 's/^/      /'

# --- Stage 3: INT3472 bridge ----------------------------------------------
section 3 "INT3472 (ACPI-Bridge: GPIOs, Clocks, Regulatoren)"
INT3472_DEVS=$(ls /sys/bus/acpi/devices 2>/dev/null | grep -i 'INT3472' || true)
if [ -n "$INT3472_DEVS" ]; then
    ok "INT3472-ACPI-Geräte vorhanden:"
    echo "$INT3472_DEVS" | sed 's/^/      /'
    [ "$STAGE_OK" -ge 1 ] && STAGE_OK=3
else
    bad "Keine INT3472-Geräte gefunden."
    note "Ohne diese Bridge bekommt der Sensortreiber weder Clock noch Reset-GPIO."
fi

# The known Meteor Lake blocker: unsupported GPIO type from a Lattice aggregator
GPIO_UNKNOWN=$(echo "$DMESG" | grep -iE 'GPIO type 0x[0-9a-f]+ unknown|int3472.*unknown' || true)
if [ -n "$GPIO_UNKNOWN" ]; then
    bad "BEKANNTER BLOCKER GEFUNDEN - nicht unterstützter GPIO-Typ:"
    echo "$GPIO_UNKNOWN" | sed 's/^/      /'
    note "Das ist das Lattice-MIPI-Aggregator-Problem (intel/ipu6-drivers#281),"
    note "bestätigt auf Meteor-Lake-Geräten. Upstream-Patches sind in Arbeit."
fi
echo "$DMESG" | grep -iE 'int3472' | tail -10 | sed 's/^/      /'

# --- Stage 4: sensor drivers ----------------------------------------------
section 4 "Sensoren (IMX681 Front / OV13858 Rück / VD55G0 IR)"
SENSOR_ACPI=$(ls /sys/bus/acpi/devices 2>/dev/null \
    | grep -iE 'OVTI|SONY|IMX|INT3474|VD55|STMI' || true)
if [ -n "$SENSOR_ACPI" ]; then
    ok "Sensor-ACPI-Geräte gefunden:"
    echo "$SENSOR_ACPI" | sed 's/^/      /'
    note "Merke dir diese HIDs - sie werden für den modprobe-Alias gebraucht."
else
    bad "Keine Sensor-ACPI-Geräte sichtbar."
fi

echo
note "I2C-Geräte mit gebundenem Treiber:"
FOUND_BOUND=0
for d in /sys/bus/i2c/devices/*; do
    [ -e "$d" ] || continue
    name=$(cat "$d/name" 2>/dev/null || echo "?")
    if [ -L "$d/driver" ]; then
        drv=$(basename "$(readlink -f "$d/driver")")
        printf '      %-24s %-20s -> \033[32m%s\033[0m\n' "$(basename "$d")" "$name" "$drv"
        FOUND_BOUND=1
    else
        printf '      %-24s %-20s -> \033[31mkein Treiber gebunden\033[0m\n' "$(basename "$d")" "$name"
    fi
done
[ "$FOUND_BOUND" = "0" ] && note "(keine I2C-Geräte mit Treiberbindung)"

if lsmod 2>/dev/null | grep -qiE 'ov13858|ov13b10|imx|ov5693|vd55'; then
    ok "Sensormodul geladen:"
    lsmod | grep -iE 'ov13858|ov13b10|imx|ov5693|vd55' | sed 's/^/      /'
    [ "$STAGE_OK" -ge 3 ] && STAGE_OK=4
else
    bad "Kein Sensortreiber geladen."
    note "Vorhandene Treiber im Kernel prüfen:  modinfo ov13858"
    note "Häufige Ursache: der ACPI-HID steht nicht in der Match-Tabelle des"
    note "Treibers. Fix (Vorbild Surface Pro 9), noch NICHT anwenden - erst"
    note "den echten HID aus Stufe 4 oben einsetzen:"
    note '  echo "alias acpi*:<HID>:* ov13858" | sudo tee /etc/modprobe.d/ov13858-surface.conf'
fi

# --- Stage 5: media graph / V4L2 ------------------------------------------
section 5 "Media-Graph und V4L2-Knoten"
if ls /dev/media* >/dev/null 2>&1; then
    ok "Media-Geräte: $(ls /dev/media* | tr '\n' ' ')"
    if command -v media-ctl >/dev/null 2>&1; then
        for m in /dev/media*; do
            note "Graph von $m:"
            media-ctl -d "$m" -p 2>/dev/null | grep -E 'entity|pad|link' | head -25 | sed 's/^/      /'
        done
    else
        note "media-ctl nicht installiert (sudo apt install v4l-utils)"
    fi
else
    bad "Keine /dev/media*-Knoten."
fi

if ls /dev/video* >/dev/null 2>&1; then
    ok "Video-Knoten: $(ls /dev/video* | tr '\n' ' ')"
    [ "$STAGE_OK" -ge 4 ] && STAGE_OK=5
    command -v v4l2-ctl >/dev/null 2>&1 && v4l2-ctl --list-devices 2>/dev/null | sed 's/^/      /'
else
    bad "Keine /dev/video*-Knoten."
    note "Hinweis: IPU6-Kameras erscheinen NICHT automatisch als /dev/video*."
    note "Dafür braucht es v4l2loopback + v4l2-relayd (siehe docs/03-camera-status.md)."
fi

# --- Stage 6: libcamera ----------------------------------------------------
section 6 "libcamera"
if command -v cam >/dev/null 2>&1; then
    CAM_OUT=$(cam -l 2>&1 || true)
    echo "$CAM_OUT" | sed 's/^/      /'
    if echo "$CAM_OUT" | grep -qiE 'Available cameras|^[0-9]+:'; then
        ok "libcamera meldet Kameras."
        [ "$STAGE_OK" -ge 5 ] && STAGE_OK=6
    else
        bad "libcamera findet keine Kamera."
    fi
else
    warn "libcamera-tools nicht installiert (sudo apt install libcamera-tools)"
fi

# --- Verdict ---------------------------------------------------------------
printf '\n\033[1m=== ERGEBNIS ===\033[0m\n'
case "$STAGE_OK" in
  0) echo "  Die Kette beginnt nicht einmal: kein IPU6 sichtbar."
     echo "  → Kernel-Version prüfen (>= 6.10 nötig), Surface-Kernel installiert?" ;;
  1) echo "  Stufe 1 erreicht: ISP vorhanden, aber Sensor-Stromversorgung/Bridge fehlt."
     echo "  → Stufe 2/3 untersuchen (IVSC-Module, INT3472)." ;;
  2) echo "  Stufe 2 erreicht: IVSC läuft, aber die INT3472-Bridge liefert nichts."
     echo "  → ACPI-Dump auswerten: bash scripts/21-camera-acpi-dump.sh" ;;
  3) echo "  Stufe 3 erreicht: Bridge da, aber kein Sensortreiber gebunden."
     echo "  → AUSSICHTSREICHSTER PUNKT. Meist fehlt nur der ACPI-HID in der"
     echo "    Match-Tabelle → modprobe-Alias (siehe Stufe 4 oben)."
     echo "  → ACPI-Dump erzeugen und teilen: bash scripts/21-camera-acpi-dump.sh" ;;
  4) echo "  Stufe 4 erreicht: Sensortreiber gebunden, aber kein Media-Graph."
     echo "  → media-ctl-Verlinkung prüfen, ggf. Treiber-Patch nötig (wie beim SP9)." ;;
  5) echo "  Stufe 5 erreicht: V4L2 da, libcamera greift noch nicht."
     echo "  → libcamera-Version prüfen, ggf. aus Quellen bauen." ;;
  6) echo "  Alle Stufen erreicht - die Kamera sollte grundsätzlich funktionieren."
     echo "  → Für Apps mit /dev/video*-Bedarf: v4l2loopback + v4l2-relayd." ;;
esac
printf '\n  Details und Hintergrund: docs/03-camera-status.md\n\n'
