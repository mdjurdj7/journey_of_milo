"""Floor 4 ground generator (Region 1, dry end): a loop around a central dune.
Reads floor4_walkable_sample.png (white = walkable, coloured dots = markers) and writes the
runtime masks to assets/field/masks/ plus floor4_layout.json and the preview here. Same
conventions as floor3_mask_gen.py. Run from this folder.
Needs Python 3 with numpy, scipy, scikit-image and Pillow:
  python -m pip install --user numpy scipy scikit-image pillow"""
import json, numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.ndimage import distance_transform_edt, gaussian_filter, label
from skimage.measure import find_contours, approximate_polygon
from scipy.ndimage import binary_dilation
from skimage.morphology import disk

PX = 30.0              # px per metre
ELEV_MAX = 3.0         # metres at elevation 1.0 -> set floor 4's elevation_max_height to this
BASE_WALK = 0.4        # walkable floor above the outer ground (m)
CREST_RISE = 1.2       # boundary ridge crest above the walkable floor (m)
FACE_W = 2.0           # inner face width (m), ~31 deg mean slope
CREST_W = 1.0
OUTER_FALL = 4.0
OUTER_EDGE_AT = FACE_W + 0.5 * CREST_W   # outer ground starts at the crest centreline (m past the walkable edge)
OUTER_EDGE_WIDTH = 0.3         # the whole outer-ground transition (m)
DUNE_TOP = 2.8         # central dune summit height (m), 2.4 m above the walk
BARRIER_IN = 0.4       # ledge barrier sits this far up each face (m)
ROCK_CENTRE = (-22.5, -41.6)   # world xz of the first exposed rock (north face of the exit neck)
ROCK_RADIUS = 3.4
MASKS_OUT = "../../"   # the runtime masks: assets/field/masks/
OUT = "./"             # the layout and the preview stay beside the sources
# The worn band (FloorData.wear_path_override, 3 to 8 points): spawn, north out of the
# entry neck, round the dune's west side, past the required fight, out along the exit neck.
WEAR_WORLD = [(0, 0), (0, -4.5), (-6.5, -9.0), (-17.5, -18.0), (-16.5, -27.0), (-13.5, -32.267), (-20.0, -35.0), (-27.767, -37.5)]
FONT = "../../../../fonts/AlegreyaSans-Regular.ttf"

src = np.array(Image.open("floor4_walkable_sample.png").convert("RGB")).astype(int)
H, W, _ = src.shape
r, g, b = src[..., 0], src[..., 1], src[..., 2]
def dot(m):
    ys, xs = np.nonzero(m); return (float(xs.mean()), float(ys.mean()))
dots = {
    "spawn": dot((r > 200) & (g < 80) & (b < 80)),
    "exit": dot((g > 200) & (r < 80) & (b < 80)),
    "required_fight": dot((b > 200) & (r < 80) & (g < 80)),
    "collector": dot((r > 200) & (g > 200) & (b < 80)),
    "optional_fight": dot((r > 200) & (b > 200) & (g < 80)),
    "dig_site": dot((g > 200) & (b > 200) & (r < 80)),
}
spawn = dots["spawn"]
walk = src.max(-1) > 127          # white, or any coloured marker dot, is walkable
def to_world(py, px_): return [round((px_ - spawn[0]) / PX, 3), round((py - spawn[1]) / PX, 3)]
def from_world(x, z): return (spawn[0] + x * PX, spawn[1] + z * PX)

# Split the non-walkable area: the central dune is the enclosed component; the rest is the boundary.
lab, n = label(~walk)
border_ids = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
inner = [i for i in range(1, n + 1) if i not in border_ids]
dune = lab == max(inner, key=lambda i: int((lab == i).sum()))   # the central dune: largest enclosed region
o = distance_transform_edt(~walk) / PX          # metres outside the walkable area

h = np.full((H, W), BASE_WALK, np.float32)
face = np.clip(o / FACE_W, 0, 1)
# boundary ridge (same profile as floor 3)
bnd = (~walk) & (~dune)
crest_h = BASE_WALK + CREST_RISE
fall_t = np.clip((o - FACE_W - CREST_W) / OUTER_FALL, 0, 1)
hb = np.where(o > FACE_W + CREST_W, crest_h * (1 - fall_t), BASE_WALK + CREST_RISE * face)
h = np.where(bnd, hb, h)
# central dune: same face, then keeps climbing to a rounded summit
o_max = float(o[dune].max())
t = np.clip((o - FACE_W) / max(o_max - FACE_W, 1e-3), 0, 1)
hd = BASE_WALK + CREST_RISE * face + (DUNE_TOP - crest_h) * (t * t * (3 - 2 * t))
h = np.where(dune, hd, h)
h = gaussian_filter(h, sigma=0.3 * PX)
elev = np.clip(h / ELEV_MAX, 0, 1)
Image.fromarray((elev * 255 + 0.5).astype(np.uint8), "L").save(MASKS_OUT + "region1_floor4_elev.png")

Image.fromarray(np.full((H, W), 255, np.uint8), "L").save(MASKS_OUT + "region1_floor4_landmass.png")

# rock: only the first exposed rock near the exit, on the boundary's inner face (dunes stay sand)
rcx, rcy = from_world(*ROCK_CENTRE)
yy, xx = np.mgrid[0:H, 0:W]
near = np.hypot(xx - rcx, yy - rcy) <= ROCK_RADIUS * PX
rock = gaussian_filter((bnd & (o < FACE_W + 1.0) & near).astype(np.float32), 2.0)
Image.fromarray((np.clip(rock, 0, 1) * 255).astype(np.uint8), "L").save(MASKS_OUT + "region1_floor4_rock.png")

# outer ground (floor 3's rule): 0 on the walkable area, the inner face and the crest's
# inner half, 1 past the crest centreline - a smoothstep OUTER_EDGE_WIDTH wide, no blur
# after it - on the boundary only, so the dune is never out of bounds. 1 along every
# canvas edge, which the shader extends past it.
t_out = np.clip((o - OUTER_EDGE_AT) / OUTER_EDGE_WIDTH + 0.5, 0, 1)
outer = np.where(bnd, t_out * t_out * (3 - 2 * t_out), 0.0)
Image.fromarray((outer * 255 + 0.5).astype(np.uint8), "L").save(MASKS_OUT + "region1_floor4_outer.png")

# ledge barriers: one ring round the outside, one round the dune
barrier = binary_dilation(walk, structure=disk(int(BARRIER_IN * PX)))
rings = sorted(find_contours(barrier.astype(float), 0.5), key=len, reverse=True)[:2]
ledges = [[to_world(p[0], p[1]) for p in approximate_polygon(c, tolerance=0.08 * PX)] for c in rings]   # ~8 cm, as floor 3

# measurements
dt = distance_transform_edt(walk) / PX
def width_at(x, z, win=4.0):
    cx, cy = from_world(x, z); s = int(win * PX)
    return round(2 * float(dt[int(cy) - s:int(cy) + s, int(cx) - s:int(cx) + s].max()), 1)
meas = {
    "west_side_width_m": width_at(-16.5, -21), "east_side_width_m": width_at(17.25, -19.5),
    "east_narrows_width_m": width_at(19.5, -13.5, 2.5), "north_width_m": width_at(0, -34.5),
    "south_width_m": width_at(0, -7.5), "exit_neck_width_m": width_at(-22.5, -36, 2.5),
    "west_to_east_across_dune_m": round(float((from_world(17.25, -21)[0] - from_world(-16.5, -21)[0]) / PX), 1),
    "dune_size_m": [round(float(np.ptp(np.nonzero(dune)[1]) / PX), 1), round(float(np.ptp(np.nonzero(dune)[0]) / PX), 1)],
}
layout = {
    "canvas_px": [W, H], "px_per_m": PX,
    "landmass_mask_origin_uv": [round(spawn[0] / W, 5), round(spawn[1] / H, 5)],
    "spawn_px": [round(spawn[0], 1), round(spawn[1], 1)],
    "markers_world_xz": {k: to_world(v[1], v[0]) for k, v in dots.items() if k != "spawn"},
    "assumed_elevation_max_height_m": ELEV_MAX,
    "heights_m": {"outer_ground": 0.0, "walkable_floor": BASE_WALK, "ridge_crest": crest_h, "dune_summit": DUNE_TOP},
    "ridge": {"inner_face_width_m": FACE_W, "crest_width_m": CREST_W, "outer_falloff_m": OUTER_FALL},
    "wear_path_world_xz": [list(p) for p in WEAR_WORLD],
    "outer_ground": {"edge_at_m": OUTER_EDGE_AT, "edge_width_m": OUTER_EDGE_WIDTH},
    "rock_world_xz": list(ROCK_CENTRE), "rock_radius_m": ROCK_RADIUS,
    "measurements": meas,
    "ledges_world_xz": ledges,
    "note": "World XZ in metres relative to spawn; +X right (east), +Z toward the image bottom (south). Two closed ledge rings: [0] the outer boundary, [1] the central dune. The required fight sits where both routes rejoin, before the exit neck, so either side can reach it. The worn band runs spawn -> west side -> required fight -> exit (wear_path_world_xz). The collector and the dig site are reserved spots only - nothing reads them yet.",
}
json.dump(layout, open(OUT + "floor4_layout.json", "w"), indent=1)

# preview: hillshade + rock + outer + ledges + labelled markers
gy, gx = np.gradient(h, 1.0 / PX)
nrm = np.dstack([-gx, -gy, np.ones_like(h)]); nrm /= np.linalg.norm(nrm, axis=2, keepdims=True)
sun = np.array([0.6, 0.35, 0.72]); sun /= np.linalg.norm(sun)
shade = np.clip(nrm @ sun, 0, 1)
slope = np.degrees(np.arctan(np.hypot(gx, gy)))
sand, stone = np.array([0.74, 0.70, 0.60]), np.array([0.56, 0.59, 0.50])
rk = np.clip((slope - 22) / 12, 0, 1) * np.clip(rock, 0, 1)
col = sand * (1 - rk[..., None]) + stone * rk[..., None]
col = col * (0.55 + 0.45 * shade)[..., None] * np.where(outer > 0.5, 0.86, 1.0)[..., None]
im = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8), "RGB")
dr = ImageDraw.Draw(im)
for ring in rings:
    poly = approximate_polygon(ring, tolerance=0.08 * PX); pts = [(p[1], p[0]) for p in poly]
    dr.line(pts + [pts[0]], fill=(30, 60, 140), width=3)
wear = [from_world(*p) for p in WEAR_WORLD]
dr.line(wear, fill=(150, 120, 80), width=10, joint="curve")
font = ImageFont.truetype(FONT, 34)
colours = {"spawn": (200, 40, 40), "exit": (40, 160, 60), "required_fight": (40, 60, 200), "collector": (210, 170, 0),
           "optional_fight": (200, 40, 200), "dig_site": (0, 170, 190)}
labels = {"spawn": "SPAWN", "exit": "EXIT (west, toward the tower)", "required_fight": "REQUIRED FIGHT",
          "collector": "COLLECTOR", "optional_fight": "OPTIONAL FIGHT", "dig_site": "DIG SITE"}
offs = {"spawn": (20, -10), "exit": (-20, 30), "required_fight": (20, 10), "collector": (-230, 30),
        "optional_fight": (20, -15), "dig_site": (20, -15)}
for k, (x, y) in dots.items():
    dr.ellipse([x - 14, y - 14, x + 14, y + 14], fill=colours[k], outline=(20, 20, 20), width=2)
    dr.text((x + offs[k][0], y + offs[k][1]), labels[k], fill=(25, 25, 25), font=font)
rx, ry = from_world(*ROCK_CENTRE); dr.text((rx - 40, ry - 50), "ROCK", fill=(25, 25, 25), font=font)
dr.text(from_world(-4.5, -22.5), "CENTRAL DUNE", fill=(60, 50, 35), font=font)
bx, by = 60, H - 90
dr.rectangle([bx, by, bx + 10 * PX, by + 10], fill=(30, 30, 30)); dr.text((bx, by + 18), "10 m", fill=(30, 30, 30), font=font)
dr.text((W - 120, 40), "N ↑", fill=(30, 30, 30), font=font)
im.save(OUT + "floor4_ground_preview.png")
print(json.dumps({k: v for k, v in layout.items() if k != "ledges_world_xz"}, indent=1))
print("ledge points:", [len(l) for l in ledges])
print("max face slope (deg):", round(float(slope[(o > 0) & (o < FACE_W)].max()), 1))
