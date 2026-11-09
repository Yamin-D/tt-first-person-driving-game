# First Person Driving Game: Tiny Tapeout chip for the Vulkos Unichip competition

Yamin's entry to Vulkos' Unichip competition: a chip design that is
manufactured on a Tiny Tapeout shuttle on GlobalFoundries 180 nm (GF180).
It is a first-person pseudo-3D driving game drawn straight to VGA, with sound.

- **Deadline: Monday 16 November 2026.** Entry = this repository's link,
  emailed to contact@vulkos.co.uk once the Datasheet, Tests and Layout build
  checks are green on the latest commit. Pushing more commits updates the entry.
- `main` is the 1x2 version. Branch `1x1-version` is the 1x1 version.
- Yamin also uses Vulkos (web IDE with LibreLane and a VGA preview). Vulkos
  pushes to and pulls from this repo; after pushing from here, he must use
  "Cool stuff > Pull from GitHub" in Vulkos before pushing from Vulkos again.

## Status (9 Nov 2026)

- The 1x2 design is on `main`: curves, traffic, crashes, score, interior,
  sunset, steering wheel, road and cars twice as wide as the eye is high.
- Tiny Tapeout build of 14f50d4 on 1x2: 84.6% core utilisation (core
  107,931 um^2), worst slow-corner setup slack +3.07 ns, 0 setup and hold
  violations, 4 routing passes, DRC/LVS/antenna clean. Before LibreLane:
  80,384 um^2. The 1x1 version (branch 1x1-version) has the same engine and
  speed changes and a 2x road: 83.9%, +6.04 ns.
- **1x2 is full and timing has almost no margin.** Slack has moved by several
  ns between near-identical layouts, so any RTL change, even a comment (it can
  change generated cell names), may break timing. Do not change dev/rtl or
  src/project.v without a reason worth a new layout round.
- Vulkos (Matthew) confirmed 1x2 is allowed, and asked for both versions to be
  submitted through the GitHub link with the README explaining there are two.
  Keep `1x1-version` green: it is a submission too, not just a backup.
- Not built, for lack of room: softer two-layer mountains, bumper strip, round
  vents, road-edge barrier, sun. The speed bar was removed to fit, so engine
  pitch is the only speed cue.

## Yamin's machine

Windows 11 on ARM64. Development runs in WSL 2 Ubuntu (Python 3.14): use apt
for Python packages (python3-numpy, python3-pil), not pip. The repo is cloned
at ~/tt-first-person-driving-game inside WSL. He uses Claude Code from the
Claude desktop app's Code tab with the WSL environment selected. OpenSTA is
not installed yet; build it from source (needs cmake, tcl-dev, swig, bison,
flex, libeigen3-dev, zlib1g-dev, and CUDD from github.com/ivmai/cudd).

## Checking on the VGA preview in Vulkos

Vulkos' VGA view drives ui_in from on-screen keys that latch on and off:
keys 0-3 are left, right, accelerate, brake. Sound comes from uio[0].

## How Yamin likes to work

- Before writing code for a new feature, explain the design: the maths, the
  hardware blocks, what runs per frame / per line / per pixel, and the area
  and timing cost. He likes diagrams and wants to agree the approach first.
- Use LaTeX for maths in explanations.
- He cares a lot that the design is optimised and actually fits on the chip.
  Measure area and timing after every change, and say plainly when
  something will not fit.
- He wants minimal time spent on extras; prioritise features he asked for.

## Layout of this repository

```
src/project.v      GENERATED single file Tiny Tapeout builds. Never edit by hand:
                   edit dev/rtl and run `make project` in dev/.
src/config.json    Tiny Tapeout's LibreLane config. CLOCK_PERIOD must stay 40 (25 MHz).
info.yaml          top_module, tiles, clock_hz 25000000, pin labels, source_files
docs/info.md       datasheet text (judges read this)
test/              the CI cocotb test (resets, runs 100 clocks, no X/Z on outputs)
dev/               everything for developing the design (not built by Tiny Tapeout)
  rtl/             the design, one module per file; top module tt_um_road_racer
  model/           road_model.py: bit-exact Python model = the specification
  test/            unit tests (Icarus) and whole-chip test (Verilator) vs the model
  synth/           Yosys and OpenSTA scripts on real GF180 cells
  gl/              gate-level simulation vs RTL
  tools/           combine.py (makes src/project.v), report.py, setup_pdk.py
  Makefile         one command per job; see below
```

## Commands (run in dev/)

| Command | What it does |
|---|---|
| `make setup` | Fetch GF180 cell library into dev/pdk (once) |
| `make model` | Render frames.png, drive.gif, engine.wav from the model |
| `make units` | Unit tests: divider (all 255 rows), car_state (11,805 frames), curve (36,720 rows), audio (315,000 samples) |
| `make chip` | Whole chip from dev/rtl for both wheel versions, frames read from the VGA pins vs the model, about 51 frames each; takes several minutes |
| `make project` | Regenerate src/project.v (renames the top to info.yaml's top_module) |
| `make check` | src/project.v up to date, and the chip test passes on it |
| `make area` | Cell area per block, flip-flops, % of a 1x1 tile (the 1x2 die is 112,783 um^2) |
| `make sta` | Slow-corner (125 C, 3.0 V) setup estimate with OpenSTA |
| `make gl` | Gate-level sim of the GF180 netlist vs RTL for 900,000 clocks |
| `make all` | units, chip, project, check, area, sta, gl |

Tools: python3 (numpy, pillow; see dev/requirements.txt), iverilog, verilator,
yosys, git. OpenSTA for `make sta` is built from source
(github.com/parallaxsw/OpenSTA, needs CUDD, tcl, swig, eigen); point `$STA`
at the binary if it is not on PATH. CI test: pip install -r test/requirements.txt,
then `make` in test/.

## Workflow for any design change

1. Change the model (dev/model/road_model.py) first; it is the specification.
   Every quantity is an integer with the width and update order the hardware uses.
2. Change dev/rtl to match. Keep everything bit-exact with the model.
3. `make units chip` must show 0 mismatches. Extend the tests to cover the
   new feature, including its extreme values.
4. `make area`, and `make sta` if OpenSTA is installed.
5. `make project check gl`, then commit and push. Watch the GitHub Actions:
   test, docs and gds (gds takes about 8 minutes) must all pass. CI going green
   does NOT mean timing is met: read final/metrics.json from the GDS_logs
   artifact (timing__setup__ws, timing__setup_vio__count,
   design__instance__utilization). Worst paths are in
   runs/wokwi/*-openroad-stapostpnr/max_ss_125C_3v00/max.rpt.

Commit and push to main is fine: Yamin asked for direct edits.

## The design

- 640x480 at 60 Hz from 25 MHz: 800 clocks per line, 525 lines per frame.
  No framebuffer: each pixel's colour is computed as the beam scans.
- Screen: sky rows 0-127 (sunset and mountains), horizon 128, road 129-351,
  dashboard 352-479. s_y = y - 128 = {~y[7], y[6:0]}. The road logic runs to
  row 383; the dashboard is drawn over its last rows.
- Road row s_y shows distance z = 2^14 / s_y. A restoring divider makes one
  quotient bit per clock in horizontal blanking (starts x = 640, 15 clocks)
  for the next line. 11 bits of z are kept.
- Road half-width w = 2 s_y (a shift). A = ((h - 320) << 6) + (P >>> 5) * s_y,
  17 bits, loaded on row 127 and built by adding P >>> 5 each line.
- Curves: Ae = (A >>> 6) -/+ kappa z / 64, built in blanking with up to three
  shifted adds (z ready x = 656, Ae loaded x = 658, adds x = 660-662), so
  x - centre = x + Ae, one adder per pixel. z is clamped to 2047 for s_y < 9,
  and when the road curves those rows are grass. Negative kappa's magnitude
  is its bit inversion. kappa moves one step every 4 wraps of D towards the
  value in the 16-segment track table (64 wraps per segment). |kappa| >= 4
  pushes the heading outwards, but only while the wheel is centred.
- Stripes: bit 3 of z + (D >> 5); off for s_y < 32 to avoid shimmer.
- Car state, once per frame, stepped over 7 clocks after the frame pulse:
  speed v (0..224, +2 per frame below 128), wheel (-2..2, self-centring), heading h (pixels, held past
  +/-96), sideways position P (p = P >>> 6, right lane p = 32, road edge
  |p| = 64, grass from 72, held past 80), distance D (9 bits, wraps). Speed
  factor k = 0, 1, 2 so products are shifts.
- Traffic: 12-bit depths with 1 fraction bit, one shared adder. Slow car in
  the right lane: +6 - v/16 per frame. Oncoming car on the left: -4 - v/16.
  Below depth 0 a car respawns far ahead. Depth < 128 with p in that car's lane
  is a crash: 63 frames stopped, red tint, noise, score reset. The score (BCD)
  counts slow cars passed.
- Cars are upright: on the last row with z >= the car's depth, Ae and s_y are
  stored, and the next frame draws from them. The stored value is replaced
  while scanning, so a car moving away loses its bottom row for that frame; the
  model copies this. Rows s/2 to s, width s, window band, lamps, side panel.
- Steering wheel: dev/rtl/steering_wheel.v, FULL = 1 (radius 128, centre
  (320, 448)) is built; it takes two clocks, which moves it one pixel right.
  WHEEL_FULL = 0 selects the small 1x1 version.
- Audio: phase accumulator stepped once per line, step (v + 32) << 2 (61-488 Hz),
  sawtooth plus sub-octave square, a little LFSR noise on half of each cycle,
  more off-road and in a crash, PWM
  against x[7:0], registered output on uio[0] (uio_oe = 1).
- Pixel colour is a 2-stage pipeline; syncs are delayed one clock to match.
  The pins show pixel (x, y) two clocks after the counters were at (x, y).
- Inputs ui[0..3] = left, right, accelerate, brake (two-flop synchroniser;
  sampled only at the frame pulse, which debounces them).

## Hard-won lessons (read before changing timing or area)

- GF180 cells are big. A flip-flop is 64 um^2, a full adder 72 um^2. Each
  register bit costs about 100 um^2 once its enable mux and sync reset are
  counted. Cutting register bits saves far more than tidying arithmetic.
- A 1x1 tile is 346.64 x 160.72 um (55,712 um^2); a 1x2 die is 112,783 um^2
  with a 107,931 um^2 core. LibreLane adds about 11,600 um^2 at this size.
  About 85% utilisation is the practical ceiling.
- Multiplying by a power of two is wiring and free; x1.5 needs an adder at every
  use. Going from a 1.5x road to 2x saved 4,900 um^2.
- Hand estimates of area have run up to 2x low. Measure, and let the layout
  decide. `make area` counts logic shared between modules twice; the real flow
  flattens and merges it.
- Timing is checked at the slow corner (125 C, 3.0 V), where gates are about
  2x slower than typical. Routing made paths about 1.5x slower than the
  pre-route OpenSTA estimate. Inputs and outputs have 8 ns external delay
  (20% of the period).
- Fixes that worked: decode strobes one clock early and register them (a
  decoded x == 799 driving 41 registers was the first failure); register the
  reset input; register anything once-per-frame logic reads; split long
  per-pixel logic into pipeline stages and delay the syncs to match; register
  output pins.
- Synthesis merges identical registers, so a "copy" to cut fan-out vanishes.
  Chain the copies, or store one inverted.
- A copy of y is one clock late, so it is only safe for logic that never draws
  column 0.
- `inside` is a SystemVerilog keyword; it broke the compile of src/project.v.
- Verilog `default_nettype none` carries over into later files: in gate-level
  sims, compile the cell models first.
- Never put spaces in file names (a "project 1.2.v" broke every CI check).
- src/config.json in this repo is Tiny Tapeout's, separate from Vulkos'
  local LibreLane config. Regenerating the config in Vulkos resets
  CLOCK_PERIOD to 20; it must be 40.
