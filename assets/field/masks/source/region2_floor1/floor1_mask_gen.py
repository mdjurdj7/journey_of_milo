# Region 2 floor 1's ground from floor1_walkable_sample.png (drawn by floor1_shape.py).
# Same conventions as Region 1's floor generators: world metres from spawn,
# +X right, +Z south (down the image), forward toward -Z; ledges sit a little
# outside the walkable edge; masks go two folders up.
# Differences: no water and no ridge. The floor is a drained lakebed bounded by
# reed walls (unwalkable lakebed) and an old shoreline (walkable, raised), and the
# pier is a walk-surface prop, so the ledge outline is cut open where its deck
# leaves the shoreline and where its boat steps land.
# Run from this folder.
# Needs Python 3 with numpy, scipy, scikit-image and Pillow:
#   python -m pip install --user numpy scipy scikit-image pillow
import json, math, numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt, gaussian_filter
from skimage.measure import find_contours, approximate_polygon
from skimage.morphology import dilation, disk
from floor1_shape import PLAN

PX = 30.0
BASE_LIFT = 0.4               # the lowest ground sits this far up the elevation scale (clears the sea plane)
BARRIER_OUT = 0.4             # ledge barrier sits this far outside the walkable edge (m)
OUTER_EDGE_AT = 0.6           # outer ground (wet silt under the reeds) starts this far past the walkable edge
OUTER_EDGE_WIDTH = 0.3
P = PLAN

src = np.array(Image.open("floor1_walkable_sample.png").convert("RGB")).astype(int)
H, W, _ = src.shape
r, g, b = src[..., 0], src[..., 1], src[..., 2]
def dot(mask):
    ys, xs = np.nonzero(mask); return (float(xs.mean()), float(ys.mean()))
spawn = dot((r > 200) & (g < 80) & (b < 80))
exit_ = dot((g > 200) & (r < 80) & (b < 80))
slot = dot((r > 200) & (g > 200) & (b < 80))
grey = (r == g) & (g == b)
walk = (src.sum(-1) > 3 * 127) | (src.max(-1) > 200)      # white, light grey or any coloured dot
shore_walk = grey & (r > 150) & (r < 230)                    # light grey = the old shoreline

yy, xx = np.mgrid[0:H, 0:W]
XX = (xx - spawn[0]) / PX
ZZ = (yy - spawn[1]) / PX
def to_world(py, px_):
    return [round((px_ - spawn[0]) / PX, 3), round((py - spawn[1]) / PX, 3)]
def seg_dist(path):
    d = np.full((H, W), 1e9); t_best = np.zeros((H, W))
    for (ax, az), (bx, bz) in zip(path[:-1], path[1:]):
        vx, vz = bx - ax, bz - az; L2 = vx * vx + vz * vz
        t = np.clip(((XX - ax) * vx + (ZZ - az) * vz) / L2, 0, 1)
        dd = np.hypot(XX - (ax + t * vx), ZZ - (az + t * vz))
        m = dd < d; d[m] = dd[m]; t_best[m] = t[m]
    return d, t_best
def smoothstep(e0, e1, v):
    t = np.clip((v - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t)

# --- heights (metres, 0 = the lakebed at spawn) -------------------------------
lake = np.where(ZZ < 0, P["lake_fall_per_m_north"] * ZZ, 0.0)
bw = P["bowl"]
lake = lake - bw["depth_m"] * (1 - smoothstep(0, bw["radius_m"], np.hypot(XX - bw["centre"][0], ZZ - bw["centre"][1])))
TOP = P["shore_rise_m"]
FACE_W = P["face_w_m"]
ex = P["exit_drop"]                                          # the step down to the next floor (lakebed only)
w_x = 1 - smoothstep(1.5, 3.0, np.abs(XX - ex["lane_x"]))
drop_t = w_x * np.clip((ex["z_from"] - ZZ) / (ex["z_from"] - ex["z_to_lane"]), 0, 1) + \
         (1 - w_x) * np.clip((ex["z_from"] - ZZ) / (ex["z_from"] - ex["z_to_elsewhere"]), 0, 1)
lake = lake - ex["drop_m"] * drop_t
lw = P["landward"]
landward = (XX <= lw["west_of_x"]) | (ZZ >= lw["south_of_z"]) | \
           ((XX <= lw["north_end"]["west_of_x"]) & (ZZ <= lw["north_end"]["north_of_z"]))
landward &= ~shore_walk & ~walk
high = shore_walk | landward
d_out_high = distance_transform_edt(~high) / PX
u = np.where(high, 1.0, np.clip(1 - d_out_high / FACE_W, 0, 1))   # 1 on the shoreline, 0 past its face
for ramp in P["ramps"]:                                      # ramps climb linearly from lakebed to shoreline
    d_r, t_r = seg_dist(ramp["path"])
    w_r = 1 - smoothstep(ramp["width"] / 2, ramp["width"] / 2 + 1.5, d_r)
    u = np.where(landward, u, w_r * t_r + (1 - w_r) * u)
h = lake + (TOP - lake) * u
d_out_shore = distance_transform_edt(~shore_walk) / PX
bank_t = np.where(landward, np.clip(d_out_shore / FACE_W, 0, 1), 0.0)   # the bank behind the shoreline
h = h + P["bank_rise_m"] * bank_t
h = gaussian_filter(h, sigma=0.3 * PX)                       # round the ends of the linear faces

h_min = float(h.min())
elev_h = h - h_min + BASE_LIFT                               # metres on the elevation scale
ELEV_MAX = math.ceil(float(elev_h.max()) * 10) / 10
def on_scale(m): return round(m - h_min + BASE_LIFT, 3)
Image.fromarray((np.clip(elev_h / ELEV_MAX, 0, 1) * 255 + 0.5).astype(np.uint8), "L").save("../../region2_floor1_elev.png")

# --- landmass: all land, no water anywhere ------------------------------------
Image.fromarray(np.full((H, W), 255, np.uint8), "L").save("../../region2_floor1_landmass.png")

# --- reeds and the outer ground -----------------------------------------------
d_out = distance_transform_edt(~walk) / PX
face_zone = (~walk) & (u > 0.02) & ~landward                 # the shoreline's face
pr = P["pier"]
d_pier, _ = seg_dist([pr["root"], pr["end"]])
(px0, px1), (pz0, pz1) = pr["platform"]
plat = (XX >= px0) & (XX <= px1) & (ZZ >= pz0) & (ZZ <= pz1)
trail_path, trail_w = P["trail"]
d_trail, _ = seg_dist(trail_path)
reed_ground = (~walk) & (~face_zone) & ~landward
short_reeds = reed_ground & ((d_pier <= P["short_reed_corridor_m"]) | plat | (d_trail <= trail_w / 2 + 0.3))
tall_reeds = reed_ground & ~short_reeds
Image.fromarray(tall_reeds.astype(np.uint8) * 255, "L").save("../../region2_floor1_reeds_tall.png")
Image.fromarray(short_reeds.astype(np.uint8) * 255, "L").save("../../region2_floor1_reeds_short.png")
# outer ground: the dark wet silt the reeds stand in; 0 on the walkable ground and the shoreline's face
t = np.clip((d_out - OUTER_EDGE_AT) / OUTER_EDGE_WIDTH + 0.5, 0, 1)
outer_ground = np.where(face_zone, 0.0, t * t * (3 - 2 * t))
# past the bank's crest the old dry land counts as outer ground too, as on floor 4
t_b = np.clip((d_out_shore - (FACE_W + 0.5)) / OUTER_EDGE_WIDTH + 0.5, 0, 1)
outer_ground = np.where(landward, t_b * t_b * (3 - 2 * t_b), outer_ground)
Image.fromarray((outer_ground * 255 + 0.5).astype(np.uint8), "L").save("../../region2_floor1_outer.png")

# --- wear: the worn main lane, fainter side lanes, the creature's trail -------
wv = P["wear"]
d_main, _ = seg_dist(P["main_lane"][0])
wear = np.clip(1.0 - (d_main - 0.6) / 1.0, 0, 1) * wv["main"]
for path in [P["patch_link"][0], P["steps_lane"][0]] + [rp["path"] for rp in P["ramps"]]:
    d_s, _ = seg_dist(path)
    wear = np.maximum(wear, np.clip(1.0 - (d_s - 0.5) / 1.0, 0, 1) * wv["side"])
wear = np.maximum(wear, np.clip(1.0 - (d_trail - 0.2) / 0.4, 0, 1) * wv["trail"])
wear = gaussian_filter(wear, 0.15 * PX)
Image.fromarray((np.clip(wear, 0, 1) * 255 + 0.5).astype(np.uint8), "L").save("../../region2_floor1_wear.png")

# --- ledges: walkable area grown BARRIER_OUT, traced, cut open at the pier ----
st = pr["steps"]
rx, rz = pr["root"]; ex_, ez = pr["end"]
vx, vz = ex_ - rx, ez - rz; Ln = math.hypot(vx, vz)
def in_pier_footprint(x, z, pad=0.6):
    # The deck's cut matches the deck exactly, so the ledge ends meet its edges
    # where it leaves the shoreline and leave no gap beside it; the platform and
    # the steps' landing keep a small pad.
    t = ((x - rx) * vx + (z - rz) * vz) / (Ln * Ln)
    qx, qz = rx + np.clip(t, 0, 1) * vx, rz + np.clip(t, 0, 1) * vz
    on_deck = (np.hypot(x - qx, z - qz) <= pr["width"] / 2) & (t >= -0.02) & (t <= 1.02)
    on_plat = (x >= px0 - pad) & (x <= px1 + pad) & (z >= pz0 - pad) & (z <= pz1 + pad)
    sx0, sx1 = sorted([st["from"][0], st["to"][0]])
    on_steps = (x >= sx0 - pad) & (x <= sx1 + pad) & (np.abs(z - st["from"][1]) <= st["width"] / 2 + pad)
    return on_deck | on_plat | on_steps
barrier = dilation(walk, disk(int(BARRIER_OUT * PX)))
cs = [c for c in find_contours(barrier.astype(float), 0.5) if np.allclose(c[0], c[-1])]
cs.sort(key=len, reverse=True)
ledges = []
for c in cs:
    poly = approximate_polygon(c, tolerance=0.08 * PX)
    pts = np.array([to_world(p[0], p[1]) for p in poly])
    dense = [pts[0]]
    for a_, b_ in zip(pts[:-1], pts[1:]):
        n = max(1, int(np.hypot(*(b_ - a_)) / 0.2))
        dense += [a_ + (b_ - a_) * k / n for k in range(1, n + 1)]
    dense = np.array(dense)
    keep = ~in_pier_footprint(dense[:, 0], dense[:, 1])
    if keep.all():
        ledges.append([[round(float(x), 3), round(float(z), 3)] for x, z in pts]); continue
    # rotate so the ring starts inside a cut, then split into open runs
    start = int(np.argmin(keep)); dense, keep = np.roll(dense, -start, 0), np.roll(keep, -start)
    run = []
    for p, k in zip(dense, keep):
        if k: run.append(p)
        elif len(run) >= 2:
            ledges.append(run); run = []
        else: run = []
    if len(run) >= 2: ledges.append(run)
ledges = [l if isinstance(l[0], list) else
          [[round(float(x), 3), round(float(z), 3)] for x, z in approximate_polygon(np.array(l), tolerance=0.08)]
          for l in ledges]
ledges.sort(key=len, reverse=True)

# --- reed polygons (outer outlines and holes) ---------------------------------
def outlines(mask):
    out = []
    for c in find_contours(np.pad(mask.astype(float), 1), 0.5):
        c = approximate_polygon(c, tolerance=0.15 * PX)
        if len(c) >= 4: out.append([to_world(p[0] - 1, p[1] - 1) for p in c])
    return out

deck_h = on_scale(TOP)
def h_at(x, z):
    j = int(round(spawn[0] + x * PX)); i = int(round(spawn[1] + z * PX)); return float(h[i, j])
layout = {
    "canvas_px": [W, H], "px_per_m": PX,
    "landmass_mask_origin_uv": [round(spawn[0] / W, 5), round(spawn[1] / H, 5)],
    "spawn_px": [round(spawn[0], 1), round(spawn[1], 1)],
    "exit_world_xz": to_world(exit_[1], exit_[0]),
    "required_slot_world_xz": to_world(slot[1], slot[0]),
    "required_slot_faces_toward_world_xz": list(P["slot_faces_toward"]),
    "elevation_max_height_m": ELEV_MAX,
    "heights_m": {"lowest_ground": on_scale(h_min), "lakebed_at_spawn": on_scale(0.0),
                  "clearing": on_scale(h_at(4.0, -41.0)), "pier_end_ground": on_scale(h_at(*pr["end"])),
                  "shoreline_top": deck_h, "next_floor_level": on_scale(h_at(4.0, -55.0)),
                  "note": "on the elevation scale (value/255 x elevation_max_height); the ground adds interior_height on top"},
    "shoreline": {"face_width_m": FACE_W, "rise_m": TOP, "ramps": [{"name": rp["name"], "path_world_xz": rp["path"], "width_m": rp["width"]} for rp in P["ramps"]]},
    "bank": {"rise_m": P["bank_rise_m"], "face_width_m": FACE_W, "top_m": on_scale(TOP + P["bank_rise_m"]),
             "meaning": "the old dry land behind the shoreline rises again: the floor's edge on the west, south and north-west"},
    "outer_ground": {"meaning": "wet silt under the reeds, and the dry land past the bank's crest", "edge_at_m": OUTER_EDGE_AT, "edge_width_m": OUTER_EDGE_WIDTH},
    "pier": {"root_world_xz": list(pr["root"]), "end_world_xz": list(pr["end"]), "width_m": pr["width"],
             "deck_height_m": deck_h, "platform_world_x": list(pr["platform"][0]), "platform_world_z": list(pr["platform"][1]),
             "mooring_posts_world_xz": [list(p) for p in pr["mooring_posts"]],
             "steps": {"from_world_xz": list(st["from"]), "to_world_xz": list(st["to"]), "width_m": st["width"],
                       "ground_at_foot_m": on_scale(h_at(*st["to"]))},
             "model": "pier.glb from make_pier.py, in floor metres from spawn on the elevation scale: place it at spawn with y = interior_height",
             "rails": "the deck's sides and the platform's three outer sides are railed; open at the root and at the steps"},
    "reeds": {"tall_mask": "region2_floor1_reeds_tall.png", "short_mask": "region2_floor1_reeds_short.png",
              "tall_outlines_world_xz": outlines(tall_reeds), "short_outlines_world_xz": outlines(short_reeds),
              "heights_m": {"tall": [2.0, 4.0], "short": [0.8, 1.5]}},
    "wear": {"file": "region2_floor1_wear.png", "main": wv["main"], "side": wv["side"], "trail": wv["trail"]},
    "main_lane_centreline_world_xz": [[float(x), float(z)] for x, z in P["main_lane"][0]],
    "ledges_world_xz": ledges,
    "note": "World XZ in metres relative to spawn; +X right, +Z toward the bottom of the image (south). Forward/exit is toward -Z. "
            "Ledges are polylines, longest first; the outline is cut open where the pier deck leaves the shoreline and where the boat steps land, "
            "so those runs are open. Reed outlines include hole outlines (masks are authoritative).",
}
json.dump(layout, open("./floor1_layout.json", "w"), indent=1)

# --- preview: hillshade (sun from ESE, 45 deg) + reeds + wear + pier + dots ---
gy, gx = np.gradient(h, 1.0 / PX)
nx, ny, nz = -gx, -gy, np.ones_like(h)
norm = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2); nx, ny, nz = nx / norm, ny / norm, nz / norm
sun = np.array([0.6, 0.35, 0.72]); sun /= np.linalg.norm(sun)
shade = np.clip(nx * sun[0] + ny * sun[1] + nz * sun[2], 0, 1)
silt = np.array([0.66, 0.63, 0.55]); shore_col = np.array([0.74, 0.70, 0.60])
reed_t = np.array([0.55, 0.62, 0.52]); reed_s = np.array([0.66, 0.71, 0.60])
col = np.where(u[..., None] > 0.5, shore_col, silt)
col = col * (1 - 0.3 * outer_ground)[..., None]
col = np.where(tall_reeds[..., None], reed_t, col)
col = np.where(short_reeds[..., None], reed_s, col)
col = col * (1 + 0.10 * np.clip(wear, 0, 1) * walk)[..., None]
col = col * (0.55 + 0.45 * shade)[..., None]
im = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8), "RGB")
dr = ImageDraw.Draw(im)
def P2(x, z): return (spawn[0] + x * PX, spawn[1] + z * PX)
dr.line([P2(*pr["root"]), P2(*pr["end"])], fill=(122, 110, 94), width=int(pr["width"] * PX))
dr.rectangle([P2(px0, pz0), P2(px1, pz1)], fill=(122, 110, 94))
dr.line([P2(*st["from"]), P2(*st["to"])], fill=(150, 138, 118), width=int(st["width"] * PX))
for mp in pr["mooring_posts"]:
    cx, cy = P2(*mp); dr.rectangle([cx - 5, cy - 5, cx + 5, cy + 5], fill=(45, 42, 38))
for poly in ledges:
    dr.line([P2(x, z) for x, z in poly], fill=(30, 60, 140), width=2)
for c_, colr in [(spawn, (200, 40, 40)), (exit_, (40, 160, 60)), (slot, (210, 170, 0))]:
    dr.ellipse([c_[0] - 10, c_[1] - 10, c_[0] + 10, c_[1] + 10], fill=colr)
im.save("./floor1_ground_preview.png")

slope = np.degrees(np.arctan(np.hypot(*np.gradient(h, 1.0 / PX))))
d_in = distance_transform_edt(walk) / PX
print("spawn", spawn, "exit", exit_, "slot", slot)
print("elevation_max_height", ELEV_MAX, " heights on scale:", layout["heights_m"])
print("max slope on walkable ground (0.6 m in from edges)", round(float(slope[walk & (d_in > 0.6)].max()), 1), "deg")
print("deck above ground: where it leaves the shore", round(TOP - h_at(-14.0, -19.7), 2),
      "m, at the end", round(TOP - h_at(*pr["end"]), 2), "m; steps drop", round(TOP - h_at(*st["to"]), 2), "m over",
      round(st["to"][0] - st["from"][0], 2), "m")
print("ledge runs", [len(l) for l in ledges])
