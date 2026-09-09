"""Integrationstest fuer den Zwei-Phasen-Modus (both)."""
import importlib.util, io, os, struct, sys, threading, time

spec = importlib.util.spec_from_file_location("mon", "scripts/34-input-monitor.py")
mon = importlib.util.module_from_spec(spec); spec.loader.exec_module(mon)

def ev(t, c, v=1): return struct.pack(mon.EVENT_FORMAT, 0, 0, t, c, v)

def run_scenario(name, touch_events, pen_events, expect_snippets):
    r1, w1 = os.pipe(); os.set_blocking(r1, False)
    fake = {"event7": (r1, w1)}

    mon.find_devices = lambda *a, **k: [("event7", "quickspi-hid 045E:0C7F Stylus")]
    mon.os.geteuid = lambda: 0
    real_open = os.open
    mon.os.open = lambda p, f: fake["event7"][0] if "event7" in p else real_open(p, f)
    mon.os.close = lambda fd: None          # Pipe erst am Ende schliessen

    def feeder():
        time.sleep(1.0)                      # in Phase 1
        for e in touch_events: os.write(w1, e)
        time.sleep(11.0)                     # in Phase 2
        for e in pen_events: os.write(w1, e)
    threading.Thread(target=feeder, daemon=True).start()

    sys.argv = ["mon", "both", "0"]
    sys.stdin = io.StringIO("\n\n")
    buf = io.StringIO(); old = sys.stdout; sys.stdout = buf
    try:
        mon.main()
    finally:
        sys.stdout = old
    out = buf.getvalue()
    os.close(r1); os.close(w1)

    ok = all(sn in out for sn in expect_snippets)
    print(f"  {'PASS' if ok else 'FAIL'}  {name}")
    if not ok:
        for sn in expect_snippets:
            if sn not in out: print(f"         fehlt: {sn!r}")
        print("         ---- Ausgabe ----"); print("         " + out.replace("\n","\n         ")[:1200])
    return ok

print("=== Zwei-Phasen-Modus ===")
results = []

# Fall A: Kontrolle ok, Stift liefert nichts -> belastbares Negativergebnis
results.append(run_scenario(
    "Finger ja / Stift nein -> belastbare Treiberluecke",
    [ev(mon.EV_KEY, 0x14a), ev(mon.EV_ABS, 0x35)],
    [],
    ["Kontrolle bestanden", "Der Stift liefert NULL", "Treiberlücke"]))

# Fall B: Kontrolle scheitert -> Ergebnis fuer ungueltig erklaeren
results.append(run_scenario(
    "Finger nein -> Messung als unbrauchbar erkannt",
    [], [],
    ["Kontrolle ist fehlgeschlagen", "unbrauchbar"]))

# Fall C: Stift liefert echte Stiftsignale -> Userspace-Problem
results.append(run_scenario(
    "Stift liefert BTN_TOOL_PEN -> Problem liegt ueber dem Treiber",
    [ev(mon.EV_KEY, 0x14a)],
    [ev(mon.EV_KEY, 0x140), ev(mon.EV_ABS, 0x18)],
    ["Kontrolle bestanden", "BTN_TOOL_PEN", "libinput"]))

print("\n" + ("ALLE BESTANDEN" if all(results) else "FEHLGESCHLAGEN"))
sys.exit(0 if all(results) else 1)
