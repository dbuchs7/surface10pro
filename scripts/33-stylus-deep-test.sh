#!/usr/bin/env bash
# Does the KERNEL deliver stylus events at all?
#
# Reads directly from the evdev nodes, bypassing libinput and the desktop, to
# place the failure on one side of that boundary:
#
#   bytes arrive  -> kernel fine, problem is libinput/libwacom/desktop
#   nothing       -> driver, protocol, or pen
#
# A negative result means nothing without a positive control, so run it twice:
#
#   bash 33-stylus-deep-test.sh pen      (default)
#   bash 33-stylus-deep-test.sh touch    (control - touch is known to work)
#
# If the touch run also reports zero, the measurement is broken, not the pen.
set -uo pipefail

MODE="${1:-pen}"
case "$MODE" in
  pen|stylus) MODE=pen ;;
  touch|finger|control) MODE=touch ;;
  *) echo "Verwendung: $0 [pen|touch]" >&2; exit 1 ;;
esac

section() { printf '\n\033[1m=== %s ===\033[0m\n' "$1"; }
note()    { printf '    %s\n' "$1"; }

# --- make sure sudo works up front ----------------------------------------
# Previously sudo ran only inside backgrounded subshells, where a password
# prompt fails silently and every node reports zero bytes regardless of input.
section "Vorbedingungen"
if ! sudo -v; then
    echo "sudo nicht verfügbar - der Test kann nicht lesen. Abbruch." >&2
    exit 1
fi
note "sudo verfügbar."
# Keep the credential fresh while the capture runs.
( while true; do sudo -n true 2>/dev/null; sleep 30; done ) &
SUDO_KEEPALIVE=$!
trap 'kill "$SUDO_KEEPALIVE" 2>/dev/null || true' EXIT

section "quickspi-Eingabegeräte"
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
    echo "Keine quickspi-Geräte gefunden - hier stimmt etwas Grundlegendes nicht." >&2
    exit 1
fi

# Verify each node is actually readable, so "no data" cannot be confused with
# "could not open".
READABLE=0
for entry in "${NODES[@]}"; do
    node="${entry%%|*}"
    if sudo -n test -r "/dev/input/$node" 2>/dev/null; then
        printf '  \033[32m✓\033[0m %-10s lesbar\n' "$node"
        READABLE=$((READABLE + 1))
    else
        printf '  \033[31m✗\033[0m %-10s NICHT lesbar\n' "$node"
    fi
done
note "$READABLE von ${#NODES[@]} Knoten lesbar."
if [ "$READABLE" = "0" ]; then
    echo "Kein Knoten lesbar - Messung nicht möglich." >&2
    exit 1
fi

# --- capture ---------------------------------------------------------------
if [ "$MODE" = "pen" ]; then
    section "MESSUNG: Stift"
    cat <<'MSG'

    15 Sekunden lang wird direkt von allen quickspi-Geräten gelesen.

    Bitte NUR MIT DEM STIFT arbeiten:
      - aufsetzen und mehrere Striche ziehen
      - knapp über dem Glas schweben lassen
      - Seitentaste drücken

    Den Finger NICHT benutzen.

MSG
else
    section "MESSUNG: Finger (Kontrolle)"
    cat <<'MSG'

    15 Sekunden lang wird direkt von allen quickspi-Geräten gelesen.

    Bitte NUR MIT DEM FINGER arbeiten - streichen, tippen, wischen.
    Den Stift weglegen.

    Das ist die Positivkontrolle: Touch funktioniert nachweislich, hier MUSS
    also etwas ankommen. Bleibt auch das bei null, misst der Test nicht
    richtig und das Stiftergebnis ist bedeutungslos.

MSG
fi
read -r -p "    Bereit? [Enter zum Start] " _

TMPD=$(mktemp -d)
for entry in "${NODES[@]}"; do
    node="${entry%%|*}"
    ( sudo -n timeout 15 cat "/dev/input/$node" > "$TMPD/$node" 2>/dev/null || true ) &
done
echo "    ... 15 Sekunden ..."
wait
echo

printf '\033[1m    Ergebnis je Gerät (%s):\033[0m\n' "$MODE"
TOTAL=0
for entry in "${NODES[@]}"; do
    node="${entry%%|*}"; name="${entry#*|}"
    size=$(stat -c %s "$TMPD/$node" 2>/dev/null || echo 0)
    TOTAL=$((TOTAL + size))
    if [ "$size" -gt 0 ]; then
        printf '      \033[32m%-10s %7s Byte\033[0m  %s\n' "$node" "$size" "$name"
    else
        printf '      %-10s %7s Byte  %s\n' "$node" "$size" "$name"
    fi
done
rm -rf "$TMPD"

section "BEFUND ($MODE)"
if [ "$MODE" = "touch" ]; then
    if [ "$TOTAL" -gt 0 ]; then
        echo "  Kontrolle bestanden: der Test misst korrekt ($TOTAL Byte)."
        echo "  → Ein Nullergebnis beim Stift ist damit belastbar."
    else
        echo "  Kontrolle FEHLGESCHLAGEN: auch Touch liefert nichts,"
        echo "  obwohl Touch funktioniert."
        echo "  → Der Test misst nicht richtig. Ein Nullergebnis beim Stift"
        echo "    sagt in dem Fall NICHTS aus."
    fi
else
    if [ "$TOTAL" -gt 0 ]; then
        echo "  Der Kernel liefert Stift-Daten ($TOTAL Byte)."
        echo "  → Treiberebene in Ordnung, Problem liegt darüber:"
        echo "    libinput, libwacom, oder Zuordnung im Desktop."
    else
        echo "  Der Kernel liefert nichts, während der Stift benutzt wird."
        echo
        echo "  WICHTIG: erst mit der Kontrolle absichern, sonst ist das"
        echo "  Ergebnis wertlos:"
        echo "      bash $0 touch"
    fi
fi
echo
