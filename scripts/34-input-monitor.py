#!/usr/bin/env python3
"""Read raw evdev events from the digitizer with a hard deadline.

Replaces the shell version, which used backgrounded readers plus sudo plus
wait - too many ways to hang. Here a single process polls all devices with
select() against an absolute deadline, so it always terminates, and decodes
the events instead of merely counting bytes.

Usage:  sudo python3 34-input-monitor.py [pen|touch] [seconds]
"""
import os
import re
import select
import struct
import sys
import time

# struct input_event on 64-bit: timeval (2x long) + type + code + value
EVENT_FORMAT = "llHHi"
EVENT_SIZE = struct.calcsize(EVENT_FORMAT)

EV_KEY, EV_ABS = 0x01, 0x03

KEY_NAMES = {
    0x110: "BTN_LEFT", 0x14a: "BTN_TOUCH",
    0x140: "BTN_TOOL_PEN", 0x141: "BTN_TOOL_RUBBER",
    0x145: "BTN_TOOL_FINGER", 0x14b: "BTN_STYLUS", 0x14c: "BTN_STYLUS2",
}
ABS_NAMES = {
    0x00: "ABS_X", 0x01: "ABS_Y", 0x18: "ABS_PRESSURE",
    0x1a: "ABS_TILT_X", 0x1b: "ABS_TILT_Y",
    0x2f: "ABS_MT_SLOT", 0x35: "ABS_MT_POSITION_X", 0x36: "ABS_MT_POSITION_Y",
    0x39: "ABS_MT_TRACKING_ID",
}
# Events only a pen produces - the decisive signal.
PEN_KEYS = {0x140, 0x141, 0x14b, 0x14c}
PEN_ABS = {0x18, 0x1a, 0x1b}


def find_devices(path="/proc/bus/input/devices", match="quickspi"):
    """Return [(event_node, name)] for every matching input device."""
    out, name, handlers = [], "", ""
    try:
        with open(path) as fh:
            for line in fh:
                line = line.rstrip("\n")
                if line.startswith("N: Name="):
                    name = line[8:].strip('"')
                elif line.startswith("H: Handlers="):
                    handlers = line[12:]
                elif not line:
                    if match in name.lower():
                        for tok in handlers.split():
                            if tok.startswith("event"):
                                out.append((tok, name))
                    name, handlers = "", ""
    except OSError as exc:
        print(f"Kann /proc/bus/input/devices nicht lesen: {exc}", file=sys.stderr)
    return out


def capture(fds, duration):
    """Poll every fd until the deadline. Always terminates: the loop is bounded
    by an absolute deadline, and select() gets the remaining time as timeout."""
    counts = {node: 0 for node, _ in fds.values()}
    seen_keys, seen_abs = set(), set()
    deadline = time.monotonic() + duration
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        ready, _, _ = select.select(list(fds), [], [], min(remaining, 0.5))
        for fd in ready:
            node = fds[fd][0]
            try:
                data = os.read(fd, EVENT_SIZE * 64)
            except (BlockingIOError, OSError):
                continue
            if not data:
                continue
            for off in range(0, len(data) - EVENT_SIZE + 1, EVENT_SIZE):
                _, _, etype, code, _ = struct.unpack(
                    EVENT_FORMAT, data[off:off + EVENT_SIZE])
                counts[node] += 1
                if etype == EV_KEY:
                    seen_keys.add(code)
                elif etype == EV_ABS:
                    seen_abs.add(code)
    return counts, seen_keys, seen_abs


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "pen"
    duration = int(sys.argv[2]) if len(sys.argv) > 2 else 15

    if os.geteuid() != 0:
        print("Bitte mit sudo starten:  sudo python3 " + sys.argv[0], file=sys.stderr)
        return 1

    devices = find_devices()
    if not devices:
        print("Keine quickspi-Eingabegeräte gefunden.", file=sys.stderr)
        return 1

    print("=== Gefundene Geräte ===")
    fds = {}
    for node, name in devices:
        path = f"/dev/input/{node}"
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
            fds[fd] = (node, name)
            print(f"  ✓ {node:<10} {name}")
        except OSError as exc:
            print(f"  ✗ {node:<10} nicht lesbar: {exc}")

    if not fds:
        print("Kein Gerät geöffnet - Messung nicht möglich.", file=sys.stderr)
        return 1

    print()
    if mode == "pen":
        print("MESSUNG: STIFT")
        print("  Bitte NUR mit dem Stift arbeiten: aufsetzen, Striche ziehen,")
        print("  schweben lassen, Seitentaste drücken. Finger nicht benutzen.")
    else:
        print("MESSUNG: FINGER (Kontrolle)")
        print("  Bitte NUR mit dem Finger arbeiten: streichen, tippen, wischen.")
        print("  Touch funktioniert nachweislich - hier MUSS etwas ankommen.")
    print()
    try:
        input(f"  [Enter] startet die {duration}-Sekunden-Messung ")
    except EOFError:
        pass

    print(f"  ... {duration} Sekunden ...")
    counts, seen_keys, seen_abs = capture(fds, duration)

    for fd in fds:
        os.close(fd)

    print(f"  (beendet nach {duration} s)\n")
    print(f"=== Ereignisse je Gerät ({mode}) ===")
    total = 0
    for node, name in devices:
        n = counts[node]
        total += n
        mark = "*" if n else " "
        print(f"  {mark} {node:<10} {n:>7} Ereignisse  {name}")

    if seen_keys:
        print("\n  Tasten/Werkzeuge:")
        for c in sorted(seen_keys):
            print(f"    {KEY_NAMES.get(c, f'code 0x{c:x}')}")
    if seen_abs:
        print("\n  Achsen:")
        for c in sorted(seen_abs):
            print(f"    {ABS_NAMES.get(c, f'code 0x{c:x}')}")

    pen_signals = (seen_keys & PEN_KEYS) | (seen_abs & PEN_ABS)

    print(f"\n=== BEFUND ({mode}) ===")
    if mode == "touch":
        if total:
            print(f"  Kontrolle bestanden: {total} Ereignisse gemessen.")
            print("  → Die Messung funktioniert. Ein Nullergebnis beim Stift")
            print("    ist damit belastbar.")
        else:
            print("  Kontrolle FEHLGESCHLAGEN: auch Touch liefert nichts,")
            print("  obwohl Touch funktioniert. Die Messung ist unbrauchbar.")
    else:
        if pen_signals:
            names = [KEY_NAMES.get(c) or ABS_NAMES.get(c) or hex(c)
                     for c in sorted(pen_signals)]
            print(f"  Der Kernel liefert STIFT-spezifische Ereignisse: {', '.join(names)}")
            print("  → Treiberebene in Ordnung. Problem liegt darüber:")
            print("    libinput, libwacom oder Desktop-Zuordnung.")
        elif total:
            print(f"  {total} Ereignisse, aber KEINE stiftspezifischen")
            print("  (kein BTN_TOOL_PEN, kein ABS_PRESSURE).")
            print("  → Vermutlich hat der Finger mitgemessen. Messung mit")
            print("    ruhiger Hand wiederholen, nur den Stift benutzen.")
        else:
            print("  Keine Ereignisse, während der Stift benutzt wurde.")
            print("  → Der Digitizer meldet den Stift nicht.")
            print("    Vorher mit der Kontrolle absichern:  ... 34-input-monitor.py touch")
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
