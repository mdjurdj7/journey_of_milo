# Floor 4's ground from floor4_walkable_sample.png (drawn by floor4_shape.py).
# Built on floor 3's generator: same ridge, rock, outer and ledge conventions.
# Run from this folder.
# Needs Python 3 with numpy, scipy, scikit-image and Pillow:
#   python -m pip install --user numpy scipy scikit-image pillow
import json, numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt, gaussian_filter
from skimage.measure import find_contours, approximate_polygon
from skimage.morphology import dilation, disk

PX = 30.0                      # px per metre (Field Asset Spec)
ELEV_MAX = 2.4                 # metres at elevation value 1.0: set region1_floor4.tres elevation_max_height to match
DUNE_PEAK = 0.6                # the central dune rises this far above the ridge crest
BASE_WALK = 0.4                # walkable floor height above the outer ground (m)
CREST_RISE = 1.2               # ridge crest above the walkable floor (m)
FACE_W = 2.0                   # inner face width (m) -> ~31 deg mean slope, under the 45 deg limit
CREST_W = 1.0                  # flat-ish crest width (m)
OUTER_FALL = 4.0               # outer slope down to the outer ground (m)
BARRIER_IN = 0.4               # ledge barrier sits this far up the inner face (m)
OUTER_EDGE_AT = FACE_W + 0.5 * CREST_W   # outer ground starts at the crest centreline (m past the walkable edge)
OUTER_EDGE_WIDTH = 0.3         # the whole outer-ground transition (m)

src = np.array(Image.open("floor4_walkable_sample.png").convert("RGB")).astype(int)
H, W, _ = src.shape
r, g, b = src[...,0], src[...,1], src[...,2]
def dot(mask):
    ys, xs = np.nonzero(mask); return (float(xs.mean()), float(ys.mean()))
spawn = dot((r > 200) & (g < 80) & (b < 80))
exit_ = dot((g > 200) & (r < 80) & (b < 80))
elite = dot((r > 200) & (g > 200) & (b < 80))
walk = (src.sum(-1) > 3*127) | (src.max(-1) > 200)   # white or any coloured dot = walkable

from scipy.ndimage import label, binary_closing
def px_of(wx, wz):
    return (spawn[0] + wx * PX, spawn[1] + wz * PX)
yy, xx = np.mgrid[0:H, 0:W]

# The collector's shelf: a stretch of ridge behind the collector's hollow
# (its north and west sides) stands SHELF_EXTRA_RISE higher than the other
# ridges, so it reads as a low rock shelf the hollow is tucked against.
# World metres from spawn (+Z south).
SHELF_PTS = [(-16.6, -15.6), (-20.0, -15.3), (-23.6, -13.2), (-24.0, -10.0), (-22.2, -8.0)]
SHELF_WIDTH_M = 3.4
SHELF_EXTRA_RISE = 0.5         # face 1.7 m over 2 m, ~40 deg mean, under the 45 deg limit
shelf_d = np.full((H, W), 1e9)
for (ax, az), (bx, bz) in zip(SHELF_PTS[:-1], SHELF_PTS[1:]):
    pax, paz = px_of(ax, az); pbx, pbz = px_of(bx, bz)
    vx, vz = pbx - pax, pbz - paz; L2 = vx * vx + vz * vz
    t = np.clip(((xx - pax) * vx + (yy - paz) * vz) / L2, 0, 1)
    shelf_d = np.minimum(shelf_d, np.hypot(xx - (pax + t * vx), yy - (paz + t * vz)) / PX)
shelf = gaussian_filter((shelf_d < 0.5 * SHELF_WIDTH_M).astype(np.float32), 1.0 * PX)

# The Adder's den: the walkable floor sinks ADDER_DIP_M toward the Adder's pocket
# along the curl, measured as walking distance from the elite dot, so the ring
# itself never dips. The ridge crests keep their height, so the den's walls stand
# taller above its floor. The drop is never more than BASE_WALK (the floor's
# lift above the outer ground), so the ground never goes below it.
ADDER_DIP_M = 0.4
ADDER_DIP_FULL_M = 2.5         # full depth within this walking distance of the Adder
ADDER_DIP_START_M = 9.0        # no dip beyond this walking distance
from skimage.graph import MCP_Geometric
_step = 3
_cost = np.where(walk[::_step, ::_step], 1.0, np.inf)
_geo, _ = MCP_Geometric(_cost).find_costs([(int(round(elite[1])) // _step, int(round(elite[0])) // _step)])
from scipy.ndimage import zoom
geo_m = zoom(np.nan_to_num(_geo, posinf=1e4), _step, order=1)[:H, :W] * _step / PX
_t = np.clip((ADDER_DIP_START_M - geo_m) / (ADDER_DIP_START_M - ADDER_DIP_FULL_M), 0, 1)
dip = _t * _t * (3 - 2 * _t)
dip = gaussian_filter(np.where(walk, dip, 0.0), 1.0 * PX) / np.maximum(gaussian_filter(walk.astype(float), 1.0 * PX), 1e-3)
dip = np.where(walk, np.clip(dip, 0, 1), 0.0)

# Floor 4 has no water: the landmass stays solid.
STREAM = False
stream = np.zeros((H, W), bool)
d_stream = np.full((H, W), 1e9)
bank = np.ones((H, W), np.float32)

# signed distance in metres: >0 outside the walkable area
d_out = distance_transform_edt(~walk) / PX
d_in = distance_transform_edt(walk) / PX

base = BASE_WALK * bank - ADDER_DIP_M * dip          # the floor, sunk toward the Adder's den
crest_abs = BASE_WALK * bank + CREST_RISE + SHELF_EXTRA_RISE * shelf   # crests keep their height
h = base.astype(np.float32)                          # walkable floor
o = d_out
face = np.clip(o / FACE_W, 0, 1)
# the face climbs from wherever the floor is at its foot up to the fixed crest
foot = distance_transform_edt(~walk, return_distances=False, return_indices=True)
base_at_foot = base[foot[0], foot[1]]
h = np.where(o > 0, base_at_foot + (crest_abs - base_at_foot) * face, h)
fall_t = np.clip((o - FACE_W - CREST_W) / OUTER_FALL, 0, 1)
crest_h = crest_abs
h = np.where(o > FACE_W + CREST_W, crest_h - crest_h * fall_t, h)
# The central dune is unwalkable ground enclosed by the ring. Outside the floor
# the ground falls away past the crest; inside the ring it must rise instead, or
# the dune reads as a crater.
lab_o, nlab = label(~walk)
edge_labels = set(np.unique(np.concatenate([lab_o[0, :], lab_o[-1, :], lab_o[:, 0], lab_o[:, -1]])))
interior = np.isin(lab_o, [i for i in range(1, nlab + 1) if i not in edge_labels])
rise_t = np.clip((o - FACE_W - CREST_W) / 3.0, 0, 1)
rise_t = rise_t * rise_t * (3 - 2 * rise_t)
h = np.where(interior & (o > FACE_W + CREST_W), crest_h + DUNE_PEAK * rise_t, h)
h = gaussian_filter(h, sigma=0.3 * PX)               # round the ends of the linear faces
# ridge shrinks where two faces meet in a narrow wedge: nothing to do, max() of distance handles it

elev = np.clip(h / ELEV_MAX, 0, 1)
Image.fromarray((elev * 255 + 0.5).astype(np.uint8), "L").save("../../region1_floor4_elev.png")

# rock mask: the inner face, grown ~1 m (the shader's slope test finds the real edge)
rock = (o > 0) & (o < FACE_W + 1.0) & (~interior)   # the central dune stays sand
rock = gaussian_filter(rock.astype(np.float32), 2.0)
Image.fromarray((np.clip(rock, 0, 1) * 255).astype(np.uint8), "L").save("../../region1_floor4_rock.png")

# outer ground: 0 on the walkable area, the inner face and the crest's inner
# half, 1 past the crest centreline - a smoothstep OUTER_EDGE_WIDTH wide, no
# blur after it. 1 along every canvas edge, which the shader extends past it.
t = np.clip((o - OUTER_EDGE_AT) / OUTER_EDGE_WIDTH + 0.5, 0, 1)
outer_ground = t * t * (3 - 2 * t)
outer_ground = np.where(interior, 0.0, outer_ground)   # the central dune is sand, not outer ground
Image.fromarray((outer_ground * 255 + 0.5).astype(np.uint8), "L").save("../../region1_floor4_outer.png")

# landmass: all land except the stream, which is enclosed water (a pool to the
# engine). ~10 px blur on its edge, as the Field Asset Spec asks.
land = np.where(stream, 0.0, 1.0).astype(np.float32)
land = gaussian_filter(land, 10.0 / 3.0) if STREAM else land
Image.fromarray((land * 255 + 0.5).astype(np.uint8), "L").save("../../region1_floor4_landmass.png")

# damp patches in the outer zone (optional: not read by the engine yet)
rng = np.random.default_rng(11)
n = gaussian_filter(rng.standard_normal((H, W)).astype(np.float32), 1.4 * PX)
n = (n - n.min()) / (n.max() - n.min())
outer = np.clip((o - (FACE_W + CREST_W + 2.0)) / 3.0, 0, 1) * (~interior)
damp = gaussian_filter(((n > 0.6).astype(np.float32)) * outer, 0.6 * PX)
Image.fromarray((np.clip(damp, 0, 1) * 255).astype(np.uint8), "L").save("./floor4_damp.png")

# ledge barrier: walkable area grown BARRIER_IN metres up the face, traced and simplified
barrier = dilation(walk, disk(int(BARRIER_IN * PX)))
# Every closed outline is a ledge, longest first: [0] the outer boundary,
# then each unwalkable island inside it (the central dune).
cs = [c for c in find_contours(barrier.astype(float), 0.5) if np.allclose(c[0], c[-1])]
cs.sort(key=len, reverse=True)
polys = [approximate_polygon(c, tolerance=0.08 * PX) for c in cs]   # ~25 cm accuracy
def to_world(py, px_):
    return [round((px_ - spawn[0]) / PX, 3), round((py - spawn[1]) / PX, 3)]   # x right, z down-image (+Z = south)
ledges = [[to_world(p[0], p[1]) for p in poly] for poly in polys]

layout = {
    "canvas_px": [W, H], "px_per_m": PX,
    "landmass_mask_origin_uv": [round(spawn[0] / W, 5), round(spawn[1] / H, 5)],
    "spawn_px": [round(spawn[0], 1), round(spawn[1], 1)],
    "exit_world_xz": to_world(exit_[1], exit_[0]),
    "elite_world_xz": to_world(elite[1], elite[0]),
    "elevation_max_height_m": ELEV_MAX,
    "heights_m": {"outer_ground": 0.0, "walkable_floor": BASE_WALK, "ridge_crest": BASE_WALK + CREST_RISE},
    "ridge": {"inner_face_width_m": FACE_W, "crest_width_m": CREST_W, "outer_falloff_m": OUTER_FALL},
    "outer_ground": {"edge_at_m": OUTER_EDGE_AT, "edge_width_m": OUTER_EDGE_WIDTH},
    "collector_shelf": {"points_world_xz": [list(p) for p in SHELF_PTS], "width_m": SHELF_WIDTH_M, "extra_rise_m": SHELF_EXTRA_RISE},
    "suggested_placements_world_xz": {
        "adder_and_basking_slab_prop": [round((elite[0] - spawn[0]) / PX, 2), round((elite[1] - spawn[1]) / PX, 2)],
        "collector": [-19.8, -11.8], "dig": [-3.0, -21.8], "dunecur": [-17.5, -22.6]},
    "ledges_world_xz": ledges,
    "note": "World XZ in metres relative to spawn; +X right, +Z toward the bottom of the image (south). Forward/exit is toward -Z. Closed ledge rings, longest first: [0] the outer boundary, [1] the central dune.",
}
json.dump(layout, open("./floor4_layout.json", "w"), indent=1)

# preview: hillshade (sun from ESE, 45 deg) + rock tint + damp + dots
gy, gx = np.gradient(h * PX / 1.0, 1.0)   # height in px units for slope
nx, ny, nz = -gx / PX * PX, -gy / PX * PX, np.ones_like(h)
norm = np.sqrt(nx**2 + ny**2 + nz**2); nx, ny, nz = nx/norm, ny/norm, nz/norm
sun = np.array([0.6, 0.35, 0.72]); sun /= np.linalg.norm(sun)   # from the east-south-east, image coords (x right, y down)
shade = np.clip(nx*sun[0] + ny*sun[1] + nz*sun[2], 0, 1)
sand = np.array([0.74, 0.70, 0.60]); stone = np.array([0.56, 0.59, 0.50])
slope = np.degrees(np.arctan(np.hypot(*np.gradient(h, 1.0/PX))))
rk = np.clip((slope - 22) / 12, 0, 1) * np.clip(rock, 0, 1)
col = sand[None,None,:]*(1-rk[...,None]) + stone[None,None,:]*rk[...,None]
col = col * (1 - 0.28*np.clip(damp,0,1))[...,None]
col = col * (0.55 + 0.45*shade)[...,None]
outside = (o > FACE_W + CREST_W) & (~interior)
col = col * np.where(outside, 0.88, 1.0)[...,None]
if STREAM:   # wet band (x0.72 at the edge, gone by 0.8 m), then the water itself
    wet = np.clip(1 - d_stream / 0.8, 0, 1) * (1 - stream)
    col = col * (1 - 0.28 * wet)[...,None]
    shallow = np.array([0.54, 0.60, 0.61]); seabed = sand * 0.72 * 0.8
    d_in_s = distance_transform_edt(stream) / PX
    k = np.clip(d_in_s / 1.2, 0, 1)[...,None] * 0.75
    water = seabed[None,None,:] * (1 - k) + shallow[None,None,:] * k
    col = np.where(stream[...,None], water, col)
img = (np.clip(col, 0, 1) * 255).astype(np.uint8)
im = Image.fromarray(img, "RGB")
from PIL import ImageDraw
dr = ImageDraw.Draw(im)
for c_, colr in [(spawn,(200,40,40)),(exit_,(40,160,60)),(elite,(210,170,0))]:
    dr.ellipse([c_[0]-10,c_[1]-10,c_[0]+10,c_[1]+10], fill=colr)
for poly in polys:
    pts = [(p[1], p[0]) for p in poly]
    dr.line(pts + [pts[0]], fill=(30,60,140), width=2)
im.save("./floor4_ground_preview.png")

slope_face = np.degrees(np.arctan(CREST_RISE / FACE_W))
print("spawn", spawn, "exit", exit_, "elite", elite)
print("ledge points", [len(l) for l in ledges], " face mean slope", round(slope_face,1), "deg")
print("max slope on faces", round(float(slope[(o>0)&(o<FACE_W)].max()),1), "deg")
print("max slope on walkable floor", round(float(slope[walk & (d_in > 0.6)].max()),1), "deg;  den floor drop", round(float((ADDER_DIP_M*dip).max()),2), "m")
print("elev values: walk", round(BASE_WALK/ELEV_MAX,3), "crest", round((BASE_WALK+CREST_RISE)/ELEV_MAX,3))
