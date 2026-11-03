# Region 2 floor 1's ground from floor1_walkable_sample.png (drawn by floor1_shape.py):
# the open basin. Same conventions as Region 1's floor generators: world metres
# from spawn, +X right, +Z south (down the image), forward toward -Z; ledges sit
# a little outside the walkable edge; masks go two folders up.
# The pier is a walk-surface prop. Its footprint is kept off the walkable ground,
# so the ledge outline seals the ground beside and under it; the outline is cut
# open only where the deck leaves the terrace top and at the foot of the boat steps.
# Run from this folder (after floor1_shape.py).
# Needs Python 3 with numpy, scipy, scikit-image and Pillow:
#   python -m pip install --user numpy scipy scikit-image pillow
import json, math, numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt, gaussian_filter
from skimage.measure import find_contours, approximate_polygon
from skimage.morphology import dilation, disk
from floor1_shape import PLAN, build, seg, seg_arc, ss, noise, XX as SXX, ZZ as SZZ, X0 as SX0, Z0 as SZ0

PX = 30.0
BASE_LIFT = 0.4               # the lowest ground sits this far up the elevation scale (clears the sea plane)
BARRIER_OUT = 0.4             # ledge barrier sits this far outside the walkable edge (m)
OUTER_EDGE_AT = 0.6           # outer ground (wet silt in the thicket) starts this far past the walkable edge
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
heron = dot((b > 200) & (r < 80) & (g < 80))
walk = (src.sum(-1) > 3 * 127) | (src.max(-1) > 200)
grey = (r == g) & (g == b) & (r > 150) & (r < 230)

def to_world(py, px_):
    return [round((px_ - spawn[0]) / PX, 3), round((py - spawn[1]) / PX, 3)]
def h_idx(x, z):
    return int(round(spawn[1] + z * PX)), int(round(spawn[0] + x * PX))

R = build()                     # the same regions the sample was drawn from
XX, ZZ = SXX, SZZ

# --- heights (metres, 0 = the lakebed at spawn) -------------------------------
hol = P["hollow"]
lake = P["lake_fall_per_m_north"] * np.minimum(ZZ, 0)
hol_e = np.sqrt(((XX - hol["centre"][0]) / hol["radii"][0]) ** 2 + ((ZZ - hol["centre"][1]) / hol["radii"][1]) ** 2) + 0.12 * noise(1.2, 21)
lake = lake - hol["depth_m"] * (1 - ss(0.25, 1.0, hol_e))
ex = P["exit_drop"]
lake = lake - ex["drop_m"] * np.clip((ex["z_from"] - ZZ) / (ex["z_from"] - ex["z_to"]), 0, 1)
FACE_W = P["face_w_m"]
T_TOP = P["terrace"]["rise_m"]
I_RISE = P["island"]["rise_m"]
d_t = distance_transform_edt(~R["terrace"]) / PX
d_i = distance_transform_edt(~R["island_top"]) / PX
u_t = np.where(R["terrace"], 1.0, np.clip(1 - d_t / FACE_W, 0, 1))
u_i = np.where(R["island_top"], 1.0, np.clip(1 - d_i / FACE_W, 0, 1))
lake_fall = P["lake_fall_per_m_north"]
for rp in R["ramp_paths"]:                                   # ramps climb evenly along the bank, then cross onto the top level
    i0, i1, j0, j1 = rp["win"]
    d_r, s_r = seg_arc(rp["path"], rp["win"])
    w_r = 1 - ss(rp["width"] / 2 + 0.5, rp["width"] / 2 + 2.0, d_r)   # full grade across the walkable width
    u_ramp = np.clip(s_r / rp["L_hug"], 0, 1)
    if rp["to"] == "terrace":
        u_t[i0:i1, j0:j1] = w_r * u_ramp + (1 - w_r) * u_t[i0:i1, j0:j1]
    else:
        u_i[i0:i1, j0:j1] = w_r * u_ramp + (1 - w_r) * u_i[i0:i1, j0:j1]
    rise = (T_TOP if rp["to"] == "terrace" else I_RISE) + lake_fall * abs(min(rp["path"][0][1], 0))
    print("ramp", rp["name"], "along the bank", round(rp["L_hug"], 1), "m, grade", round(math.degrees(math.atan(rise / rp["L_hug"])), 1), "deg")
u_t = np.where(R["terrace"], 1.0, u_t)                     # a ramp never lowers the top it climbs to
u_i = np.where(R["island_top"], 1.0, u_i)
h = lake + (T_TOP - lake) * u_t
h = h + I_RISE * u_i
# the bank: the old dry land behind the terrace rises again
d_up = distance_transform_edt(~R["upland"]) / PX
d_from_terrace = distance_transform_edt(~R["terrace"]) / PX
h = np.where(R["upland"], np.maximum(h, T_TOP + P["bank_rise_m"] * np.clip(d_from_terrace / 2.2, 0, 1)), h)
h = gaussian_filter(h, sigma=0.3 * PX)                       # round the ends of the faces
# ease the few steep spots left on walkable ground (where a ramp turns onto its top)
from scipy.ndimage import binary_dilation
_walk = R["lake_walk"] | R["raised_walk"]
_d_in = distance_transform_edt(_walk) / PX
for _ in range(5):
    _sl = np.degrees(np.arctan(np.hypot(*np.gradient(h, 1.0 / PX))))
    _bad = _walk & (_d_in > 0.4) & (_sl > 28)
    if not _bad.any(): break
    _m = gaussian_filter(binary_dilation(_bad, iterations=int(1.0 * PX)).astype(float), 0.4 * PX)
    h = h + np.clip(_m * 1.5, 0, 1) * (gaussian_filter(h, 0.7 * PX) - h)

h_min = float(h.min())
elev_h = h - h_min + BASE_LIFT
ELEV_MAX = math.ceil(float(elev_h.max()) * 10) / 10
def on_scale(m): return round(m - h_min + BASE_LIFT, 3)
def h_at(x, z): i, j = h_idx(x, z); return float(h[i, j])
Image.fromarray((np.clip(elev_h / ELEV_MAX, 0, 1) * 255 + 0.5).astype(np.uint8), "L").save("../../region2_floor1_elev.png")
Image.fromarray((np.clip(elev_h / ELEV_MAX, 0, 1) * 65535 + 0.5).astype(np.uint16)).save("../../region2_floor1_elev16.png")   # same, in 16 bits (8 m span: 0.12 mm steps vs 31 mm)

# --- landmass: all land, no water anywhere ------------------------------------
Image.fromarray(np.full((H, W), 255, np.uint8), "L").save("../../region2_floor1_landmass.png")

# --- vegetation: three layers, as in the game-camera target -------------------
# willow = the clumps (solid dark masses, ledged); reeds_tall = the edge thicket (a continuous wall, ledged);
# reeds_short = waist-high reeds in loose patches on the lakebed (walk-through, no collision);
# grass_dry = sparse dry grass on the high ground (terrace, island top): vegetation marks the level.
d_main, _ = seg(P["main_path"])
ramps_any = np.zeros((H, W), bool)
for rp in R["ramp_paths"]:
    i0, i1, j0, j1 = rp["win"]; d_r, _ = seg_arc(rp["path"], rp["win"]); ramps_any[i0:i1, j0:j1] |= d_r < rp["width"] / 2 + 0.8
willow = R["clumps"]
tall = R["thicket"]
(px0_, px1_), (pz0_, pz1_) = P["pier"]["platform"]
d_plat = np.hypot(np.maximum(np.maximum(px0_ - XX, XX - px1_), 0), np.maximum(np.maximum(pz0_ - ZZ, ZZ - pz1_), 0))
pier_ring = (d_plat < 5.0) | R["footprint"]                          # reeds gather around the pier's ground
short = ((noise(1.8, 7) + 0.35 * noise(0.8, 17) > 0.12) | pier_ring) & (R["lake_walk"] | R["footprint"]) & (d_main > 1.6) & ~ramps_any & ~tall & ~willow
grass = (noise(2.0, 9) > -0.15) & (R["terrace"] | R["island_top"]) & ~ramps_any & ~willow
Image.fromarray(willow.astype(np.uint8) * 255, "L").save("../../region2_floor1_willow.png")
Image.fromarray(tall.astype(np.uint8) * 255, "L").save("../../region2_floor1_reeds_tall.png")
Image.fromarray(short.astype(np.uint8) * 255, "L").save("../../region2_floor1_reeds_short.png")
Image.fromarray(grass.astype(np.uint8) * 255, "L").save("../../region2_floor1_grass_dry.png")
tall = tall | willow                                                 # both are impassable, for the outer mask and preview

# rock / bank mask: the terrace's and island's faces (not their ramps), grown ~1 m like floor 4's
# (the shader's slope test finds the real edge). This is what makes the old shorelines read as banks.
face_any = ((u_t > 0.02) & ~R["terrace"]) | ((u_i > 0.02) & ~R["island_top"])
ramp_core = np.zeros((H, W), bool)
for rp in R["ramp_paths"]:
    i0, i1, j0, j1 = rp["win"]; d_r, _ = seg_arc(rp["path"], rp["win"]); ramp_core[i0:i1, j0:j1] |= d_r < rp["width"] / 2 + 0.3
rock = face_any & ~ramp_core
rock = dilation(rock, disk(int(0.5 * PX))) & ~ramp_core
rock = gaussian_filter(rock.astype(np.float32), 2.0)
Image.fromarray((np.clip(rock, 0, 1) * 255).astype(np.uint8), "L").save("../../region2_floor1_rock.png")

# dry ground: terrace, island top, their faces, the bank (1); the lakebed (0); for a per-level ground tint
dry = gaussian_filter(np.clip(np.maximum(u_t, u_i) + R["upland"], 0, 1).astype(np.float32), 0.3 * PX)
Image.fromarray((np.clip(dry, 0, 1) * 255 + 0.5).astype(np.uint8), "L").save("../../region2_floor1_dry.png")

# outer ground: 0 on walkable ground, faces and ramps; 1 in the thicket and on the dry land past the bank's crest
d_out = distance_transform_edt(~walk) / PX
t = np.clip((d_out - OUTER_EDGE_AT) / OUTER_EDGE_WIDTH + 0.5, 0, 1)
outer = t * t * (3 - 2 * t)
outer = np.where((u_t > 0.02) | (u_i > 0.02), 0.0, outer)
t_b = np.clip((d_from_terrace - (FACE_W + 0.5)) / OUTER_EDGE_WIDTH + 0.5, 0, 1)
outer = np.where(R["upland"], t_b * t_b * (3 - 2 * t_b), outer)
Image.fromarray((outer * 255 + 0.5).astype(np.uint8), "L").save("../../region2_floor1_outer.png")

# --- wear: a faint worn path spawn → exit, fainter ramps, the creature's trail -
wv = P["wear"]
wear = np.clip(1.0 - (d_main - 0.6) / 1.0, 0, 1) * wv["main"]
for rp in R["ramp_paths"]:
    i0, i1, j0, j1 = rp["win"]; d_r, _ = seg_arc(rp["path"], rp["win"])
    wear[i0:i1, j0:j1] = np.maximum(wear[i0:i1, j0:j1], np.clip(1.0 - (d_r - 0.5) / 1.0, 0, 1) * wv["side"])
d_tr, _ = seg(P["trail"])
wear = np.maximum(wear, np.clip(1.0 - (d_tr - 0.2) / 0.4, 0, 1) * wv["trail"])
wear = gaussian_filter(wear, 0.15 * PX)
Image.fromarray((np.clip(wear, 0, 1) * 255 + 0.5).astype(np.uint8), "L").save("../../region2_floor1_wear.png")

# --- ledges: walkable area grown BARRIER_OUT, traced, cut at the pier's two openings
pr = P["pier"]; st = pr["steps"]
rx, rz = pr["root"]; ex_, ez = pr["end"]
vx, vz = ex_ - rx, ez - rz; Ln = math.hypot(vx, vz)
u_t_ds = u_t
def cut_here(x, z):
    t_ = ((x - rx) * vx + (z - rz) * vz) / (Ln * Ln)
    qx, qz = rx + np.clip(t_, 0, 1) * vx, rz + np.clip(t_, 0, 1) * vz
    near_deck = np.hypot(x - qx, z - qz) <= pr["width"] / 2 + 0.05     # the cut matches the deck: its rails do the rest
    i = np.clip(np.round(spawn[1] + z * PX).astype(int), 0, H - 1); j = np.clip(np.round(spawn[0] + x * PX).astype(int), 0, W - 1)
    on_terrace_side = u_t_ds[i, j] > 0.5                           # where the deck leaves the terrace top
    foot_x = st["to"][0] - 0.6
    at_foot = (np.abs(x - foot_x) < 0.6 + BARRIER_OUT) & (np.abs(z - st["from"][1]) <= st["width"] / 2 + 0.2)
    return (near_deck & on_terrace_side) | at_foot
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
    keep = ~cut_here(dense[:, 0], dense[:, 1])
    if keep.all():
        ledges.append([[round(float(x), 3), round(float(z), 3)] for x, z in pts]); continue
    start = int(np.argmin(keep)); dense, keep = np.roll(dense, -start, 0), np.roll(keep, -start)
    run = []
    for p_, k in zip(dense, keep):
        if k: run.append(p_)
        elif len(run) >= 2: ledges.append(run); run = []
        else: run = []
    if len(run) >= 2: ledges.append(run)
ledges = [l if isinstance(l[0], list) else
          [[round(float(x), 3), round(float(z), 3)] for x, z in approximate_polygon(np.array(l), tolerance=0.08)]
          for l in ledges]
ledges.sort(key=len, reverse=True)

def outlines(mask):
    out = []
    for c in find_contours(np.pad(mask.astype(float), 1), 0.5):
        c = approximate_polygon(c, tolerance=0.15 * PX)
        if len(c) >= 4: out.append([to_world(p[0] - 1, p[1] - 1) for p in c])
    return out

deck_h = on_scale(T_TOP)
(px0, px1), (pz0, pz1) = pr["platform"]
hp = P["heron"]
layout = {
    "canvas_px": [W, H], "px_per_m": PX,
    "landmass_mask_origin_uv": [round(spawn[0] / W, 5), round(spawn[1] / H, 5)],
    "spawn_px": [round(spawn[0], 1), round(spawn[1], 1)],
    "exit_world_xz": to_world(exit_[1], exit_[0]),
    "exit_gate_suggested_world_xz": [[1.5, -55.0], [7.5, -55.0]],
    "required_slot_world_xz": to_world(slot[1], slot[0]),
    "required_slot_faces_toward_world_xz": list(P["slot_faces_toward"]),
    "island_find": {"world_xz": list(P["island_find"]["pos"]), "facing_deg": P["island_find"]["facing_deg"],
                    "prop": "an upturned rowboat, about 3.2 x 1.2 x 0.6 m, hull up, old and grey (placeholder: a low rounded box)",
                    "pickup": "one minor pickup, always there, at the boat's bow (the island's reason to climb it; no fight)",
                    "why": "a boat on the island top, higher than the lakebed by 4 m, says the water once stood above the island"},
    "optional_slot": {"name": "terrace heron", "world_xz": to_world(heron[1], heron[0]), "chance": hp["chance"],
                      "faces_toward_world_xz": list(hp["faces_toward"]),
                      "empty_state": {"nest_scrape_world_xz": list(hp["nest_scrape"]),
                                      "meaning": "when the slot rolls empty, a flattened nest scrape at the old waterline marks the spot"},
                      "note": "placeholder enemy until the heron exists; standard optional reward for now"},
    "elevation_max_height_m": ELEV_MAX,
    "elevation_16bit": {"file": "region2_floor1_elev16.png", "meaning": "the same heights in 16 bits; use it if the loader can read 16-bit PNGs (the 8-bit file steps by ~31 mm at this span)"},
    "heights_m": {"lowest_ground": on_scale(h_min), "lakebed_at_spawn": on_scale(0.0),
                  "terrace_top": deck_h, "island_top": on_scale(h_at(*P["island"]["centre"])),
                  "required_slot": on_scale(h_at(4.0, -45.0)),
                  "next_floor_level": on_scale(h_at(5.0, -62.0)),
                  "note": "on the elevation scale (value/255 x elevation_max_height); the ground adds sea level + interior_height on top"},
    "terrace": {"rise_m": T_TOP, "face_width_m": FACE_W,
                "ramps": [{"name": rp["name"], "path_world_xz": [[round(x, 2), round(z, 2)] for x, z in rp["path"]], "along_bank_m": round(rp["L_hug"], 1),
                           "width_m": rp["width"], "to": rp["to"]} for rp in R["ramp_paths"]]},
    "island": {"centre_world_xz": list(P["island"]["centre"]), "rise_m": I_RISE},
    "bank": {"rise_m": P["bank_rise_m"], "meaning": "the old dry land behind the terrace rises again: the floor's edge on the west and south"},
    "outer_ground": {"meaning": "wet silt in the thicket, and the dry land past the bank's crest", "edge_at_m": OUTER_EDGE_AT, "edge_width_m": OUTER_EDGE_WIDTH},
    "rock": {"file": "region2_floor1_rock.png", "meaning": "the terrace's and island's faces (not the ramps), grown ~1 m, as floor 4's rock mask"},
    "dry": {"file": "region2_floor1_dry.png", "meaning": "1 on the terrace, island top, their faces and the bank; 0 on the lakebed. Not read by the engine yet."},
    "pier": {"root_world_xz": list(pr["root"]), "end_world_xz": list(pr["end"]), "width_m": pr["width"],
             "deck_height_m": deck_h, "platform_world_x": [px0, px1], "platform_world_z": [pz0, pz1],
             "mooring_posts_world_xz": [list(p) for p in pr["mooring_posts"]],
             "steps": {"from_world_xz": list(st["from"]), "to_world_xz": list(st["to"]), "width_m": st["width"],
                       "ground_at_foot_m": on_scale(h_at(*st["to"]))},
             "model": "pier.glb from make_pier.py, in floor metres from spawn on the elevation scale: place it at spawn with y = sea level + interior_height",
             "rails": "deck sides and the platform's outer sides railed; open at the root and at the steps; the steps have handrails",
             "under": "the ground under and beside the deck is not walkable (ledged), since the engine has one walk height per spot"},
    "vegetation": {
        "willow": {"mask": "region2_floor1_willow.png", "meaning": "willow clumps: solid dark masses, ledged", "height_m": [3.0, 5.0],
                   "outlines_world_xz": outlines(willow)},
        "reeds_tall": {"mask": "region2_floor1_reeds_tall.png", "meaning": "the edge thicket: a continuous reed wall, ledged", "height_m": [2.5, 3.5],
                       "outlines_world_xz": outlines(R["thicket"] & (np.abs(XX) < 34) & (ZZ > -74) & (ZZ < 20))},
        "reeds_short": {"mask": "region2_floor1_reeds_short.png", "meaning": "waist-high reeds in loose patches on the lakebed; walk-through, no collision; must not hide the Wanderer",
                        "height_m": [0.8, 1.1], "outlines_world_xz": outlines(short)},
        "grass_dry": {"mask": "region2_floor1_grass_dry.png", "meaning": "sparse dry grass tufts on the terrace and island tops; marks high ground",
                      "height_m": [0.3, 0.6], "density": "sparse", "outlines_world_xz": outlines(grass)},
    },
    "palette_target": {
        "source": "game-camera target image (Nov 3), sampled; silt and reeds lifted a step so the Wanderer stays the darkest thing off the path",
        "dry_ground_top": "#a6988a", "bank_face": "#8e877f", "worn_path": "#7e7a70", "lakebed_silt": "#727266",
        "reeds_short": "#6a6d60", "thicket_wall": "#61665a", "willow_mass": "#56594c", "pier_wood": "#8b8788", "figure_max": "#494d50",
        "value_order": "dry top 0.65 > bank 0.56 > path 0.50 > silt 0.45 > reeds 0.43 > thicket 0.40 > willow 0.35 > Wanderer <= 0.31"},
    "wear": {"file": "region2_floor1_wear.png", "main": wv["main"], "side": wv["side"], "trail": wv["trail"]},
    "main_path_centreline_world_xz": [[float(x), float(z)] for x, z in P["main_path"]],
    "ledges_world_xz": ledges,
    "note": "World XZ in metres relative to spawn; +X right, +Z toward the bottom of the image (south). Forward/exit is toward -Z. "
            "Ledges are polylines, longest first: closed rings (the floor's boundary, the island, the clumps) and open runs where the outline "
            "is cut for the pier's root and the steps' foot. Reed outlines may include holes (masks are authoritative).",
}
json.dump(layout, open("./floor1_layout.json", "w"), indent=1)

# --- preview ------------------------------------------------------------------
gy, gx = np.gradient(h, 1.0 / PX)
nx, ny, nz = -gx, -gy, np.ones_like(h)
norm = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2); nx, ny, nz = nx / norm, ny / norm, nz / norm
sun = np.array([0.6, 0.35, 0.72]); sun /= np.linalg.norm(sun)
shade = np.clip(nx * sun[0] + ny * sun[1] + nz * sun[2], 0, 1)
silt = np.array([0.64, 0.62, 0.54]); dry_c = np.array([0.75, 0.71, 0.61]); deep = np.array([0.55, 0.55, 0.49])
col = np.where((dry[..., None] > 0.5), dry_c, silt)
col = np.where(((h < -1.0) & (dry < 0.5))[..., None], deep, col)
col = col * (1 - 0.3 * outer)[..., None]
col = np.where(short[..., None], col * 0.84 + np.array([0.09, 0.13, 0.05]), col)
col = np.where(grass[..., None], col * 0.95 + np.array([0.04, 0.03, 0.0]), col)
col = np.where(tall[..., None], np.array([0.36, 0.44, 0.34]), col)
col = col * (1 + 0.10 * np.clip(wear, 0, 1) * walk)[..., None]
col = col * (0.55 + 0.45 * shade)[..., None]
im = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8), "RGB")
dr = ImageDraw.Draw(im)
def P2(x, z): return (spawn[0] + x * PX, spawn[1] + z * PX)
dr.line([P2(*pr["root"]), P2(*pr["end"])], fill=(112, 100, 85), width=int(pr["width"] * PX))
dr.rectangle([P2(px0, pz0), P2(px1, pz1)], fill=(112, 100, 85))
dr.line([P2(*st["from"]), P2(*st["to"])], fill=(140, 128, 110), width=int(st["width"] * PX))
for mp in pr["mooring_posts"]:
    cx, cy = P2(*mp); dr.rectangle([cx - 6, cy - 6, cx + 6, cy + 6], fill=(45, 42, 38))
for poly in ledges:
    dr.line([P2(x, z) for x, z in poly], fill=(30, 60, 140), width=3)
cx, cy = P2(*hp["nest_scrape"]); dr.ellipse([cx - 8, cy - 6, cx + 8, cy + 6], outline=(70, 60, 50), width=3)
for c_, colr in [(spawn, (200, 40, 40)), (exit_, (40, 160, 60)), (slot, (210, 170, 0)), (heron, (40, 70, 200))]:
    dr.ellipse([c_[0] - 12, c_[1] - 12, c_[0] + 12, c_[1] + 12], fill=colr)
im.save("./floor1_ground_preview.png")

slope = np.degrees(np.arctan(np.hypot(*np.gradient(h, 1.0 / PX))))
d_in = distance_transform_edt(walk) / PX
print("spawn", spawn, "exit", exit_, "slot", slot, "heron", heron)
print("elevation_max_height", ELEV_MAX, " heights:", {k: v for k, v in layout["heights_m"].items() if k != "note"})
print("max slope on walkable ground (0.6 m in from edges)", round(float(slope[walk & (d_in > 0.6)].max()), 1), "deg")
print("deck above ground: at the end", round(T_TOP - h_at(*pr["end"]), 2), "m; steps drop", round(T_TOP - h_at(*st["to"]), 2),
      "m over", round(st["to"][0] - st["from"][0], 2), "m")
print("ledge runs", [len(l) for l in ledges])
