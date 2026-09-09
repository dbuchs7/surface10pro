# Fehlerbericht-Vorlage für linux-surface

Zwei getrennte Befunde, die beide meldenswert sind. Vor dem Absenden mit
`bash scripts/35-collect-bugreport.sh` die Belege erzeugen und den
Report-Deskriptor (`bash scripts/36-hid-driver-probe.sh rdesc`) anhängen.

Zu melden unter: https://github.com/linux-surface/linux-surface/issues

---

## Befund 1 — Stift wird nie gemeldet (Hauptproblem)

**Titel:** `Surface Pro 10 for Business: stylus produces no input events (touch works)`

```markdown
## Device
Microsoft Surface Pro 10 for Business (Intel Core Ultra, Meteor Lake)
Digitizer: 045E:0C7F, QuickSPI mode (intel_quickspi / intel_thc)

## Distro / kernels tested
Zorin OS 18.1 (Ubuntu 24.04 base)
- 6.19.8-surface-3        -> same result
- 7.1.2-070102-generic    -> same result

## Summary
The touchscreen works. The stylus (Surface Slim Pen 2, charged, Bluetooth
connected, verified working under Windows on this same machine) produces no
input events at all.

## Measurement
Reading raw evdev directly from every input node of the digitizer, bypassing
libinput and the desktop, with a positive control:

| run                | events |
|--------------------|--------|
| finger (control)   | 2272-2504 on the touchscreen node (BTN_TOUCH, ABS_X, ABS_Y) |
| stylus             | 0 on every node, including the node named "Stylus" |

The control proves the measurement works, so the zero is meaningful: no pen
reports reach the kernel.

## What was ruled out
- Not userspace: nothing arrives at evdev, so libinput/libwacom/desktop
  mapping cannot be the cause.
- Not the kernel version: identical on 6.19.8-surface-3 and 7.1.2 mainline.
- Not the HID driver binding: hid-generic claims the device by default; after
  rebinding to hid-multitouch (via new_id) the device layout changed from 9
  input nodes to 2 and touch kept working, but the stylus still produced zero.
- Not the hardware or the pen: both work under Windows on this machine.

## Observation
Both hid-generic and hid-multitouch create an input device named
"quickspi-hid 045E:0C7F Stylus", so the HID report descriptor does declare a
stylus collection. The kernel knows a pen should exist; the device simply
never sends reports for it.

This looks like a missing initialisation: something Windows does to put the
digitizer into pen-reporting mode that the Linux THC/QuickSPI path does not.

## Attachments
- output of the diagnostic script (system, dmesg, input devices, rdesc)
- HID report descriptor
```

---

## Befund 2 — iptsd legt den Digitizer lahm (eigenständiger Bug)

**Titel:** `intel_quickspi: oversized report kills digitizer permanently (DMA buffer overflow)`

```markdown
## Device
Surface Pro 10 for Business, digitizer 045E:0C7F in QuickSPI mode.

## Summary
With iptsd running, the digitizer dies completely - touch and stylus - until
reboot. iptsd switches the device into raw mode, where reports exceed the
intel_quickspi DMA buffer:

    intel_quickspi 0000:00:10.0: Copied 4096 bytes instead of requested 4356
    intel_quickspi 0000:00:10.0: read DMA buffer failed -5
    ACPI: \_SB.PC00.THC0._RST: Excess arguments - Caller passed 1, ACPI requires 0
    intel_quickspi 0000:00:10.0: THC interrupt already unquiesce
    intel_quickspi 0000:00:10.0: Wait RESET_RESPONSE timeout, ret:0
    intel_quickspi 0000:00:10.0: Reset touch device failed, ret = -110

## Reproduction
1. Surface Pro 10, iptsd active (installed as a dependency of the usual
   linux-surface setup)
2. Boot - touch works for a few seconds
3. Take the stylus off the charger, so it becomes active
4. Digitizer dies entirely; only a reboot brings it back

Activating the pen appears to trigger a report larger than the 4096-byte
buffer.

## Workaround
Disabling iptsd makes touch permanently stable. On this device iptsd has no
role anyway - the digitizer runs in QuickSPI mode and iptsd-find-hidraw
reports "No devices found" (see linux-surface/iptsd#180).

## Suggestion
Two separate things worth addressing:
1. A report larger than the DMA buffer should not leave the device
   permanently dead - the reset path fails and never recovers.
2. iptsd should not attach to QuickSPI digitizers at all, or the packaging
   should not enable it on devices where it cannot work.
```

---

## Hinweis zur Erwartung

Ein Fehlerbericht ist keine Lösung, sondern ein Beitrag. Befund 2 ist gut
umrissen und könnte relativ zügig aufgegriffen werden. Befund 1 hängt an der
Reifung des THC-/QuickSPI-Stacks im Kernel und braucht vermutlich Geduld.

Der Bericht ist trotzdem sinnvoll: Die Datenlage ist ungewöhnlich sauber —
zwei Kernel, zwei Treiber, Positivkontrolle, Windows als Gegenprobe. Genau
solche Berichte sind für Entwickler brauchbar.
