#!/usr/bin/env bash
# Investigates which HID driver serves the digitizer, and optionally tries to
# hand it to hid-multitouch.
#
# Background: dmesg shows hid-generic claiming the device, and touch arrives
# without any ABS_MT_* axes - the signature of a naive HID parse. Windows
# Precision digitizers are normally served by hid-multitouch, which is also
# what understands the pen collections. If the HID core failed to classify
# this device as multitouch, that would explain touch working crudely while
# the pen produces nothing.
#
# "status" and "rdesc" are read-only. "try" changes the binding and can leave
# touch inoperative until "revert" or a reboot - it asks first.
set -uo pipefail

ACTION="${1:-status}"
HID_ID=""

find_hid_id() {
    for d in /sys/bus/hid/devices/*045E:0C7F*; do
        [ -e "$d" ] && { HID_ID=$(basename "$d"); return 0; }
    done
    return 1
}

if ! find_hid_id; then
    echo "Kein HID-Gerät 045E:0C7F gefunden." >&2
    exit 1
fi

current_driver() {
    local link="/sys/bus/hid/devices/$HID_ID/driver"
    [ -L "$link" ] && basename "$(readlink -f "$link")" || echo "(keiner)"
}

case "$ACTION" in
  status)
    echo "=== HID-Gerät ==="
    echo "  ID:      $HID_ID"
    echo "  Treiber: $(current_driver)"
    echo
    echo "=== Verfügbare HID-Treiber ==="
    ls /sys/bus/hid/drivers/ | sed 's/^/  /'
    echo
    echo "=== Eingabegeräte dieses HID-Geräts ==="
    for i in /sys/bus/hid/devices/"$HID_ID"/input/input*; do
        [ -e "$i" ] || continue
        printf '  %-12s %s\n' "$(basename "$i")" "$(cat "$i/name" 2>/dev/null)"
    done
    echo
    echo "Hinweis: erwartet würde hid-multitouch. Steht dort hid-generic,"
    echo "hat der HID-Kern das Gerät nicht als Multitouch/Digitizer erkannt."
    echo
    echo "Weiter mit:"
    echo "  bash $0 rdesc    # Report-Deskriptor ansehen (nur lesen)"
    echo "  bash $0 try      # hid-multitouch zuweisen (umkehrbar)"
    ;;

  rdesc)
    # The descriptor settles whether the device declares a pen at all.
    if [ ! -d /sys/kernel/debug/hid ]; then
        echo "debugfs nicht eingehängt. Einmalig:"
        echo "  sudo mount -t debugfs none /sys/kernel/debug"
        exit 1
    fi
    D="/sys/kernel/debug/hid/$HID_ID"
    [ -d "$D" ] || { echo "Kein debugfs-Eintrag für $HID_ID" >&2; exit 1; }
    echo "=== Report-Deskriptor ($HID_ID) ==="
    sudo cat "$D/rdesc" 2>/dev/null
    echo
    echo "=== Interpretation ==="
    RD=$(sudo cat "$D/rdesc" 2>/dev/null)
    # Usage page 0x0D is Digitizers; usage 0x02 Pen, 0x20 Stylus, 0x04 Touch Screen
    echo "$RD" | grep -qi '0d' && echo "  Digitizer-Usage-Page (0x0D) vorhanden" \
                              || echo "  KEINE Digitizer-Usage-Page gefunden"
    echo "$RD" | grep -qiE 'Stylus|Pen' && echo "  Stift-Usage im Klartext gefunden" || true
    echo
    echo "Bitte diese Ausgabe teilen - daraus lässt sich ablesen, ob das Gerät"
    echo "eine Stift-Funktion überhaupt deklariert."
    ;;

  try)
    echo "Aktueller Treiber: $(current_driver)"
    cat <<'MSG'

Es wird versucht, das Gerät von hid-generic zu lösen und hid-multitouch
zuzuweisen.

WICHTIG: Währenddessen kann der Touchscreen ausfallen. Rückgängig mit
"revert" oder schlicht einem Neustart - die Änderung ist nicht dauerhaft.
Am besten eine Maus oder Tastatur bereithalten.
MSG
    read -r -p "Fortfahren? [y/N] " ans
    [ "${ans,,}" = "y" ] || exit 1

    echo "==> hid-multitouch laden"
    sudo modprobe hid-multitouch 2>/dev/null || true

    echo "==> Von aktuellem Treiber lösen"
    CUR=$(current_driver)
    if [ "$CUR" != "(keiner)" ]; then
        echo "$HID_ID" | sudo tee "/sys/bus/hid/drivers/$CUR/unbind" >/dev/null 2>&1 || true
    fi
    sleep 1

    echo "==> hid-multitouch für 045E:0C7F registrieren"
    # HID new_id format: bus vendor product (hex)
    echo "0001 045E 0C7F" | sudo tee /sys/bus/hid/drivers/hid-multitouch/new_id >/dev/null 2>&1 || true
    sleep 1
    echo "$HID_ID" | sudo tee /sys/bus/hid/drivers/hid-multitouch/bind >/dev/null 2>&1 || true
    sleep 2

    echo
    echo "Neuer Treiber: $(current_driver)"
    echo
    echo "Neue Eingabegeräte:"
    for i in /sys/bus/hid/devices/"$HID_ID"/input/input*; do
        [ -e "$i" ] || continue
        printf '  %-12s %s\n' "$(basename "$i")" "$(cat "$i/name" 2>/dev/null)"
    done
    cat <<'MSG'

Jetzt testen:
  sudo python3 scripts/34-input-monitor.py

Zurück zum Ausgangszustand:
  bash scripts/36-hid-driver-probe.sh revert     (oder einfach neu starten)
MSG
    ;;

  revert)
    CUR=$(current_driver)
    echo "==> Von $CUR lösen"
    if [ "$CUR" != "(keiner)" ]; then
        echo "$HID_ID" | sudo tee "/sys/bus/hid/drivers/$CUR/unbind" >/dev/null 2>&1 || true
    fi
    sleep 1
    echo "==> An hid-generic zurückgeben"
    echo "$HID_ID" | sudo tee /sys/bus/hid/drivers/hid-generic/bind >/dev/null 2>&1 || true
    sleep 1
    echo "Treiber jetzt: $(current_driver)"
    echo "Falls der Touchscreen nicht zurückkommt: neu starten, dann ist alles wie vorher."
    ;;

  *)
    echo "Verwendung: $0 [status|rdesc|try|revert]" >&2
    exit 1
    ;;
esac
