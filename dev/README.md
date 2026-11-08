# Development notes: road racer, stage 1

See ../CLAUDE.md for the workflow and commands (`make all` in this folder).

A first-person pseudo-3D driving scene for the Unichip (Tiny Tapeout, GF180)
competition: perspective road with stripes and kerbs, speed, steering with a
real heading angle, distant mountains, a speed bar and engine sound.

## Controls and pins

| Pin | Use |
|---|---|
| `ui_in[0]` | steer left |
| `ui_in[1]` | steer right |
| `ui_in[2]` | accelerate |
| `ui_in[3]` | brake |
| `uo_out` | Tiny VGA PMOD (RGB222 + syncs) |
| `uio[0]` | audio, PWM (output enable set) |

## Files

```
rtl/project.v        top level, tt_um_road_racer (combine.py renames it for src/project.v)
rtl/vga_timing.v     640x480 timing; x, y, active, frame pulse
rtl/ip_input_sync.v  two-flop button synchroniser
rtl/car_state.v      speed, wheel, heading, position, distance; once per frame
rtl/line_setup.v     divider for z = 2^14 / s_y, steering accumulator A; once per line
rtl/pixel_colour.v   colour of each pixel; adders and comparators only
rtl/engine_audio.v   engine pitch from speed, gravel noise off-road, PWM out
model/road_model.py  bit-exact Python model (the specification)
test/                unit tests and whole-chip test against the model
synth/               Yosys scripts for GF180 area and slow-corner delay
```

## Tests

```
make units   # Icarus Verilog: divider (all 255 rows, full 15 bits),
                              # car_state (3305 frames), audio (315000 samples)
make chip    # Verilator: whole chip read from the VGA pins and
                              # compared pixel for pixel with the model, 21 frames
```

## Results

| | |
|---|---|
| Cell area (Yosys, gf180mcu_fd_sc_mcu7t5v0) | 32,849 um^2, 59% of the 1x1 tile (55,712 um^2) |
| Flip-flops | 184 |
| Worst setup slack, slow corner (125 C, 3.0 V), before routing | +16.7 ns on a 40 ns clock (OpenSTA) |

Timing history at the slow corner (LibreLane routed results):

1. First run: -2.2 ns. The decoded end-of-line strobe drove 41 registers.
   Fixed by decoding strobes a clock early and registering them.
2. Third run: -2.3 ns, now in the per-pixel colour path; routing added about
   14 ns to the 28 ns estimated before routing. Fixed by splitting
   pixel_colour into two pipeline stages (syncs delayed to match), and by
   registering the off-road flag, the speed step, the speed factor, the
   divisor and the reset input. Worst path before routing went from 27.6 ns
   to 22.2 ns.

## Layout

Sky rows 0-127, horizon 128, road 129-383, dashboard 384-479. These boundaries
make s_y = y - 128 and every region test a slice of the bits of y.
