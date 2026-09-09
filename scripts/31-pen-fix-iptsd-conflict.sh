#!/usr/bin/env bash
# Reversible experiment: stop iptsd so the native quickspi-hid path has the
# digitizer to itself.
#
# Background: iptsd exists for the older IPTS raw-data path. On kernels that
# drive the digitizer natively through quickspi-hid (THC), running both can
# leave the stylus dead. Nothing is uninstalled here - iptsd is only stopped
# and masked, and the last section undoes it.
set -euo pipefail

if [ "$(id -u)" = "0" ]; then
    echo "Bitte als normaler Benutzer ausführen (sudo wird selbst aufgerufen)." >&2
    exit 1
fi

ACTION="${1:-disable}"

case "$ACTION" in
  disable)
    echo "==> Aktueller iptsd-Zustand"
    systemctl list-units 'iptsd*' --all --no-pager 2>/dev/null | head -8 || true
    pgrep -a iptsd || echo "    (kein Prozess aktiv)"
    echo
    echo "Es wird iptsd gestoppt und maskiert. Das Paket bleibt installiert."
    echo "Rückgängig jederzeit mit:  bash $0 enable"
    read -r -p "Fortfahren? [y/N] " ans
    [ "${ans,,}" = "y" ] || exit 1

    echo "==> iptsd stoppen"
    sudo systemctl stop 'iptsd@*' 2>/dev/null || true
    sudo systemctl stop iptsd 2>/dev/null || true
    sudo pkill -f iptsd 2>/dev/null || true

    echo "==> iptsd maskieren (startet nicht mehr automatisch)"
    sudo systemctl mask 'iptsd@.service' 2>/dev/null || true
    sudo systemctl mask iptsd.service 2>/dev/null || true

    cat <<'MSG'

==> Erledigt. Jetzt testen:

    1. Stift auf dem Bildschirm ausprobieren - zeichnet er?
    2. Falls nein, einmal neu starten und erneut testen:
         sudo reboot
    3. Ereignisse prüfen:
         bash scripts/30-pen-diagnose.sh

    Hilft es nicht, alles zurücknehmen mit:
         bash scripts/31-pen-fix-iptsd-conflict.sh enable
MSG
    ;;

  enable)
    echo "==> Maskierung aufheben und iptsd wieder starten"
    sudo systemctl unmask 'iptsd@.service' 2>/dev/null || true
    sudo systemctl unmask iptsd.service 2>/dev/null || true
    sudo udevadm trigger 2>/dev/null || true
    echo "==> Zustand:"
    systemctl list-units 'iptsd*' --all --no-pager 2>/dev/null | head -8 || true
    echo
    echo "Ausgangszustand wiederhergestellt. Ggf. neu starten: sudo reboot"
    ;;

  *)
    echo "Verwendung: $0 [disable|enable]" >&2
    exit 1
    ;;
esac
