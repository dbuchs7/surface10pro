# Stift & Touchscreen einrichten

Zielsystem: Surface Pro 10 for Business, Zorin OS 18.1 Core (Ubuntu 24.04 LTS
Unterbau, HWE-Kernel 6.17). Wir installieren den gepatchten
`linux-surface`-Kernel **zusätzlich** zum bestehenden Zorin-Kernel — dein
aktueller Kernel bleibt als Fallback erhalten.

## 0. Diagnose (read-only, ungefährlich)

```bash
bash scripts/00-check-system.sh
```

Prüft Zorin-/Ubuntu-Version, Secure-Boot-Status, vorhandene Pakete sowie den
aktuellen Zustand von Stift/Touch und Kamera. Ändert nichts.

## 1. Installation

```bash
bash scripts/10-install-pen-touch.sh
```

Das Skript:
1. fügt das linux-surface apt-Repository + Signing-Key hinzu,
2. installiert `linux-image-surface`, `linux-headers-surface`,
   `libwacom-surface`, `iptsd`,
3. erkennt automatisch, ob Secure Boot aktiv ist, und installiert bei Bedarf
   `linux-surface-secureboot-mok`,
4. aktualisiert GRUB.

Vor jedem größeren Schritt wird nachgefragt.

## 2. Neustart & MOK-Enrollment (nur bei aktivem Secure Boot)

Nach `sudo reboot` erscheint ein **blaues MokManager-Menü**:

1. „Enroll MOK" auswählen
2. „Continue"
3. „Yes" bestätigen
4. Passwort: `surface`
5. Neustart

Ohne diesen Schritt bootet der neue Kernel bei aktivem Secure Boot nicht.
Das Passwort `surface` ist der Standard des linux-surface-Pakets — es wird nur
einmalig zur Bestätigung der Schlüsselregistrierung im UEFI benötigt.

## 3. Prüfen, ob der richtige Kernel läuft

```bash
uname -a
```

Muss `surface` enthalten. Falls nicht: beim Booten im GRUB-Menü „Advanced
options for Ubuntu" wählen und den Eintrag mit `surface` im Namen nehmen.

GRUB sortiert Kernel nach Versionsnummer, nicht nach Name — es kann also
passieren, dass der Zorin-HWE-Kernel (6.17) höher sortiert wird als der
Surface-Kernel. Erst wenn alles läuft, ggf. `GRUB_DEFAULT` in
`/etc/default/grub` fest auf den Surface-Eintrag setzen und `sudo update-grub`
ausführen.

## 4. Stift & Touch testen

```bash
systemctl status iptsd
sudo libinput debug-events
```

Beim zweiten Befehl Bildschirm berühren bzw. Stift annähern — es sollten Events
erscheinen. Mit `Strg+C` beenden.

Für Druckstufen in Zeichenprogrammen (Krita, GIMP, Xournal++) ist zusätzlich
`libwacom-surface` nötig — wird vom Installationsskript mitinstalliert.

## Falls etwas schiefgeht

```bash
bash scripts/90-uninstall-surface-kernel.sh
```

Entfernt den linux-surface-Kernel; beim nächsten Neustart läuft wieder der
ursprüngliche Zorin-Kernel.

Kommst du gar nicht mehr ins System: im GRUB-Menü „Advanced options" den alten
Kernel wählen — er wurde nie entfernt.

## Bekannte Stolpersteine

- **Bootet nicht in den Surface-Kernel**: siehe GRUB-Hinweis in Schritt 3.
- **iptsd startet nicht**: `sudo dmesg | grep -iE 'ipts|ithc'` prüfen. Meist
  hakt es an der Firmware-/Kalibrierungsdatei des Digitizers.
- **Touch funktioniert, Stift nicht (oder ohne Druckstufen)**: prüfen, ob
  `libwacom-surface` installiert ist (`dpkg -l | grep libwacom`) — das
  Standard-`libwacom` von Ubuntu kennt die Surface-Geräte nicht.
- **Nach Kernel-Update kein Stift mehr**: `iptsd` neu starten
  (`sudo systemctl restart iptsd`); ggf. wurde ein Nicht-Surface-Kernel gebootet.
