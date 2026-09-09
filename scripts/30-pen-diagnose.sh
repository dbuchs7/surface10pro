#!/usr/bin/env bash
# Focused stylus diagnostic for Surface Pro 10.
#
# Read-only. Answers three questions:
#   1. Which driver path is actually serving the digitizer?
#   2. Do raw input events arrive when the pen touches the screen?
#   3. Is iptsd interfering with the native quickspi-hid path?
set -uo pipefail

section() { printf '\n\033[1m=== %s ===\033[0m\n' "$1"; }
note()    { printf '    %s\n' "$1"; }

section "Kernel und Digitizer-Module"
uname -r
lsmod 2>/dev/null | grep -iE 'quickspi|thc|ipts|ithc|hid_multitouch|wacom' \
    || note "Keine passenden Module gefunden."

section "Kernelmeldungen zum Digitizer"
sudo dmesg 2>/dev/null | grep -iE 'quickspi|ipts|ithc|thc |045E:0C7F' | tail -20 \
    || note "Keine Meldungen."

section "Eingabegeräte im Detail"
# Full entries so we see which handler (eventN) belongs to which device.
awk '/^I:/{d=""} {d=d $0 "\n"} /^$/{if (d ~ /[Ss]tylus|[Tt]ouchscreen|IPTSD|quickspi/) printf "%s\n", d}' \
    /proc/bus/input/devices 2>/dev/null || note "/proc/bus/input/devices nicht lesbar."

section "iptsd-Zustand"
if dpkg -l 2>/dev/null | grep -q '^ii  iptsd'; then
    note "Paket installiert: $(dpkg -l | awk '/^ii  iptsd/{print $3}')"
    systemctl list-units 'iptsd*' --all --no-pager 2>/dev/null | head -8
    if pgrep -a iptsd >/dev/null 2>&1; then
        printf '  \033[33m!\033[0m iptsd LÄUFT:\n'
        pgrep -a iptsd | sed 's/^/      /'
        note "Auf Kernel >= 7.x mit quickspi-hid ist iptsd in der Regel"
        note "überflüssig und kann den nativen Pfad stören."
    else
        note "Kein iptsd-Prozess aktiv."
    fi
else
    note "iptsd nicht installiert."
fi

section "iptsd: findet es überhaupt ein Gerät?"
# Known issue on the Pro 10 (linux-surface/iptsd#180): iptsd-find-hidraw
# reports no devices because the digitizer runs over QuickSPI as a normal HID
# device, not over the legacy IPTS raw-data path.
if command -v iptsd-find-hidraw >/dev/null 2>&1; then
    OUT=$(sudo iptsd-find-hidraw 2>&1 || true)
    echo "$OUT" | sed 's/^/    /'
    if echo "$OUT" | grep -qi 'no devices'; then
        note ""
        note "→ iptsd findet KEIN Gerät. Auf dem Pro 10 ist das der erwartete"
        note "  Zustand: der Digitizer läuft über QuickSPI als normales"
        note "  HID-Gerät. iptsd ist hier nicht zuständig und kann abgeschaltet"
        note "  werden (scripts/31-pen-fix-iptsd-conflict.sh disable)."
    fi
else
    note "iptsd-find-hidraw nicht vorhanden."
fi

section "iptsd-Protokoll seit dem Start"
journalctl -b -u 'iptsd*' --no-pager 2>/dev/null | tail -25 \
    || note "Keine Journaleinträge (oder keine Berechtigung)."

section "hidraw-Geräte und zugehörige Treiber"
for h in /sys/class/hidraw/hidraw*; do
    [ -e "$h" ] || continue
    dev=$(readlink -f "$h/device" 2>/dev/null || echo "?")
    name=$(cat "$dev/../input"*/name 2>/dev/null | head -1 || cat "$dev/uevent" 2>/dev/null | grep -m1 HID_NAME | cut -d= -f2 || echo "?")
    drv="?"
    [ -L "$dev/driver" ] && drv=$(basename "$(readlink -f "$dev/driver")")
    printf '    %-12s %-34s Treiber: %s\n' "$(basename "$h")" "${name:0:34}" "$drv"
done

section "libwacom-Erkennung"
if command -v libwacom-list-local-devices >/dev/null 2>&1; then
    sudo libwacom-list-local-devices 2>&1 | head -30
else
    note "libwacom-list-local-devices nicht verfügbar."
    note "(Paket libwacom-bin bzw. libwacom-surface)"
fi

section "Sitzungstyp"
note "XDG_SESSION_TYPE = ${XDG_SESSION_TYPE:-unbekannt}"
note "(Wayland und X11 behandeln Tablet-Eingaben unterschiedlich.)"

# --- live event capture ---------------------------------------------------
section "LIVE-TEST: Ereignisse mitschneiden"
if ! command -v libinput >/dev/null 2>&1; then
    note "libinput-tools fehlt: sudo apt install libinput-tools"
    exit 0
fi

cat <<'MSG'

    Gleich werden 20 Sekunden lang alle Eingabe-Ereignisse mitgeschnitten.

    Bitte in dieser Zeit:
      1. mit dem FINGER über den Bildschirm streichen
      2. dann mit dem STIFT aufsetzen und einen Strich ziehen
      3. den Stift knapp über dem Glas schweben lassen

MSG
read -r -p "    Bereit? [Enter drücken zum Start] " _

TMP=$(mktemp)
timeout 20 sudo libinput debug-events > "$TMP" 2>&1 || true

echo
note "Mitgeschnitten: $(wc -l < "$TMP") Zeilen"
echo

TOUCH=$(grep -cE 'TOUCH_(DOWN|MOTION|UP)' "$TMP" 2>/dev/null || echo 0)
TABLET=$(grep -cE 'TABLET_TOOL' "$TMP" 2>/dev/null || echo 0)
POINTER=$(grep -cE 'POINTER_MOTION' "$TMP" 2>/dev/null || echo 0)

printf '    Finger/Touch-Ereignisse : %s\n' "$TOUCH"
printf '    Stift/Tablet-Ereignisse : %s\n' "$TABLET"
printf '    Zeiger-Ereignisse       : %s\n' "$POINTER"
echo
note "Beispielzeilen (Stift):"
grep -E 'TABLET_TOOL' "$TMP" 2>/dev/null | head -8 | sed 's/^/      /' \
    || note "  (keine)"

printf '\n\033[1m=== BEFUND ===\033[0m\n'
if [ "$TABLET" -gt 0 ]; then
    echo "  Der Stift LIEFERT Ereignisse auf Treiberebene."
    echo "  → Das Problem liegt weiter oben: Desktop/Anwendung, Zuordnung"
    echo "    zum Bildschirm, oder libwacom-Definition."
elif [ "$TOUCH" -gt 0 ]; then
    echo "  Touch funktioniert, der Stift liefert NICHTS."
    echo "  → Digitizer arbeitet grundsätzlich. Verdächtig: Stift ohne"
    echo "    Ladung/nicht gekoppelt, oder iptsd blockiert den Stiftpfad."
else
    echo "  WEDER Touch NOCH Stift liefern Ereignisse."
    echo "  → Der Digitizer-Pfad selbst ist gestört. Verdächtig: Konflikt"
    echo "    zwischen iptsd und quickspi-hid."
fi
echo
note "Rohmitschnitt liegt unter: $TMP"
