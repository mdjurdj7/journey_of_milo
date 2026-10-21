# Floor 3's ground from floor3_walkable_sample.png. Run from this folder.
# Needs Python 3 with numpy, scipy, scikit-image and Pillow:
#   python -m pip install --user numpy scipy scikit-image pillow
#
# 2026-10-21 rework (drawn here, not painted - the sample is unchanged):
#   - WEST LUMP: the wagon lobe and the west bulge become one lump, split from
#     the hub by a dune ridge, entered through a neck that faces spawn.
#   - RIM TRAIL: a raised walkable strip from the top of the lump along the
#     north rim, ending in a bank that drops into the top arm east of the
#     required fight. One-way is NOT in the masks: the wiring adds it.
#   - ROCKY PATH: the Wardling's arm narrowed to a 3 m path; rock on its floor.
#   - SEA: open water past the Wardling's pocket, a distant view.
#   ELEV_MAX goes 1.8 -> 2.4 so the raised trail's ridge isn't clipped:
#   region1_floor3.tres elevation_max_height must be set to 2.4 to match.
import json, numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt, gaussian_filter, label, binary_closing
from scipy.interpolate import splprep, splev
from skimage.measure import find_contours, approximate_polygon
from skimage.morphology import dilation, disk

PX = 30.0                      # px per metre (Field Asset Spec)
ELEV_MAX = 2.4                 # metres at elevation value 1.0 (region1_floor3.tres elevation_max_height) - WAS 1.8
BASE_WALK = 0.4                # walkable floor height above the outer ground (m)
CREST_RISE = 1.2               # ridge crest above the floor beside it (m)
FACE_W = 2.0                   # inner face width (m) -> ~31 deg mean slope, under the 45 deg limit
CREST_W = 1.0                  # flat-ish crest width (m)
OUTER_FALL = 4.0               # outer slope down to the outer ground (m)
BARRIER_IN = 0.4               # ledge barrier sits this far up the inner face (m)
OUTER_EDGE_AT = FACE_W + 0.5 * CREST_W   # outer ground starts at the crest centreline (m past the walkable edge)
OUTER_EDGE_WIDTH = 0.3         # the whole outer-ground transition (m)

src = np.array(Image.open("floor3_walkable_sample.png").convert("RGB")).astype(int)
# Canvas padding (2026-10-21): the rim trail runs within ~3 m of the sample's
# top edge, and the shader extends edge values past the canvas (straight
# north-south streaks on the slopes); the sea needs room so its far side
# (mask_beyond_is_land) sits out of view. The sample stays as painted; every
# image-px constant below is in sample px and goes through Y()/P().
PAD_T, PAD_R = 240, 300
src = np.pad(src, ((PAD_T, 0), (0, PAD_R), (0, 0)))
def Y(y): return y + PAD_T
def P(pts): return [(x, Y(y)) for x, y in pts]
H, W, _ = src.shape
r, g, b = src[...,0], src[...,1], src[...,2]
def dot(mask):
    ys, xs = np.nonzero(mask); return (float(xs.mean()), float(ys.mean()))
spawn = dot((r > 200) & (g < 80) & (b < 80))
exit_ = dot((g > 200) & (r < 80) & (b < 80))
elite = dot((r > 200) & (g > 200) & (b < 80))
walk = (src.sum(-1) > 3*127)            # white or any coloured dot = walkable
yy, xx = np.mgrid[0:H, 0:W]
def px_of(wx, wz):
    return (spawn[0] + wx * PX, spawn[1] + wz * PX)
def smooth_local(m, window, close_m, smooth_m):
    closed = binary_closing(m, structure=disk(int(close_m * PX)))
    sm = gaussian_filter(closed.astype(float), smooth_m * PX) > 0.5
    return np.where(window, sm, m)
def polyline_dist(pts):
    d = np.full((H, W), 1e9)
    for (x0, y0), (x1, y1) in zip(pts[:-1], pts[1:]):
        vx, vy = x1 - x0, y1 - y0
        t = np.clip(((xx - x0) * vx + (yy - y0) * vy) / (vx * vx + vy * vy), 0, 1)
        d = np.minimum(d, np.hypot(xx - (x0 + t * vx), yy - (y0 + t * vy)))
    return d
def spline(pts, n=800):
    sx, sy = zip(*pts)
    tck, _ = splprep([sx, sy], s=0, k=min(3, len(pts) - 1))
    u = np.linspace(0, 1, n)
    x_, y_ = splev(u, tck)
    return np.array(x_), np.array(y_)

# ROCKY PATH: the Wardling's arm, between the hub and the lobe cut, becomes a
# PATH_WIDTH_M path along PATH_PTS (an elbow). Done before the lobe so the lobe's neck
# (measured at the cut) comes out at the path's width.
LOBE_CUT_X = 14.6              # where the painted neck starts widening into the old lobe
ROCKY_PATH = True
PATH_X0 = 800                  # px: the hub's east edge, where the path starts
PATH_Y = 938                   # px: path centreline (the lobe centre's row is 933)
PATH_WIDTH_M = 3.0
cut_px = spawn[0] + LOBE_CUT_X * PX
path_band = np.zeros((H, W), bool)
PATH_PTS = P([(790, 950), (880, 1000), (975, 990), (1052, 936)])   # an elbow: dips south-east, turns north-east into the pocket
if ROCKY_PATH:
    arm = (xx >= PATH_X0) & (xx <= cut_px + 2) & (yy > Y(840)) & (yy < Y(1090))
    walk = walk & ~arm
    px_, py_ = spline(PATH_PTS, 500)
    rr = 0.5 * PATH_WIDTH_M * PX
    for x_, y_ in zip(px_, py_):
        x0, x1 = int(x_ - rr - 1), int(x_ + rr + 2); y0, y1 = int(y_ - rr - 1), int(y_ + rr + 2)
        sub = (xx[y0:y1, x0:x1] - x_) ** 2 + (yy[y0:y1, x0:x1] - y_) ** 2 <= rr * rr
        path_band[y0:y1, x0:x1] |= sub
    path_band &= xx <= cut_px
    walk |= path_band
    win = (xx > PATH_X0 - 2 * PX) & (xx < PATH_X0 + 2 * PX) & (yy > Y(820)) & (yy < Y(1110))
    walk = smooth_local(walk, win, 1.0, 0.6)

# The east lobe (the Wardling's) is drawn here, not painted: the painted
# lobe past LOBE_CUT_X goes, the neck runs on at its own width to the
# lobe's centre, and an ellipse round that centre is the lobe; the joins
# are filleted LOBE_FILLET round, within a window round the lobe only.
# World metres from spawn (+Z south). The elite dot moves to ELITE_WORLD.
LOBE_CENTRE = (18.1, -14.4)
LOBE_RADII = (3.5, 4.17)       # x (east-west), z (north-south)
LOBE_FILLET = 1.0
ELITE_WORLD = (17.6, -13.6)
lab, _ = label(walk & (xx >= cut_px))
walk = walk & ~(lab == lab[int(round(elite[1])), int(round(elite[0]))])
cx, cz = px_of(*LOBE_CENTRE)
col = walk[:, int(cut_px) - 1]
top = bot = int(round(cz))
while col[top - 1]: top -= 1
while col[bot + 1]: bot += 1
neck = (xx >= cut_px - 1) & (xx <= cx) & (yy >= top) & (yy <= bot)
lobe = ((xx - cx) / (LOBE_RADII[0] * PX)) ** 2 + ((yy - cz) / (LOBE_RADII[1] * PX)) ** 2 <= 1.0
walk = walk | neck | lobe
window = (xx > cut_px - 2 * PX) & (np.abs(yy - cz) < (LOBE_RADII[1] + 1.5) * PX)
walk = np.where(window, binary_closing(walk, structure=disk(int(LOBE_FILLET * PX))), walk)
elite = px_of(*ELITE_WORLD)
# (rock stops at the pocket entrance: the lobe neck is not path)

# WEST LUMP: blobs join the wagon lobe and the west bulge down the west side;
# a ridge (unwalkable, RIDGE_GAP_M wide) cuts the lump off the hub from the
# notch above the wagon lobe down to RIDGE_PTS' last point; below that is the
# neck, facing spawn. Image px.
WEST_LUMP = True
LUMP_BLOBS = [((330, Y(700)), 110), ((335, Y(880)), 115)]
RIDGE_PTS = P([(600, 480), (520, 620), (462, 760), (452, 830)])   # ends halfway down the lump: the neck opens mid-hub
RIDGE_GAP_M = 3.7
if WEST_LUMP:
    for (bx, by), br in LUMP_BLOBS:
        walk |= (xx - bx) ** 2 + (yy - by) ** 2 <= br * br
    win = (xx < 640) & (yy > Y(560)) & (yy < Y(1240))
    walk = smooth_local(walk, win, 1.5, 0.8)
    walk &= polyline_dist(RIDGE_PTS) > 0.5 * RIDGE_GAP_M * PX

# RIM TRAIL: a raised strip from the top of the lump along the north rim,
# past the stream's head, down a bank into the top arm east of the fight.
# Heights: rises TRAIL_RISE_M over TRAIL_RAMP_M from the lump, holds, and
# drops back over the last BANK_M where it meets the top arm. Image px.
RIM_TRAIL = True
TRAIL_PTS = P([(420, 455), (428, 330), (500, 215), (660, 150), (830, 110), (960, 92), (1030, 120), (1045, 190), (1042, 266)])
TRAIL_WIDTH_M = 2.7
TRAIL_RISE_M = 0.8
TRAIL_RAMP_M = 12.0
BANK_M = 1.2
trail = np.zeros((H, W), bool)
trail_s = np.full((H, W), -1.0)
if RIM_TRAIL:
    tx, ty = spline(TRAIL_PTS, 1200)
    seg = np.hypot(np.diff(tx), np.diff(ty)); s_arc = np.r_[0, np.cumsum(seg)] / PX
    rr = 0.5 * TRAIL_WIDTH_M * PX
    for x_, y_, s_ in zip(tx, ty, s_arc):
        x0, x1 = int(x_ - rr - 1), int(x_ + rr + 2); y0, y1 = int(y_ - rr - 1), int(y_ + rr + 2)
        sub = (xx[y0:y1, x0:x1] - x_) ** 2 + (yy[y0:y1, x0:x1] - y_) ** 2 <= rr * rr
        blk = trail_s[y0:y1, x0:x1]
        blk[sub & (blk < 0)] = s_
        trail[y0:y1, x0:x1] |= sub
    trail &= ~walk
    trail_s[~trail] = -1.0
    main = walk.copy()
    walk |= trail
    TRAIL_LEN_M = float(s_arc[-1])

# The stream across the top bend (unchanged).
STREAM = True
STREAM_PTS = P([(898, 282), (872, 352), (872, 440), (846, 512), (862, 594)])
STREAM_WIDTH_M = (1.8, 3.2)
STREAM_INTO_FACE_M = 0.5
STREAM_BANK_M = 5.0
stream = np.zeros((H, W), bool)
if STREAM:
    sx, sy = zip(*STREAM_PTS)
    tck, _ = splprep([sx, sy], s=0, k=3)
    for u in np.linspace(0, 1, 600):
        x_, y_ = splev(u, tck)
        w_ = np.interp(abs(2 * u - 1) ** 2, [0, 1], STREAM_WIDTH_M)
        r_ = 0.5 * w_ * PX
        x0, x1 = int(x_ - r_ - 1), int(x_ + r_ + 2)
        y0, y1 = int(y_ - r_ - 1), int(y_ + r_ + 2)
        sub = (xx[y0:y1, x0:x1] - x_) ** 2 + (yy[y0:y1, x0:x1] - y_) ** 2 <= r_ * r_
        stream[y0:y1, x0:x1] |= sub
    stream &= dilation(main if RIM_TRAIL else walk, disk(int(STREAM_INTO_FACE_M * PX)))
d_stream = distance_transform_edt(~stream) / PX if STREAM else np.full((H, W), 1e9)
bank = np.clip(d_stream / STREAM_BANK_M, 0, 1)
bank = bank * bank * (3 - 2 * bank)

# SEA: open water past the Wardling's pocket (east canvas edge). Image px.
SEA = True
SEA_COAST = P([(1950, 420), (1740, 520), (1580, 640), (1500, 760), (1468, 880), (1452, 960), (1470, 1060), (1500, 1180), (1488, 1300), (1530, 1420), (1620, 1560), (1780, 1660), (1950, 1700)])
sea = np.zeros((H, W), bool)
if SEA:
    cxs, cys = spline(SEA_COAST, 400)
    im = Image.new("L", (W, H), 0)
    ImageDraw.Draw(im).polygon(list(zip(cxs, cys)) + [(W + 5, Y(1700)), (W + 5, Y(420))], fill=255)
    sea = np.array(im) > 127

# floor heights: the floor (dipped to the stream), the trail raised on it
floor = BASE_WALK * bank
if RIM_TRAIL:
    s = np.clip(trail_s / TRAIL_RAMP_M, 0, 1); ramp = s * s * (3 - 2 * s)
    d_main = distance_transform_edt(~main) / PX
    near_end = trail_s > TRAIL_LEN_M - 6.0                 # only the bank end drops, not the lump end
    drop = np.where(near_end, np.clip(d_main / BANK_M, 0, 1), 1.0)
    floor = np.where(trail, floor + TRAIL_RISE_M * ramp * drop, floor)

# signed distance: >0 outside the walkable area; every outside cell takes the
# floor height of its nearest walkable cell as its base
d_out, (iy, ix) = distance_transform_edt(~walk, return_indices=True)
d_out = d_out / PX
base = floor[iy, ix]
base = np.where(walk, base, gaussian_filter(base, 1.2 * PX))   # no steps where two bases meet on a ridge
o = d_out
h = np.where(walk, floor, 0.0).astype(np.float32)
face = np.clip(o / FACE_W, 0, 1)
h = np.where(o > 0, base + CREST_RISE * face, h)
fall_t = np.clip((o - FACE_W - CREST_W) / OUTER_FALL, 0, 1)
crest_h = base + CREST_RISE
h = np.where(o > FACE_W + CREST_W, crest_h - crest_h * fall_t, h)
h = gaussian_filter(h, sigma=0.3 * PX)

elev = np.clip(h / ELEV_MAX, 0, 1)
Image.fromarray((elev * 255 + 0.5).astype(np.uint8), "L").save("../../region1_floor3_elev.png")

# rock mask: the inner face grown ~1 m, plus scree on the rocky path's floor
rock = (o > 0) & (o < FACE_W + 1.0)
rock = gaussian_filter(rock.astype(np.float32), 2.0)
if ROCKY_PATH:
    rng_r = np.random.default_rng(7)
    scree = gaussian_filter(rng_r.standard_normal((H, W)).astype(np.float32), 0.35 * PX)
    scree = np.clip((scree - scree.mean()) / (scree.std() + 1e-6) * 0.5 + 0.75, 0.45, 1.0)
    pb = gaussian_filter(path_band.astype(np.float32), 0.3 * PX)
    rock = np.maximum(rock, pb * scree)
Image.fromarray((np.clip(rock, 0, 1) * 255).astype(np.uint8), "L").save("../../region1_floor3_rock.png")

t = np.clip((o - OUTER_EDGE_AT) / OUTER_EDGE_WIDTH + 0.5, 0, 1)
outer_ground = t * t * (3 - 2 * t)
Image.fromarray((outer_ground * 255 + 0.5).astype(np.uint8), "L").save("../../region1_floor3_outer.png")

# landmass: land except the stream (an enclosed pool) and the sea (open, at
# the canvas edge). ~10 px blur on the edges.
land = np.where(stream | sea, 0.0, 1.0).astype(np.float32)
land = gaussian_filter(land, 10.0 / 3.0)
Image.fromarray((land * 255 + 0.5).astype(np.uint8), "L").save("../../region1_floor3_landmass.png")

rng = np.random.default_rng(11)
n = gaussian_filter(rng.standard_normal((H, W)).astype(np.float32), 1.4 * PX)
n = (n - n.min()) / (n.max() - n.min())
outer = np.clip((o - (FACE_W + CREST_W + 2.0)) / 3.0, 0, 1)
damp = gaussian_filter(((n > 0.6).astype(np.float32)) * outer * (1 - sea), 0.6 * PX)
Image.fromarray((np.clip(damp, 0, 1) * 255).astype(np.uint8), "L").save("./floor3_damp.png")

barrier = dilation(walk, disk(int(BARRIER_IN * PX)))
cs = find_contours(barrier.astype(float), 0.5)
c = max(cs, key=len)
poly = approximate_polygon(c, tolerance=0.08 * PX)
def to_world(py, px_):
    return [round((px_ - spawn[0]) / PX, 3), round((py - spawn[1]) / PX, 3)]
ledge = [to_world(p[0], p[1]) for p in poly]
# Interior barrier loops: since the rim trail closes a ring (lump - trail -
# top arm - hub), the ridges inside that ring are holes in the walkable area,
# not part of the outer loop. Each becomes its own closed barrier loop, so the
# ridges block like every other ledge; the neck and the trail's bank stay open
# (the bank's one-way ledge is added in the wiring).
barrier_holes = []
for c_h in cs:
    if c_h is c or len(c_h) < 40:
        continue
    py_, px_ = c_h[:, 0], c_h[:, 1]
    area = 0.5 * abs(np.dot(px_, np.roll(py_, 1)) - np.dot(py_, np.roll(px_, 1)))
    if area < (2.0 * PX) ** 2:
        continue
    poly_h = approximate_polygon(c_h, tolerance=0.08 * PX)
    barrier_holes.append([to_world(q[0], q[1]) for q in poly_h])

extra = {}
if RIM_TRAIL:
    ex, ey = TRAIL_PTS[-1]
    bank_cells = trail & (trail_s > TRAIL_LEN_M - 6.0) & (d_main < BANK_M + 0.2) & (d_main > 0)
    bys, bxs = np.nonzero(bank_cells)
    extra["rim_trail"] = {
        "centreline_world_xz": [to_world(y_, x_) for x_, y_ in TRAIL_PTS],
        "width_m": TRAIL_WIDTH_M, "length_m": round(TRAIL_LEN_M, 1),
        "rise_above_floor_m": TRAIL_RISE_M, "bank_m": BANK_M,
        "drop_centre_world_xz": to_world(float(bys.mean()), float(bxs.mean())),
        "drop_note": "One-way: the wiring adds a ledge segment across the trail at the bank that can be walked down, not up, plus the drop trigger.",
        "head_world_xz": to_world(TRAIL_PTS[0][1], TRAIL_PTS[0][0]),
    }
if WEST_LUMP:
    extra["west_lump"] = {"ridge_world_xz": [to_world(y_, x_) for x_, y_ in RIDGE_PTS], "ridge_gap_m": RIDGE_GAP_M,
                          "neck_note": "South of the ridge's last point, opening onto the middle of the hub."}
if ROCKY_PATH:
    extra["rocky_path"] = {"x_from_to_world": [round((PATH_X0 - spawn[0]) / PX, 2), round(LOBE_CUT_X, 2)],
                           "centreline_world_xz": [to_world(y_, x_) for x_, y_ in PATH_PTS], "width_m": PATH_WIDTH_M,
                           "note": "Rock mask carries scree on the path floor. If the shader gates rock by slope, the floor shows sand: then flat slabs/scree go in as no-collision scatter, boulders with collision on both sides."}
if SEA:
    extra["sea"] = {"coast_world_xz": [to_world(y_, x_) for x_, y_ in SEA_COAST], "note": "Open water at the east canvas edge (landmass 0)."}

layout = {
    "canvas_px": [W, H], "px_per_m": PX, "canvas_pad_px": {"top": PAD_T, "right": PAD_R, "note": "Padded 2026-10-21 from 1650x1710. Pad the hand-painted wear mask the same way (black rows on top, black columns on the right) and update mask_origin in region1_floor3.tres to landmass_mask_origin_uv."},
    "landmass_mask_origin_uv": [round(spawn[0] / W, 5), round(spawn[1] / H, 5)],
    "spawn_px": [round(spawn[0], 1), round(spawn[1], 1)],
    "exit_world_xz": to_world(exit_[1], exit_[0]),
    "elite_world_xz": to_world(elite[1], elite[0]),
    "assumed_elevation_max_height_m": ELEV_MAX,
    "heights_m": {"outer_ground": 0.0, "walkable_floor": BASE_WALK, "ridge_crest": BASE_WALK + CREST_RISE,
                  "rim_trail": BASE_WALK + TRAIL_RISE_M},
    "ridge": {"inner_face_width_m": FACE_W, "crest_width_m": CREST_W, "outer_falloff_m": OUTER_FALL},
    "outer_ground": {"edge_at_m": OUTER_EDGE_AT, "edge_width_m": OUTER_EDGE_WIDTH},
    "east_lobe": {"cut_x_m": LOBE_CUT_X, "centre_world_xz": list(LOBE_CENTRE), "radii_m": list(LOBE_RADII), "fillet_m": LOBE_FILLET},
    **extra,
    "ledge_barrier_world_xz": ledge,
    "ledge_barrier_holes_world_xz": barrier_holes,
    "note": "World XZ in metres relative to spawn; +X right, +Z toward the bottom of the image (south). Forward/exit is toward -Z.",
}
json.dump(layout, open("./floor3_layout.json", "w"), indent=1)

# preview: hillshade (sun from ESE, 45 deg) + rock tint + damp + dots
gy, gx = np.gradient(h * PX / 1.0, 1.0)
nx, ny, nz = -gx, -gy, np.ones_like(h)
norm = np.sqrt(nx**2 + ny**2 + nz**2); nx, ny, nz = nx/norm, ny/norm, nz/norm
sun = np.array([0.6, 0.35, 0.72]); sun /= np.linalg.norm(sun)
shade = np.clip(nx*sun[0] + ny*sun[1] + nz*sun[2], 0, 1)
sand = np.array([0.74, 0.70, 0.60]); stone = np.array([0.56, 0.59, 0.50])
slope = np.degrees(np.arctan(np.hypot(*np.gradient(h, 1.0/PX))))
rk = np.clip((slope - 22) / 12, 0, 1) * np.clip(rock, 0, 1)
rk = np.maximum(rk, np.clip(rock, 0, 1) * path_band * 0.8)
col = sand[None,None,:]*(1-rk[...,None]) + stone[None,None,:]*rk[...,None]
col = col * (1 - 0.28*np.clip(damp,0,1))[...,None]
col = col * (0.55 + 0.45*shade)[...,None]
outside = (o > FACE_W + CREST_W)
col = col * np.where(outside, 0.88, 1.0)[...,None]
if STREAM:
    wet = np.clip(1 - d_stream / 0.8, 0, 1) * (1 - stream)
    col = col * (1 - 0.28 * wet)[...,None]
    shallow = np.array([0.54, 0.60, 0.61]); seabed = sand * 0.72 * 0.8
    d_in_s = distance_transform_edt(stream) / PX
    k = np.clip(d_in_s / 1.2, 0, 1)[...,None] * 0.75
    water = seabed[None,None,:] * (1 - k) + shallow[None,None,:] * k
    col = np.where(stream[...,None], water, col)
if SEA:
    col = np.where(sea[...,None], np.array([0.42, 0.52, 0.56])[None,None,:], col)
img = (np.clip(col, 0, 1) * 255).astype(np.uint8)
im = Image.fromarray(img, "RGB")
dr = ImageDraw.Draw(im)
for c_, colr in [(spawn,(200,40,40)),(exit_,(40,160,60)),(elite,(210,170,0))]:
    dr.ellipse([c_[0]-10,c_[1]-10,c_[0]+10,c_[1]+10], fill=colr)
pts = [(p[1], p[0]) for p in poly]
dr.line(pts + [pts[0]], fill=(30,60,140), width=2)
im.save("./floor3_ground_preview.png")

print("spawn", spawn, "exit", exit_, "elite", elite)
print("ledge points", len(ledge), "hole loops", [len(hh) for hh in barrier_holes])
print("max slope on faces", round(float(slope[(o>0)&(o<FACE_W)].max()),1), "deg")
if RIM_TRAIL:
    print("trail length m", round(TRAIL_LEN_M,1), "trail height range m", round(float(floor[trail].min()),2), round(float(floor[trail].max()),2))
    print("bank slope max deg", round(float(slope[trail & (trail_s > TRAIL_LEN_M - 6)].max()),1))
lab_all, nlab = label(walk); print("walkable regions", nlab)
print("elev clipped px", int((h / ELEV_MAX > 1).sum()))
