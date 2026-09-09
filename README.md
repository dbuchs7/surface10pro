# surface10pro

Treiber-Setup und Doku für ein **Microsoft Surface Pro 10 for Business**
(Intel Core Ultra / Meteor Lake) unter **Zorin OS 18.1 Core** (Ubuntu 24.04 LTS
Unterbau) — Schwerpunkt Stift/Touchscreen und Kamera.

Dieses Repo enthält Skripte, die **du auf deinem eigenen Gerät** ausführst.
Es wird kein Fernzugriff auf die Hardware vorausgesetzt.

## Status auf einen Blick

| Komponente     | Status                                                        |
|----------------|---------------------------------------------------------------|
| Stift / Touch  | ✅ lösbar über den linux-surface-Kernel                        |
| Kamera         | ❌ Sensortreiber fehlen (ISP selbst wird unterstützt)          |

Details: [docs/01-hardware-status.md](docs/01-hardware-status.md)

## Schnellstart

```bash
# 1. Read-only Diagnose, ändert nichts
bash scripts/00-check-system.sh

# 2. Stift/Touchscreen einrichten (fragt vor jedem Schritt nach)
bash scripts/10-install-pen-touch.sh

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

Analyse und Optionen: [docs/03-camera-status.md](docs/03-camera-status.md)

## Struktur

```
scripts/
  00-check-system.sh              read-only Diagnose (Stift, Touch, Kamera, Secure Boot)
  10-install-pen-touch.sh         linux-surface-Kernel + iptsd + libwacom-surface
  90-uninstall-surface-kernel.sh  Rollback
docs/
  01-hardware-status.md           Support-Matrix mit Quellen
  02-pen-touch-setup.md           Schritt-für-Schritt-Anleitung
  03-camera-status.md             Kamera-Analyse, Workarounds, Entwicklungspfad
```
