# surface10pro

Treiber-Setup und Doku für ein **Microsoft Surface Pro 10 for Business**
(Intel Core Ultra / Meteor Lake) unter **Zorin OS 18.1 Core** (Ubuntu 24.04 LTS
Unterbau) — Schwerpunkt Stift/Touchscreen und Kamera.

Dieses Repo enthält Skripte, die **du auf deinem eigenen Gerät** ausführst.
Es wird kein Fernzugriff auf die Hardware vorausgesetzt.

## Status auf einen Blick

| Komponente     | Status                                                        |
|----------------|---------------------------------------------------------------|
| Touchscreen    | ✅ läuft stabil (nach Abschalten von iptsd)                    |
| Stift          | ❌ Treiberlücke — lokal ausgeschöpft, Bericht vorbereitet      |
| Kamera         | ⚠️ ISP + Sensortreiber laufen; Blocker in Abklärung            |

**Gemessener Zustand vom Gerät: [docs/04-befund.md](docs/04-befund.md)** — dort
steht die vollständige Fehlersuche inklusive der gefundenen Ursache für den
Touch-Ausfall (DMA-Pufferüberlauf durch iptsd).

Allgemeiner Rahmen: [docs/01-hardware-status.md](docs/01-hardware-status.md)

## Schnellstart

```bash
# 1. Read-only Diagnose, ändert nichts
bash scripts/00-check-system.sh

# 2. iptsd abschalten - auf dem Pro 10 die Ursache des Digitizer-Ausfalls
bash scripts/31-pen-fix-iptsd-conflict.sh disable

# Falls nötig: sauber zurückrollen
bash scripts/90-uninstall-surface-kernel.sh
```

Ausführliche Anleitung inkl. Secure-Boot-Schritten:
[docs/02-pen-touch-setup.md](docs/02-pen-touch-setup.md)

## Zur Kamera

Der Surface Pro 10 nutzt einen **IPU6EP**-Bildprozessor. Dessen Treiber ist seit
Kernel 6.10 in mainline — der ISP ist also nicht das Problem. Es fehlen die
**Sensortreiber**: IMX681 (Front) hat gar keinen Linux-Treiber, OV13858 (Rück)
hat einen, aber die Plattform-Verdrahtung fehlt.

Kurzfristig ist eine externe USB-Webcam die praktikable Lösung. Der
aussichtsreichste Entwicklungspfad ist die Rückkamera, mit dem Surface Pro 9 als
funktionierender Vorlage.

Wo die Treiberkette real abbricht, zeigt `bash scripts/20-camera-analyze.sh`.

Analyse und Optionen: [docs/03-camera-status.md](docs/03-camera-status.md)

## Struktur

```
scripts/
  00-check-system.sh              read-only Diagnose (Stift, Touch, Kamera, Secure Boot)
  10-install-pen-touch.sh         linux-surface-Kernel + iptsd + libwacom-surface
  20-camera-analyze.sh            stufenweise Kamera-Diagnose mit Befund
  21-camera-acpi-dump.sh          ACPI-Auszug zur Sensor-Verdrahtung
  30-pen-diagnose.sh              Stift-Diagnose mit Live-Mitschnitt
  31-pen-fix-iptsd-conflict.sh    iptsd abschalten (disable/enable/status)
  32-capture-failure.sh           Zustandsaufnahme nach einem Ausfall
  34-input-monitor.py             misst evdev-Ereignisse (Kontrolle + Stift)
  35-collect-bugreport.sh         Belege für einen Upstream-Fehlerbericht
  36-hid-driver-probe.sh          HID-Treiberbindung prüfen und umhängen
  90-uninstall-surface-kernel.sh  Rollback
docs/
  01-hardware-status.md           Support-Matrix mit Quellen
  02-pen-touch-setup.md           Schritt-für-Schritt-Anleitung
  03-camera-status.md             Kamera-Analyse, Workarounds, Entwicklungspfad
  04-befund.md                    Messung vom echten Gerät (09.09.2026)
  05-bugreport.md                 fertige Vorlage für den Upstream-Bericht
```
