# Hardware-Support-Status: Surface Pro 10 for Business unter Linux

**Stand: September 2026.** Treibersupport für dieses Gerät ist noch in Bewegung
(Meteor Lake / Core Ultra, Gerät von 2024) — vor größeren Aktionen lohnt ein
Blick auf die unten verlinkten Quellen, ob sich etwas geändert hat.

| Komponente             | Status                        | Weg                                                  |
|------------------------|-------------------------------|------------------------------------------------------|
| Tastatur (Type Cover)  | ✅ funktioniert               | out of the box                                       |
| Bluetooth              | ✅ funktioniert               | out of the box                                       |
| Touchscreen            | ✅ mit linux-surface-Kernel   | `linux-image-surface` + `iptsd`                      |
| Stift (Digitizer)      | ✅ mit linux-surface-Kernel   | `linux-image-surface` + `iptsd` + `libwacom-surface` |
| Kamera Front (IMX681)  | ❌ kein Sensortreiber         | siehe [03-camera-status.md](03-camera-status.md)     |
| Kamera Rück (OV13858)  | ❌ noch nicht funktionsfähig  | Treiber existiert, Verdrahtung fehlt                 |
| Kamera IR (VD55G0)     | ❌ kein Sensortreiber         | Windows Hello entfällt damit                         |
| WLAN                   | zu prüfen                     | i.d.R. Intel-Chip, meist mainline unterstützt        |

## Stift & Touch

Das ist der Teil, der sich zuverlässig lösen lässt. Der gepatchte
`linux-surface`-Kernel bringt die nötigen Treiber mit, `iptsd` übersetzt die
Rohdaten des Digitizers in Eingabe-Events, `libwacom-surface` liefert die
Gerätedefinitionen für Druckstufen und Stift-Buttons.

Anleitung: [02-pen-touch-setup.md](02-pen-touch-setup.md)

## Kamera — wo genau es klemmt

Wichtige Präzisierung: Der Surface Pro 10 nutzt **IPU6EP** (Meteor Lake), nicht
IPU7 — IPU7 kommt erst mit Lunar Lake (Surface Pro 11 Intel). Das ist relevant,
weil der IPU6-Treiber seit **Kernel 6.10 in mainline** ist. Der Bildprozessor
selbst ist also nicht mehr das Problem.

Die Kette sieht so aus:

```
mei_vsc_hw → mei_vsc → ivsc-ace → ivsc-csi → <Sensortreiber> → intel_ipu6_isys
                                              ^^^^^^^^^^^^^^^
                                              hier bricht es ab
```

- **IMX681** (Front): Es existiert schlicht **kein Linux-Treiber** für diesen
  Sony-Sensor. Unter Windows läuft er über eine proprietäre `imx681_extension`.
  Ohne Sensortreiber kein Bild — das ist der harte Blocker.
- **OV13858** (Rück): Hier gibt es einen mainline-Treiber. Was fehlt, ist
  typischerweise die Plattform-Verdrahtung (ACPI/INT3472-Bridge, GPIO/Clock-
  Zuordnung, Firmware-Tuning-Dateien). Das ist die aussichtsreichste Baustelle.
- **VD55G0** (IR): Kein Treiber, entsprechend kein Windows Hello.

Ermutigend: Auf demselben IPU6-Unterbau hat die Community den **Surface Pro 9**
zum Laufen gebracht (Front + Rück). Der Weg ist also grundsätzlich gangbar, es
fehlt die gerätespezifische Arbeit für den Pro 10.

Details und praktischer Umgang: [03-camera-status.md](03-camera-status.md)

## Quellen

- [linux-surface Feature-Matrix](https://github.com/linux-surface/linux-surface/wiki/Supported-Devices-and-Features)
- [linux-surface Camera Support Wiki](https://github.com/linux-surface/linux-surface/wiki/Camera-Support)
- [Discussion #1354 — Camera support (IPU6)](https://github.com/linux-surface/linux-surface/discussions/1354)
- [Discussion #2198 — Surface Pro 9 Kamera funktionsfähig (IPU6, Writeup)](https://github.com/linux-surface/linux-surface/discussions/2198)
- [intel/ipu6-drivers](https://github.com/intel/ipu6-drivers)
- [Kernel-Doku: Intel IPU6 Driver](https://docs.kernel.org/driver-api/media/drivers/ipu6.html)
