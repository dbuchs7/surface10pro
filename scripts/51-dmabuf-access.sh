#!/usr/bin/env bash
# Grants access to a dma-buf provider so libcamera's software ISP can run.
#
# Why: libcamera 0.7.2 detects the rear camera on this machine, but reports
#   ERROR DmaBufAllocator: Could not open any dma-buf provider
#   ERROR SoftwareIsp: Failed to create DmaBufAllocator object
#   WARN  SimplePipeline: Failed to create software ISP, disabling software debayering
# The software ISP turns the sensor's raw Bayer data into a usable image, so
# without it there is no picture. It needs /dev/dma_heap/system or /dev/udmabuf,
# and both are root-only by default.
#
#   status   show what exists and who may use it (read-only)
#   grant    load udmabuf if needed and add a udev rule for group video
#   revoke   remove that rule again
set -euo pipefail

RULE=/etc/udev/rules.d/99-libcamera-dmabuf.rules
ACTION="${1:-status}"

show() {
    echo "=== dma-buf-Anbieter ==="
    if [ -d /dev/dma_heap ]; then
        ls -l /dev/dma_heap/ | sed 's/^/  /'
    else
        echo "  /dev/dma_heap fehlt"
    fi
    if [ -e /dev/udmabuf ]; then
        ls -l /dev/udmabuf | sed 's/^/  /'
    else
        echo "  /dev/udmabuf fehlt (Modul udmabuf nicht geladen?)"
    fi
    echo
    echo "=== Deine Gruppen ==="
    echo "  $(id -nG)"
    echo
    echo "=== Zugriff möglich? ==="
    local any=0
    for d in /dev/dma_heap/system /dev/dma_heap/linux,cma /dev/udmabuf; do
        [ -e "$d" ] || continue
        if [ -r "$d" ] && [ -w "$d" ]; then
            echo "  ✓ $d les- und schreibbar"
            any=1
        else
            echo "  ✗ $d vorhanden, aber kein Zugriff"
        fi
    done
    [ "$any" = "1" ] || echo "  → Kein nutzbarer Anbieter. 'grant' behebt das."
}

case "$ACTION" in
  status)
    show
    echo
    echo "Rechte vergeben mit:  bash $0 grant"
    ;;

  grant)
    show
    echo
    echo "Es wird das Modul udmabuf geladen (falls nötig) und eine udev-Regel"
    echo "angelegt, die der Gruppe 'video' Zugriff auf die dma-buf-Knoten gibt."
    echo "Rückgängig mit:  bash $0 revoke"
    read -r -p "Fortfahren? [y/N] " ans
    [ "${ans,,}" = "y" ] || exit 1

    echo "==> udmabuf laden und dauerhaft eintragen"
    sudo modprobe udmabuf 2>/dev/null || echo "  (udmabuf nicht verfügbar - dma_heap reicht ggf. aus)"
    echo udmabuf | sudo tee /etc/modules-load.d/udmabuf.conf >/dev/null

    echo "==> udev-Regel schreiben"
    sudo tee "$RULE" >/dev/null <<'RULEEOF'
# libcamera's software ISP needs a dma-buf provider. The default permissions
# are root-only, which makes the ISP fail and leaves the camera without
# debayering. Grant the video group access instead of running as root.
SUBSYSTEM=="dma_heap", GROUP="video", MODE="0660"
KERNEL=="udmabuf", GROUP="video", MODE="0660"
RULEEOF

    echo "==> Regeln neu laden"
    sudo udevadm control --reload-rules
    sudo udevadm trigger --subsystem-match=dma_heap 2>/dev/null || true
    sudo udevadm trigger --name-match=udmabuf 2>/dev/null || true
    sleep 1

    if ! id -nG | grep -qw video; then
        echo "==> Dich zur Gruppe 'video' hinzufügen"
        sudo usermod -aG video "$USER"
        echo "  ACHTUNG: dafür ist ein Ab- und Anmelden (oder Neustart) nötig."
    fi

    echo
    show
    cat <<'MSG'

Jetzt erneut testen:
  bash scripts/50-libcamera-build.sh test

Erscheinen die DmaBufAllocator-Fehler nicht mehr, war es die Rechtevergabe.
Bleiben sie trotz vorhandener Knoten, hilft zur Eingrenzung ein Lauf als root:
  sudo ~/libcamera-build/libcamera/build/src/apps/cam/cam -l
MSG
    ;;

  revoke)
    sudo rm -f "$RULE" /etc/modules-load.d/udmabuf.conf
    sudo udevadm control --reload-rules
    echo "Regel entfernt. Gruppenmitgliedschaft bleibt bestehen; entfernen mit:"
    echo "  sudo gpasswd -d $USER video"
    ;;

  *)
    echo "Verwendung: $0 [status|grant|revoke]" >&2
    exit 1
    ;;
esac
