# Kontext für Claude Code

## Gerät und System

- **Hardware:** Microsoft Surface Pro 10 for Business (Intel Core Ultra, Meteor Lake)
- **OS:** Zorin OS 18.1 Core (Ubuntu 24.04 LTS Unterbau)
- **Laufender Kernel:** `7.1.2-070102-generic` (Mainline) — der ebenfalls
  installierte `6.19.8-surface-3` wird **nicht** gebootet
- **Secure Boot:** deaktiviert, Platform in Setup Mode → kein MOK-Enrollment nötig

Gemessener Zustand: `docs/04-befund.md`. Diese Datei hier nur als Kurzüberblick.

## Stand der Dinge

**Stift:** Funktioniert NICHT — kein Strich. Aber: die Pakete (`iptsd`,
`libwacom-surface`, linux-surface-Kernel) sind bereits installiert, und es
existieren Eingabegeräte auf beiden Pfaden gleichzeitig:

```
quickspi-hid 045E:0C7F Stylus      ← nativer Mainline-Treiber
IPTSD Virtual Stylus 045E:0C7F     ← von iptsd erzeugt
```

Arbeitshypothese: Konflikt zwischen iptsd und dem nativen quickspi-hid-Pfad.
`scripts/30-pen-diagnose.sh` grenzt ein, `scripts/31-pen-fix-iptsd-conflict.sh`
testet die Hypothese reversibel.

**Touch:** Status unklar — muss getestet werden. Falls Touch geht und nur der
Stift nicht, liegt es eher am Stift selbst (Ladung/Kopplung) als am Treiber.

**Kamera:** Weiter als erwartet. IPU6 startet inkl. Firmware-Authentifizierung,
`ov13858` (Rück-Sensor) ist geladen, beide Sensoren in ACPI sichtbar
(`OVTID858` Rück, `SONY0681` Front), drei INT3472-Bridges. Zwei konkrete
Blocker:

1. `int3472-discrete INT3472:00: GPIO type 0x08 unknown` — der laufende Kernel
   kennt GPIO-Typ `0x08` nicht. Patch existiert (Behandlung als Regulator-Pin
   `dvdd`, `GPIO_ACTIVE_HIGH`); trat beim Surface Pro 9 identisch auf.
   **Offene billige Frage:** Bringt der installierte linux-surface-Kernel den
   Patch mit? Kostet nur einen Neustart zum Testen.
2. `libcamera 0.2.0` ist zu alt — IPU6 braucht ≥ 0.3.2, der erfolgreiche
   Pro-9-Fall nutzte 0.7.1.

Details und Vorgehen: `docs/03-camera-status.md`, `docs/04-befund.md`.

## Wichtig zur Arbeitsweise

- **Die Skripte sind auf echter Hardware weitgehend ungetestet.** Sie entstanden
  in einer Cloud-Session ohne Zugriff auf das Gerät; nur `00-check-system.sh`
  ist einmal real gelaufen. Vor dem Ausführen prüfen, ob die Annahmen passen.
- **Vor systemverändernden Schritten erklären, was passiert** — besonders bei
  Kernel-, GRUB- und Modulthemen.
- Änderungen möglichst **reversibel** anlegen (siehe Muster in
  `31-pen-fix-iptsd-conflict.sh` mit `disable`/`enable`).
- `scripts/10-install-pen-touch.sh` ist **gegenstandslos** — die Pakete sind
  bereits installiert.

## Nächste Schritte

1. `bash scripts/30-pen-diagnose.sh` — liefert Touch- vs. Stift-Ereignisse und
   damit den Befund, wo der Stift hängt.
2. Je nach Ergebnis: `scripts/31-pen-fix-iptsd-conflict.sh disable` testen.
3. Kamera: in den linux-surface-Kernel booten (GRUB → Advanced options →
   `6.19.8-surface`), dann `bash scripts/20-camera-analyze.sh` — prüfen, ob die
   `GPIO type 0x08`-Warnung verschwindet.
4. Unabhängig davon: libcamera aktualisieren.
