#!/usr/bin/env bash
# Converts frames captured by "cam --file" into viewable PNGs.
#
# cam writes unprocessed buffer contents: 32-bit pixels, and the line stride is
# padded beyond the visible width. On this machine a frame is 52985856 bytes
# over 3136 lines, i.e. 16896 bytes per line = 4224 pixels of padding for a
# visible width of 4216.
#
# The byte order of libcamera's ABGR8888 is not obvious from the name, so both
# plausible interpretations are written out - open them and keep whichever has
# correct colours rather than swapped red and blue.
set -euo pipefail

RAW="${1:-}"
HEIGHT="${2:-3136}"
VISIBLE_W="${3:-4216}"

if [ -z "$RAW" ] || [ ! -f "$RAW" ]; then
    echo "Verwendung: $0 <datei.raw> [höhe] [sichtbare breite]" >&2
    echo "Beispiel:   $0 /tmp/framecam0-stream0-000000.raw" >&2
    exit 1
fi

command -v ffmpeg >/dev/null || {
    echo "ffmpeg fehlt. Installieren mit:  sudo apt install -y ffmpeg" >&2
    exit 1
}

SIZE=$(stat -c %s "$RAW")
STRIDE=$((SIZE / HEIGHT))
PADDED_W=$((STRIDE / 4))

echo "=== Aufnahme ==="
echo "  Datei:            $RAW"
echo "  Größe:            $SIZE Byte"
echo "  Zeilen:           $HEIGHT"
echo "  Bytes pro Zeile:  $STRIDE"
echo "  Breite gepolstert: $PADDED_W px"
echo "  Breite sichtbar:   $VISIBLE_W px"

if [ $((STRIDE * HEIGHT)) -ne "$SIZE" ]; then
    echo
    echo "WARNUNG: Größe nicht durch Zeilenzahl teilbar - Höhe stimmt vermutlich nicht." >&2
fi

BASE="${RAW%.raw}"
for FMT in rgba bgra; do
    OUT="${BASE}-${FMT}.png"
    echo
    echo "==> $FMT → $OUT"
    if ffmpeg -hide_banner -loglevel error -y \
        -f rawvideo -pixel_format "$FMT" \
        -video_size "${PADDED_W}x${HEIGHT}" \
        -i "$RAW" \
        -vf "crop=${VISIBLE_W}:${HEIGHT}:0:0" \
        -frames:v 1 "$OUT"; then
        echo "    $(ls -lh "$OUT" | awk '{print $5}')"
    else
        echo "    fehlgeschlagen"
    fi
done

cat <<MSG

Fertig. Beide Varianten ansehen und vergleichen:

  xdg-open ${BASE}-rgba.png
  xdg-open ${BASE}-bgra.png

Bei einer stimmen die Farben, bei der anderen sind Rot und Blau vertauscht.

Zur Einordnung: Ohne Kalibrierungsdatei (ov13858.yaml fehlt für das IPA-Modul)
sind Weißabgleich und Belichtung ungenau. Das Bild darf also flau oder
farbstichig aussehen - entscheidend ist, dass ein erkennbares Motiv da ist.
MSG
