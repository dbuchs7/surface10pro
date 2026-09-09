# Kontext für Claude Code

## Gerät und System

- **Hardware:** Microsoft Surface Pro 10 for Business (Intel Core Ultra, Meteor Lake)
- **OS:** Zorin OS 18.1 Core (Ubuntu 24.04 LTS Unterbau)
- **Kernel:** `6.19.8-surface-3` ist der richtige für dieses Gerät.
  `7.1.2-070102-generic` (Mainline) bleibt als Fallback installiert, taugt aber
  **nicht für die Kamera** — ihm fehlen die linux-surface-Patches.
- **Secure Boot:** deaktiviert, Platform in Setup Mode → kein MOK nötig
- **iptsd:** abgeschaltet und maskiert. Muss so bleiben.

Vollständige Fehlersuche: `docs/04-befund.md`.

## Stand

**Touch: gelöst.** iptsd schaltete den Digitizer in den Rohdatenmodus, dort
sendet er 4356-Byte-Meldungen, der DMA-Puffer von `intel_quickspi` fasst 4096
→ `read DMA buffer failed -5` → Reset-Timeout `-110` → Digitizer tot bis zum
Neustart. Das Aktivieren des Stifts löste solche Meldungen aus. Nach
`scripts/31-pen-fix-iptsd-conflict.sh disable` läuft Touch dauerhaft.

**Stift: Treiberlücke, lokal ausgeschöpft.** Gemessen mit
`scripts/34-input-monitor.py` (liest direkt von allen evdev-Knoten, mit
Positivkontrolle): Finger ~2000–2500 Ereignisse, Stift **null**. Ohne Wirkung
blieben: Mainline-Kernel 7.1.2, Bindung an `hid-multitouch` statt
`hid-generic`. Beide Treiber legen ein Gerät `…Stylus` an — der HID-Deskriptor
deklariert also einen Stift, das Gerät sendet nur nie Berichte dafür. Derselbe
Stift funktioniert unter Windows.
→ Nichts mehr lokal zu holen. Fertige Berichtsvorlage: `docs/05-bugreport.md`.

**Kamera: aussichtsreich, Messung auf dem Surface-Kernel steht aus.**
Auf Mainline 7.1.2 gemessen und damit erklärt:
`GPIO type 0x08 unknown` → kein Regulator → keine Spannung → `ov13858` kann die
Chip-ID nicht lesen (`failed to find sensor: -5`) → kein Sensor im Media-Graph
→ libcamera findet nichts.

Entscheidend: [linux-surface PR #1867](https://github.com/linux-surface/linux-surface/pull/1867)
(gemerged 31.12.2025) behandelt GPIO-Typ `0x08` als Regulator `pwr1`, gibt
`ov13858` Regulator-/Reset-/Takt-Steuerung und trägt `OVTID858` (4 Lanes,
540 MHz) in die ipu-bridge ein — exakt diese Hardware. Diese Patches sind im
**Surface-Kernel**, nicht in Mainline. Dazu passt, dass der Surface-Kernel
`ov13858: Reset de-asserted, sensor should be ready` meldet.

Erwartung: Auf `6.19.8-surface-3` bindet der Sensor, und es bleibt allein
**libcamera 0.2.0** (zu alt, IPU6 braucht ≥ 0.3.2, Pro-9-Fall nutzte 0.7.1).

## Arbeitsweise

- **Skripte vor der Auslieferung prüfen.** In dieser Sitzung sind mehrfach
  ungetestete Skripte an der echten Hardware gescheitert: `wait` ohne
  Argumente (Endlosschleife), `awk match()` mit drei Argumenten (Ubuntu hat
  mawk), `grub.cfg` ohne sudo gelesen (Modus 600). Wo möglich Tests in
  `tests/` ergänzen, sie haben zwei dieser Fehler vorab gefunden.
- **Vor systemverändernden Schritten erklären, was passiert.**
- Änderungen **reversibel** anlegen (Muster: `disable`/`enable`/`revert`).
- `scripts/10-install-pen-touch.sh` ist gegenstandslos — Pakete sind installiert.

## Nächste Schritte

1. `bash scripts/40-grub-default.sh set` → Surface-Kernel als GRUB-Standard,
   dann Neustart und `uname -r` prüfen.
2. `bash scripts/20-camera-analyze.sh` **auf dem Surface-Kernel** — die
   entscheidende offene Messung.
3. Je nach Ergebnis: libcamera ≥ 0.3.2 bauen (Distribution liefert nur 0.2.0).
   Danach `v4l2loopback` + `v4l2-relayd`, damit Anwendungen die Kamera als
   `/dev/video*` sehen — IPU6-Kameras erscheinen dort nicht von selbst.
4. Optional: Fehlerbericht zum Stift und zum `intel_quickspi`-DMA-Überlauf
   absenden (`docs/05-bugreport.md`, Belege via `scripts/35-collect-bugreport.sh`).
