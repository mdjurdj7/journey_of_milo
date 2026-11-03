# Region 2 floor 1's walkable sample, drawn from parameters: an open drained
# basin. The lakebed is walkable almost everywhere; the old shoreline terrace
# follows the rim around the west and south (wide where the water once lapped,
# fading to nothing on the north and east); an old island stands in the
# middle-east; reeds gather on the low ground around the pier.
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
    "terrace": {"max_frac": 0.26, "rise_m": 4.0},          # band width as a fraction of the bowl radius; the bank stands ~2.2x the Wanderer, as in the camera target
    "face_w_m": 2.0,                                        # shoreline and island faces (~31 / 39 deg)
    "bank_rise_m": 1.2,                                     # the old dry land rising again behind the terrace
    "island": {"centre": (12.0, -24.0), "radii": (7.0, 5.2), "top_frac": 0.82, "rise_m": 4.0},
    "hollow": {"centre": (-6.0, -36.0), "radii": (8.0, 6.5), "depth_m": 0.0},   # dropped: the 4 m bank makes the pier read
    "lake_fall_per_m_north": 0.015,
    # ramps hug the bank: each runs along the face at a fixed offset from the top's edge, from "start"
    # (its lakebed foot) to "end", then turns straight in onto the top. Anchors are snapped to the offset line.
    "ramps": [{"name": "step you came down", "start": (2.0, -1.0), "end": (12.5, -6.0), "width": 3.0, "to": "terrace"},
              {"name": "north-west ramp", "start": (-9.6, -49.0), "end": (-12.9, -38.5), "width": 3.0, "to": "terrace"},
              {"name": "island ramp", "start": (8.5, -16.5), "end": (19.5, -22.5), "width": 3.0, "to": "island"}],
    "ramp_offset_extra_m": 0.3,                             # ramp centre sits face_w + width/2 + this from the top's edge
    "clumps": [((4.6, -8.8), (4.4, 3.5), 31),            # the big entrance willow: you round it to see the basin
               ((-8.0, -6.0), (3.0, 2.3), 32),
               ((19.0, -40.0), (3.6, 3.1), 33), ((-3.0, -51.0), (2.7, 2.1), 34),
               ((5.2, -39.4), (3.1, 2.4), 35)],          # screens the fight from the south until you pass it
    "main_path": [(0, 0), (-2.0, -6.5), (-2.4, -14), (0.6, -22), (2.0, -30), (0.2, -37), (1.8, -43), (4.0, -45), (4.0, -52), (4.5, -57), (5.5, -63)],
    "exit_lane": [(4.0, -50.0), (4.5, -56.0), (6.0, -64.0)],
    "exit_drop": {"z_from": -52.0, "z_to": -57.0, "drop_m": 1.2},
    "trail": [(4.0, -45.0), (9.0, -49.5), (13.5, -56.0)],   # the creature's run, into the north-east thicket
    "slot_faces_toward": (13.5, -56.0),
    "island_find": {"pos": (12.8, -25.0), "facing_deg": 35},   # an upturned rowboat stranded on the island top: the water once stood above it
    "heron": {"pos": HERON, "chance": 0.5, "nest_scrape": (-12.8, -50.4), "faces_toward": (-7.0, -47.0)},
    "pier": {"root": (-20.5, -23.0), "end": (-7.0, -35.0), "width": 2.0,
             "platform": ((-9.0, -5.0), (-37.0, -33.0)),
             "mooring_posts": [(-9.0, -37.0), (-5.0, -37.0)],
             "steps": {"from": (-5.0, -35.0), "to": (3.0, -35.0), "width": 1.4}},
    "pier_footprint_pad_m": 0.3,
    "wear": {"main": 0.85, "side": 0.5, "trail": 0.2},
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


def seg_arc(path, win=None):
    """Distance to a polyline and arc length (m) of the nearest point, optionally inside a window (i0,i1,j0,j1)."""
    if win is None: X_, Z_ = XX, ZZ
    else: X_, Z_ = XX[win[0]:win[1], win[2]:win[3]], ZZ[win[0]:win[1], win[2]:win[3]]
    d = np.full(X_.shape, 1e9); s_ = np.zeros(X_.shape); acc = 0.0
    for (ax, az), (bx, bz) in zip(path[:-1], path[1:]):
        vx, vz = bx - ax, bz - az; L2 = max(vx * vx + vz * vz, 1e-9); L = np.sqrt(L2)
        t = np.clip(((X_ - ax) * vx + (Z_ - az) * vz) / L2, 0, 1)
        dd = np.hypot(X_ - (ax + t * vx), Z_ - (az + t * vz)); m = dd < d
        d[m] = dd[m]; s_[m] = acc + t[m] * L; acc += L
    return d, s_


def window(path, pad_m):
    xs_ = [p[0] for p in path]; zs_ = [p[1] for p in path]
    j0 = int(max(0, (min(xs_) - pad_m - X0) * PX)); j1 = int(min(W, (max(xs_) + pad_m - X0) * PX))
    i0 = int(max(0, (min(zs_) - pad_m - Z0) * PX)); i1 = int(min(H, (max(zs_) + pad_m - Z0) * PX))
    return (i0, i1, j0, j1)


def hug_path(d_top, start, end, offset):
    """The ramp's centreline: the iso-line d_top == offset between the anchors, then a leg straight onto the top."""
    from skimage.measure import find_contours
    win = window([start, end], 14.0); i0, i1, j0, j1 = win
    sub = d_top[i0:i1, j0:j1]
    best = None
    for c in find_contours(sub, offset):
        pts = np.c_[X0 + (c[:, 1] + j0 + 0.5) / PX, Z0 + (c[:, 0] + i0 + 0.5) / PX]
        da = np.hypot(*(pts - start).T); db = np.hypot(*(pts - end).T)
        score = da.min() + db.min()
        if best is None or score < best[0]: best = (score, pts, int(da.argmin()), int(db.argmin()))
    _, pts, ia, ib = best
    closed = np.allclose(pts[0], pts[-1])
    fwd = pts[ia:ib + 1] if ia <= ib else np.r_[pts[ia:], pts[1:ib + 1]] if closed else pts[ib:ia + 1][::-1]
    if closed:                                                  # a closed line (around the island): take the shorter way
        bwd = (pts[ib:ia + 1] if ib <= ia else np.r_[pts[ib:], pts[1:ia + 1]])[::-1]
        arc = lambda q: float(np.hypot(*np.diff(q, axis=0).T).sum())
        fwd = fwd if arc(fwd) <= arc(bwd) else bwd
    hug = fwd
    keep = [hug[0]]
    for p in hug[1:]:
        if np.hypot(*(p - keep[-1])) >= 0.5: keep.append(p)
    hug = np.array(keep)
    gz, gx = np.gradient(sub, 1.0 / PX)
    leg = [hug[-1].copy()]; p = hug[-1].copy()
    for _ in range(int((offset + 1.5) / 0.25)):                # walk down the distance field onto the top, 1.5 m in
        i = int((p[1] - Z0) * PX) - i0; j = int((p[0] - X0) * PX) - j0
        g = np.array([gx[i, j], gz[i, j]]); n = np.hypot(*g)
        if n < 1e-6: break
        p = p - 0.25 * g / n
        if np.hypot(*(p - leg[-1])) >= 0.75: leg.append(p.copy())
    leg.append(p.copy())
    return [tuple(map(float, q)) for q in hug], [tuple(map(float, q)) for q in leg[1:]]


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
    terrace &= np.hypot(XX - SPAWN[0], ZZ - SPAWN[1]) + 0.6 * noise(2.0, 61) > 5.5   # the bank stands back from spawn
    isl = P["island"]
    isl_e = blob(isl["centre"], isl["radii"], 22, 0.10) + 0.16 * noise(3.0, 23) + 0.06 * np.sin(np.arctan2(ZZ - isl["centre"][1], XX - isl["centre"][0]) * 3 + 1.1)
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
    face = (~high) & (d_high < P["face_w_m"] + 0.5)              # walkable ground stays 0.5 m clear of a face's foot
    d_terr = distance_transform_edt(~terrace) / PX
    d_isl = distance_transform_edt(~island_top) / PX
    ramp = np.zeros(XX.shape, bool); skirt = np.zeros(XX.shape, bool); ramp_paths = []
    for rp in P["ramps"]:
        d_top = d_terr if rp["to"] == "terrace" else d_isl
        off = P["face_w_m"] + rp["width"] / 2 + P["ramp_offset_extra_m"]
        hug, leg = hug_path(d_top, rp["start"], rp["end"], off)
        path = hug + leg
        win = window(path, rp["width"] / 2 + 3.0); i0, i1, j0, j1 = win
        d_r, s_r = seg_arc(path, win)
        sub_r = d_r < rp["width"] / 2
        sub_sk = (d_r >= rp["width"] / 2) & (d_r < rp["width"] / 2 + 2.8) & (s_r > 0.4)   # past the 2.0 m blend, so no steep walkable edge
        ramp[i0:i1, j0:j1] |= sub_r; skirt[i0:i1, j0:j1] |= sub_sk
        L_hug = float(sum(np.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(hug[:-1], hug[1:])))
        ramp_paths.append(dict(name=rp["name"], to=rp["to"], width=rp["width"], hug=hug, leg=leg, path=path, L_hug=L_hug, win=win))
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
    lw, rw = smooth(lake_walk), smooth(raised_walk)
    lw |= (np.hypot(XX - SPAWN[0], ZZ - SPAWN[1]) < 1.2) & ~high   # a small pad so spawn always stands on walkable ground
    rw = rw & ~lw
    from scipy.ndimage import label
    lab, _ = label(lw | rw)                                     # keep only ground reachable from spawn
    keep = lab == lab[int((SPAWN[1] - Z0) * PX), int((SPAWN[0] - X0) * PX)]
    lw, rw = lw & keep, rw & keep
    return dict(e=e, bowl=bowl, terrace=terrace, island_top=island_top, isl_e=isl_e, upland=upland, ramp_paths=ramp_paths, skirt=skirt,
                thicket=thicket, clumps=clumps, face=face, ramp=ramp, exit_lane=exit_lane, footprint=footprint,
                lake_walk=lw, raised_walk=rw)


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
