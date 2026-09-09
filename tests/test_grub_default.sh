set -uo pipefail
SCRIPT=/home/user/surface10pro/scripts/40-grub-default.sh
# find_entry aus dem echten Skript extrahieren und gegen die Test-grub.cfg laufen lassen
GRUB_CFG=$(dirname "$0")/fixtures-grub.cfg
eval "$(sed -n '/^find_entry() {/,/^}/p' "$SCRIPT")"

FAIL=0
chk() { # name erwartet erhalten
  if [ "$2" = "$3" ]; then echo "  PASS  $1"
  else echo "  FAIL  $1"; echo "        erwartet: $2"; echo "        erhalten: $3"; FAIL=1; fi
}
chk "Surface-Kernel, kein Recovery" \
    "gnulinux-advanced-1234-abcd>gnulinux-6.19.8-surface-3-advanced-1234-abcd" \
    "$(find_entry surface)"
chk "Mainline über anderes Muster" \
    "gnulinux-advanced-1234-abcd>gnulinux-7.1.2-070102-generic-advanced-1234-abcd" \
    "$(find_entry 7.1.2)"
chk "unbekanntes Muster liefert leer" "" "$(find_entry nichtvorhanden)"

# Sonderfall: grub.cfg mit doppelten Anfuehrungszeichen statt einfachen
cat > /tmp/grub2-test.cfg <<'CFG'
submenu "Advanced options" $menuentry_id_option "gnulinux-advanced-xyz" {
	menuentry "Zorin, with Linux 6.19.8-surface-3" $menuentry_id_option "gnulinux-6.19.8-surface-3-advanced-xyz" {
	}
}
CFG
GRUB_CFG=/tmp/grub2-test.cfg
chk "doppelte Anführungszeichen" \
    "gnulinux-advanced-xyz>gnulinux-6.19.8-surface-3-advanced-xyz" \
    "$(find_entry surface)"

echo
[ "$FAIL" = "0" ] && echo "ALLE TESTS BESTANDEN" || exit 1
