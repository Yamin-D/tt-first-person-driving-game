"""Area and slow-corner timing estimates on the real GF180 cells.

    python3 dev/tools/report.py area     cell area per block, flip-flops, % of tile
    python3 dev/tools/report.py sta      worst setup paths at 125 C / 3.0 V (OpenSTA)
    python3 dev/tools/report.py          both

These run before place and route, so they are estimates. From this design's
history: LibreLane adds about 10,000 um^2 (clock tree, buffers, tap cells) on
a 1x1 tile, and routing made the slowest paths about 1.5x slower than the
pre-route STA said. Keep the pre-route worst slack at +15 ns or more on the
40 ns clock.
Needs dev/pdk (python3 dev/tools/setup_pdk.py) and yosys; `sta` needs the
OpenSTA binary on PATH or in $STA.
"""
import os, re, shutil, subprocess, sys

DEV = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SYNTH = os.path.join(DEV, "synth")
TILE_UM2 = {"1x1": 346.64 * 160.72}

def area():
    subprocess.run(["yosys", "-q", "-l", "synth.log", "synth.ys"], cwd=SYNTH, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    log = open(os.path.join(SYNTH, "synth.log")).read()
    last = log[log.rfind("Printing statistics"):]
    print("block                 area um^2   flip-flops")
    for sec in re.split(r"\n=== ", last)[1:]:
        name = sec.split(" ===")[0]
        m = re.search(r"Chip area for (?:top )?module .*: ([\d.]+)\s*$", sec, re.M)
        if not m:
            continue
        ffs = sum(int(n) for n in re.findall(r"__dff\w*\s+(\d+)", sec))
        # "$paramod\line_setup\Z_BITS=..." -> "line_setup"; "\car_state" -> "car_state"
        label = "TOTAL" if name == "design hierarchy" else \
            [part for part in name.replace("$paramod", "").split("\\") if part][0]
        print("%-20s %10.0f %10d" % (label, float(m.group(1)), ffs))
        if name == "design hierarchy":
            print("= %.1f%% of a 1x1 GF180 tile (%.0f um^2)" % (100 * float(m.group(1)) / TILE_UM2["1x1"], TILE_UM2["1x1"]))

def sta():
    exe = os.environ.get("STA") or shutil.which("sta") or os.path.expanduser("~/OpenSTA/build/sta")
    if not os.path.exists(exe):
        sys.exit("OpenSTA not found: build https://github.com/parallaxsw/OpenSTA and put `sta` on PATH")
    subprocess.run(["yosys", "-q", "netlist.ys"], cwd=SYNTH, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    rpt = subprocess.run([exe, "-no_init", "-exit", "sta.tcl"], cwd=SYNTH,
                         capture_output=True, text=True).stdout
    open(os.path.join(SYNTH, "sta.rpt"), "w").write(rpt)
    net = open(os.path.join(SYNTH, "netlist.v")).read()
    q = {m.group(1): m.group(2).strip() for m in re.finditer(
        r"dffq_1 (\S+) \(\s*\.CLK\([^)]*\),\s*\.D\([^)]*\),\s*\.Q\(([^)]*)\)", net)}
    print("slow-corner endpoint (register or pin)   arrival ns   slack ns")
    rows = [(q.get(m.group(1), m.group(1)), m.group(3), m.group(4)) for m in re.finditer(
        r"^(\S+)/D \(\S+\)\s+([\d.]+)\s+([\d.]+)\s+(-?[\d.]+)", rpt, re.M)]
    rows += [(m.group(1) + " (pin)", m.group(3), m.group(4)) for m in re.finditer(
        r"^(\S+) \(output\)\s+([\d.]+)\s+([\d.]+)\s+(-?[\d.]+)", rpt, re.M)]
    rows.sort(key=lambda r: float(r[2]))
    for r in rows[:10]:
        print("%-40s %10s %10s" % r)
    s = re.search(r"Startpoint: (\S+)", rpt)
    if s:
        print("worst path starts at", q.get(s.group(1), s.group(1)), "(full report: dev/synth/sta.rpt)")

if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "both"
    if what in ("area", "both"):
        area()
    if what in ("sta", "both"):
        sta()
