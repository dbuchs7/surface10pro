#!/usr/bin/env bash
# Extracts the camera-relevant parts of the ACPI tables on a Surface Pro 10.
#
# Read-only with respect to the system; writes only into an output directory.
# The result is the raw material needed to work out how the camera sensors are
# actually wired (GPIOs, clocks, regulators, CSI-2 ports) - the prerequisite
# for any sensor-enabling work.
set -euo pipefail

OUT="${1:-$HOME/surface-acpi}"

if ! command -v acpidump >/dev/null 2>&1 || ! command -v iasl >/dev/null 2>&1; then
    echo "Es fehlen Werkzeuge. Installieren mit:"
    echo "  sudo apt install acpica-tools"
    exit 1
fi

mkdir -p "$OUT"
cd "$OUT"

echo "==> ACPI-Tabellen auslesen nach $OUT"
sudo acpidump -b

echo "==> Tabellen dekompilieren (Fehler bei Nebentabellen sind normal)"
iasl -d ./*.dat >/dev/null 2>&1 || true

if [ ! -f dsdt.dsl ] && [ ! -f DSDT.dsl ]; then
    echo "DSDT konnte nicht dekompiliert werden - bitte Ausgabe von 'ls' hier prüfen:"
    ls -la
    exit 1
fi

DSDT=$(ls dsdt.dsl DSDT.dsl 2>/dev/null | head -1)

echo "==> Kamera-relevante Abschnitte extrahieren"
SUMMARY="$OUT/camera-acpi-summary.txt"
{
    echo "# Kamera-relevante ACPI-Auszüge"
    echo "# Gerät: $(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unbekannt)"
    echo "# Kernel: $(uname -r)"
    echo "# Erzeugt: $(date -Is)"
    echo

    echo "## Treffer nach Suchbegriff"
    for term in IMX681 OV13858 OV13B10 VD55G0 INT3472 INT3474 OVTI SONY LATT; do
        count=$(grep -c "$term" "$DSDT" 2>/dev/null || echo 0)
        printf '  %-10s %s Treffer\n' "$term" "$count"
    done
    echo

    echo "## Device-Blöcke mit Kamerabezug (mit Kontext)"
    for term in IMX681 OV13858 VD55G0 INT3472; do
        if grep -q "$term" "$DSDT" 2>/dev/null; then
            echo
            echo "### $term"
            grep -n -B 5 -A 60 "$term" "$DSDT" | head -200
        fi
    done
    echo

    echo "## _DSM-Methoden (GPIO-/Clock-Mapping der Bridge)"
    grep -n -A 30 '_DSM' "$DSDT" | grep -iE '_DSM|79234640|GPIO|CLK|Package|Return' | head -80
} > "$SUMMARY" 2>/dev/null

echo
echo "==> Fertig."
echo "    Vollständige Tabellen : $OUT"
echo "    Zusammenfassung       : $SUMMARY"
echo
echo "Diese Zusammenfassung ist die richtige Datei zum Teilen für die Analyse."
echo "Sie enthält nur Hardware-Beschreibungen, keine persönlichen Daten."
echo
head -20 "$SUMMARY"
