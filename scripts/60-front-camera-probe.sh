#!/usr/bin/env bash
# Explores whether the front sensor (IMX681, ACPI id SONY0681) can be reached
# and whether an existing driver can drive it.
#
# The point is to establish facts before anyone writes code:
#   1. Does INT3472 power the sensor, i.e. does it answer on I2C at all?
#   2. What model id does it report? CCS/SMIA++ sensors expose one at 0x0000.
#   3. Does the kernel's generic MIPI CCS driver bind to it?
#
# If the sensor is CCS compliant, no new driver is needed - only a binding.
# If it stays silent on I2C, the problem is power sequencing, not the driver.
#
#   probe    read-only exploration
#   try-ccs  attempt to bind the generic ccs driver (reversible)
#   revert   undo that binding
set -uo pipefail

ACTION="${1:-probe}"
FRONT_ACPI="SONY0681:00"
CCS_CONF=/etc/modprobe.d/ccs-imx681-surface.conf

section() { printf '\n\033[1m=== %s ===\033[0m\n' "$1"; }
note()    { printf '    %s\n' "$1"; }

find_i2c() {
    # Resolve the ACPI device to its i2c adapter number and address.
    for d in /sys/bus/i2c/devices/*; do
        [ -e "$d/name" ] || continue
        if [ "$(cat "$d/name" 2>/dev/null)" = "$FRONT_ACPI" ]; then
            basename "$d"
            return 0
        fi
    done
    return 1
}

case "$ACTION" in
  probe)
    section "ACPI-Gerät"
    if [ -d "/sys/bus/acpi/devices/$FRONT_ACPI" ]; then
        echo "  ✓ $FRONT_ACPI vorhanden"
        for f in status hid path; do
            [ -r "/sys/bus/acpi/devices/$FRONT_ACPI/$f" ] && \
                note "$f: $(cat "/sys/bus/acpi/devices/$FRONT_ACPI/$f" 2>/dev/null)"
        done
    else
        echo "  ✗ $FRONT_ACPI nicht gefunden - läuft der Surface-Kernel?"
        exit 1
    fi

    section "I2C-Anbindung"
    I2C_DEV=$(find_i2c || true)
    if [ -z "$I2C_DEV" ]; then
        echo "  ✗ Kein I2C-Client für $FRONT_ACPI angelegt."
        note "Ohne I2C-Client kann kein Treiber binden."
        exit 1
    fi
    echo "  ✓ I2C-Client: $I2C_DEV"
    BUS="${I2C_DEV%%-*}"; ADDR_HEX="${I2C_DEV##*-}"
    # Names look like "3-0010": adapter 3, address 0x10.
    BUS=$(echo "$I2C_DEV" | cut -d- -f1)
    ADDR=$(echo "$I2C_DEV" | cut -d- -f2)
    if [ "$BUS" = "i2c" ]; then
        note "Der Client trägt noch den ACPI-Namen, keine Bus-/Adressform."
        note "Das heißt: es ist noch kein Treiber gebunden."
        note "Adresse lässt sich so nicht ableiten - Treiberbindung nötig."
    else
        note "Bus $BUS, Adresse 0x$ADDR"
    fi
    if [ -L "/sys/bus/i2c/devices/$I2C_DEV/driver" ]; then
        note "Treiber: $(basename "$(readlink -f "/sys/bus/i2c/devices/$I2C_DEV/driver")")"
    else
        note "Kein Treiber gebunden."
    fi

    section "Stromversorgung (INT3472)"
    sudo dmesg 2>/dev/null | grep -iE 'INT3472:0[12]' | tail -10 | sed 's/^/      /' \
        || note "keine Meldungen"
    note ""
    note "INT3472:00 versorgt die Rückkamera. Für die Frontkamera ist eine der"
    note "anderen Instanzen zuständig - dort muss ebenfalls ein Regulator"
    note "registriert worden sein, sonst bekommt der Sensor keine Spannung."

    section "Verfügbare generische Treiber"
    for m in ccs ccs-pll; do
        if /usr/sbin/modinfo "$m" >/dev/null 2>&1 || modinfo "$m" >/dev/null 2>&1; then
            echo "  ✓ $m vorhanden"
        else
            echo "  ✗ $m nicht im Kernel"
        fi
    done

    section "Kernelmeldungen zum Frontsensor"
    sudo dmesg 2>/dev/null | grep -iE 'sony0681|imx681' | tail -10 | sed 's/^/      /' \
        || note "keine - kein Treiber versucht zu binden"

    cat <<'MSG'

=== EINSCHÄTZUNG ===
  Entscheidend ist, ob der Sensor auf I2C antwortet. Antwortet er, ist die
  Stromversorgung in Ordnung und es fehlt nur die Ansteuerung - dann lohnt
  der Versuch mit dem generischen CCS-Treiber:

      bash scripts/60-front-camera-probe.sh try-ccs

  Antwortet er nicht, liegt es an der Stromsequenz (INT3472), und ein
  Sensortreiber allein würde nichts ändern.
MSG
    ;;

  try-ccs)
    cat <<'MSG'
Es wird versucht, den generischen MIPI-CCS-Treiber an den Frontsensor zu
binden. CCS ist ein Standard, den viele Sony-Sensoren erfüllen; trifft das
auf den IMX681 zu, wird kein eigener Treiber gebraucht.

Der Versuch ist umkehrbar und verändert nichts dauerhaft, solange du nicht
neu startest. Schlägt er fehl, passiert nichts weiter als eine Fehlermeldung
im Kernel-Log.
MSG
    read -r -p "Fortfahren? [y/N] " ans
    [ "${ans,,}" = "y" ] || exit 1

    echo "==> ccs-Modul laden"
    sudo modprobe ccs 2>/dev/null || { echo "ccs nicht verfügbar." >&2; exit 1; }

    echo "==> ACPI-Bindung für SONY0681 eintragen"
    echo "alias acpi*:SONY0681:* ccs" | sudo tee "$CCS_CONF" >/dev/null
    sudo modprobe -r ccs 2>/dev/null || true
    sudo modprobe ccs

    echo "==> Geräte neu durchsuchen"
    sudo udevadm trigger --subsystem-match=i2c 2>/dev/null || true
    sleep 2

    echo
    echo "=== Ergebnis ==="
    I2C_DEV=$(find_i2c || true)
    if [ -n "$I2C_DEV" ] && [ -L "/sys/bus/i2c/devices/$I2C_DEV/driver" ]; then
        echo "  ✓ Treiber gebunden: $(basename "$(readlink -f "/sys/bus/i2c/devices/$I2C_DEV/driver")")"
    else
        echo "  ✗ Kein Treiber gebunden."
    fi
    echo
    echo "  Kernel-Log dazu:"
    sudo dmesg 2>/dev/null | grep -iE 'ccs|sony0681|imx681' | tail -15 | sed 's/^/      /'
    cat <<'MSG'

Die Meldungen sind der eigentliche Ertrag: Meldet ccs eine gelesene Modell-ID,
antwortet der Sensor und ist grundsätzlich ansprechbar - dann lohnt Weiterarbeit.
Kommt ein Lesefehler (-EIO), fehlt Spannung oder Takt.

Rückgängig:  bash scripts/60-front-camera-probe.sh revert
MSG
    ;;

  revert)
    sudo rm -f "$CCS_CONF"
    sudo modprobe -r ccs 2>/dev/null || true
    echo "Bindung entfernt. Ausgangszustand nach einem Neustart garantiert."
    ;;

  *)
    echo "Verwendung: $0 [probe|try-ccs|revert]" >&2
    exit 1
    ;;
esac
