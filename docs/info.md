## How it works

A first-person pseudo-3D driving game drawn straight to a VGA monitor. There is
no framebuffer: every pixel's colour is worked out as the screen is scanned
("racing the beam"), at 640x480, 60 Hz, from a 25 MHz clock.

**The road.** Each screen row below the horizon at row 128 shows the road at one
distance. With the eye at height H and focal length f, row s_y below the horizon
shows the road at distance z = fH / s_y. That is the only division in the
design: a small serial divider produces one quotient bit per clock while the
previous line is in horizontal blanking. Everything else is linear in s_y, so
the road's half-width is just twice s_y and the steering offset is built by
adding the car's sideways position once per line. Stripes, kerbs and the centre
line come from one bit of z plus the distance travelled, so they rush towards
you as you speed up. Above the road is a sunset behind a ridge of mountains.

**Driving.** Once per frame the car's speed, wheel angle, heading and sideways
position are updated. Holding left or right turns the wheel; the heading follows
the wheel and the car drifts across the road according to its heading, both in
proportion to speed. Turning slides the whole view, including the mountains on
the horizon. On the grass the car is slowed down.

**Steering wheel.** A steering wheel is drawn in the foreground and turns as you
steer. Its angle has only five values, so no trigonometry is needed: the rim is
the gap between two octagons, tested from |dx|, |dy| and |dx| + |dy|, and the
spoke is sheared with a slope of wheel/4, which is a shift.

**Sound.** The engine note is a sawtooth plus a square an octave below, with a
pitch that rises with speed (about 61 Hz idling to 488 Hz flat out) and a little
LFSR noise on half of each cycle. Off the road, more noise is mixed in for a
gravel rumble. The audio pin is PWM.

The design was written against a bit-exact Python model and checked frame by
frame against it from the VGA pins.

## How to test

1. Connect a VGA monitor through a Tiny VGA PMOD on the output pins, and an
   amplified speaker (through a simple RC low-pass filter) on uio[0].
2. Set the clock to 25 MHz (25.175 MHz is the ideal VGA value; both work).
3. Hold rst_n low for a few clocks, then release it.
4. Inputs (active high): ui[0] steer left, ui[1] steer right, ui[2] accelerate,
   ui[3] brake. The vertical bar on the dashboard shows the current speed.

## External hardware

- Tiny VGA PMOD (or any RGB222 VGA adapter with the standard Tiny Tapeout pinout)
  on uo[7:0]
- Four push buttons on ui[3:0] (active high)
- Speaker or headphones with an RC low-pass filter and amplifier on uio[0]
