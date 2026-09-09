# Kontext für Claude Code

## Gerät und System

- **Hardware:** Microsoft Surface Pro 10 for Business (Intel Core Ultra, Meteor Lake)
- **OS:** Zorin OS 18.1 Core (Ubuntu 24.04 LTS Unterbau, HWE-Kernel 6.17)
- **Ziel:** Stift/Touchscreen und Kamera zum Laufen bringen

## Stand der Dinge

**Stift/Touch:** Lösbar über den gepatchten `linux-surface`-Kernel plus `iptsd`
und `libwacom-surface`. Skript liegt bereit unter
`scripts/10-install-pen-touch.sh`, Anleitung in `docs/02-pen-touch-setup.md`.
Noch nicht ausgeführt.

**Kamera:** Funktioniert nicht. Wichtig — der Blocker ist **nicht** der
Bildprozessor: Das Gerät nutzt **IPU6EP** (nicht IPU7, das kommt erst mit Lunar
Lake / Surface Pro 11). Der IPU6-Treiber ist seit Kernel 6.10 mainline. Es
fehlen die **Sensortreiber**:

- IMX681 (Front): kein Linux-Treiber existiert — harter Blocker
- OV13858 (Rück): Mainline-Treiber vorhanden, Plattform-Verdrahtung
  (ACPI/INT3472, GPIO, Clocks) fehlt — aussichtsreichste Baustelle
- VD55G0 (IR): kein Treiber

Vorlage für die Rückkamera: linux-surface Discussion #2198 (Surface Pro 9,
gleicher IPU6-Unterbau, front+rear erfolgreich zum Laufen gebracht).
Analyse in `docs/03-camera-status.md`.

## Wichtig zur Arbeitsweise

- **Die Skripte wurden nie auf echter Hardware getestet.** Sie entstanden in
  einer Cloud-Session ohne Zugriff auf das Surface. Syntax und Ablauflogik sind
  geprüft, das Verhalten auf dem Gerät nicht. Vor dem Ausführen prüfen, ob die
  Annahmen zum tatsächlichen System passen.
- **Vor systemverändernden Schritten erklären, was passiert** — insbesondere
  bei Kernel-Installation, GRUB-Änderungen und Secure-Boot-/MOK-Enrollment.
- Der bestehende Zorin-Kernel muss als Fallback erhalten bleiben.
- `scripts/00-check-system.sh` ist read-only und der richtige erste Schritt.

## Nächster Schritt

`scripts/00-check-system.sh` ausführen und auswerten. Besonders relevant:
Secure-Boot-Status (bestimmt, ob MOK-Enrollment nötig wird), tatsächliche
Kernel-Version, und ob im Kamera-Abschnitt `INT3472`-ACPI-Einträge oder
IPU-Module auftauchen — das würde zeigen, wie weit die Treiberkette real kommt.

Für die Kamera-Analyse ist ein ACPI-Dump der nächste sinnvolle Schritt:
`sudo acpidump -b -o acpi.dat && iasl -d *.dat`, dann `DSDT.dsl` nach
`IMX681`, `OV13858` und `INT3472` durchsuchen.
