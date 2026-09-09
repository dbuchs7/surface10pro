# Kamera: Status, Analyse & Entwicklungspfad

**Kurzfassung:** Die Kameras funktionieren nicht. Der Grund ist aber deutlich
enger eingrenzbar als „kein Treiber vorhanden" — der Bildprozessor wird
unterstützt, es hakt an der Verdrahtung und den Sensortreibern. Auf demselben
Unterbau ist das beim Surface Pro 9 gelungen.

## Die Treiberkette

```
[1] IPU6 ISP → [2] IVSC/MEI → [3] INT3472 → [4] Sensortreiber → [5] V4L2 → [6] libcamera
     ✅            ✅            ⚠️              ❌                 ❌          ❌
```

Der Surface Pro 10 (Meteor Lake) nutzt **IPU6EP**. Der IPU6-Treiber ist seit
**Kernel 6.10 mainline**, libcamera unterstützt IPU6 seit 0.3.2. Zorin OS 18.1
bringt Kernel 6.17 mit — Stufe 1 ist also vorhanden.

Wo es real abbricht, ermittelst du mit:

```bash
bash scripts/20-camera-analyze.sh
```

Das Skript geht die Kette Stufe für Stufe durch und nennt am Ende den genauen
Abbruchpunkt samt nächstem sinnvollen Schritt.

## Die zwei wahrscheinlichen Blocker

### A) INT3472 / Lattice-MIPI-Aggregator (Stufe 3)

Auf Meteor-Lake-Geräten ist ein bekanntes Problem dokumentiert: Die
INT3472-Bridge meldet einen GPIO-Typ `0x12`, den der Kernel nicht kennt.
Im `dmesg` sieht das so aus:

```
GPIO type 0x12 unknown; the sensor may not work
```

Ursache ist ein **Lattice-MIPI-Aggregator**, der auf neueren Plattformen die
Rolle des früheren IO-Expanders übernimmt (Takt, Spannungen, Reset/Powerdown).
Upstream-Patches sind in Arbeit, aber noch nicht vollständig integriert —
siehe [intel/ipu6-drivers#281](https://github.com/intel/ipu6-drivers/issues/281).

Ob dein Gerät betroffen ist, zeigt `scripts/20-camera-analyze.sh` in Stufe 3.

### B) Sensortreiber bindet nicht (Stufe 4)

| Sensor  | Position | Lage                                                    |
|---------|----------|---------------------------------------------------------|
| IMX681  | Front    | **Kein Linux-Treiber existiert.** Harter Blocker.       |
| OV13858 | Rück     | Mainline-Treiber vorhanden — aussichtsreichste Baustelle |
| VD55G0  | IR       | Kein Treiber → kein Windows Hello                       |

Beim OV13858 ist die häufigste Ursache banal: Der ACPI-HID des Geräts steht
nicht in der Match-Tabelle des Treibers, also bindet er nicht. Genau das war
beim Surface Pro 9 der Fall und ließ sich mit einem modprobe-Alias lösen.

## Das Surface-Pro-9-Vorbild

Auf gleichem IPU6-Unterbau wurde dort Front- **und** Rückkamera zum Laufen
gebracht ([Discussion #2198](https://github.com/linux-surface/linux-surface/discussions/2198),
Linux Mint 22.2 auf Ubuntu-24.04-Basis — also praktisch dieselbe Ausgangslage
wie Zorin 18.1). Nötig waren vier Dinge:

1. **ACPI-Bindung per modprobe-Alias**, damit der vorhandene Treiber überhaupt
   greift:
   ```
   # /etc/modprobe.d/ov5693-surface.conf
   alias acpi*:OVTI5693:* ov5693
   ```
2. **Kleiner Treiber-Patch** — ein Register (`MIPI_CTRL00`) musste vor
   Stream-Start geschrieben werden; als DKMS-Modul gebaut, bei aktivem Secure
   Boot mit MOK signiert.
3. **libcamera aus Quellen** (0.7.1 plus ein Fix gegen schwarze Bilder bei
   kleinen Auflösungen).
4. **v4l2loopback + v4l2-relayd** als Brücke, damit Apps die Kamera als
   klassisches `/dev/video*` sehen — IPU6-Kameras erscheinen dort **nicht**
   automatisch. Das erklärt auch, warum Zoom/Teams selbst dann nichts finden,
   wenn libcamera bereits ein Bild liefert.

Für den Pro 10 wäre der analoge Weg: gleicher Ablauf, aber mit `ov13858` und
dem tatsächlichen HID deines Geräts.

## Vorgehen

### Schritt 1 — Abbruchpunkt bestimmen
```bash
bash scripts/20-camera-analyze.sh
```

### Schritt 2 — Verdrahtung auslesen
```bash
sudo apt install acpica-tools
bash scripts/21-camera-acpi-dump.sh
```
Erzeugt `~/surface-acpi/camera-acpi-summary.txt` mit den kamerarelevanten
ACPI-Abschnitten — GPIOs, Clocks, Regulatoren, `_DSM`-Methoden. Das ist die
Grundlage für alles Weitere und die richtige Datei zum Teilen.

### Schritt 3 — je nach Befund
- **Sensor-HID gefunden, Treiber bindet nicht** → modprobe-Alias setzen und
  testen. Kleinster Aufwand, echte Erfolgschance.
- **GPIO-Typ 0x12 im dmesg** → Lattice-Problem; auf Upstream warten oder die
  vorhandenen Patches aus Issue #281 testen.
- **Sensor bindet, aber kein Bild** → Treiber-Patch nach SP9-Vorbild.

Referenz für den gesamten Prozess:
[hao-yao/ipu6-sensor-guide](https://github.com/hao-yao/ipu6-sensor-guide) —
Intels Anleitung zum Aktivieren neuer Sensoren auf IPU6.

## Realistische Einschätzung

- **Rückkamera (OV13858):** Machbar. Wenn es nur am modprobe-Alias liegt, sind
  es Minuten; wenn ein Treiber-Patch nötig wird, Tage. Wenn der
  Lattice-Aggregator im Weg ist, hängt es an Upstream.
- **Frontkamera (IMX681):** Ohne Treiber und ohne Datenblatt Reverse-Engineering
  im Monatsbereich. Nicht empfehlenswert.
- **IR (VD55G0):** Analog zur Front. Windows Hello entfällt.

## Pragmatischer Zwischenweg: USB-Webcam

Für Videocalls sofort einsatzbereit, ohne Zusatztreiber:

```bash
sudo apt install v4l-utils
lsusb                     # wird die Kamera erkannt?
v4l2-ctl --list-devices    # erscheint sie als /dev/videoX?
```

Erscheint ein `/dev/video*`-Node, funktioniert sie in Zoom, Teams, Firefox etc.

## Quellen

- [Discussion #2198 — Surface Pro 9 Kamera funktionsfähig (Writeup)](https://github.com/linux-surface/linux-surface/discussions/2198)
- [Discussion #1354 — Camera support (IPU6)](https://github.com/linux-surface/linux-surface/discussions/1354)
- [intel/ipu6-drivers#281 — INT3472 GPIO 0x12 / Lattice-Aggregator](https://github.com/intel/ipu6-drivers/issues/281)
- [hao-yao/ipu6-sensor-guide](https://github.com/hao-yao/ipu6-sensor-guide)
- [Kernel-Doku: IPU6 ISYS](https://docs.kernel.org/admin-guide/media/ipu6-isys.html)
- [linux-surface Camera Support Wiki](https://github.com/linux-surface/linux-surface/wiki/Camera-Support)

---

## Entscheidender Fund: die Patches existieren bereits (Sept. 2026)

[linux-surface PR #1867](https://github.com/linux-surface/linux-surface/pull/1867)
— „Add camera support for Surface Pro 9", **gemerged am 31.12.2025** — deckt
exakt die Hardware des Surface Pro 10 mit ab:

| Datei | Änderung | Bezug zum Pro 10 |
|---|---|---|
| `discrete.c` (INT3472) | GPIO-Typ **0x08** wird als Regulator `pwr1` behandelt | genau der gemeldete Blocker |
| `ov13858.c` | Regulatoren `avdd`/`pwr1`, Reset-GPIO, xvclk, Suspend/Resume | genau der Rück-Sensor |
| `ipu-bridge.c` | Konfiguration für **`OVTID858`**: 4 Lanes, 540 MHz | genau die ACPI-Kennung des Geräts |
| `ov5693.c` | ACPI-ID `OVTI5693` ergänzt | betrifft den Pro 9, nicht den Pro 10 |

### Der Kernel entscheidet alles

Messung vom 09.09.2026 auf **Mainline 7.1.2** (ohne diese Patches):

```
int3472-discrete INT3472:00: GPIO type 0x08 unknown; the sensor may not work
ov13858 i2c-OVTID858:00: failed to find sensor: -5
ov13858 i2c-OVTID858:00: probe with driver ov13858 failed with error -5
OVTID858:00 → kein Treiber
```

Die Kette ist damit vollständig erklärt: INT3472 versteht GPIO-Typ `0x08` nicht
→ der Regulator wird nicht angelegt → der Sensor bekommt keine Spannung → der
Treiber kann die Chip-ID nicht über I2C lesen (`-EIO`) → Probe scheitert → kein
Sensor im Media-Graph → libcamera findet nichts.

Frühere Meldung auf dem **Surface-Kernel 6.19.8-surface-3**:

```
ov13858 i2c-OVTID858:00: Reset de-asserted, sensor should be ready
```

Diese Zeile stammt aus dem **gepatchten** Treiber mit Reset-Steuerung. Sie
existiert im Mainline-Treiber nicht.

### Konsequenz

Für die Kamera ist der **Surface-Kernel zwingend** — der Mainline-Kernel hat
die nötigen Patches nicht und wird sie so bald auch nicht bekommen. Die
Kamera-Analyse gehört deshalb auf `6.19.8-surface-3` wiederholt.

Damit reduziert sich die Frage vermutlich auf libcamera: Version 0.2.0 aus
Zorin/Ubuntu kann IPU6 nicht, nötig ist mindestens 0.3.2.
