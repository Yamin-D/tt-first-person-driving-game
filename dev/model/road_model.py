"""
Stage 1 golden model for the Unichip driving sim (area-optimised layout).

Every quantity here is an integer with the same width and update order the
Verilog uses, so frames rendered here are exactly what the chip draws.
Run:  python3 road_model.py
Outputs: frames.png (montage), drive.gif (short drive), engine.wav (sound)

Screen layout: sky rows 0-127, horizon row 128, road rows 129-383,
dashboard rows 384-479. These boundaries make s_y = y - 128 and most region
tests plain bit slices in hardware.
"""
import numpy as np
from PIL import Image
import wave

# ---------------------------------------------------------------- constants
W_SCREEN, H_SCREEN = 640, 480
HORIZON  = 128          # row level with the eye
DASH_TOP = 384          # dashboard starts here
C_SHIFT  = 14           # fH = 2**14, so z = 2**14 // s_y, s_y = 1..255
STRIPE_BIT = 3          # band half-period = 8 units of road
D_SHIFT  = 5            # stripes use D >> 5 (4 bits)
FOG_SY   = 32           # no stripes for s_y < 32 (s_y[7:5] == 0)
V_MAX    = 224
WHEEL_FULL = False      # False: small wheel for 1x1, True: full wheel for 1x2
BAR_X0, BAR_X1 = 64, 96 # columns of the vertical speed bar
ROAD_EDGE, KERB_EDGE = 64, 72   # |p| thresholds (W/H = 1, kerb is w/8)

# RGB222 colours, written RR_GG_BB
def c(rr, gg, bb): return (rr << 4) | (gg << 2) | bb
SKY      = [c(0,0,1), c(1,0,2), c(3,1,1), c(3,2,0)]   # bands of 32 rows
MOUNTAIN = c(1,0,1)
DASH_COL = c(1,1,1)
BAR_COL  = c(3,2,0)
LINE_COL = c(3,3,3)
TARMAC   = (c(1,1,1), c(2,2,2))     # (stripe=0, stripe=1)
KERB     = (c(3,3,3), c(3,0,0))
GRASS    = (c(0,2,0), c(1,2,0))
WHEEL0, WHEEL1 = c(0,0,0), c(2,2,2)

# ---------------------------------------------------------------- divider
def serial_recip(s_y):
    """Restoring division of 2**14 by s_y, one quotient bit per clock.
    Mirrors the hardware: 8-bit remainder register, 15-bit quotient."""
    r, q = 0, 0
    for i in range(C_SHIFT, -1, -1):
        r = (r << 1) | ((1 << C_SHIFT) >> i & 1)   # at most 9 bits
        bit = r >= s_y
        if bit:
            r -= s_y
        q = ((q << 1) | bit) & 0x7FFF
    return q

# ---------------------------------------------------------------- car state
P_FRAC = 6             # fraction bits on the sideways position

LIMIT = 96             # |h| stops growing outwards beyond this
P_LIMIT = 72           # and |p| beyond this

def at_limit(value, step, limit=LIMIT):
    """True if adding `step` would push `value` further past +/-96. The
    hardware tests only the top three bits: value >= 96 or value <= -97."""
    return (step > 0 and value >= limit) or (step < 0 and value <= -limit - 1)

class Car:
    def __init__(self):
        self.v, self.D, self.n = 0, 0, 0      # 8u speed, 9u distance, 3u frame count
        self.wheel = 0                        # 3s, -2..2
        self.h = 0                            # 8s heading, pixels, about -100..99
        self.P = 0                            # 14s sideways position, p = P >> 6

    @property
    def p(self):
        return self.P >> P_FRAC

    @p.setter
    def p(self, value):
        self.P = value << P_FRAC

    def offroad(self):
        return self.p >= KERB_EDGE or self.p <= -KERB_EDGE

    def frame(self, left=0, right=0, accel=0, brake=0):
        """One update on the frame pulse. The speed change is worked out from
        the current state and applied with a single adder; the wheel, heading
        and position then use the new speed. Heading and position stop moving
        outwards past +/-96, which keeps every value inside its bit width."""
        v = self.v
        if self.offroad() and v > 96:  d = -4 if brake else -2   # grass drag
        elif accel:        d = 0 if v == V_MAX else (2 if v < 128 else 1)
        elif brake:        d = -4
        elif self.n == 0:  d = -1
        else:              d = 0
        v = max(0, v + d)
        self.v = v
        # wheel: move towards the held direction, centre itself when released
        if left and not right:    self.wheel = max(self.wheel - 1, -2)
        elif right and not left:  self.wheel = min(self.wheel + 1, 2)
        elif self.wheel:          self.wheel -= 1 if self.wheel > 0 else -1
        k = 2 if v >= 128 else (1 if v >= 64 else 0)   # speed factor: a shift
        dh = self.wheel * k
        if not at_limit(self.h, dh):
            self.h += dh
        dP = self.h * k
        if not at_limit(self.p, dP, P_LIMIT):
            self.P += dP
        self.D = (self.D + v) & 0x1FF
        self.n = (self.n + 1) & 0x7

# ---------------------------------------------------------------- steering wheel
def wheel_code(wheel, full):
    """Per-pixel wheel code for the whole screen: 0 none, 1 black, 2 yellow,
    3 grey. Centre (320, 448). a and b use bit inversion, as the hardware does;
    negative shears are one's complement (no carry), which keeps the across
    spoke exactly mirror-symmetric between w and -w."""
    y_, x_ = np.mgrid[0:H_SCREEN, 0:W_SCREEN]
    dx, dy = x_ - 320, y_ - 448
    a = np.where(dx < 0, ~dx, dx)
    b = np.where(dy < 0, ~dy, dy)
    s = a + b
    shift = {0: None, 1: 2, 2: 1}[abs(wheel)]       # slope wheel/4
    tx = 0 * dx if shift is None else dx >> shift
    sh = dy + ~tx if wheel > 0 else dy + tx
    code = np.zeros_like(x_)
    if full:
        on = (x_ >= 192) & (x_ < 448) & (y_ >= 320)
        in_out = (a < 96) & (b < 96) & (s < 136)
        in_in  = (a < 84) & (b < 84) & (s < 119)
        rim = in_out & ~in_in
        hub = (a < 14) & (b < 14) & (s < 20)
        m = (dx >> 3) - 2 * wheel
        marker = rim & (dy < 0) & ((m == 0) | (m == -1))
        ty = 0 * dy if shift is None else dy >> shift
        sv = dx + ~ty if wheel < 0 else dx + ty
        sp_h = (sh >= -8) & (sh < 8)
        sp_v = (sv >= -8) & (sv < 8) & (dy >= 0)
        code[in_in & (sp_h | sp_v)] = 3
        code[hub] = 2
        code[rim] = 1
        code[marker] = 2
    else:
        on = (x_ >= 256) & (x_ < 384) & (y_ >= 384)
        in_in = (a < 56) & (b < 56) & (s < 80)
        rim = (s < 92) & ~in_in
        spoke = in_in & (sh >= -4) & (sh < 4)
        code[rim | spoke] = 1
    code[~on] = 0
    return code

# ---------------------------------------------------------------- renderer
def render(car):
    """Draw one frame exactly as the hardware would, line by line."""
    img = np.zeros((H_SCREEN, W_SCREEN), dtype=np.uint8)
    x = np.arange(W_SCREEN)
    d_hi = car.D >> D_SHIFT                # 4 bits of distance
    u = ((x + car.h) & 0xFF) >> 1          # mountain column, twice as wide: wraps every 256 px
    tri = np.where(u & 0x20, 31 - (u & 0x1F), u & 0x1F)        # 0..31 ramp
    mountain_h = tri + np.where(u & 0x40, tri >> 1, 0)          # alternate peaks
    bar = (x >= BAR_X0) & (x < BAR_X1)
    A = 0
    for y in range(H_SCREEN):
        if y < HORIZON:
            row = np.full(W_SCREEN, SKY[y >> 5], np.uint8)
            row[(127 - y) < mountain_h] = MOUNTAIN    # i.e. 128 - y <= height
            img[y] = row
        elif y >= DASH_TOP:
            row = np.full(W_SCREEN, DASH_COL, np.uint8)
            if H_SCREEN - 1 - y < car.v >> 1:   # v/2 rows up from the bottom
                row[bar] = BAR_COL
            img[y] = row
        else:
            s_y = y - HORIZON
            if s_y == 0:                   # horizon row: far grass
                img[y] = GRASS[0]
            else:
                z = serial_recip(s_y)      # computed in previous line's hblank
                w = s_y << 1               # the road is twice as wide as the eye is high
                kerb_w = w + (w >> 3)
                dash_w = (w >> 5) + 1
                dx = x + (A >> 6)          # x - centre, one adder
                d = np.where(dx < 0, -dx - 1, dx)   # bit inversion, not negation
                stripe = ((z + d_hi) >> STRIPE_BIT) & 1 if s_y >= FOG_SY else 0
                row = np.full(W_SCREEN, GRASS[stripe], np.uint8)
                row[d < kerb_w] = KERB[stripe]
                row[d < w] = TARMAC[stripe]
                if stripe:
                    row[d < dash_w] = LINE_COL
                img[y] = row
        # end-of-line updates at x = 799
        if y == HORIZON - 1:
            A = (car.h - 320) << 6         # centre offset folded into A
        elif HORIZON <= y < DASH_TOP:
            A += car.P >> 5                # each unit of p counts double on screen
    code = wheel_code(car.wheel, WHEEL_FULL)
    img[code == 1] = WHEEL0
    img[code == 2] = BAR_COL
    img[code == 3] = WHEEL1
    return img

def to_rgb(img):
    r = (img >> 4) & 3; g = (img >> 2) & 3; b = img & 3
    return (np.stack([r, g, b], -1) * 85).astype(np.uint8)

# ---------------------------------------------------------------- audio
LINE_RATE = 25_000_000 // 800          # 31250 Hz sample/step rate

def engine_audio(speeds, offroads):
    """Per-line engine model. speeds/offroads are per-frame values;
    each frame lasts 525 lines."""
    phase, lfsr = 0, 0x7FFF
    out = []
    for v, off in zip(speeds, offroads):
        inc = (v + 32) << 2                # 61 Hz idle to 488 Hz at top speed
        for _ in range(525):
            phase = (phase + inc) & 0x1FFFF
            fb = ((lfsr >> 14) ^ (lfsr >> 13)) & 1
            lfsr = ((lfsr << 1) | fb) & 0x7FFF
            s = ((phase >> 9) & 0x7F) + (64 if (phase >> 16) & 1 else 0)
            if off:
                s ^= lfsr & 0x3F
            elif (phase >> 15) & 1:            # rough: noise on half of each cycle
                s ^= lfsr & 0x0F
            out.append(s & 0xFF)
    return np.array(out, np.uint8)

# ---------------------------------------------------------------- scripts
def drive_script():
    """Buttons for each frame of the demo drive (also used by the tests)."""
    A_ = dict(accel=1)
    return ([A_] * 130 + [dict(accel=1, right=1)] * 8 + [A_] * 25 +
            [dict(accel=1, left=1)] * 16 + [A_] * 30 +
            [dict(accel=1, right=1)] * 6 + [A_] * 40 + [dict(brake=1)] * 50)

def random_script(n, seed=1):
    """Random button presses, held for random lengths, to reach edge cases."""
    import random
    rng = random.Random(seed)
    out = []
    while len(out) < n:
        keys = dict(left=rng.random() < 0.3, right=rng.random() < 0.3,
                    accel=rng.random() < 0.6, brake=rng.random() < 0.15)
        out += [keys] * rng.randint(1, 40)
    return out[:n]

def keys_to_bits(k):
    return "%d%d%d%d" % (k.get("left", 0), k.get("right", 0),
                         k.get("accel", 0), k.get("brake", 0))

# ---------------------------------------------------------------- main
if __name__ == "__main__":
    # 1. divider check against plain integer division
    bad = [s for s in range(1, 256) if serial_recip(s) != (1 << C_SHIFT) // s]
    print("divider mismatches:", bad or "none")

    # 2. still frames for tuning: (label, p, v, D, heading h in pixels)
    shots = [("centred, straight", 0, 120, 0, 0),
             ("centred, turned right", 0, 120, 37, 100),
             ("left of centre, turned left", -32, 160, 300, -90),
             ("on the grass, pointing back", 90, 90, 150, -60)]
    tiles = []
    for _, p, v, D, h in shots:
        car = Car(); car.p, car.v, car.D, car.h = p, v, D, h
        tiles.append(to_rgb(render(car)))
    top = np.concatenate(tiles[:2], 1); bot = np.concatenate(tiles[2:], 1)
    Image.fromarray(np.concatenate([top, bot], 0)).save("frames.png")

    # 3. a scripted drive: turn right, drift, counter-steer back, brake
    car = Car(); frames = []; speeds = []; offs = []
    trace = []
    for i, keys in enumerate(drive_script()):
        car.frame(**keys)
        if i % 10 == 0:
            trace.append((i, car.v, car.wheel, car.h, car.p))
        speeds.append(car.v); offs.append(car.offroad())
        if i % 2 == 0:
            frames.append(Image.fromarray(to_rgb(render(car))).resize((320, 240)))
    frames[0].save("drive.gif", save_all=True, append_images=frames[1:],
                   duration=33, loop=0)
    print("frame  v  wheel    h     p")
    for row in trace:
        print("%5d %3d %5d %5d %5d" % row)

    # 4. engine sound for the same drive
    pcm = engine_audio(speeds, offs)
    with wave.open("engine.wav", "wb") as w:
        w.setnchannels(1); w.setsampwidth(1); w.setframerate(LINE_RATE)
        w.writeframes(pcm.tobytes())
    print("audio seconds: %.1f" % (len(pcm) / LINE_RATE))
