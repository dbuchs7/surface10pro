#!/usr/bin/env bash
# Builds a current libcamera from source and tests it WITHOUT installing.
#
# Why: Zorin/Ubuntu 24.04 ship libcamera 0.2.0, which predates IPU6 support
# (0.3.2 minimum). Everything below libcamera already works on this machine -
# INT3472 registers the pwr1 regulator, the IPU6 reports "Connected 1 cameras",
# and ov13858 is bound to i2c-OVTID858:00 - so this is the remaining blocker.
#
# The build stays in a work directory and is tested from there. Nothing
# system-wide is touched unless you later run the "install" action, which is
# deliberately a separate decision: replacing the distro libcamera affects
# PipeWire and every application that uses it.
#
#   deps     install build dependencies
#   build    clone and compile (no system changes)
#   test     run the freshly built cam -l against the hardware
#   install  install system-wide (only after test looks right)
set -euo pipefail

WORK="${LIBCAMERA_WORK:-$HOME/libcamera-build}"
SRC="$WORK/libcamera"
ACTION="${1:-help}"

case "$ACTION" in
  deps)
    echo "==> Build-Abhängigkeiten installieren"
    sudo apt update
    sudo apt install -y \
        git meson ninja-build pkg-config cmake \
        python3-yaml python3-ply python3-jinja2 python3-setuptools \
        libyaml-dev libssl-dev libgnutls28-dev openssl \
        libudev-dev libevent-dev libdrm-dev libjpeg-dev \
        libtiff-dev libexif-dev \
        libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
        build-essential

    # Optional: if the distro has libyuv, meson uses it instead of building
    # the CMake subproject. Not fatal when missing.
    sudo apt install -y libyuv-dev 2>/dev/null || \
        echo "  (libyuv-dev nicht verfügbar - wird als Unterprojekt gebaut, dafür ist cmake nötig)"

    echo
    echo "Fertig. Weiter mit:  bash $0 build"
    ;;

  build)
    MISSING=()
    for t in meson ninja cmake; do
        command -v "$t" >/dev/null || MISSING+=("$t")
    done
    if [ "${#MISSING[@]}" -gt 0 ]; then
        echo "Es fehlen: ${MISSING[*]}" >&2
        echo "Nachinstallieren mit:  sudo apt install -y ${MISSING[*]}" >&2
        echo "oder komplett:         bash $0 deps" >&2
        exit 1
    fi
    mkdir -p "$WORK"
    if [ -d "$SRC/.git" ]; then
        echo "==> Vorhandenen Klon aktualisieren"
        git -C "$SRC" fetch --tags --quiet
    else
        echo "==> libcamera klonen"
        git clone https://git.libcamera.org/libcamera/libcamera.git "$SRC"
    fi

    # Pick the newest stable tag; a release is safer than the moving branch.
    TAG=$(git -C "$SRC" tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
    if [ -z "$TAG" ]; then
        echo "Kein Release-Tag gefunden, benutze den Hauptzweig." >&2
        TAG=$(git -C "$SRC" rev-parse --abbrev-ref HEAD)
    fi
    echo "==> Auf $TAG wechseln"
    git -C "$SRC" checkout --quiet "$TAG"

    echo "==> Konfigurieren"
    rm -rf "$SRC/build"
    # Defaults enable the pipeline handlers; IPU6 is served by the simple
    # pipeline handler with the software ISP.
    meson setup "$SRC/build" "$SRC" \
        --buildtype=release \
        -Dprefix=/usr/local \
        -Ddocumentation=disabled \
        -Dtest=false

    echo "==> Bauen (das dauert einige Minuten)"
    ninja -C "$SRC/build"

    echo
    echo "==> Fertig gebaut, NICHTS am System geändert."
    echo "    Jetzt testen:  bash $0 test"
    ;;

  test)
    CAM="$SRC/build/src/apps/cam/cam"
    [ -x "$CAM" ] || { echo "Nicht gebaut. Erst: bash $0 build" >&2; exit 1; }
    echo "=== Systemweites libcamera (zum Vergleich) ==="
    command -v cam >/dev/null && cam -l 2>&1 | grep -vE '^\[' | head -5 | sed 's/^/  /' \
        || echo "  (kein systemweites cam)"
    echo
    echo "=== Frisch gebautes libcamera ==="
    "$CAM" -l 2>&1 | head -20 | sed 's/^/  /'
    echo
    if "$CAM" -l 2>&1 | grep -qiE "^\s*[0-9]+:|Available cameras.*[1-9]"; then
        echo "  ✓ Die neue Version SIEHT eine Kamera."
        echo
        echo "  Bild aufnehmen zum Gegentest:"
        echo "    $CAM -c 1 --capture=3 --file=/tmp/frame#.raw"
        echo
        echo "  Wenn das Bilder liefert, lohnt die systemweite Installation:"
        echo "    bash $0 install"
    else
        echo "  ✗ Auch die neue Version findet keine Kamera."
        echo "    Dann liegt es nicht an der libcamera-Version - bitte die"
        echo "    vollständige Ausgabe oben zurückmelden."
    fi
    ;;

  install)
    [ -d "$SRC/build" ] || { echo "Nicht gebaut. Erst: bash $0 build" >&2; exit 1; }
    cat <<'MSG'
Das installiert libcamera nach /usr/local und ersetzt damit faktisch die
Version der Distribution für alles, was danach sucht - auch PipeWire und
darüber Browser und Videokonferenz-Programme.

Rückgängig: sudo ninja -C <build> uninstall

MSG
    read -r -p "Fortfahren? [y/N] " ans
    [ "${ans,,}" = "y" ] || exit 1
    sudo ninja -C "$SRC/build" install
    sudo ldconfig
    echo
    echo "==> Installiert. Prüfen mit:  cam -l"
    echo "    Deinstallieren:  sudo ninja -C $SRC/build uninstall"
    ;;

  *)
    cat <<MSG
Verwendung: $0 [deps|build|test|install]

  deps     Build-Abhängigkeiten installieren
  build    libcamera klonen und übersetzen (ändert nichts am System)
  test     die gebaute Version gegen die Hardware testen
  install  systemweit installieren (erst nach erfolgreichem Test)

Arbeitsverzeichnis: $WORK
MSG
    ;;
esac
