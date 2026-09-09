# Kamera: Status, Analyse & praktischer Umgang

**Kurzfassung:** Die Kameras funktionieren aktuell nicht. Der Grund ist aber
enger eingrenzbar als „kein Treiber vorhanden" — der Bildprozessor wird
unterstützt, es fehlen die **Sensortreiber**.

## Die Treiberkette und wo sie abbricht

```
mei_vsc_hw → mei_vsc → ivsc-ace → ivsc-csi → <Sensortreiber> → intel_ipu6_isys → libcamera
   ✅          ✅         ✅          ✅            ❌                 ✅              ✅
```

Der Surface Pro 10 (Meteor Lake) nutzt **IPU6EP**. Der IPU6-Treiber ist seit
**Kernel 6.10 in mainline**, libcamera unterstützt IPU6 seit 0.3.2. Zorin OS
18.1 bringt Kernel 6.17 mit — der ISP-Teil ist also vorhanden.

| Sensor  | Position | Lage                                                                 |
|---------|----------|----------------------------------------------------------------------|
| IMX681  | Front    | **Kein Linux-Treiber existiert.** Harter Blocker.                     |
| OV13858 | Rück     | Mainline-Treiber vorhanden; Plattform-Verdrahtung (ACPI/INT3472, GPIO, Clocks, Tuning-Dateien) fehlt. |
| VD55G0  | IR       | Kein Treiber → kein Windows Hello / Gesichtserkennung.                |

## Was realistisch geht

### Option A: Externe USB-Webcam (sofort, empfohlen)

Pragmatischste Lösung für Videocalls. Jede UVC-konforme USB-Webcam läuft ohne
Zusatztreiber:

```bash
sudo apt install v4l-utils
lsusb                     # wird die Kamera erkannt?
v4l2-ctl --list-devices    # taucht sie als /dev/videoX auf?
```

Erscheint ein `/dev/video*`-Node, funktioniert sie in Zoom, Teams, Firefox etc.

### Option B: Fortschritt beobachten und periodisch neu testen

Kein Skript kann den fehlenden Sensortreiber ersetzen. Nach größeren Kernel-
oder linux-surface-Updates lohnt ein erneuter Test:

```bash
bash scripts/00-check-system.sh   # der Kamera-Abschnitt zeigt den Zustand der Kette
```

Konkret interessant: ob unter „ACPI sensor/bridge devices" `INT3472`-Einträge
auftauchen und ob `dmesg` Sensor-Bindungen zeigt statt Fehlermeldungen.

Quellen zum Verfolgen:
- [Camera Support Wiki](https://github.com/linux-surface/linux-surface/wiki/Camera-Support) (Matrix wird gepflegt)
- [Discussion #1354 — Camera support (IPU6)](https://github.com/linux-surface/linux-surface/discussions/1354)
- [intel/ipu6-drivers](https://github.com/intel/ipu6-drivers)

### Option C: Rückkamera selbst zum Laufen bringen (ambitioniert, aber machbar)

Die aussichtsreichste Baustelle, weil der `ov13858`-Treiber bereits existiert.
Zu tun wäre im Wesentlichen die Plattform-Verdrahtung:

1. Aus den ACPI-Tabellen (`acpidump`/`iasl`) ermitteln, wie der Sensor
   angebunden ist — GPIOs, Clocks, Regulatoren, CSI-2-Port-Zuordnung.
2. Prüfen, ob eine `INT3472`-Bridge-Definition vorhanden ist bzw. ergänzt
   werden muss (das ist der Mechanismus, über den Linux MIPI-Sensoren auf
   IPU6-Plattformen verdrahtet).
3. Gegebenenfalls einen Kernel-Patch oder ein Overlay bauen, das die fehlende
   Zuordnung nachreicht.
4. Mit `cam -l` (libcamera) testen, ob der Sensor erkannt und ein Stream
   möglich ist.

**Als Vorlage dient der Surface Pro 9**, für den die Community genau diesen Weg
erfolgreich gegangen ist — gleicher IPU6-Unterbau:
[Discussion #2198 (vollständiges Writeup)](https://github.com/linux-surface/linux-surface/discussions/2198).

Realistischer Aufwand: Tage bis Wochen, mit unsicherem Ausgang, und es braucht
Zugriff auf das echte Gerät für jeden Testschritt. Wenn du das angehen willst,
ist der erste konkrete Schritt ein ACPI-Dump von deinem Surface:

```bash
sudo apt install acpica-tools
sudo acpidump -b -o /tmp/acpi.dat && cd /tmp && iasl -d *.dat
# Interessant: DSDT.dsl nach "IMX681", "OV13858", "INT3472" durchsuchen
```

Damit könnten wir gemeinsam analysieren, wie die Sensoren tatsächlich verdrahtet
sind — das ist die Grundlage für alles Weitere.

### Option D: Fronkamera per eigenem Treiber (unrealistisch)

Für den IMX681 müsste ein Sensortreiber von Grund auf geschrieben werden, ohne
Datenblatt und ohne Referenzimplementierung. Das ist Reverse-Engineering im
Monatsbereich und wurde bislang von niemandem in der Community angegangen.
Für den Alltag ist Option A die deutlich sinnvollere Antwort.
