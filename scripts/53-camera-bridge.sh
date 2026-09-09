#!/usr/bin/env bash
# Publishes the libcamera stream as a /dev/video* device for browsers.
#
# Browsers and conferencing apps look for V4L2 devices; IPU6 cameras never
# appear there. v4l2loopback provides the node, and a GStreamer pipeline feeds
# it from libcamera.
#
# Two things to know about this machine:
#   - The distro GStreamer plugin is built against libcamera 0.2.0 and cannot
#     talk to the 0.7.2 build, so the plugin from that build tree is used.
#   - Capturing below roughly 1296 pixels wide yields empty buffers (same as
#     reported for the Pro 9), so capture larger and scale down here.
#
#   deps       install v4l2loopback and GStreamer plugins
#   check      verify prerequisites (read-only)
#   start      run the bridge in the foreground, for testing
#   install    start it automatically at login
#   uninstall  remove the service and module configuration
set -euo pipefail

BUILD="${LIBCAMERA_BUILD:-$HOME/libcamera-build/libcamera/build}"
SRCDIR="${LIBCAMERA_SRC:-$HOME/libcamera-build/libcamera}"
VIDEO_NR="${VIDEO_NR:-42}"
DEV="/dev/video$VIDEO_NR"
LABEL="${CARD_LABEL:-Surface Rear Camera}"
# exclusive_caps=1 makes the node advertise CAPTURE only, and v4l2sink then
# refuses it with "not an output device" (caps 0x24a00001, no VIDEO_OUTPUT).
# 0 keeps both directions available, which is what the feeding pipeline needs.
# Some browsers prefer 1; override with EXCLUSIVE_CAPS=1 if yours does.
EXCLUSIVE_CAPS="${EXCLUSIVE_CAPS:-0}"

# Capture above the empty-buffer threshold, deliver a conferencing-friendly size.
CAP_W="${CAP_W:-2560}"; CAP_H="${CAP_H:-1440}"
OUT_W="${OUT_W:-1280}"; OUT_H="${OUT_H:-720}"
FPS="${FPS:-30}"

MODCONF=/etc/modprobe.d/v4l2loopback-surface.conf
LOADCONF=/etc/modules-load.d/v4l2loopback-surface.conf
UNIT="$HOME/.config/systemd/user/surface-camera-bridge.service"

export LD_LIBRARY_PATH="$BUILD/src/libcamera:$BUILD/src/libcamera/base:${LD_LIBRARY_PATH:-}"
export GST_PLUGIN_PATH="$BUILD/src/gstreamer:${GST_PLUGIN_PATH:-}"

pipeline_args() {
    echo "libcamerasrc ! video/x-raw,width=$CAP_W,height=$CAP_H,framerate=$FPS/1 ! videoconvert ! videoscale ! video/x-raw,width=$OUT_W,height=$OUT_H,format=YUY2 ! v4l2sink device=$DEV sync=false"
}

case "${1:-check}" in
  deps)
    sudo apt update
    sudo apt install -y v4l2loopback-dkms v4l2loopback-utils \
        gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good
    echo
    echo "Fertig. Weiter mit:  bash $0 check"
    ;;

  check)
    echo "=== Voraussetzungen ==="
    ok=1
    if [ -f "$BUILD/src/gstreamer/libgstlibcamera.so" ]; then
        echo "  ✓ GStreamer-Plugin aus dem eigenen Build vorhanden"
    else
        echo "  ✗ $BUILD/src/gstreamer/libgstlibcamera.so fehlt"
        echo "    libcamera wurde ohne GStreamer-Unterstützung gebaut."
        echo "    Abhilfe: bash scripts/50-libcamera-build.sh deps && ... build"
        ok=0
    fi
    # modinfo lives in /usr/sbin, which is often outside a normal user's PATH,
    # so "command not found" would otherwise read as "module missing".
    MODINFO=$(command -v modinfo || echo /usr/sbin/modinfo)
    if "$MODINFO" v4l2loopback >/dev/null 2>&1 \
       || [ -n "$(find /lib/modules/"$(uname -r)" -name 'v4l2loopback*' -print -quit 2>/dev/null)" ]; then
        echo "  ✓ v4l2loopback verfügbar"
    else
        echo "  ✗ v4l2loopback für Kernel $(uname -r) nicht gebaut - bash $0 deps"
        ok=0
    fi
    command -v gst-launch-1.0 >/dev/null \
        && echo "  ✓ gst-launch-1.0 vorhanden" \
        || { echo "  ✗ gst-launch-1.0 fehlt - bash $0 deps"; ok=0; }
    if id -nG | grep -qw video; then
        echo "  ✓ Du bist in der Gruppe 'video'"
    else
        echo "  ✗ Gruppe 'video' fehlt - nach 51-dmabuf-access.sh neu anmelden"
        ok=0
    fi
    echo
    echo "=== Erkannte Kameras ==="
    CAMS=$("$BUILD/src/apps/cam/cam" -l 2>/dev/null | grep -E '^\s*[0-9]+:' || true)
    echo "${CAMS:-  (keine)}" | sed 's/^/  /'
    if ! echo "$CAMS" | grep -q 'CAMR'; then
        echo
        echo "  ✗ Die echte Kamera (CAMR) fehlt - nur virtuelle Testkameras."
        echo "    Läuft der richtige Kernel? Aktuell: $(uname -r)"
        echo "    Nötig ist 6.19.8-surface-3; Mainline hat die Sensor-Patches nicht."
        ok=0
    fi
    echo
    echo "=== Geplante Pipeline ==="
    echo "  Aufnahme:  ${CAP_W}x${CAP_H} @ ${FPS} fps"
    echo "  Ausgabe:   ${OUT_W}x${OUT_H} auf $DEV"
    echo
    [ "$ok" = "1" ] && echo "Bereit. Test mit:  bash $0 start" \
                    || echo "Erst die fehlenden Punkte oben beheben."
    ;;

  start)
    if [ ! -e "$DEV" ]; then
        echo "==> v4l2loopback laden"
        sudo modprobe -r v4l2loopback 2>/dev/null || true
        sudo modprobe v4l2loopback video_nr="$VIDEO_NR" \
            card_label="$LABEL" exclusive_caps="$EXCLUSIVE_CAPS"
        sleep 1
    fi
    [ -e "$DEV" ] || { echo "$DEV wurde nicht angelegt." >&2; exit 1; }
    echo "==> $DEV bereit"
    echo "==> Pipeline startet - mit Strg+C beenden"
    echo
    echo "    In einem zweiten Terminal testen:"
    echo "      ffplay $DEV        (oder im Browser eine Kamera-Seite öffnen)"
    echo
    # shellcheck disable=SC2046
    exec gst-launch-1.0 -v $(pipeline_args)
    ;;

  install)
    echo "Das richtet ein, dass die Kamera bei jeder Anmeldung bereitsteht:"
    echo "  - v4l2loopback wird beim Systemstart geladen ($DEV)"
    echo "  - ein Benutzerdienst startet die Weiterleitung"
    echo
    echo "Beachte: die Pipeline läuft dann dauerhaft und kostet Rechenleistung"
    echo "und Akku, auch wenn keine Konferenz läuft."
    read -r -p "Fortfahren? [y/N] " ans
    [ "${ans,,}" = "y" ] || exit 1

    echo "==> Modulkonfiguration"
    printf 'options v4l2loopback video_nr=%s card_label="%s" exclusive_caps=%s\n' \
        "$VIDEO_NR" "$LABEL" "$EXCLUSIVE_CAPS" | sudo tee "$MODCONF" >/dev/null
    echo v4l2loopback | sudo tee "$LOADCONF" >/dev/null

    echo "==> Benutzerdienst"
    mkdir -p "$(dirname "$UNIT")"
    cat > "$UNIT" <<UNITEOF
[Unit]
Description=Surface rear camera to $DEV
After=graphical-session.target

[Service]
Environment=LD_LIBRARY_PATH=$BUILD/src/libcamera:$BUILD/src/libcamera/base
Environment=GST_PLUGIN_PATH=$BUILD/src/gstreamer
ExecStart=/usr/bin/gst-launch-1.0 $(pipeline_args)
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
UNITEOF
    systemctl --user daemon-reload
    systemctl --user enable --now surface-camera-bridge.service
    echo
    systemctl --user status surface-camera-bridge.service --no-pager | head -12
    cat <<MSG

Steuerung:
  systemctl --user status surface-camera-bridge
  systemctl --user restart surface-camera-bridge
  systemctl --user stop surface-camera-bridge

Entfernen:  bash $0 uninstall
MSG
    ;;

  uninstall)
    systemctl --user disable --now surface-camera-bridge.service 2>/dev/null || true
    rm -f "$UNIT"
    systemctl --user daemon-reload 2>/dev/null || true
    sudo rm -f "$MODCONF" "$LOADCONF"
    sudo modprobe -r v4l2loopback 2>/dev/null || true
    echo "Entfernt."
    ;;

  *)
    echo "Verwendung: $0 [deps|check|start|install|uninstall]" >&2
    exit 1
    ;;
esac
