#!/usr/bin/env bash
# Makes a chosen kernel the GRUB default, so it boots without picking it from
# the menu each time.
#
# On this machine the surface kernel is what the camera needs, and touch works
# there too, so it is the sensible default. The other kernels stay installed
# and remain selectable under "Advanced options".
#
#   status  show which entry currently boots (read-only)
#   set     make the surface kernel the default
#   revert  restore the previous /etc/default/grub
set -euo pipefail

GRUB_CFG=/boot/grub/grub.cfg
GRUB_DEF=/etc/default/grub
BACKUP=/etc/default/grub.bak-surface10pro
PATTERN="${2:-surface}"
ACTION="${1:-status}"

[ -r "$GRUB_CFG" ] || { echo "$GRUB_CFG nicht lesbar." >&2; exit 1; }

# Extract "<submenu id>><menuentry id>" for the newest non-recovery entry
# whose title mentions PATTERN.
#
# python3 rather than awk: match() with three arguments is a GNU awk
# extension and Ubuntu/Zorin ship mawk, where it fails outright.
#
# Nesting is tracked by counting braces, not by a flag: a menu entry inside
# the submenu has its own closing brace, which would otherwise be read as the
# end of the submenu and hide every entry after the first.
find_entry() {
    python3 - "$GRUB_CFG" "$1" <<'GRUBPY'
import re, sys

cfg, pattern = sys.argv[1], sys.argv[2]
id_re = re.compile(r"""\$menuentry_id_option\s+['"]([^'"]+)['"]""")

depth = 0
sub_id = None
sub_depth = None
try:
    with open(cfg, errors="replace") as fh:
        for line in fh:
            stripped = line.strip()
            if stripped.startswith("submenu "):
                m = id_re.search(line)
                sub_id = m.group(1) if m else None
                sub_depth = depth
            elif (stripped.startswith("menuentry ")
                  and sub_id is not None
                  and sub_depth is not None
                  and depth > sub_depth
                  and "recovery mode" not in line
                  and pattern in line):
                m = id_re.search(line)
                if m:
                    print(sub_id + ">" + m.group(1))
                    break
            depth += line.count("{") - line.count("}")
except OSError:
    pass
GRUBPY
}

case "$ACTION" in
  status)
    echo "=== Aktuelle GRUB-Einstellung ==="
    grep -E '^GRUB_DEFAULT|^GRUB_TIMEOUT|^GRUB_SAVEDEFAULT' "$GRUB_DEF" | sed 's/^/  /'
    echo
    echo "=== Installierte Kernel ==="
    ls -1 /boot/vmlinuz-* 2>/dev/null | sed 's|/boot/vmlinuz-|  |'
    echo
    echo "  Aktuell gebootet: $(uname -r)"
    echo
    echo "=== Passender Menüeintrag für '$PATTERN' ==="
    E=$(find_entry "$PATTERN" || true)
    if [ -n "$E" ]; then
        echo "  $E"
    else
        echo "  Kein Eintrag gefunden. Vorhandene Einträge:"
        grep -oP "menuentry '\K[^']+" "$GRUB_CFG" | sed 's/^/    /'
    fi
    echo
    echo "Setzen mit:  sudo bash $0 set"
    ;;

  set)
    E=$(find_entry "$PATTERN" || true)
    if [ -z "$E" ]; then
        echo "Kein Menüeintrag für '$PATTERN' gefunden - nichts geändert." >&2
        echo "Vorhandene Einträge:" >&2
        grep -oP "menuentry '\K[^']+" "$GRUB_CFG" | sed 's/^/  /' >&2
        exit 1
    fi
    echo "Gefundener Eintrag:"
    echo "  $E"
    echo
    echo "Das setzt GRUB_DEFAULT in $GRUB_DEF."
    echo "Alle anderen Kernel bleiben installiert und im Menü wählbar."
    echo "Eine Sicherung wird unter $BACKUP abgelegt."
    read -r -p "Fortfahren? [y/N] " ans
    [ "${ans,,}" = "y" ] || exit 1

    sudo cp -n "$GRUB_DEF" "$BACKUP" 2>/dev/null || true
    echo "==> Sicherung: $BACKUP"

    # Replace or append GRUB_DEFAULT, and make sure saved-default mode is off,
    # since it would override an explicit default.
    sudo sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT="'"$E"'"/' "$GRUB_DEF"
    grep -q '^GRUB_DEFAULT=' "$GRUB_DEF" || \
        echo "GRUB_DEFAULT=\"$E\"" | sudo tee -a "$GRUB_DEF" >/dev/null
    sudo sed -i 's/^GRUB_SAVEDEFAULT=true/GRUB_SAVEDEFAULT=false/' "$GRUB_DEF" 2>/dev/null || true

    echo "==> Neue Einstellung:"
    grep -E '^GRUB_DEFAULT|^GRUB_SAVEDEFAULT' "$GRUB_DEF" | sed 's/^/    /'

    echo "==> update-grub"
    sudo update-grub

    cat <<'MSG'

==> Fertig. Beim nächsten Start bootet der Surface-Kernel automatisch.

    Prüfen nach dem Neustart:   uname -r
    Anderer Kernel bei Bedarf:  im GRUB-Menü "Advanced options"
    Rückgängig:                 sudo bash scripts/40-grub-default.sh revert
MSG
    ;;

  revert)
    [ -f "$BACKUP" ] || { echo "Keine Sicherung unter $BACKUP." >&2; exit 1; }
    sudo cp "$BACKUP" "$GRUB_DEF"
    echo "==> $GRUB_DEF aus Sicherung wiederhergestellt:"
    grep -E '^GRUB_DEFAULT' "$GRUB_DEF" | sed 's/^/    /'
    sudo update-grub
    echo "Erledigt."
    ;;

  *)
    echo "Verwendung: $0 [status|set|revert] [suchmuster]" >&2
    exit 1
    ;;
esac
