#!/usr/bin/env bash
# Camera diagnostic for Surface Pro 10 (Meteor Lake / IPU6EP).
#
# Read-only. Rewritten around what this machine actually reports, rather than
# the generic assumptions of the first version:
#   - the ISP is IPU6, mainline since kernel 6.10, and it initialises here
#   - the rear sensor driver ov13858 is present and loads
#   - INT3472 warns about GPIO type 0x08, for which a patch exists upstream
#   - the distro libcamera is 0.2.0, while IPU6 needs 0.3.2 or newer
set -uo pipefail

section() { printf '\n\033[1m=== %s ===\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
note() { printf '    %s\n' "$1"; }

DMESG=$(sudo dmesg 2>/dev/null || true)
BLOCKERS=()

section "Kernel"
note "$(uname -r)"

# --- 1. ISP ----------------------------------------------------------------
section "1. IPU6-Bildprozessor"
if echo "$DMESG" | grep -q 'ipu6.*hardware version'; then
    ok "IPU6 initialisiert:"
    echo "$DMESG" | grep -iE 'ipu6.*(hardware version|authenticate)' | tail -3 | sed 's/^/      /'
else
    bad "Keine IPU6-Initialisierung im Log."
    BLOCKERS+=("IPU6 startet nicht")
fi
lsmod | grep -qE '^intel_ipu6' && ok "Module: $(lsmod | grep -cE '^intel_ipu6|^ipu_bridge') geladen" \
                               || bad "intel_ipu6 nicht geladen"

# --- 2. INT3472 ------------------------------------------------------------
section "2. INT3472-Bridge (Strom, Takt, Reset)"
ls /sys/bus/acpi/devices 2>/dev/null | grep -i INT3472 | sed 's/^/      /' || bad "keine INT3472-Geräte"
GPIO_WARN=$(echo "$DMESG" | grep -iE 'GPIO type 0x[0-9a-f]+ unknown' || true)
if [ -n "$GPIO_WARN" ]; then
    bad "Unbekannter GPIO-Typ - Stromsequenz unvollständig:"
    echo "$GPIO_WARN" | sed 's/^/      /'
    note "Für Typ 0x08 existiert ein Patch (Behandlung als Regulator 'dvdd')."
    BLOCKERS+=("INT3472 GPIO-Typ unbekannt")
else
    ok "Keine GPIO-Warnung - Bridge vollständig ausgewertet."
fi

# --- 3. Sensoren -----------------------------------------------------------
section "3. Sensoren"
ls /sys/bus/acpi/devices 2>/dev/null | grep -iE 'OVTI|SONY|VD55' | sed 's/^/      /' || true
echo
note "Treiberbindung der I2C-Sensoren:"
SENSOR_BOUND=0
for d in /sys/bus/i2c/devices/*; do
    [ -e "$d/name" ] || continue
    n=$(cat "$d/name" 2>/dev/null)
    case "$n" in
        *ov13858*|*OVTID858*|*SONY*|*imx*|*IMX*|*VD55*)
            if [ -L "$d/driver" ]; then
                printf '      \033[32m%-22s → %s\033[0m\n' "$n" "$(basename "$(readlink -f "$d/driver")")"
                SENSOR_BOUND=1
            else
                printf '      \033[31m%-22s → kein Treiber\033[0m\n' "$n"
            fi ;;
    esac
done
[ "$SENSOR_BOUND" = "1" ] || BLOCKERS+=("kein Sensortreiber gebunden")
echo
echo "$DMESG" | grep -iE 'ov13858|imx681|vd55' | tail -5 | sed 's/^/      /' || note "(keine Sensormeldungen)"

# --- 4. Media-Graph --------------------------------------------------------
section "4. Media-Graph (ist der Sensor mit dem ISP verbunden?)"
if command -v media-ctl >/dev/null 2>&1; then
    for m in /dev/media*; do
        [ -e "$m" ] || continue
        ENT=$(media-ctl -d "$m" -p 2>/dev/null | grep -c 'entity ' || echo 0)
        note "$m: $ENT Entities"
        media-ctl -d "$m" -p 2>/dev/null | grep -iE 'entity.*(ov13858|imx|csi|ipu)' | head -8 | sed 's/^/        /'
    done
else
    warn "media-ctl fehlt: sudo apt install v4l-utils"
fi

# --- 5. libcamera ----------------------------------------------------------
section "5. libcamera"
if command -v cam >/dev/null 2>&1; then
    VER=$(cam -l 2>&1 | grep -oE 'libcamera v[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's/libcamera v//')
    if [ -n "$VER" ]; then
        MAJ=${VER%%.*}; REST=${VER#*.}; MIN=${REST%%.*}
        note "Version: $VER"
        # IPU6 support landed in 0.3.2
        if [ "$MAJ" -eq 0 ] && [ "$MIN" -lt 3 ]; then
            bad "ZU ALT für IPU6 - nötig ist mindestens 0.3.2"
            BLOCKERS+=("libcamera $VER zu alt (>= 0.3.2 nötig)")
        else
            ok "Version ausreichend für IPU6"
        fi
    fi
    echo
    cam -l 2>&1 | grep -vE '^\[' | head -10 | sed 's/^/      /'
    cam -l 2>&1 | grep -qiE '^\s*[0-9]+:' && ok "libcamera meldet eine Kamera" \
        || { bad "libcamera findet keine Kamera"; BLOCKERS+=("libcamera erkennt nichts"); }
else
    warn "libcamera-tools fehlt: sudo apt install libcamera-tools"
    BLOCKERS+=("libcamera-tools nicht installiert")
fi

# --- Ergebnis --------------------------------------------------------------
printf '\n\033[1m=== BEFUND ===\033[0m\n'
if [ "${#BLOCKERS[@]}" = "0" ]; then
    echo "  Keine Blocker erkannt - die Kamera sollte ansprechbar sein."
    echo "  Test:  cam -c 1 --capture=5 --file=/tmp/frame#.raw"
else
    echo "  Offene Punkte, in dieser Reihenfolge anzugehen:"
    i=1
    for b in "${BLOCKERS[@]}"; do
        echo "    $i. $b"
        i=$((i+1))
    done
fi
printf '\n  Hintergrund: docs/03-camera-status.md\n\n'
