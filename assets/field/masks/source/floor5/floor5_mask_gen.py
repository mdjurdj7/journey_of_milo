"""Floor 5 ground generator (Region 1's last floor): a broad slope climbing north out of the
dunes to a rocky crest, where the region-end fight is; the exit drops away beyond it.
Reads floor5_walkable_sample.png (white = walkable, coloured dots = markers) and writes the
runtime masks plus floor5_layout.json. Conventions follow floor3/floor4_mask_gen.py: outer-ground
smoothstep on the crest centreline, ledge tolerance 0.08 m. New here: the walk floor rises along
the route (WALK_PROFILE), and the boundary and outer ground rise with it."""
import json, os, numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import distance_transform_edt, gaussian_filter, binary_dilation
from skimage.measure import find_contours, approximate_polygon
from skimage.morphology import disk

PX = 30.0
ELEV_MAX = 5.0            # metres at elevation 1.0 -> set floor 5's elevation_max_height to this
CREST_RISE = 1.2          # boundary crest above the local walk floor (m)
FACE_W, CREST_W, OUTER_FALL = 2.0, 1.0, 4.0
OUTER_DROP = 0.4          # outer ground sits this far below the local walk floor
OUTER_EDGE_AT, OUTER_EDGE_WIDTH = FACE_W + CREST_W / 2, 0.3
BARRIER_IN = 0.4
LEDGE_TOL = 0.08
# walk-floor height (m) against world z (north negative): foot, long climb, rock shelf, crest flat, drop to exit
WALK_PROFILE = [(8.0, 0.4), (0.0, 0.4), (-29.5, 2.4), (-30.5, 2.45), (-33.0, 3.4), (-34.0, 3.45),
                (-49.0, 3.45), (-60.0, 2.45), (-70.0, 2.45)]
SHELF_Z = (-34.5, -29.0)  # the exposed rock shelf band's outer reach (world z range)
# The shelf's stone edges wobble along x so it emerges irregularly from the sand, not as a stripe:
# each edge sits on the contour where the shelf turns steep enough for stone (rock_slope_min 10 deg,
# z -30.3 south and -33.4 north), moved +-SHELF_WOBBLE m by low-frequency noise and feathered over
# SHELF_FEATHER m. Pulled in, an edge trims at most ~1 m of the margin; the steepest line
# (z ~-31.9) is covered everywhere.
SHELF_EDGE_Z = (-33.4, -30.3)
SHELF_WOBBLE, SHELF_FEATHER = 1.0, 1.0
SHELF_WAVES_M = (13.0, 7.0)   # wavelengths along x of the two noise terms (the second at half weight)
ROCKY_FROM_Z = -28.0      # boundary faces north of this may show rock (the crest is the region's first bare rock)
_sp = json.load(open("floor5_sample_params.json"))
POCKET = (_sp["pocket"][0], _sp["pocket"][1], 4.5)  # the side pocket's outcrop: centre x, z and radius for rock on its walls
def centre_x(z): return _sp["centre_x_amp"] * np.sin(-np.asarray(z, dtype=float) * 2 * np.pi / _sp["centre_x_period_m"])
OUT = os.path.join("..", "..")  # runtime masks go to assets/field/masks/ (two levels up from source/floor5/)
if not os.path.isdir(os.path.join(OUT, "source")):
    OUT = "."             # running outside the repo: write next to the script
FONT_CANDIDATES = [os.path.join(OUT, "..", "..", "fonts", "AlegreyaSans-Regular.ttf"),
                   "../../../fonts/AlegreyaSans-Regular.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]

src = np.array(Image.open("floor5_walkable_sample.png").convert("RGB")).astype(int)
H, W, _ = src.shape
r, g, b = src[..., 0], src[..., 1], src[..., 2]
def dot(m):
    ys, xs = np.nonzero(m); return (float(xs.mean()), float(ys.mean()))
dots = {
    "spawn": dot((r > 200) & (g < 80) & (b < 80)),
    "exit": dot((g > 200) & (r < 80) & (b < 80)),
    "region_end_fight": dot((r > 200) & (g > 200) & (b < 80)),
    "finding": dot((g > 200) & (b > 200) & (r < 80)),
}
spawn = dots["spawn"]
walk = src.max(-1) > 127
def to_world(py, px_): return [round((px_ - spawn[0]) / PX, 3), round((py - spawn[1]) / PX, 3)]
def from_world(x, z): return (spawn[0] + x * PX, spawn[1] + z * PX)

yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
wz = (yy - spawn[1]) / PX
wx = (xx - spawn[0]) / PX
pz, ph = zip(*WALK_PROFILE)
walk_h = np.interp(-wz, -np.array(pz), np.array(ph)).astype(np.float32)   # local walk-floor height by z
walk_h = gaussian_filter(walk_h, sigma=0.8 * PX)                           # round the profile's corners

o = distance_transform_edt(~walk) / PX
face = np.clip(o / FACE_W, 0, 1)
crest_h = walk_h + CREST_RISE
fall_t = np.clip((o - FACE_W - CREST_W) / OUTER_FALL, 0, 1)
outer_h = walk_h - OUTER_DROP
hb = np.where(o > FACE_W + CREST_W, crest_h + (outer_h - crest_h) * fall_t, walk_h + CREST_RISE * face)
h = np.where(walk, walk_h, hb)
h = gaussian_filter(h, sigma=0.3 * PX)
elev = np.clip(h / ELEV_MAX, 0, 1)
Image.fromarray((elev * 255 + 0.5).astype(np.uint8), "L").save(os.path.join(OUT, "region1_floor5_elev.png"))
Image.fromarray(np.full((H, W), 255, np.uint8), "L").save(os.path.join(OUT, "region1_floor5_landmass.png"))

# rock: the shelf band, the boundary faces around the crest, and the side pocket's walls
rng_shelf = np.random.default_rng(11)
def edge_noise():   # +-1 along x, low frequency
    ph = rng_shelf.uniform(0, 2 * np.pi, len(SHELF_WAVES_M))
    n = sum(w * np.sin(2 * np.pi * wx / L + p) for w, L, p in zip((1.0, 0.5), SHELF_WAVES_M, ph))
    return n / 1.5
south_edge = SHELF_EDGE_Z[1] + SHELF_WOBBLE * edge_noise()
north_edge = SHELF_EDGE_Z[0] + SHELF_WOBBLE * edge_noise()
def feather(t):
    t = np.clip(t, 0, 1); return t * t * (3 - 2 * t)
shelf_band = feather((south_edge + SHELF_FEATHER / 2 - wz) / SHELF_FEATHER) * feather((wz - north_edge + SHELF_FEATHER / 2) / SHELF_FEATHER)
shelf_band *= (wz <= SHELF_Z[1]) & (wz >= SHELF_Z[0]) & (o < FACE_W + 1.0)   # walkable band and its boundary faces only
crest_faces = (~walk) & (o < FACE_W + 1.0) & (wz <= ROCKY_FROM_Z)
pcx, pcz, pr = POCKET
pocket_walls = (~walk) & (o < FACE_W + 1.0) & (np.hypot(wx - pcx, wz - pcz) <= pr)
rock = np.maximum(gaussian_filter((crest_faces | pocket_walls).astype(np.float32), 0.4 * PX),
                  gaussian_filter(shelf_band.astype(np.float32), 0.4 * PX))
Image.fromarray((np.clip(rock, 0, 1) * 255).astype(np.uint8), "L").save(os.path.join(OUT, "region1_floor5_rock.png"))

# outer: out-of-bounds ground beyond the boundary crest centreline (floor 3's smoothstep)
t = np.clip((o - (OUTER_EDGE_AT - OUTER_EDGE_WIDTH / 2)) / OUTER_EDGE_WIDTH, 0, 1)
outer = np.where(walk, 0.0, t * t * (3 - 2 * t))
Image.fromarray((outer * 255 + 0.5).astype(np.uint8), "L").save(os.path.join(OUT, "region1_floor5_outer.png"))

# ledge barrier: one ring
barrier = binary_dilation(walk, structure=disk(int(BARRIER_IN * PX)))
ring = max(find_contours(barrier.astype(float), 0.5), key=len)
ring_s = approximate_polygon(ring, tolerance=LEDGE_TOL * PX)
ledges = [[to_world(p[0], p[1]) for p in ring_s]]

# measurements
dt = distance_transform_edt(walk) / PX
def width_at(z):
    row = int(from_world(0, z)[1]); cx = int(from_world(float(centre_x(z)), z)[0])
    left = cx
    while left > 0 and walk[row, left - 1]: left -= 1
    right = cx
    while right < W - 1 and walk[row, right + 1]: right += 1
    return round(float((right - left) / PX), 1)
gy, gx = np.gradient(h, 1.0 / PX)
slope = np.degrees(np.arctan(np.hypot(gx, gy)))
def route_slope(z0, z1):
    vals = []
    for z in np.arange(z1, z0, 0.25):
        rr = int(from_world(0, z)[1]); c = int(from_world(float(centre_x(z)), z)[0])
        vals.append(float(slope[rr, c - 15:c + 15].max()))
    return round(max(vals), 1)
crest_flat = walk & (np.abs(walk_h - 3.45) < 0.05)
cy_, cx_ = np.nonzero(crest_flat)
WEAR = [[round(float(centre_x(z)), 2), z] for z in (0, -10, -20, -30, -42, -52, -60)]
meas = {
    "width_m": {"foot_z-2": width_at(-2), "lower_z-8": width_at(-8), "waist_z-22": width_at(-22),
                "upper_z-34": width_at(-34), "crest_z-42": width_at(-42), "exit_neck_z-54": width_at(-54)},
    "walk_floor_m": {"spawn": 0.4, "below_shelf": 2.4, "crest": 3.45, "exit": 2.45},
    "max_slope_deg": {"climb_z0_to_-28": route_slope(0, -28), "shelf_z-28_to_-35": route_slope(-28, -35),
                      "crest_z-36_to_-48": route_slope(-36, -48), "descent_z-50_to_-60": route_slope(-50, -60)},
    "crest_flat_m": [round(float(np.ptp(cx_) / PX), 1), round(float(np.ptp(cy_) / PX), 1)],
    "route_length_spawn_to_fight_m": 42.0, "route_length_fight_to_exit_m": 18.0,
}
layout = {
    "canvas_px": [W, H], "px_per_m": PX,
    "landmass_mask_origin_uv": [round(spawn[0] / W, 5), round(spawn[1] / H, 5)],
    "spawn_px": [round(spawn[0], 1), round(spawn[1], 1)],
    "markers_world_xz": {k: to_world(v[1], v[0]) for k, v in dots.items() if k != "spawn"},
    "assumed_elevation_max_height_m": ELEV_MAX,
    "walk_profile_z_height_m": WALK_PROFILE, "shelf_z": list(SHELF_Z),
    "ridge": {"crest_rise_above_walk_m": CREST_RISE, "inner_face_width_m": FACE_W, "crest_width_m": CREST_W,
              "outer_falloff_m": OUTER_FALL, "outer_below_walk_m": OUTER_DROP},
    "outer_edge": {"at_m": OUTER_EDGE_AT, "width_m": OUTER_EDGE_WIDTH},
    "suggested_wear_path_world_xz": WEAR,
    "measurements": meas,
    "ledges_world_xz": ledges,
    "note": "World XZ in metres relative to spawn; +X east, +Z south (north is negative). One closed ledge ring "
            "(the outer boundary). The walk floor rises from 0.4 m at spawn to 3.45 m on the crest; the rock shelf "
            "is the steep step at z -30.5 to -33. Exit direction is north (0, -1); the gate sits beyond the region-end fight.",
}
json.dump(layout, open("floor5_layout.json", "w"), indent=1)

# preview: hillshade, rock, outer, 0.5 m contours, ledge, worn band, labels
nrm = np.dstack([-gx, -gy, np.ones_like(h)]); nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
sun = np.array([0.6, 0.35, 0.72]); sun /= np.linalg.norm(sun)
shade = np.clip(nrm @ sun, 0, 1)
sand, stone = np.array([0.74, 0.70, 0.60]), np.array([0.56, 0.59, 0.50])
rk = np.clip((slope - 12) / 8, 0, 1) * np.clip(rock, 0, 1)
col = sand * (1 - rk[..., None]) + stone * rk[..., None]
col = col * (0.55 + 0.45 * shade)[..., None] * np.where(outer > 0.5, 0.86, 1.0)[..., None]
contour = (np.abs((h / 0.5) - np.round(h / 0.5)) < 0.03) & walk
col[contour] *= 0.88
im = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8), "RGB")
dr = ImageDraw.Draw(im)
pts = [(p[1], p[0]) for p in ring_s]; dr.line(pts + [pts[0]], fill=(30, 60, 140), width=3)
dr.line([from_world(*p) for p in WEAR], fill=(150, 120, 80), width=10, joint="curve")
font = next((ImageFont.truetype(f, 34) for f in FONT_CANDIDATES if os.path.exists(f)), ImageFont.load_default())
cols = {"spawn": (200, 40, 40), "exit": (40, 160, 60), "region_end_fight": (210, 170, 0), "finding": (0, 170, 190)}
labels = {"spawn": "SPAWN (foot)", "exit": "EXIT (north)", "region_end_fight": "REGION-END FIGHT (crest)", "finding": "FINDING"}
offs = {"spawn": (20, -10), "exit": (20, -15), "region_end_fight": (20, -15), "finding": (-40, 30)}
for k, (x, y) in dots.items():
    dr.ellipse([x - 14, y - 14, x + 14, y + 14], fill=cols[k], outline=(20, 20, 20), width=2)
    dr.text((x + offs[k][0], y + offs[k][1]), labels[k], fill=(25, 25, 25), font=font)
sx, sy = from_world(11.0, -32); dr.text((sx, sy), "ROCK SHELF", fill=(25, 25, 25), font=font)
for z, lab in [(-2, "0.4 m"), (-20, "~1.8 m"), (-42, "3.45 m"), (-58, "~2.6 m")]:
    tx, ty = from_world(-24.5, z); dr.text((tx, ty), lab, fill=(40, 40, 40), font=font)
bx, by = 40, H - 70
dr.rectangle([bx, by, bx + 10 * PX, by + 10], fill=(30, 30, 30)); dr.text((bx, by + 16), "10 m", fill=(30, 30, 30), font=font)
dr.text((W - 110, 30), "N ↑", fill=(30, 30, 30), font=font)
im.save("floor5_ground_preview.png")
print(json.dumps({k: v for k, v in layout.items() if k not in ("ledges_world_xz", "walk_profile_z_height_m")}, indent=1))
print("ledge points:", len(ledges[0]))
