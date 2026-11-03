# Region 2 floor 1's walkable sample, drawn from parameters: an open drained
# basin. The lakebed is walkable almost everywhere; the old shoreline terrace
# follows the rim around the west and south (wide where the water once lapped,
# fading to nothing on the north and east); an old island stands in the
# middle-east; a hollow (the old lake's deepest part) sits under the pier.
# Impassable: the shoreline's and island's faces (except at ramps), a few
# willow/reed clumps, the dense thicket past the north and east rim, and the
# rising bank behind the terrace. No straight lines or right angles anywhere:
# every edge comes from ellipses, blobs and noise. The pier is a prop (walk
# surface), straight on purpose; its footprint is kept off the walkable ground
# so nothing walks under it.
# World metres from spawn: +X right (east), +Z down (south); forward is -Z.
# Writes floor1_walkable_sample.png:
#   white      = walkable lakebed and ramps
#   light grey = walkable raised ground (terrace top, island top)
#   black      = not walkable
#   dots: spawn (red), exit (green), required fight (yellow), optional heron slot (blue)
# floor1_mask_gen.py imports PLAN and build() from this file.
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter, distance_transform_edt

PX = 30.0
X0, Z0 = -42.0, -80.0                         # world metres at the canvas's top-left
W, H = 2520, 3240                             # 84 x 108 m: >= 16 m past every walkable edge
SPAWN, EXIT, SLOT, HERON = (0.0, 0.0), (5.0, -60.0), (4.0, -45.0), (-13.0, -51.0)

PLAN = {
    "bowl": {"centre": (0.0, -24.0), "radii": (24.0, 36.0)},
    "terrace": {"max_frac": 0.26, "rise_m": 1.2},          # band width as a fraction of the bowl radius
    "face_w_m": 2.0,                                        # shoreline and island faces (~31 / 39 deg)
    "bank_rise_m": 1.2,                                     # the old dry land rising again behind the terrace
    "island": {"centre": (12.0, -24.0), "radii": (7.0, 5.2), "top_frac": 0.82, "rise_m": 1.6},
    "hollow": {"centre": (-6.0, -37.0), "radii": (8.0, 7.0), "depth_m": 1.8},
    "lake_fall_per_m_north": 0.015,
    # ramps: lakebed end first, raised end last
    "ramps": [{"name": "step you came down", "path": [(0.0, -1.5), (0.0, 4.6)], "width": 4.0, "to": "terrace"},
              {"name": "south-west ramp", "path": [(-11.0, -13.6), (-18.2, -16.2)], "width": 3.2, "to": "terrace"},
              {"name": "north-west ramp", "path": [(-7.0, -44.8), (-16.0, -47.6)], "width": 3.2, "to": "terrace"},
              {"name": "island ramp", "path": [(12.0, -15.0), (12.0, -20.6)], "width": 3.0, "to": "island"}],
    "clumps": [((12.5, -7.5), (3.1, 2.4), 31), ((-8.0, -6.0), (3.0, 2.3), 32),
               ((19.0, -40.0), (3.6, 3.1), 33), ((-3.0, -51.0), (2.7, 2.1), 34)],
    "main_path": [(0, 0), (1.5, -9), (1.0, -18), (2.0, -28), (4.5, -38), (4.0, -45), (4.0, -52), (4.5, -57), (5.5, -63)],
    "exit_lane": [(4.0, -50.0), (4.5, -56.0), (6.0, -64.0)],
    "exit_drop": {"z_from": -52.0, "z_to": -57.0, "drop_m": 1.2},
    "trail": [(4.0, -45.0), (9.0, -49.5), (13.5, -56.0)],   # the creature's run, into the north-east thicket
    "slot_faces_toward": (13.5, -56.0),
    "heron": {"pos": HERON, "chance": 0.5, "nest_scrape": (-12.8, -50.4), "faces_toward": (-7.0, -47.0)},
    "pier": {"root": (-20.5, -23.0), "end": (-7.0, -35.0), "width": 2.0,
             "platform": ((-9.0, -5.0), (-37.0, -33.0)),
             "mooring_posts": [(-9.0, -37.0), (-5.0, -37.0)],
             "steps": {"from": (-5.0, -35.0), "to": (-0.5, -35.0), "width": 1.4}},
    "pier_footprint_pad_m": 0.3,
    "wear": {"main": 1.0, "side": 0.6, "trail": 0.2},
}
P = PLAN

xs = X0 + (np.arange(W) + 0.5) / PX
zs = Z0 + (np.arange(H) + 0.5) / PX
XX, ZZ = np.meshgrid(xs, zs)


def px(x, z): return ((x - X0) * PX, (z - Z0) * PX)


def ss(a, b, v):
    t = np.clip((v - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)


def noise(scale_m, seed):
    n = gaussian_filter(np.random.default_rng(seed).standard_normal(XX.shape), scale_m * PX)
    return n / np.abs(n).max()


def blob(c, r, seed, amp):
    return np.sqrt(((XX - c[0]) / r[0]) ** 2 + ((ZZ - c[1]) / r[1]) ** 2) + amp * noise(1.2, seed)


def seg(path):
    d = np.full(XX.shape, 1e9); tb = np.zeros(XX.shape)
    for (ax, az), (bx, bz) in zip(path[:-1], path[1:]):
        vx, vz = bx - ax, bz - az; L2 = vx * vx + vz * vz
        t = np.clip(((XX - ax) * vx + (ZZ - az) * vz) / L2, 0, 1)
        dd = np.hypot(XX - (ax + t * vx), ZZ - (az + t * vz)); m = dd < d; d[m] = dd[m]; tb[m] = t[m]
    return d, tb


def build():
    """All derived regions, shared with floor1_mask_gen.py."""
    b = P["bowl"]; C, R = b["centre"], b["radii"]
    ang = np.arctan2((ZZ - C[1]) / R[1], (XX - C[0]) / R[0])
    e = np.sqrt(((XX - C[0]) / R[0]) ** 2 + ((ZZ - C[1]) / R[1]) ** 2) + 0.09 * noise(5, 1) + 0.05 * noise(2.5, 11)
    bowl = e < 1
    west, south = np.clip(-np.cos(ang), 0, 1), np.clip(np.sin(ang), 0, 1)
    north, east = np.clip(-np.sin(ang), 0, 1), np.clip(np.cos(ang), 0, 1)
    w = P["terrace"]["max_frac"] * ss(0.2, 0.75, np.maximum(west, south) ** 1.2) + 0.03 * noise(3, 4)
    terrace = bowl & (e > 1 - w) & (w > 0.05)
    isl = P["island"]
    isl_e = blob(isl["centre"], isl["radii"], 22, 0.10)
    island_top = isl_e < isl["top_frac"]
    up_blob = np.minimum(blob((-31, -24), (13, 40), 51, 0.25), blob((-4, 15), (30, 11), 52, 0.25))
    upland = (~bowl) & (up_blob < 1)                              # the dry land behind the terrace (not walkable)
    thicket_out = (~bowl) & ~upland
    d_exit, _ = seg(P["exit_lane"])
    exit_lane = d_exit + 0.5 * noise(1.0, 41) < 2.4
    thicket_in = bowl & (e > 0.93) & (north + east > 0.6) & ~terrace
    thicket = (thicket_out | thicket_in) & ~exit_lane
    clumps = np.zeros(XX.shape, bool)
    for c, r, sd in P["clumps"]:
        clumps |= blob(c, r, sd, 0.22) < 1
    high = terrace | island_top
    d_high = distance_transform_edt(~high) / PX
    face = (~high) & (d_high < P["face_w_m"])
    ramp = np.zeros(XX.shape, bool); skirt = np.zeros(XX.shape, bool)
    for rp in P["ramps"]:
        d_r, t_r = seg(rp["path"]); ramp |= d_r < rp["width"] / 2
        # the ground beside a ramp rises with it: not walkable (ledged), except past its lakebed end
        skirt |= (d_r >= rp["width"] / 2) & (d_r < rp["width"] / 2 + 2.0) & (t_r > 0.02)
    # the pier's footprint stays off the walkable ground (one walk height per spot: nothing walks under it)
    pr = P["pier"]; pad = P["pier_footprint_pad_m"]
    d_deck, _ = seg([pr["root"], pr["end"]])
    (px0, px1), (pz0, pz1) = pr["platform"]
    st = pr["steps"]
    footprint = (d_deck < pr["width"] / 2 + pad) | \
                ((XX > px0 - pad) & (XX < px1 + pad) & (ZZ > pz0 - pad) & (ZZ < pz1 + pad)) | \
                ((XX > st["from"][0] - pad) & (XX < st["to"][0] - 0.6) & (np.abs(ZZ - st["from"][1]) < st["width"] / 2 + pad))
    lake_walk = ((bowl & ~high & ~face & ~thicket & ~clumps & ~skirt) | exit_lane | (ramp & ~clumps)) & ~footprint & ~high
    raised_walk = high & ~(footprint & ~terrace) & ~clumps        # the deck's root sits on the terrace top
    smooth = lambda m: gaussian_filter(m.astype(float), 0.3 * PX) > 0.5
    return dict(e=e, bowl=bowl, terrace=terrace, island_top=island_top, isl_e=isl_e, upland=upland,
                thicket=thicket, clumps=clumps, face=face, ramp=ramp, exit_lane=exit_lane, footprint=footprint,
                lake_walk=smooth(lake_walk), raised_walk=smooth(raised_walk) & ~smooth(lake_walk))


if __name__ == "__main__":
    R_ = build()
    a = np.zeros((H, W), np.uint8)
    a[R_["raised_walk"]] = 190
    a[R_["lake_walk"]] = 255
    img = Image.fromarray(a, "L").convert("RGB")
    dr = ImageDraw.Draw(img)
    for (x, z), col in [(SPAWN, (255, 0, 0)), (EXIT, (0, 255, 0)), (SLOT, (255, 255, 0)), (HERON, (0, 0, 255))]:
        cx, cy = px(x, z); dr.ellipse([cx - 9, cy - 9, cx + 9, cy + 9], fill=col)
    img.save("floor1_walkable_sample.png")
    walk = R_["lake_walk"] | R_["raised_walk"]
    print("walkable extent m:", round(np.ptp(walk.any(0).nonzero()[0]) / PX, 1), "x",
          round(np.ptp(walk.any(1).nonzero()[0]) / PX, 1), " walkable area m2:", round(walk.sum() / PX / PX))
