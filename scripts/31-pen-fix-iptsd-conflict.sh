#!/usr/bin/env bash
# Disable iptsd on the Surface Pro 10, where it is not just unnecessary but
# actively fatal.
#
# Why: iptsd switches the digitizer into raw/heatmap mode. In that mode the
# device emits reports of ~4356 bytes, larger than the 4096-byte DMA buffer of
# the intel_quickspi driver:
#
#   intel_quickspi: Copied 4096 bytes instead of requested 4356
#   intel_quickspi: read DMA buffer failed -5
#   intel_quickspi: Wait RESET_RESPONSE timeout, ret:0
#   intel_quickspi: Reset touch device failed, ret = -110
#
# The driver then resets the touch controller, the reset times out, and both
# touch and stylus are dead until reboot. Activating the pen triggers such a
# large report, which is why taking the stylus off the charger kills input.
#
# The Pro 10 digitizer (045E:0C7F) runs in QuickSPI mode and is natively
# supported since kernel 6.14 - iptsd has no role here.
#
# Nothing is uninstalled. "enable" restores the original state.
set -euo pipefail

if [ "$(id -u)" = "0" ]; then
    echo "Bitte als normaler Benutzer ausführen (sudo wird selbst aufgerufen)." >&2
    exit 1
fi

UDEV_OVERRIDE=/etc/udev/rules.d/99-iptsd-disabled.rules
ACTION="${1:-disable}"

show_state() {
    echo "--- Aktueller Zustand ---"
    systemctl list-units 'iptsd*' --all --no-pager 2>/dev/null | grep -E 'iptsd|UNIT' || echo "  (keine iptsd-Units aktiv)"
    if pgrep -a iptsd >/dev/null 2>&1; then
        echo "  Laufende Prozesse:"
        pgrep -a iptsd | sed 's/^/    /'
    else
        echo "  Kein iptsd-Prozess aktiv."
    fi
    echo "-------------------------"
}

case "$ACTION" in
  disable)
    show_state
    echo
    echo "iptsd wird gestoppt, maskiert und per udev-Regel am Neustart gehindert."
    echo "Das Paket bleibt installiert. Rückgängig mit:  bash $0 enable"
    read -r -p "Fortfahren? [y/N] " ans
    [ "${ans,,}" = "y" ] || exit 1

    echo "==> Laufende Instanzen stoppen"
    # Stop every concrete instance, not just the template.
    for unit in $(systemctl list-units 'iptsd@*' --all --no-legend 2>/dev/null | awk '{print $1}'); do
        echo "    stoppe $unit"
        sudo systemctl stop "$unit" 2>/dev/null || true
        sudo systemctl disable "$unit" 2>/dev/null || true
        sudo systemctl mask "$unit" 2>/dev/null || true
    done
    sudo systemctl stop iptsd.service 2>/dev/null || true

    echo "==> Template maskieren"
    sudo systemctl mask 'iptsd@.service' 2>/dev/null || true
    sudo systemctl mask iptsd.service 2>/dev/null || true

    echo "==> udev-Regel neutralisieren"
    # The packaged rule tags the hidraw node so systemd starts iptsd@<dev>.
    # A later-sorting rule removes that tag again.
    sudo tee "$UDEV_OVERRIDE" >/dev/null <<'RULE'
# Disabled on Surface Pro 10: iptsd puts the digitizer into raw mode, whose
# report size exceeds the intel_quickspi DMA buffer and kills touch + stylus.
# The digitizer is served natively by quickspi-hid.
SUBSYSTEM=="hidraw", ENV{SYSTEMD_WANTS}=""
RULE
    sudo udevadm control --reload-rules 2>/dev/null || true

    echo "==> Reste beenden"
    sudo pkill -f iptsd 2>/dev/null || true
    sleep 1

    echo
    show_state
    cat <<'MSG'

==> Erledigt. Jetzt neu starten und den 6.19.8-surface-Kernel wählen:

      sudo reboot

    Nach dem Neustart PRÜFEN, dass iptsd wirklich weg ist:

      pgrep -a iptsd        # darf nichts ausgeben
      dmesg | grep -i quickspi   # keine DMA-/Reset-Fehler mehr

    Dann Finger UND Stift testen - diesmal den Stift bewusst aus der
    Ladestation nehmen, das war bisher der Auslöser.
MSG
    ;;

  enable)
    echo "==> Maskierungen aufheben"
    for unit in $(systemctl list-unit-files 'iptsd*' --no-legend 2>/dev/null | awk '{print $1}'); do
        sudo systemctl unmask "$unit" 2>/dev/null || true
    done
    sudo systemctl unmask 'iptsd@.service' 2>/dev/null || true
    sudo systemctl unmask iptsd.service 2>/dev/null || true

    echo "==> udev-Regel entfernen"
    sudo rm -f "$UDEV_OVERRIDE"
    sudo udevadm control --reload-rules 2>/dev/null || true
    sudo udevadm trigger 2>/dev/null || true

    echo
    show_state
    echo "Ausgangszustand wiederhergestellt. Für volle Wirkung neu starten."
    ;;

  status)
    show_state
    ;;

  *)
    echo "Verwendung: $0 [disable|enable|status]" >&2
    exit 1
    ;;
esac
