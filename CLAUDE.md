# First Person Driving Game: Tiny Tapeout chip for the Vulkos Unichip competition

Yamin's entry to Vulkos' Unichip competition: a chip design that is
manufactured on a Tiny Tapeout shuttle on GlobalFoundries 180 nm (GF180).
It is a first-person pseudo-3D driving game drawn straight to VGA, with sound.

- **Deadline: Monday 16 November 2026.** Entry = this repository's link,
  emailed to contact@vulkos.co.uk once the Datasheet, Tests and Layout build
  checks are green on the latest commit. Pushing more commits updates the entry.
- Stage 1 (current) passes all three GitHub checks on a 1x1 tile.
- Yamin also uses Vulkos (web IDE with LibreLane and a VGA preview). Vulkos
  pushes to and pulls from this repo; after pushing from here, he must use
  "Cool stuff > Pull from GitHub" in Vulkos before pushing from Vulkos again.

## Status (8 Nov 2026)

- Stage 1 pushed and green: Datasheet, Tests, Layout build (GDS, precheck,
  gate-level test). Tiny Tapeout's own build reported no setup or hold
  violations and about 69% utilisation at global placement on 1x1.
- Yamin's local LibreLane run in Vulkos on 1x1: DRC, LVS and antenna clean,
  about 80% of the core after LibreLane's additions, timing met at 40 ns.
- Still to do by Yamin: email Vulkos the repo link (if not done) and ask
  whether a 1x2 tile is allowed.
- Steering wheel: dev/rtl/steering_wheel.v, selected by WHEEL_FULL in
  dev/rtl/project.v (0 = small for 1x1, the default; 1 = full for 1x2, also set
  WHEEL_FULL = True in the model and `tiles: "1x2"`). Before LibreLane: small
  34,247 um^2, full 36,851 um^2. `make chip` tests both.
- Next after the wheel (Yamin's priorities): a car interior and dashboard
  that look real, and curved roads.

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
| `make units` | Unit tests: divider (all 255 rows), car_state (3,305 frames), audio (315,000 samples) |
| `make chip` | Whole chip from dev/rtl, frames read from the VGA pins vs the model, 21 frames |
| `make project` | Regenerate src/project.v (renames the top to info.yaml's top_module) |
| `make check` | src/project.v up to date, and the chip test passes on it |
| `make area` | Cell area per block, flip-flops, % of a 1x1 tile |
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
4. `make area sta`. Targets on a 1x1 tile: under about 60% before LibreLane,
   worst pre-route slack +15 ns or more.
5. `make project check gl`, then commit and push. Watch the GitHub Actions:
   test, docs and gds (gds takes about 8 minutes) must all pass.

Commit and push to main is fine: Yamin asked for direct edits.

## The stage 1 design

- 640x480 at 60 Hz from 25 MHz: 800 clocks per line, 525 lines per frame.
  No framebuffer: each pixel's colour is computed as the beam scans.
- Screen: sky rows 0-127 (mountains), horizon 128, road 129-383, dashboard
  384-479 (speed bar). These boundaries make s_y = y - 128 = {~y[7], y[6:0]}
  and every region test a bit slice of y.
- Road row s_y shows distance z = 2^14 / s_y. A restoring divider makes one
  quotient bit per clock in horizontal blanking (starts x = 640, 15 clocks)
  for the next line. Only z[3:0] is kept in stage 1 (parameter Z_BITS; curves
  will need more).
- Road half-width w = s_y. Centre: A = ((h - 320) << 6) + p * s_y, loaded at
  the end of row 127 and built by adding p each line, so x - centre =
  x + (A >>> 6), one adder per pixel. |x - c| uses bit inversion, not negation.
- Stripes: bit 3 of z + (D >> 5); off for s_y < 32 to avoid shimmer.
- Car state, once per frame, spread over 4 clocks after the frame pulse:
  speed v (0..192), wheel (-2..2, self-centring), heading h (pixels, held past
  +/-96), sideways position P (p = P >>> 6, road edge |p| = 64, grass from 72,
  held past 96), distance D (9 bits, wraps). Speed factor k = 0, 1, 2 so
  products are shifts.
- Audio: phase accumulator stepped once per line, step 128 + 2v (61-244 Hz),
  sawtooth plus sub-octave square, LFSR noise off-road, PWM against x[7:0],
  registered output on uio[0] (uio_oe = 1).
- Pixel colour is a 2-stage pipeline; syncs are delayed one clock to match.
  The pins show pixel (x, y) two clocks after the counters were at (x, y).
- Inputs ui[0..3] = left, right, accelerate, brake (two-flop synchroniser;
  sampled only at the frame pulse, which debounces them).

## Hard-won lessons (read before changing timing or area)

- GF180 cells are big. A flip-flop is 64 um^2, a full adder 72 um^2. Each
  register bit costs about 100 um^2 once its enable mux and sync reset are
  counted. Cutting register bits saves far more than tidying arithmetic.
- A 1x1 tile is 346.64 x 160.72 um (55,712 um^2). LibreLane adds about
  10,000 um^2 (clock tree, timing repair buffers, tap cells). Stage 1 used
  about 80% of the core after LibreLane and routed cleanly.
- Timing is checked at the slow corner (125 C, 3.0 V), where gates are about
  2x slower than typical. Routing made paths about 1.5x slower than the
  pre-route OpenSTA estimate. Inputs and outputs have 8 ns external delay
  (20% of the period).
- Fixes that worked: decode strobes one clock early and register them (a
  decoded x == 799 driving 41 registers was the first failure); register the
  reset input; register anything once-per-frame logic reads; split long
  per-pixel logic into pipeline stages and delay the syncs to match; register
  output pins.
- Verilog `default_nettype none` carries over into later files: in gate-level
  sims, compile the cell models first.
- Never put spaces in file names (a "project 1.2.v" broke every CI check).
- src/config.json in this repo is Tiny Tapeout's, separate from Vulkos'
  local LibreLane config. Regenerating the config in Vulkos resets
  CLOCK_PERIOD to 20; it must be 40.

## Stage 2 plan (agreed priorities)

1. **Steering wheel in the foreground** (Yamin: a must). The wheel angle has
   only 5 values, so no trigonometry: octagonal rim from max(|dx|, |dy|) and
   |dx| + |dy|, a spoke tilted with slope wheel/4 (a shift), a marker on the
   top of the rim that slides with the angle. Estimated 3,500 um^2.
2. **Curved roads.** Keep more bits of z (Z_BITS), curvature per track
   segment from a hash of the segment index, per-line offset (1/2) kappa f z
   folded into the per-line centre so the pixel path stays one adder;
   curvature also pushes the heading. Estimated 6,000 um^2. A cheaper
   fallback is Out Run-style per-row offsets without depth.
3. Traffic only if there is room.

Area budget: stage 1 is about 32,850 um^2 before LibreLane (59% of 1x1)
and about 80% of the 1x1 core after it; routing needed 4 passes at that
level, so treat about 85% as the 1x1 ceiling. A 1x2 tile roughly doubles the
core area.

Stage 1 plus both would not fit 1x1. Plan: move to a 1x2 tile (set
`tiles: "1x2"` in info.yaml; size can change on a later push). Yamin is
asking Vulkos whether 1x2 is allowed; the current 1x1 build is the fallback.
