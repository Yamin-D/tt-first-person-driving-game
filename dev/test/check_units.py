"""Unit tests: run each block in Icarus Verilog and compare with road_model.py."""
import os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "rtl")
sys.path.insert(0, os.path.join(HERE, "..", "model"))
import road_model as m

BUILD = os.path.join(HERE, "build")
os.makedirs(BUILD, exist_ok=True)

def run(tb, srcs):
    exe = os.path.join(BUILD, tb + ".vvp")
    subprocess.run(["iverilog", "-g2012", "-o", exe, os.path.join(HERE, tb + ".v")] +
                   [os.path.join(SRC, s) for s in srcs], check=True)
    out = subprocess.run(["vvp", "-n", exe], cwd=BUILD, check=True,
                         capture_output=True, text=True).stdout
    return [l for l in out.splitlines() if l and (l[0].isdigit() or l[0] == "-")]

failures = 0

# ---- divider: every road row
lines = run("tb_divider", ["line_setup.v"])
bad = [(s, z) for s, z in (map(int, l.split()) for l in lines)
       if z != (1 << m.C_SHIFT) // s]
print("divider:   %d rows checked, %d mismatches" % (len(lines), len(bad)))
failures += len(bad)

# ---- car state: the demo drive, then 3000 frames of random buttons
seen_kappa = set(); wrapped = False; crashes = 0; best = 0
for name, script in [("drive", m.drive_script()),
                     ("random", m.random_script(3000)),
                     ("laps", m.lap_script(7000)),
                     ("crash", m.crash_script(1500))]:
    with open(os.path.join(BUILD, "script.txt"), "w") as f:
        f.write("\n".join(m.keys_to_bits(k) for k in script) + "\n")
    hw = run("tb_car_state", ["car_state.v"])
    car = m.Car(); bad = 0
    for i, (keys, line) in enumerate(zip(script, hw)):
        car.frame(**keys)
        want = (car.v, car.wheel, car.h, car.P, car.D, int(car.offroad()), car.kappa, car.track,
                car.slow, car.onc, car.crash, car.tens, car.ones)
        crashes += car.crash == m.CRASH_FRAMES; best = max(best, car.tens * 10 + car.ones)
        seen_kappa.add(car.kappa); wrapped |= (i > 0 and car.track == 0 and car.v > 0 and name == "laps")
        got = tuple(int(t) for t in line.split())
        if got != want:
            if bad < 5:
                print("  frame %d: hw %s model %s" % (i, got, want))
            bad += 1
    print("car_state (%s): %d frames, %d mismatches" % (name, len(hw), bad))
    failures += bad + (len(hw) != len(script))

print("car_state coverage: %d crashes, best score %d" % (crashes, best))
if not ({-8, 7} <= seen_kappa and wrapped and crashes and best):
    print("  coverage: kappa seen %s, track wrapped %s" % (sorted(seen_kappa), wrapped))
    failures += 1

# ---- curve offset: every road row, all curvatures, extreme heading and position
lines = run("tb_curve", ["line_setup.v"])
bad = 0
for l in lines:
    h, p, k, s, got = map(int, l.split())
    A = ((h - 320) << 6) + p * s
    if got != m.line_centre(A, m.serial_recip(s), s, k):
        bad += 1
print("curve:     %d rows checked, %d mismatches" % (len(lines), bad))
failures += bad + (len(lines) != 3 * 3 * 16 * 255)

# ---- audio: speeds from the random script, including off-road stretches
car = m.Car(); speeds = []; offs = []
for keys in m.random_script(600):           # off-road from frame 356
    car.frame(**keys)
    speeds.append(car.v); offs.append(int(car.offroad()))
with open(os.path.join(BUILD, "speeds.txt"), "w") as f:
    f.write("\n".join("%d %d" % so for so in zip(speeds, offs)) + "\n")
hw = [int(l) for l in run("tb_audio", ["engine_audio.v"])]
want = list(m.engine_audio(speeds, offs))
bad = sum(a != b for a, b in zip(hw, want)) + abs(len(hw) - len(want))
print("audio:     %d samples, %d mismatches (off-road in %d of %d frames)"
      % (len(hw), bad, sum(offs), len(offs)))
failures += bad

print("ALL PASS" if failures == 0 else "FAILURES: %d" % failures)
sys.exit(1 if failures else 0)
