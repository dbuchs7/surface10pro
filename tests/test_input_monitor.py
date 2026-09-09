"""Tests fuer 34-input-monitor.py"""
import importlib.util, os, struct, sys, tempfile, time, threading

spec = importlib.util.spec_from_file_location("mon", "scripts/34-input-monitor.py")
mon = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mon)

FAILED = []
def check(name, cond, detail=""):
    print(f"  {'PASS' if cond else 'FAIL'}  {name}" + (f"  [{detail}]" if detail else ""))
    if not cond: FAILED.append(name)

def ev(etype, code, value=1):
    return struct.pack(mon.EVENT_FORMAT, 0, 0, etype, code, value)

print("=== 1. Geraetesuche ===")
with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as f:
    f.write('I: Bus=0001\nN: Name="quickspi-hid 045E:0C7F Stylus"\nH: Handlers=event7 \nB: EV=b\n\n')
    f.write('I: Bus=0001\nN: Name="quickspi-hid 045E:0C7F"\nH: Handlers=event1 \nB: EV=b\n\n')
    f.write('I: Bus=0001\nN: Name="AT Keyboard"\nH: Handlers=kbd event0 \nB: EV=3\n\n')
    path = f.name
devs = mon.find_devices(path)
check("findet beide quickspi-Geraete", len(devs) == 2, f"{devs}")
check("ignoriert Fremdgeraete", all("quickspi" in n.lower() for _, n in devs))
check("liest den event-Knoten", devs[0][0] == "event7", devs[0][0])
os.unlink(path)

print("\n=== 2. Zeitgrenze bei Geraeten, die NICHTS liefern ===")
r, w = os.pipe()            # bleibt offen, liefert nie Daten -> blockiert
os.set_blocking(r, False)
fds = {r: ("eventX", "stumm")}
t0 = time.monotonic()
counts, keys, absl = mon.capture(fds, 3)
elapsed = time.monotonic() - t0
check("endet nach ~3s statt zu haengen", 2.7 <= elapsed <= 4.0, f"{elapsed:.1f}s")
check("meldet null Ereignisse", counts["eventX"] == 0)
os.close(r); os.close(w)

print("\n=== 3. Auswertung echter Stift-Ereignisse ===")
r, w = os.pipe()
os.set_blocking(r, False)
fds = {r: ("event7", "Stylus")}
def feed():
    time.sleep(0.3)
    os.write(w, ev(mon.EV_KEY, 0x140) + ev(mon.EV_ABS, 0x18) + ev(mon.EV_ABS, 0x00))
threading.Thread(target=feed, daemon=True).start()
counts, keys, absl = mon.capture(fds, 2)
check("zaehlt alle drei Ereignisse", counts["event7"] == 3, str(counts))
check("erkennt BTN_TOOL_PEN", 0x140 in keys)
check("erkennt ABS_PRESSURE", 0x18 in absl)
check("Stift-Signal wird als solches gewertet",
      bool((keys & mon.PEN_KEYS) | (absl & mon.PEN_ABS)))
os.close(r); os.close(w)

print("\n=== 4. Touch darf NICHT als Stift gelten ===")
r, w = os.pipe()
os.set_blocking(r, False)
fds = {r: ("event4", "Touchscreen")}
def feed_touch():
    time.sleep(0.2)
    os.write(w, ev(mon.EV_KEY, 0x14a) + ev(mon.EV_ABS, 0x35) + ev(mon.EV_ABS, 0x36))
threading.Thread(target=feed_touch, daemon=True).start()
counts, keys, absl = mon.capture(fds, 2)
check("zaehlt Touch-Ereignisse", counts["event4"] == 3, str(counts))
check("wertet Touch NICHT als Stift",
      not bool((keys & mon.PEN_KEYS) | (absl & mon.PEN_ABS)))
os.close(r); os.close(w)

print("\n" + ("ALLE TESTS BESTANDEN" if not FAILED else f"FEHLGESCHLAGEN: {FAILED}"))
sys.exit(1 if FAILED else 0)
