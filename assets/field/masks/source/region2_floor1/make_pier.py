# Placeholder pier for Region 2 floor 1: a weathered wooden jetty that runs out
# level from the old shoreline over the drained lakebed and ends in the air,
# with a platform, railings, two mooring posts and boat steps down to the lane.
# Built from floor1_layout.json and the floor's elevation mask, so every piling
# reaches the ground under it. Age is placement and weathering, never damage:
# the wood is silvered and the planks sit a little unevenly; nothing is broken or missing.
# glb, metres, Y up. Its frame is the floor's: x east, z south, origin at spawn,
# y on the elevation scale (elevation value / 255 x elevation_max_height).
# Place it at spawn with y = the floor's interior_height. Visual only: the walk
# surface and rail collision belong to the Pier prop.
# Run from this folder after floor1_mask_gen.py.
#   python -m pip install --user numpy scipy pillow trimesh
import json, math, numpy as np, trimesh
from PIL import Image
from scipy.ndimage import gaussian_filter

L = json.load(open("floor1_layout.json"))
pr = L["pier"]
PX = L["px_per_m"]; ELEV_MAX = L["elevation_max_height_m"]; sx, sy = L["spawn_px"]
elev = np.array(Image.open("../../region2_floor1_elev.png").convert("L")).astype(float) / 255 * ELEV_MAX
def ground(x, z):
    j = int(round(sx + x * PX)); i = int(round(sy + z * PX))
    i = min(max(i, 0), elev.shape[0] - 1); j = min(max(j, 0), elev.shape[1] - 1)
    return float(elev[i, j])

DECK = pr["deck_height_m"]               # top of the planks
PLANK_T, PLANK_W, GAP = 0.06, 0.22, 0.025
SUNK = 0.4                               # pilings and posts go this far below the ground
rng = np.random.default_rng(5)

verts, faces, uvs = [], [], []
def box(center, size, yaw=0.0, pitch=0.0):
    """size = (along, up, across) before rotation; yaw about Y, pitch about the local across axis."""
    lx, ly, lz = [s / 2 for s in size]
    corners = np.array([[sx_ * lx, sy_ * ly, sz_ * lz] for sx_ in (-1, 1) for sy_ in (-1, 1) for sz_ in (-1, 1)])
    cp, sp = math.cos(pitch), math.sin(pitch)
    Rp = np.array([[cp, -sp, 0], [sp, cp, 0], [0, 0, 1]])
    cy, sy_ = math.cos(yaw), math.sin(yaw)
    Ry = np.array([[cy, 0, sy_], [0, 1, 0], [-sy_, 0, cy]])
    pts = corners @ Rp.T @ Ry.T + np.array(center)
    quads = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    dims = [(size[2], size[1]), (size[2], size[1]), (size[0], size[1]), (size[0], size[1]), (size[0], size[2]), (size[0], size[2])]
    off = rng.uniform(0, 1, 2)
    for q, (du, dv) in zip(quads, dims):
        base = len(verts)
        for k, (u_, v_) in zip(q, [(0, 0), (0, 1), (1, 1), (1, 0)]):
            verts.append(pts[k]); uvs.append((off[0] + u_ * du * 0.5, off[1] + v_ * dv * 0.5))
        faces.extend([(base, base + 1, base + 2), (base, base + 2, base + 3)])

rx, rz = pr["root_world_xz"]; ex, ez = pr["end_world_xz"]
dx, dz = ex - rx, ez - rz; LEN = math.hypot(dx, dz); ux, uz = dx / LEN, dz / LEN
nx, nz = -uz, ux                                   # across the deck
yaw = math.atan2(-uz, ux)                          # box "along" axis follows the pier
HW = pr["width_m"] / 2
(px0, px1), (pz0, pz1) = pr["platform_world_x"], pr["platform_world_z"]
def on_platform(x, z, pad=0.0): return px0 - pad <= x <= px1 + pad and pz0 - pad <= z <= pz1 + pad

# deck planks across the walk, from the root until the platform takes over
n_planks = int(LEN / (PLANK_W + GAP))
for k in range(n_planks):
    s = (k + 0.5) * (PLANK_W + GAP)
    cx, cz = rx + ux * s, rz + uz * s
    if on_platform(cx, cz): continue
    lift = rng.uniform(-0.008, 0.008)           # planks sit a little unevenly
    box((cx, DECK - PLANK_T / 2 + lift, cz), (PLANK_W, PLANK_T, pr["width_m"] + rng.uniform(-0.04, 0.04)), yaw)
# two stringers under the planks
for side in (-1, 1):
    cx, cz = rx + ux * LEN / 2 + nx * side * (HW - 0.25), rz + uz * LEN / 2 + nz * side * (HW - 0.25)
    box((cx, DECK - PLANK_T - 0.1, cz), (LEN, 0.2, 0.12), yaw)
# platform planks (laid east-west) and its frame
z = pz0
while z < pz1:
    box(((px0 + px1) / 2, DECK - PLANK_T / 2, z + PLANK_W / 2), (px1 - px0, PLANK_T, PLANK_W))
    z += PLANK_W + GAP
# pilings: pairs along the deck where the ground has fallen away, and under the platform
def piling(x, z):
    g = ground(x, z)
    if DECK - g < 0.5: return
    top, bot = DECK - PLANK_T, g - SUNK
    box((x, (top + bot) / 2, z), (0.2, top - bot, 0.2), rng.uniform(-0.1, 0.1))
s = 1.6
while s < LEN:
    for side in (-1, 1):
        x, z = rx + ux * s + nx * side * (HW - 0.1), rz + uz * s + nz * side * (HW - 0.1)
        if not on_platform(x, z, 0.3): piling(x, z)
    s += 2.6
for x in (px0 + 0.1, (px0 + px1) / 2, px1 - 0.1):
    for z in (pz0 + 0.1, (pz0 + pz1) / 2, pz1 - 0.1):
        piling(x, z)

# railings: posts every 2.6 m, a top rail and a mid rail
RAIL_H = 0.95
def rail(a, b):
    ax, az = a; bx, bz = b; l = math.hypot(bx - ax, bz - az)
    if l < 0.3: return
    yw = math.atan2(-(bz - az), bx - ax)
    for frac in np.arange(0, 1.0001, min(1.0, 2.6 / l)):
        box((ax + (bx - ax) * frac, DECK + RAIL_H / 2, az + (bz - az) * frac), (0.12, RAIL_H, 0.12))
    for hgt, th in ((RAIL_H - 0.04, 0.08), (RAIL_H * 0.5, 0.06)):
        box(((ax + bx) / 2, DECK + hgt, (az + bz) / 2), (l, th, th), yw)
def clip_to_platform(a, b):
    """Shorten segment a->b so it stops where it enters the platform."""
    steps = 200
    for k in range(steps + 1):
        t = k / steps
        if on_platform(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, 0.05):
            return (a, (a[0] + (b[0] - a[0]) * max(t - 1 / steps, 0), a[1] + (b[1] - a[1]) * max(t - 1 / steps, 0)))
    return (a, b)
for side in (-1, 1):                              # deck sides, open at the root
    a = (rx + ux * 0.6 + nx * side * HW, rz + uz * 0.6 + nz * side * HW)
    b = (ex + nx * side * HW, ez + nz * side * HW)
    rail(*clip_to_platform(a, b))
sf, stp = pr["steps"]["from_world_xz"], pr["steps"]["to_world_xz"]; SW = pr["steps"]["width_m"]
entry_hi = rx + ux * 0  # the deck meets the platform's south-west corner; keep that corner open
rail((px0, pz0), (px1, pz0))                                   # north side
rail((px0, pz0), (px0, pz1 - 1.6))                              # west side, open where the deck arrives
rail((px0 + 2.0, pz1), (px1, pz1))                              # south side, open where the deck arrives
rail((px1, pz0), (px1, sf[1] - SW / 2 - 0.1))                   # east side, open for the steps
rail((px1, sf[1] + SW / 2 + 0.1), (px1, pz1))

# mooring posts: stout, standing proud of the deck at the platform's far corners
for (mx, mz) in pr["mooring_posts_world_xz"]:
    g = ground(mx, mz); top = DECK + 0.65
    box((mx, (top + g - SUNK) / 2, mz), (0.28, top - g + SUNK, 0.28), 0.2)

# boat steps: two stringers and treads from the platform's edge down to the lane
foot = pr["steps"]["ground_at_foot_m"]
run = stp[0] - sf[0]; drop = DECK - foot; n = max(2, round(drop / 0.27))
pitch = math.atan2(-drop, run)
sl = math.hypot(run, drop)
for side in (-1, 1):
    box(((sf[0] + stp[0]) / 2, (DECK + foot) / 2 - 0.12, sf[1] + side * (SW / 2 - 0.06)), (sl, 0.24, 0.1), 0.0, pitch)
for k in range(n):
    t = (k + 0.5) / n
    box((sf[0] + run * t, DECK - drop * (k + 1) / n + 0.03, sf[1]), (run / n + 0.04, 0.06, SW))
for side in (-1, 1):                               # a post at the foot of each stringer
    box((stp[0], foot + 0.35 - SUNK / 2, sf[1] + side * (SW / 2 - 0.06)), (0.14, 0.7 + SUNK, 0.14))
# handrails down both sides of the steps, on the stringers' line (the Pier prop's rail collision follows them)
for side in (-1, 1):
    zr = sf[1] + side * (SW / 2 - 0.06)
    for frac in (0.0, 0.5, 1.0):
        x = sf[0] + run * frac; base_y = DECK - drop * frac
        box((x, base_y + RAIL_H / 2, zr), (0.1, RAIL_H, 0.1))
    box(((sf[0] + stp[0]) / 2, (DECK + foot) / 2 + RAIL_H - 0.04, zr), (sl, 0.07, 0.07), 0.0, pitch)

# painted texture: silvered wood leaning slightly warm, a step darker than sand, long grain
S = 256
base = np.array([0.55, 0.52, 0.47])
grain = gaussian_filter(rng.standard_normal((S, S)), (0.6, 14)); grain /= np.abs(grain).max()
blot = gaussian_filter(rng.standard_normal((S, S)), 20); blot /= np.abs(blot).max()
val = 1 + 0.06 * grain + 0.05 * blot
tex = np.clip(base[None, None, :] * val[..., None], 0, 1)
img = Image.fromarray((tex * 255 + 0.5).astype(np.uint8), "RGB")
img.save("pier_albedo.png")

mesh = trimesh.Trimesh(vertices=np.array(verts), faces=np.array(faces), process=False)
mat = trimesh.visual.material.PBRMaterial(baseColorTexture=img, metallicFactor=0.0, roughnessFactor=1.0)
mesh.visual = trimesh.visual.TextureVisuals(uv=np.array(uvs), material=mat)
mesh.export("pier.glb")
b = mesh.bounds
print("bounds (m): x", np.round(b[:, 0], 2), " y", np.round(b[:, 1], 2), " z", np.round(b[:, 2], 2),
      " tris", len(faces), " steps", n, "x", round(drop / n, 2), "m")
