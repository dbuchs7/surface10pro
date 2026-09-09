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
