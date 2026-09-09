#!/usr/bin/env bash
# Tests the GRUB menu-entry extraction of scripts/40-grub-default.sh against
# synthetic grub.cfg files. Run from anywhere: bash tests/test_grub_default.sh
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/../scripts/40-grub-default.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAIL=0

# Pull find_entry out of the real script so the test exercises shipped code.
eval "$(sed -n '/^find_entry() {/,/^}/p' "$SCRIPT")"

chk() { # name expected actual
    if [ "$2" = "$3" ]; then
        echo "  PASS  $1"
    else
        echo "  FAIL  $1"
        echo "        erwartet: $2"
        echo "        erhalten: $3"
        FAIL=1
    fi
}

# --- Fixture 1: typical Ubuntu/Zorin layout, two kernels plus recovery -----
GRUB_CFG="$HERE/fixtures-grub.cfg"
chk "Surface-Kernel gefunden, Recovery übersprungen" \
    "gnulinux-advanced-1234-abcd>gnulinux-6.19.8-surface-3-advanced-1234-abcd" \
    "$(find_entry surface)"
chk "Mainline über anderes Suchmuster" \
    "gnulinux-advanced-1234-abcd>gnulinux-7.1.2-070102-generic-advanced-1234-abcd" \
    "$(find_entry 7.1.2)"
chk "unbekanntes Muster liefert leer" "" "$(find_entry nichtvorhanden)"

# --- Fixture 2: double quotes instead of single ----------------------------
GRUB_CFG="$TMP/quotes.cfg"
cat > "$GRUB_CFG" <<'CFG'
submenu "Advanced options" $menuentry_id_option "gnulinux-advanced-xyz" {
	menuentry "Zorin, with Linux 6.19.8-surface-3" $menuentry_id_option "gnulinux-6.19.8-surface-3-advanced-xyz" {
	}
}
CFG
chk "doppelte Anführungszeichen" \
    "gnulinux-advanced-xyz>gnulinux-6.19.8-surface-3-advanced-xyz" \
    "$(find_entry surface)"

# --- Fixture 3: surface entry last, after several others -------------------
# Regression guard: a flag-based nesting check lost every entry after the first.
GRUB_CFG="$TMP/many.cfg"
cat > "$GRUB_CFG" <<'CFG'
submenu 'Advanced options' $menuentry_id_option 'gnulinux-advanced-m' {
	menuentry 'Zorin, with Linux 9.0.0-generic' $menuentry_id_option 'gnulinux-9.0.0-generic-advanced-m' {
		linux /vmlinuz-9.0.0
	}
	menuentry 'Zorin, with Linux 8.0.0-generic' $menuentry_id_option 'gnulinux-8.0.0-generic-advanced-m' {
		linux /vmlinuz-8.0.0
	}
	menuentry 'Zorin, with Linux 6.19.8-surface-3' $menuentry_id_option 'gnulinux-6.19.8-surface-3-advanced-m' {
		linux /vmlinuz-6.19.8-surface-3
	}
}
CFG
chk "Eintrag an dritter Stelle wird gefunden" \
    "gnulinux-advanced-m>gnulinux-6.19.8-surface-3-advanced-m" \
    "$(find_entry surface)"

echo
if [ "$FAIL" = "0" ]; then echo "ALLE TESTS BESTANDEN"; else echo "FEHLGESCHLAGEN"; exit 1; fi
