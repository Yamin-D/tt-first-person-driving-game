"""
Stage 1 golden model for the Unichip driving sim (area-optimised layout).

Every quantity here is an integer with the same width and update order the
Verilog uses, so frames rendered here are exactly what the chip draws.
Run:  python3 road_model.py
Outputs: frames.png (montage), drive.gif (short drive), engine.wav (sound)

Screen layout: sky rows 0-127, horizon row 128, road rows 129-383,
dashboard rows 352-479. These boundaries make s_y = y - 128 and most region
tests plain bit slices in hardware.
"""
import numpy as np
from PIL import Image
import wave

# ---------------------------------------------------------------- constants
W_SCREEN, H_SCREEN = 640, 480
HORIZON  = 128          # row level with the eye
DASH_TOP = 352          # dashboard starts here; it is drawn over the road
C_SHIFT  = 14           # fH = 2**14, so z = 2**14 // s_y, s_y = 1..255
STRIPE_BIT = 3          # band half-period = 8 units of road
D_SHIFT  = 5            # stripes use D >> 5 (4 bits)
FOG_SY   = 32           # no stripes for s_y < 32 (s_y[7:5] == 0)
V_MAX    = 224
WHEEL_FULL = True       # False: small wheel for 1x1, True: full wheel for 1x2
ROAD_EDGE, KERB_EDGE = 64, 72   # |p| thresholds (W/H = 1, kerb is w/8)

# curvature wanted in each of the 16 track segments (64 distance wraps each).
# kappa is 4 bits; a negative value's magnitude is its bit inversion, so 5 and
# -6, or 7 and -8, are the same bend in opposite directions.
TRACK = [0, 0, 5, 5, 0, -6, -6, 0, 7, -8, 0, -5, -5, 6, 0, 0]
Z_SAT_SY = 9            # rows with s_y below this use z = 2047

# traffic. Depths are 12 bits with 1 fraction bit: Z >> 1 compares with row depth z.
LANE_P     = 32         # sideways position of the right lane's centre
SLOW_STEP  = 6          # per frame, added to the slow car's depth
ONC_STEP   = -4        # per frame, added to the oncoming car's depth
FAR_HOLD   = 4032      # the slow car stops drawing away at this depth
NEAR_Z     = 128        # depths below this can collide
CRASH_FRAMES = 63
SEGMENTS = {0: "abcdef", 1: "bc", 2: "abdeg", 3: "abcdg", 4: "bcfg", 5: "acdfg",
            6: "acdefg", 7: "abc", 8: "abcdefg", 9: "abcdfg"}

# RGB222 colours, written RR_GG_BB
def c(rr, gg, bb): return (rr << 4) | (gg << 2) | bb
SKY      = [c(0,0,1), c(1,0,2), c(3,1,1), c(3,2,0), c(3,3,1)]   # sunset, bands of 32 rows
MOUNTAIN = c(1,0,1)
DASH_COL = c(1,1,1)
COCKPIT  = c(0,0,1)     # roof, left pillar, top of the dashboard
MIRROR   = c(2,2,2)
VENT_COL = c(2,2,2)
SLOW_BODY, SLOW_LAMP = c(0,1,3), c(3,0,0)
ONC_BODY,  ONC_LAMP  = c(3,3,3), c(3,3,0)
SLOW_SIDE, ONC_SIDE = c(0,0,1), c(1,1,1)
SLOW_GLASS, ONC_GLASS = c(2,1,1), c(2,1,0)     # the sunset, reflected
PANEL_COL = c(0,0,0)
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
P_LIMIT = 80           # and |p| beyond this

def at_limit(value, step, limit=LIMIT):
    """True if adding `step` would push `value` further past +/-96. The
    hardware tests only the top three bits: value >= 96 or value <= -97."""
    return (step > 0 and value >= limit) or (step < 0 and value <= -limit - 1)

class Car:
    def __init__(self):
        self.v, self.D, self.n = 0, 0, 0      # 8u speed, 9u distance, 3u frame count
        self.wheel = 0                        # 3s, -2..2
        self.h = 0                            # 8s heading, pixels, about -100..99
        self.P = LANE_P << P_FRAC             # 14s sideways position, p = P >> 6; right lane
        self.slow = self.onc = 2048           # 12u depths of the two cars
        self.crash = 0                        # 6u frames left of the crash stop
        self.tens = self.ones = 0             # score, cars overtaken, BCD
        self.cap_slow = self.cap_onc = (0, 0) # (Ae, s_y) of each car's base row
        self.track = 0                        # 10u distance wraps; top 4 bits are the segment
        self.kappa = 0                        # 4s road curvature

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
        self.cap_slow = base_row(self, self.slow) or self.cap_slow   # from the frame just drawn
        self.cap_onc = base_row(self, self.onc) or self.cap_onc
        if self.crash:
            self.crash -= 1
            self.n = (self.n + 1) & 0x7
            return
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
        # a hard bend (|kappa| >= 4) pushes the heading outwards
        mag = ~self.kappa if self.kappa < 0 else self.kappa
        push = 0 if mag < 4 or self.wheel != 0 else (1 if self.kappa < 0 else -1)   # not while steering
        dh = (self.wheel + push) * k
        if not at_limit(self.h, dh):
            self.h += dh
        dP = self.h * k
        if not at_limit(self.p, dP, P_LIMIT):
            self.P += dP
        total = self.D + v
        self.D = total & 0x1FF
        if total > 0x1FF:                     # every 512 units of distance
            target = TRACK[self.track >> 6]
            if self.kappa != target and self.track & 3 == 0:   # eases in: every 4 wraps
                self.kappa += 1 if self.kappa < target else -1
            self.track = (self.track + 1) & 0x3FF
        self.n = (self.n + 1) & 0x7
        self.traffic()

    def traffic(self):
        """After the car has moved: each car's depth changes by one shared adder,
        then the collision test."""
        rnd = (self.D & 31) ^ (((self.track & 3) << 3) | self.n)
        def step(z, k, r):
            delta = k - (self.v >> 4)
            if z + delta < 0:                  # passed: respawn far ahead
                return (1 << 11) | (r << 6), True
            if delta >= 0 and z >= FAR_HOLD:
                return z, False
            return z + delta, False
        self.slow, passed = step(self.slow, SLOW_STEP, rnd)
        self.onc, onc_passed = step(self.onc, ONC_STEP, ~rnd & 31)
        if passed:
            self.cap_slow = (self.cap_slow[0], 0)
        if onc_passed:
            self.cap_onc = (self.cap_onc[0], 0)
        if passed:
            self.ones += 1
            if self.ones == 10:
                self.ones = 0
                self.tens = (self.tens + 1) % 10
        p = self.p
        hit = (self.slow < NEAR_Z and 0 <= p < 64) or (self.onc < NEAR_Z and -64 <= p < 0)
        if hit:
            self.crash = CRASH_FRAMES
            self.v = self.wheel = self.h = 0
            self.P = LANE_P << P_FRAC
            self.slow = (1 << 11) | (rnd << 6)
            self.onc = (1 << 11) | ((~rnd & 31) << 6)
            self.tens = self.ones = 0
            self.cap_slow = (self.cap_slow[0], 0)
            self.cap_onc = (self.cap_onc[0], 0)

# ---------------------------------------------------------------- curves
def wrap11(value):
    return ((value + 1024) & 2047) - 1024

def line_centre(A, z, s_y, kappa):
    """The per-line value Ae with x - centre = x + Ae: A >> 6 plus the curve
    offset kappa * z / 64, built as the hardware does with up to three shifted
    adds in horizontal blanking. Each is one's complement when kappa >= 0."""
    A = ((A + 65536) & 131071) - 65536      # A is 17 bits
    Ae = wrap11(A >> 6)
    zs = 2047 if s_y < Z_SAT_SY else z & 0x7FF
    mag = (~kappa if kappa < 0 else kappa) & 7
    for bit, shift in enumerate((6, 5, 4)):
        if (mag >> bit) & 1:
            term = zs >> shift
            Ae = wrap11(Ae + (term if kappa < 0 else ~term))
    return Ae

# ---------------------------------------------------------------- steering wheel
def wheel_code(wheel, full):
    """Per-pixel wheel code for the whole screen: 0 none, 1 black, 2 yellow,
    3 grey. Centre (320, 448). a and b use bit inversion, as the hardware does;
    negative shears are one's complement (no carry), which keeps the across
    spoke exactly mirror-symmetric between w and -w."""
    y_, x_ = np.mgrid[0:H_SCREEN, 0:W_SCREEN]
    x1 = x_ - 1 if full else x_             # the full wheel takes one more clock
    dx, dy = x1 - 320, y_ - 448
    a = np.where(dx < 0, ~dx, dx)
    b = np.where(dy < 0, ~dy, dy)
    s = a + b
    shift = {0: None, 1: 2, 2: 1}[abs(wheel)]       # slope wheel/4
    tx = 0 * dx if shift is None else dx >> shift
    sh = dy + ~tx if wheel > 0 else dy + tx
    code = np.zeros_like(x_)
    if full:
        on = (x1 >= 192) & (x1 < 448) & (y_ >= 320)
        in_out = s < 181                    # a, b < 128 from their widths
        in_in  = (a < 112) & (b < 112) & (s < 158)
        rim = in_out & ~in_in
        hub = (a < 20) & (b < 20) & (s < 28)
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

# ---------------------------------------------------------------- traffic and score
RECIP = [0] + [serial_recip(s) for s in range(1, 256)]

def row_depth(s_y):
    """The depth a row is compared with: z, clamped very near the horizon."""
    return 2047 if s_y < Z_SAT_SY else RECIP[s_y] & 0x7FF

def base_row(car, Z):
    """Scanning down, the last row with z >= zc is the car's base; the hardware
    stores (Ae, s_y) there, and the next frame draws from them. Returns None if
    no base row was seen in rows 1..254."""
    zc, found = Z >> 1, None
    for s in range(1, 255):
        if row_depth(s) >= zc and row_depth(s + 1) < zc:
            A = ((car.h - 320) << 6) + (car.P >> 5) * s
            found = (line_centre(A, RECIP[s], s, car.kappa), s)
    return found

def draw_cars(row, d, left, s_y, car, now):
    """Upright cars, one width and position for every row, from the stored base.
    The side panel lies beyond the rear face and stops at the road's ground line
    for that row, so it vanishes when the car is straight ahead."""
    x = np.arange(W_SCREEN)
    Sy = s_y << 1
    a_row, b_row = Sy >> 2, (Sy >> 1) + (Sy >> 2)
    for (Ae, s), base, is_left, body, lamp, flank, glass in (
            (car.cap_slow, now[0], False, SLOW_BODY, SLOW_LAMP, SLOW_SIDE, SLOW_GLASS),
            (car.cap_onc, now[1], True, ONC_BODY, ONC_LAMP, ONC_SIDE, ONC_GLASS)):
        # below this frame's base row the stored value has already been replaced
        if base is not None and s_y > base[1]:
            continue
        if s_y > s or s_y < (s >> 1):                   # a cuboid, s/2 tall
            continue
        dc = ((x + Ae + 1024) & 2047) - 1024
        da = np.where(dc < 0, ~dc, dc) & 1023
        lane = (dc < 0) if is_left else (dc >= 0)
        road_side = left if is_left else ~left
        S = s << 1
        a, b, w = S >> 2, (S >> 1) + (S >> 2), S >> 3
        inner = lane & road_side & (da >= a - w) & (da < a) & (d >= a_row)
        outer = lane & road_side & (da >= b) & (da < b + w) & (d < b_row)
        row[inner | outer] = flank
        face = lane & (da >= a) & (da < b)
        outside = (da < a + (S >> 4)) | (da >= b - (S >> 4))
        row[face] = body
        # the top band is the window; an oncoming car's windscreen is taller
        if s_y < (s >> 1) + ((s >> 2) if is_left else (s >> 3)):
            row[face & ~outside] = glass
        else:
            row[face & outside] = lamp

def score_code(tens, ones):
    """0 none, 1 panel, 2 lit segment, rows 384-447: the score at columns 128-191."""
    y_, x_ = np.mgrid[0:H_SCREEN, 0:W_SCREEN]
    rows = (y_ >= 384) & (y_ < 448)
    right = (x_ >= 128) & (x_ < 192) & rows
    panel = right
    cx, cy = (x_ >> 2) & 7, (y_ >> 3) & 7
    mid = (cx >= 1) & (cx <= 5)
    upper, lower = (cy >= 1) & (cy <= 3), (cy >= 5) & (cy <= 6)
    parts = dict(a=mid & (cy == 0), b=(cx == 6) & upper, c=(cx == 6) & lower, d=mid & (cy == 7),
                 e=(cx == 0) & lower, f=(cx == 0) & upper, g=mid & (cy == 4))
    lit = np.zeros_like(x_, dtype=bool)
    for digit, columns in ((tens, right & (x_ < 160)), (ones, right & (x_ >= 160))):
        for name in SEGMENTS[digit]:
            lit |= parts[name] & columns
    code = np.zeros_like(x_)
    code[panel] = 1
    code[panel & lit] = 2
    return code

# ---------------------------------------------------------------- interior
def interior_code():
    """Per-pixel interior code: 0 none, 1 roof or pillar, 2 mirror, 3 top of the
    dashboard, 4 console panel, 5 grille slat, 6 side window. We sit on the left,
    so only the left has a pillar. t = y/4 + ~x uses one's complement, and the
    pillar is where t is -48..-1 and the window where t >= 0."""
    y_, x_ = np.mgrid[0:H_SCREEN, 0:W_SCREEN]
    t = (y_ >> 2) + ~x_
    dash = y_ >= DASH_TOP
    roof = y_ < 16
    pillar = ~dash & (t >= -48) & (t < 0)
    window = ~dash & ~roof & (t >= 0)
    mirror = (x_ >= 256) & (x_ < 384) & (y_ >= 16) & (y_ < 32)
    pad = dash & (y_ < DASH_TOP + 16)
    console = (x_ >= 512) & (y_ >= 416)
    vent = (y_ >= 424) & (x_ >= 528) & ((y_ >> 2) & 1 == 1)   # the grille
    code = np.zeros_like(x_)
    code[window] = 6
    code[console] = 4
    code[vent] = 5
    code[pad] = 3
    code[roof | pillar] = 1
    code[mirror] = 2
    return code

# ---------------------------------------------------------------- renderer
def render(car):
    """Draw one frame exactly as the hardware would, line by line."""
    img = np.zeros((H_SCREEN, W_SCREEN), dtype=np.uint8)
    x = np.arange(W_SCREEN)
    d_hi = car.D >> D_SHIFT                # 4 bits of distance
    u = ((x + car.h) & 0xFF) >> 1          # mountain column, twice as wide: wraps every 256 px
    tri = np.where(u & 0x20, 31 - (u & 0x1F), u & 0x1F)        # 0..31 ramp
    mountain_h = np.where(u & 0x40, tri, tri >> 1)              # alternate hills: no adder
    A = 0
    bases = (base_row(car, car.slow), base_row(car, car.onc))
    for y in range(H_SCREEN):
        if y < HORIZON:
            # the lower half of each band is a checkerboard with the next colour
            dither = ((x ^ y) & 1) & ((y >> 4) & 1)
            row = np.array(SKY, np.uint8)[(y >> 5) + dither]
            row[(127 - y) < mountain_h] = MOUNTAIN    # i.e. 128 - y <= height
            img[y] = row
        elif y >= DASH_TOP:
            row = np.full(W_SCREEN, DASH_COL, np.uint8)
            img[y] = row
        else:
            s_y = y - HORIZON
            mag = (~car.kappa if car.kappa < 0 else car.kappa) & 7
            if s_y == 0 or (s_y < Z_SAT_SY and mag):   # horizon, or a curve out of sight
                img[y] = GRASS[0]
            else:
                z = serial_recip(s_y)      # computed in previous line's hblank
                w = s_y << 1               # the road is twice as wide as the eye is high
                kerb_w = w + (w >> 3)
                dash_w = (w >> 5) + 1
                dx = x + line_centre(A, z, s_y, car.kappa)   # x - centre, one adder
                d = np.where(dx < 0, -dx - 1, dx)   # bit inversion, not negation
                stripe = ((z + d_hi) >> STRIPE_BIT) & 1 if s_y >= FOG_SY else 0
                row = np.full(W_SCREEN, GRASS[stripe], np.uint8)
                row[d < kerb_w] = KERB[stripe]
                row[d < w] = TARMAC[stripe]
                if stripe:
                    row[d < dash_w] = LINE_COL
                draw_cars(row, d, dx < 0, s_y, car, bases)
                img[y] = row
        # end-of-line updates at x = 799
        if y == HORIZON - 1:
            A = (car.h - 320) << 6         # centre offset folded into A
        elif HORIZON <= y < DASH_TOP:
            A += car.P >> 5                # each unit of p counts double on screen
    inner = interior_code()
    tint = (img >> 1) & 0b01_01_01          # each channel halved
    img[inner == 6] = tint[inner == 6]
    img[inner == 1] = COCKPIT
    img[inner == 2] = MIRROR
    img[inner == 3] = COCKPIT
    img[inner == 4] = PANEL_COL
    img[inner == 5] = VENT_COL
    score = score_code(car.tens, car.ones)
    img[score == 1] = PANEL_COL
    img[score == 2] = BAR_COL
    code = wheel_code(car.wheel, WHEEL_FULL)
    img[code == 1] = WHEEL0
    img[code == 2] = BAR_COL
    img[code == 3] = WHEEL1
    if car.crash:
        img |= 0b11_00_00                   # red flash
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

def crash_script(n):
    """Hold the right lane flat out, into the slow car."""
    car = Car(); out = []
    for _ in range(n):
        err = car.h + ((car.p - LANE_P) >> 1)
        keys = dict(accel=1, left=err > 4, right=err < -4)
        car.frame(**keys)
        out.append(keys)
    return out

def lap_script(n):
    """Drives the bends: keeps right and overtakes when the left lane is clear."""
    car = Car(); out = []
    for _ in range(n):
        blocked = car.slow < 450
        clear = car.onc > 1750
        overtaking = blocked and (car.p < 0 or clear)
        target = -LANE_P if overtaking else LANE_P
        err = car.h + ((car.p - target) >> 1)
        keys = dict(accel=overtaking or not blocked, brake=blocked and not overtaking,
                    left=err > 4, right=err < -4)
        car.frame(**keys)
        out.append(keys)
    return out

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
        speeds.append(car.v); offs.append(car.offroad() or car.crash != 0)
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
