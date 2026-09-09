# Befund vom echten Gerät (09.09.2026)

Erste Messung auf dem tatsächlichen Surface Pro 10 for Business. Ergebnis in
einem Satz: **Stift und Touch laufen bereits, und die Kamera ist viel weiter
als die linux-surface-Matrix vermuten lässt** — es fehlen zwei konkrete,
benennbare Dinge.

## Systemzustand

| | |
|---|---|
| OS | Zorin OS 18.1 (noble) |
| Laufender Kernel | `7.1.2-070102-generic` — **Mainline, nicht der Surface-Kernel** |
| Installiert, aber nicht gebootet | `linux-image-surface 6.19.8-surface-3` |
| Secure Boot | deaktiviert, Platform in Setup Mode → kein MOK nötig |
| linux-surface Repo | eingerichtet |
| iptsd / libwacom-surface | installiert (3.1.0-1 / 2.17.0-1) |

Wichtig: Der linux-surface-Kernel ist **installiert, läuft aber nicht**.
Gebootet wird ein neuerer Mainline-Kernel (7.1.2).

## Stift und Touchscreen: funktionieren

```
input: IPTSD Virtual Touchscreen 045E:0C7F
input: IPTSD Virtual Stylus   045E:0C7F

Device: quickspi-hid 045E:0C7F Touchscreen   Capabilities: touch
Device: quickspi-hid 045E:0C7F Stylus        Capabilities: tablet
```

Der Digitizer wird vom Mainline-Treiber `quickspi-hid` bedient (Intel Touch
Host Controller), zusätzlich laufen die iptsd-Virtualgeräte. `scripts/10-install-pen-touch.sh`
ist damit **gegenstandslos** — die Pakete sind bereits installiert.

## Kamera: zwei konkrete Blocker, beide bekannt

Was bereits funktioniert:

```
00:05.0 Multimedia controller [8086:7d19]
intel-ipu6: Sending BOOT_LOAD to CSE → CSE authenticate_run done
intel-ipu6: IPU6-v4[7d19] hardware version 6
Module geladen: intel_ipu6, intel_ipu6_isys, ipu_bridge, ov13858
ACPI: INT3472:00  INT3472:01  INT3472:02  OVTID858:00  SONY0681:00
/dev/video0 ... /dev/video47 vorhanden
```

Der ISP initialisiert sauber inklusive Firmware-Authentifizierung, der
Rück-Sensortreiber `ov13858` ist geladen, alle drei INT3472-Bridges und beide
Sensoren sind in ACPI sichtbar (`OVTID858` = OV13858 Rück, `SONY0681` = IMX681
Front).

### Blocker 1 — INT3472 GPIO-Typ 0x08

```
int3472-discrete INT3472:00: GPIO type 0x08 unknown; the sensor may not work
```

Der Kernel kennt den GPIO-Typ `0x08` nicht und bricht die Ressourcen-Zuordnung
für diese Bridge ab — der Sensor bekommt damit keine saubere Stromsequenz.

Die bekannten Typen sind `0x00` Reset, `0x01` Powerdown, `0x02` Strobe,
`0x0b` Power enable, `0x0c` Clock enable, `0x0d` Privacy LED, `0x10` DOVDD,
`0x12` Handshake, `0x13` Hotplug detect. Für `0x08` existiert ein Patch, der
ihn als Regulator-Pin (`dvdd`, `GPIO_ACTIVE_HIGH`) behandelt. Dasselbe Problem
trat beim Surface Pro 9 auf.

Der laufende Mainline-Kernel 7.1.2 hat diesen Patch offensichtlich nicht.
**Ob der linux-surface-Kernel ihn mitbringt, ist die billigste offene Frage** —
er ist bereits installiert, es kostet einen Neustart.

### Blocker 2 — libcamera zu alt

```
libcamera v0.2.0
Available cameras:
   (leer)
```

Zorin 18.1 liefert **libcamera 0.2.0**. IPU6-Unterstützung gibt es erst ab
**0.3.2**; der erfolgreiche Surface-Pro-9-Fall nutzte 0.7.1. Selbst wenn der
Sensor sauber initialisiert, kann diese Version keine Kamera melden.

Dieser Blocker ist unabhängig vom ersten und muss ohnehin behoben werden.

## Nächste Schritte, nach Aufwand sortiert

1. **In den linux-surface-Kernel booten** und `scripts/20-camera-analyze.sh`
   erneut laufen lassen. Kostet einen Neustart, ist bereits installiert, Secure
   Boot ist aus. Wenn die `0x08`-Warnung verschwindet, ist Blocker 1 erledigt.
2. **libcamera aktualisieren** — nötig in jedem Fall.
3. **Nur falls 1 nicht hilft:** int3472 mit dem `0x08`-Patch als DKMS-Modul
   bauen.

## Hinweis zu den /dev/video-Knoten

Die 48 `/dev/video*`-Knoten sind die ISYS-Capture-Knoten des IPU6, **keine**
fertigen Kameras. Anwendungen wie Zoom oder Teams können damit nichts anfangen.
Dafür braucht es später zusätzlich `v4l2loopback` + `v4l2-relayd`
(siehe [03-camera-status.md](03-camera-status.md)).

---

## Nachtrag: weder Touch noch Stift reagieren

Rückmeldung vom Gerät: Der Stift zeichnet nicht, **und der Touchscreen reagiert
ebenfalls nicht**. Der Stift ist geladen und per Bluetooth verbunden — die
BT-Verbindung betrifft aber nur Knopf und Haptik, nicht den Strich. Der Strich
läuft über den Digitizer im Display.

Damit liefert der gesamte Digitizer-Pfad nichts, obwohl beide Eingabegeräte
angelegt sind.

### Die eigentliche Ursache: eine gemischte Konfiguration

Es gibt zwei in sich stimmige Wege, den Digitizer zu betreiben:

| | Kernel | Digitizer-Weg | iptsd |
|---|---|---|---|
| **A — der linux-surface-Weg** | `6.19.8-surface-3` | IPTS/ITHC-Rohdaten | **wird gebraucht** |
| **B — der Mainline-Weg** | neuer Mainline-Kernel | `quickspi-hid` nativ | **stört nur** |

Auf dem Gerät läuft derzeit eine **Mischung aus beidem**: Mainline-Kernel
`7.1.2-070102-generic` *plus* aktives `iptsd`. In dieser Kombination schaltet
iptsd den Digitizer in den Rohdatenmodus und verarbeitet die Daten selbst —
kennt aber das Format nicht. Gleichzeitig bekommt `quickspi-hid` keine normalen
HID-Meldungen mehr, weil das Gerät umgeschaltet wurde. Ergebnis: Geräte
sichtbar, Eingaben tot. Genau das beobachtete Symptom.

Der laufende Kernel ist zudem weder der Zorin-Standardkernel (6.17 HWE) noch
der Surface-Kernel, sondern ein Mainline-Build aus dem PPA.

### Vorgehen: erst Weg A, dann Weg B

**Weg A hat Vorrang** — alle Pakete dafür sind bereits installiert, es fehlt nur
der passende Kernel, und derselbe Neustart beantwortet nebenbei die offene
Kamera-Frage (ob der Surface-Kernel den INT3472-Patch für GPIO-Typ `0x08`
mitbringt).

1. Neu starten, im GRUB-Menü `6.19.8-surface` wählen → Touch und Stift testen
2. Klappt es: gleich `bash scripts/20-camera-analyze.sh` laufen lassen
3. Klappt es nicht: zurück auf den Mainline-Kernel und dort Weg B testen
   (`scripts/31-pen-fix-iptsd-conflict.sh disable`)

---

## Nachtrag 2: Touch läuft kurz nach dem Boot, dann stirbt es

Auf dem Surface-Kernel `6.19.8-surface-3` reagierte der Touchscreen **kurz nach
dem Hochfahren**, danach nicht mehr. Der Stift zu keinem Zeitpunkt.

Das ergibt eine schlüssige Abfolge:

1. Beim Boot bindet `quickspi-hid` den Digitizer und liefert normale
   HID-Ereignisse → Touch funktioniert
2. Wenige Sekunden später startet `iptsd` (udev-getriggert; im dmesg der ersten
   Messung bei 3,97 s sichtbar) und beansprucht das Gerät
3. Der Digitizer wird in den Rohdatenmodus geschaltet → `quickspi-hid` bekommt
   keine HID-Meldungen mehr, und iptsd selbst kann das Format nicht verwerten
4. Ergebnis: beide Eingabewege tot

### Korrektur einer früheren Annahme

Ursprünglich stand hier, der linux-surface-Kernel brauche iptsd („Weg A").
Das gilt für ältere Surface-Modelle mit IPTS/ITHC. **Für den Surface Pro 10
nicht:** Dessen Digitizer (`045E:0C7F`) arbeitet im **QuickSPI-Modus** und ist
seit **Kernel 6.14 nativ unterstützt**. Passend dazu meldet
`iptsd-find-hidraw` auf diesem Modell „No devices found"
([linux-surface/iptsd#180](https://github.com/linux-surface/iptsd/issues/180)).

Die richtige Konfiguration für dieses Gerät lautet also:

| | |
|---|---|
| Kernel | `6.19.8-surface-3` (oder neuer) |
| Digitizer | `quickspi-hid`, nativ |
| iptsd | **abgeschaltet** |

Ein veröffentlichter Erfahrungsbericht zum selben Gerät auf Kernel
`6.19.8-surface` bestätigt, dass Touchscreen und Slim Pen inklusive Radierer
und Seitentaste damit funktionieren.

### Konkreter Schritt

```bash
bash scripts/31-pen-fix-iptsd-conflict.sh disable
sudo reboot          # dabei wieder den 6.19.8-surface-Eintrag wählen
```

Funktioniert es, sollte der Surface-Kernel dauerhaft als GRUB-Standard gesetzt
werden, damit die Auswahl beim Booten entfällt.

---

## Ursache gefunden: DMA-Pufferüberlauf im intel_quickspi-Treiber

Die Zustandsaufnahme direkt nach dem Ausfall (09.09.2026, 08:57) liefert die
vollständige Fehlerkette:

```
intel_quickspi 0000:00:10.0: Copied 4096 bytes instead of requested 4356
intel_quickspi 0000:00:10.0: read DMA buffer failed -5
ACPI: \_SB.PC00.THC0._RST: Excess arguments - Caller passed 1, ACPI requires 0
intel_quickspi 0000:00:10.0: THC interrupt already unquiesce
intel_quickspi 0000:00:10.0: Wait RESET_RESPONSE timeout, ret:0
intel_quickspi 0000:00:10.0: Reset touch device failed, ret = -110
```

### Was passiert

1. Der Digitizer sendet eine Meldung von **4356 Byte**
2. Der DMA-Puffer des `intel_quickspi`-Treibers fasst **4096 Byte** →
   abgeschnitten, Lesefehler `-5` (EIO)
3. Der Treiber versucht, den Touch-Controller zurückzusetzen
4. Der Reset läuft in einen Timeout (`-110`, ETIMEDOUT)
5. Touch **und** Stift sind tot bis zum Neustart

### Warum 4356 Byte — und warum beim Stift

Im Protokoll lief zu diesem Zeitpunkt:

```
iptsd@dev-hidraw0.service   loaded active running
875 /usr/bin/iptsd /dev/hidraw0
```

`iptsd` öffnet `/dev/hidraw0` und schaltet den Digitizer in den
Rohdaten-/Heatmap-Modus. Dort werden große Meldungen gesendet statt kleiner
HID-Berichte. Das Aktivieren des Stifts löst genau so eine große Meldung aus —
deshalb das beobachtete Muster: Touch läuft kurz, Stift aus der Ladestation
genommen, alles tot.

### Konsequenz

Der Befund von oben wird damit bestätigt und präzisiert: iptsd ist auf dem
Pro 10 nicht nur überflüssig, sondern **die Ursache des Ausfalls**. Der
Digitizer wird von `quickspi-hid` nativ bedient und braucht keinen Daemon.

Zusätzlich sichtbar, aber nicht ursächlich:
`Can't find wake GPIO resource` und die ACPI-Warnung zu `THC0._RST`
(überzähliges Argument) — beides beeinträchtigt den Normalbetrieb nicht.

### Offener Kernel-Fehler

Unabhängig von iptsd ist das Verhalten des Treibers ein Bug: Eine Meldung, die
größer als der DMA-Puffer ist, sollte nicht zum unwiederbringlichen Ausfall des
Geräts führen. Das wäre ein wertvoller Fehlerbericht an linux-surface, weil der
Reproduktionsweg präzise ist: *iptsd aktiv auf einem QuickSPI-Gerät, Stift
aktivieren, Digitizer stirbt mit `read DMA buffer failed -5`.*

---

## Bestätigt: iptsd war die Ursache — Touch läuft stabil

Nach dem gründlichen Abschalten von iptsd (Instanz `iptsd@dev-hidraw0.service`
gestoppt und maskiert, udev-Regel neutralisiert):

- **Touch funktioniert dauerhaft**
- Der Ausfall tritt **nicht mehr** auf, auch nicht beim wiederholten Entnehmen
  des Stifts aus der Ladestation
- Der DMA-Überlauf im `intel_quickspi`-Treiber ist damit behoben, weil der
  Digitizer im normalen HID-Modus bleibt und keine 4356-Byte-Meldungen mehr
  erzeugt

Die Diagnose ist damit vollständig bestätigt.

### Offen: der Stift zeichnet weiterhin nicht

Touch ist stabil, der Stift liefert nichts. Da der Digitizer jetzt sauber
arbeitet, ist die entscheidende Frage, auf welcher Ebene es scheitert:

| Beobachtung | Bedeutung |
|---|---|
| Kernel liefert Bytes auf dem evdev-Knoten | Treiber in Ordnung → Problem in libinput/libwacom/Desktop |
| Kernel liefert nichts | Digitizer meldet den Stift nicht → Treiber- oder Hardwareebene |

`scripts/33-stylus-deep-test.sh` liest dafür **direkt von den evdev-Knoten**,
unter Umgehung von libinput und Desktop, und trennt damit die beiden Fälle.

Zur Einordnung: Der Digitizer legt neun Eingabegeräte an (`input1`–`input9`),
von denen nur zwei sprechende Namen tragen (`Touchscreen` = input4,
`Stylus` = input7). Die Stiftdaten könnten auch auf einem der unbenannten
Geräte ankommen — deshalb liest der Test von allen gleichzeitig.

---

## Endbefund Stift: der Digitizer meldet ihn nicht an den Kernel

Messung mit `scripts/34-input-monitor.py`, das direkt von allen neun
evdev-Knoten liest — an libinput und Desktop vorbei:

| Durchlauf | Ergebnis |
|---|---|
| **Finger (Kontrolle)** | **2007 Ereignisse** auf `event4`, mit `BTN_TOUCH`, `ABS_X`, `ABS_Y` |
| **Stift** | **0 Ereignisse** auf allen neun Knoten |

Die Kontrolle beweist, dass die Messung funktioniert. Das Nullergebnis beim
Stift ist damit belastbar.

**Schlussfolgerung:** Es erreichen überhaupt keine Stift-Berichte den Kernel.
Das ist **kein** Problem von libinput, libwacom oder der Desktop-Zuordnung —
auf dieser Ebene könnte man nichts reparieren, weil dort nie etwas ankommt.

Bemerkenswert: `event7` trägt den Namen `quickspi-hid 045E:0C7F Stylus`, das
Gerät existiert also und der HID-Deskriptor deklariert eine Stift-Funktion.
Es kommt nur nie ein Bericht darauf an. Der Digitizer sendet im aktuellen
Zustand schlicht keine Stiftdaten.

Gegenprobe: Derselbe Stift (Surface Slim Pen 2, geladen, per Bluetooth
verbunden) funktioniert auf demselben Gerät **unter Windows**. Hardware und
Stift sind damit ausgeschlossen.

### Bewertung

Der `intel_quickspi`-Treiber ist jung — Intels THC-Treiber kamen erst kürzlich
in den Kernel, und der HID-over-SPI-Modus wird gerade erst ausgebaut. Eine
fehlende Initialisierung für den Stiftbetrieb, die Windows durchführt, ist die
plausibelste Erklärung. Das ist nichts, was sich lokal konfigurieren lässt.

### Verbleibende Optionen

1. **Anderen Kernel testen** — der Mainline-Kernel `7.1.2-070102-generic` ist
   noch installiert und ist **neuer** als der Surface-Kernel 6.19.8. Da iptsd
   jetzt systemweit abgeschaltet ist, wäre ein Testlauf dort sauber. Billigster
   noch offener Versuch: ein Neustart.
2. **Fehlerbericht bei linux-surface** — die Datenlage ist ungewöhnlich gut:
   exakte Kernel-Version, saubere Messung mit Positivkontrolle, Windows als
   Gegenprobe, plus der unabhängige iptsd/DMA-Befund.
   `scripts/35-collect-bugreport.sh` stellt die Belege zusammen.
3. **Warten** auf Reifung des THC-/QuickSPI-Stacks im Kernel.

Ein zweiter, unabhängig meldenswerter Befund bleibt bestehen: `intel_quickspi`
sollte eine zu große Meldung nicht mit einem unwiederbringlichen Geräteausfall
quittieren.
