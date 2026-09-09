#!/usr/bin/env bash
# Deep stylus test: does the KERNEL deliver pen events at all?
#
# Read-only. Reads directly from the evdev nodes, bypassing libinput and the
# desktop, so the failure can be placed on one side of that line:
#
#   bytes arrive  -> kernel is fine, problem is libinput/desktop/mapping
#   nothing       -> driver or hardware level
set -uo pipefail

section() { printf '\n\033[1m=== %s ===\033[0m\n' "$1"; }
note()    { printf '    %s\n' "$1"; }

section "Alle quickspi-Eingabegeräte mit Fähigkeiten"
# Parse /proc/bus/input/devices into: event node, name, EV bitmask, key bits.
awk '
/^I: /{name=""; handlers=""; ev=""; abs=""; key=""}
/^N: Name=/{gsub(/^N: Name="|"$/,""); name=$0}
/^H: Handlers=/{sub(/^H: Handlers=/,""); handlers=$0}
/^B: EV=/{sub(/^B: EV=/,""); ev=$0}
/^B: ABS=/{sub(/^B: ABS=/,""); abs=$0}
/^B: KEY=/{sub(/^B: KEY=/,""); key=$0}
/^$/{
  if (name ~ /quickspi|IPTSD|Stylus|Touchscreen/) {
    ev_node="?"
    n=split(handlers,h," ")
    for(i=1;i<=n;i++) if (h[i] ~ /^event/) ev_node=h[i]
    printf "  %-10s  %-40s EV=%s\n", ev_node, substr(name,1,40), ev
    if (abs != "") printf "              ABS=%s\n", abs
    if (key != "") printf "              KEY=%s\n", substr(key,1,60)
  }
}' /proc/bus/input/devices

note ""
note "EV=b bedeutet SYN+KEY+ABS -> typisch für Touch/Stift."
note "Ein Stiftgerät sollte ABS-Bits für Druck (ABS_PRESSURE) haben."

# --- find candidate event nodes -------------------------------------------
mapfile -t NODES < <(awk '
/^I: /{name=""; handlers=""}
/^N: Name=/{gsub(/^N: Name="|"$/,""); name=$0}
/^H: Handlers=/{sub(/^H: Handlers=/,""); handlers=$0}
/^$/{
  if (name ~ /quickspi/) {
    n=split(handlers,h," ")
    for(i=1;i<=n;i++) if (h[i] ~ /^event/) print h[i] "|" name
  }
}' /proc/bus/input/devices)

if [ "${#NODES[@]}" = "0" ]; then
    echo
    echo "Keine quickspi-Eingabegeräte gefunden - hier stimmt etwas Grundlegendes nicht."
    exit 1
fi

section "ROHTEST: liefert der Kernel Bytes?"
cat <<'MSG'

    Es wird 15 Sekunden lang DIREKT von allen quickspi-Geräten gelesen -
    ohne libinput, ohne Desktop.

    Bitte in dieser Zeit NUR MIT DEM STIFT arbeiten:
      - Stift aufsetzen und mehrere Striche ziehen
      - Stift knapp über dem Glas schweben lassen
      - Seitentaste drücken

    Den Finger diesmal NICHT benutzen - sonst ist nicht unterscheidbar,
    welches Gerät die Daten geliefert hat.

MSG
read -r -p "    Bereit? [Enter zum Start] " _

declare -A BYTES
TMPDIR_=$(mktemp -d)

for entry in "${NODES[@]}"; do
    node="${entry%%|*}"
    [ -r "/dev/input/$node" ] || sudo chmod a+r "/dev/input/$node" 2>/dev/null || true
    ( timeout 15 sudo cat "/dev/input/$node" > "$TMPDIR_/$node" 2>/dev/null || true ) &
done

echo "    ... 15 Sekunden lang mit dem Stift arbeiten ..."
wait
echo

printf '\033[1m    Ergebnis je Gerät:\033[0m\n'
TOTAL=0
for entry in "${NODES[@]}"; do
    node="${entry%%|*}"
    name="${entry#*|}"
    size=$(stat -c %s "$TMPDIR_/$node" 2>/dev/null || echo 0)
    TOTAL=$((TOTAL + size))
    if [ "$size" -gt 0 ]; then
        printf '      \033[32m%-10s %6s Byte\033[0m  %s\n' "$node" "$size" "$name"
    else
        printf '      %-10s %6s Byte  %s\n' "$node" "$size" "$name"
    fi
done

section "BEFUND"
if [ "$TOTAL" -gt 0 ]; then
    echo "  Der KERNEL liefert Stift-Daten ($TOTAL Byte)."
    echo "  → Die Treiberebene ist in Ordnung. Das Problem liegt darüber:"
    echo "    libinput, libwacom-Definition, oder die Zuordnung im Desktop."
    echo "    Nächster Schritt: libwacom prüfen und Sitzungstyp (Wayland/X11)."
else
    echo "  Der Kernel liefert NICHTS, während der Stift benutzt wird."
    echo "  → Der Digitizer meldet den Stift nicht. Möglichkeiten:"
    echo "    - Stift wird vom Digitizer nicht erkannt (Protokoll/Firmware)"
    echo "    - Stift-Meldungen kommen auf einem HID-Report, den der Treiber"
    echo "      nicht auswertet"
    echo "    - Hardware-/Kompatibilitätsproblem des konkreten Stifts"
fi

echo
note "Zum Vergleich derselbe Test mit dem FINGER (Touch funktioniert ja):"
note "  bash $0 --touch"
rm -rf "$TMPDIR_"
