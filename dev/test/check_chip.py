"""Whole-chip test: build with Verilator, run the drive script, and compare
frames read from the VGA pins with road_model.render(), pixel for pixel."""
import os, subprocess, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
sys.path.insert(0, os.path.join(ROOT, "model"))
import road_model as m

BUILD = os.path.join(HERE, "build")
OBJ = os.path.join(BUILD, "obj_chip")
os.makedirs(BUILD, exist_ok=True)

srcs = [os.path.join(ROOT, "rtl", f) for f in
        ["project.v", "vga_timing.v", "ip_input_sync.v", "car_state.v",
         "line_setup.v", "pixel_colour.v", "steering_wheel.v", "engine_audio.v"]]
if os.environ.get("ROAD_SRC") == "project":       # test the generated src/project.v
    import re
    text = open(os.path.join(ROOT, "..", "src", "project.v")).read()
    top = re.search(r"^module (tt_um_\w+)", text, re.M).group(1)
    renamed = os.path.join(BUILD, "project_as_road_racer.v")
    open(renamed, "w").write(text.replace("module " + top, "module tt_um_road_racer"))
    srcs = [renamed]
    OBJ = OBJ + "_project"
full = os.environ.get("ROAD_FULL", str(int(m.WHEEL_FULL))) == "1"  # which wheel version
m.WHEEL_FULL = full
if full:
    OBJ = OBJ + "_full"
print("sources:", ", ".join(os.path.relpath(s, ROOT) for s in srcs))
print("wheel version:", "full (1x2)" if full else "small (1x1)")
subprocess.run(["verilator", "--cc", "--exe", "--build", "-O3", "-Wno-fatal",
                "-Wno-lint", "-GWHEEL_FULL=%d" % full, "--top-module", "tt_um_road_racer", "-Mdir", OBJ,
                "-o", "tb_chip", os.path.join(HERE, "tb_chip.cpp")] + srcs,
               check=True, stdout=subprocess.DEVNULL)

def pick_extremes(script, k=8):
    """Frames where the road centre is furthest from the middle of the screen."""
    car = m.Car(); scored = []
    for i, keys in enumerate(script):
        car.frame(**keys)
        scored.append((abs(car.h) * 64 + abs(car.p) * 199, i + 1))
    return sorted(i for _, i in sorted(scored)[-k:])

def coverage_frames(script):
    """First frame at each wheel angle and at top speed: the extreme values of
    the wheel and the speed bar."""
    car = m.Car(); first = {}
    for i, keys in enumerate(script):
        car.frame(**keys)
        first.setdefault(("wheel", car.wheel), i + 1)
        if car.v == m.V_MAX:
            first.setdefault("top speed", i + 1)
        if car.kappa in (-8, 7):
            first.setdefault(("kappa", car.kappa), i + 1)
    return first

runs = [("drive", m.drive_script(), [0, 1, 64, 131, 140, 150, 166, 175, 200, 215, 240, 290, 305]),
        ("random", m.random_script(1200), None),
        ("laps", m.lap_script(1900), [])]
failures = 0; outs = []; covered = set()
for name, script, check in runs:
    if check is None:
        check = pick_extremes(script)
    first = coverage_frames(script)
    covered |= set(first)
    check = sorted(set(check) | set(first.values()))
    with open(os.path.join(BUILD, "script.txt"), "w") as f:
        f.write("\n".join(m.keys_to_bits(k) for k in script) + "\n")
    out = subprocess.run([os.path.join(OBJ, "tb_chip"), os.path.join(BUILD, "script.txt"),
                          BUILD] + [str(c) for c in check],
                         check=True, capture_output=True, text=True).stdout
    outs.append(out)
    print("--- %s script\n%s" % (name, out.strip()))
    car = m.Car(); expect = {0: m.render(car)}
    for i, keys in enumerate(script):
        car.frame(**keys)
        if i + 1 in check:
            expect[i + 1] = (m.render(car), car.h, car.p)
    for n in check:
        hw = np.fromfile(os.path.join(BUILD, "frame_%d.bin" % n), np.uint8).reshape(480, 640)
        ref = expect[n] if n == 0 else expect[n][0]
        diff = int((hw != ref).sum())
        failures += diff
        extra = "" if n == 0 else "   h=%4d p=%4d" % expect[n][1:]
        print("frame %4d: %6d pixels differ%s" % (n, diff, extra))
        if name == "drive" and n == 150:
            Image.fromarray(m.to_rgb(hw)).save(os.path.join(BUILD, "chip_frame_150.png"))
    out = "".join(outs)

missing = {("wheel", w) for w in range(-2, 3)} | {"top speed", ("kappa", -8), ("kappa", 7)}
missing -= covered
print("coverage missing:", sorted(map(str, missing)) or "none")
ok = not missing and failures == 0 and all("sync errors: 0" in o and "uio_oe errors: 0" in o for o in outs)
print("ALL PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
