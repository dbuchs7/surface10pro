# Welche Linux-Distribution läuft auf dem Surface Pro 10 mit Stift, Touch und Kamera?

**Kurzantwort: Keine — und ein Wechsel der Distribution ändert daran nichts.**

Die drei offenen Punkte hängen nicht an der Distribution, sondern an Code, den
alle Distributionen gemeinsam nutzen. Ein Wechsel kostet einen Arbeitstag und
bringt in der Sache nichts.

## Wo die Unterstützung tatsächlich herkommt

| Baustein | Herkunft | Distributionsabhängig? |
|---|---|---|
| Digitizer (Stift/Touch) | Linux-Kernel, Treiber `intel_quickspi`/`intel_thc` | **nein** — gleicher Code überall |
| Kamera-ISP (IPU6) | Linux-Kernel, seit 6.10 mainline | **nein** |
| Stromversorgung Sensoren | Kernel, `int3472` + linux-surface-Patches | nur: ob linux-surface-Kernel verfügbar ist |
| Sensortreiber (IMX681, OV13858) | Kernel bzw. `intel/ipu6-drivers` | **nein** |
| libcamera | Distributionspaket | **ja** — hier gibt es Unterschiede |
| PipeWire-Kameraanbindung | Distributionspaket | **ja** |

Entscheidend ist die dritte Spalte: Alles, was bei diesem Gerät fehlt, steht in
den Zeilen mit **nein**.

## Die drei offenen Punkte im Einzelnen

### Frontkamera (IMX681) — von keiner Distribution unterstützt

Für diesen Sensor existiert **kein Linux-Treiber**. Weder im Mainline-Kernel
noch in Intels Out-of-Tree-Repository `intel/ipu6-drivers`, das folgende
Sensoren abdeckt:

```
HM11B1, OV01A1S, OV01A10, OV02C10, OV02E10, OV2740, HM2170, HM2172, HI556
```

IMX681 ist nicht dabei. Distributionen schreiben keine eigenen Sensortreiber —
sie packen den Kernel, den es gibt. Ob Fedora, Arch, openSUSE oder Ubuntu:
alle greifen auf dieselbe Treiberbasis zu, und in der fehlt dieser Sensor.

**Fazit: Es gibt derzeit keine Linux-Distribution, auf der die Frontkamera des
Surface Pro 10 funktioniert.**

### Stift — Treiberlücke im Kernel, auf zwei Kerneln geprüft

Gemessen auf diesem Gerät (siehe [04-befund.md](04-befund.md)):

| Kernel | Touch | Stift |
|---|---|---|
| `6.19.8-surface-3` | 2007 Ereignisse | **0** |
| `7.1.2-070102-generic` (Mainline) | 2272 Ereignisse | **0** |

Zusätzlich ohne Wirkung: Wechsel von `hid-generic` auf `hid-multitouch`.

Der Digitizer meldet den Stift nicht an den Kernel. Das ist Kernelcode, den
jede Distribution identisch verwendet. Eine andere Distribution mit demselben
oder neuerem Kernel wird dasselbe Ergebnis liefern.

### Rückkamera — funktioniert bereits, andernorts mit weniger Handarbeit

Das ist der einzige Punkt, an dem die Distribution einen Unterschied macht.

Auf diesem Gerät läuft sie inzwischen: Aufnahme mit rund 30 fps, nachdem
libcamera 0.7.2 selbst gebaut wurde (Zorin liefert 0.2.0, zu alt für IPU6).

Fedora liefert seit Version 41 IPU6-Kameraunterstützung mit aktuellem
libcamera und PipeWire-Anbindung ab Werk. Dort hätte dieser Schritt weniger
Handarbeit gekostet — **er ist auf diesem Gerät aber bereits erledigt.**

## Vergleich der Distributionen

| | Zorin 18.1 (jetzt) | Fedora 42+ | Arch | Ubuntu 24.04 |
|---|---|---|---|---|
| linux-surface-Kernel | ✅ Paketquelle | ✅ Paketquelle | ✅ AUR/Repo | ✅ Paketquelle |
| Touch | ✅ läuft | ✅ | ✅ | ✅ |
| Stift | ❌ | ❌ | ❌ | ❌ |
| Rückkamera | ✅ (selbst gebaut) | ✅ eher ab Werk | ✅ aktuelles libcamera | ❌ libcamera zu alt |
| Frontkamera | ❌ | ❌ | ❌ | ❌ |
| IR / Windows Hello | ❌ | ❌ | ❌ | ❌ |
| Aufwand für dich | **null, läuft** | Neuinstallation | Neuinstallation | Neuinstallation |

## Empfehlung

**Auf Zorin bleiben.** Der Zustand ist erreicht, die Nacharbeit erledigt. Ein
Wechsel würde die Frontkamera nicht bringen, den Stift nicht bringen, und die
bereits gelöste Rückkamera erneut Arbeit kosten.

Fedora wäre erwägenswert **wenn** du ohnehin neu aufsetzt und weniger
Eigenbau möchtest — die IPU6-Anbindung ist dort integrierter. Als Grund für
einen Wechsel reicht das nicht.

## Was dein Arbeitsszenario tatsächlich braucht

Für Citrix VDI mit Webmeetings ist die interne Frontkamera nicht erforderlich.
Die Citrix Workspace App unter Linux greift Kameras über `/dev/video*` ab und
reicht sie per HDX in die Sitzung weiter. Was dort liegt, ist ihr gleichgültig:

| Quelle | Aufwand | Bildqualität |
|---|---|---|
| USB-Webcam | anstecken, fertig | gut bis sehr gut |
| Handy als Webcam (droidcam o.ä.) | einmalige Einrichtung | meist besser als eingebaut |
| Rückkamera über die Brücke | bereits eingerichtet | brauchbar, zeigt nach hinten |

Damit ist das Gerät für den geschäftlichen Einsatz verwendbar — mit einer
externen Kamera statt der eingebauten.

## Die ehrliche Gesamtbilanz

| Komponente | Stand | Aussicht |
|---|---|---|
| Touchscreen | ✅ läuft stabil | — |
| Tastatur, Touchpad, WLAN, Bluetooth, Akku | ✅ | — |
| Rückkamera | ✅ läuft | — |
| Stift | ❌ | offen; hängt an der Reifung des THC/QuickSPI-Stacks im Kernel |
| Frontkamera | ❌ | offen; erfordert einen neuen Sensortreiber, den niemand begonnen hat |
| IR / Windows Hello | ❌ | wie Frontkamera |

Wer Stift und Frontkamera zwingend braucht, ist auf diesem Gerät derzeit auf
Windows angewiesen. Das ist keine Aussage über Linux oder über Zorin, sondern
über ein Gerät von 2024, für das der Hersteller keine Linux-Treiber liefert
und dessen Sensoren noch niemand nachgebaut hat.
