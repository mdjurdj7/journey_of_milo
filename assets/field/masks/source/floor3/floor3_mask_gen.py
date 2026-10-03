# Floor 3's ground from floor3_walkable_sample.png. Run from this folder.
# Needs Python 3 with numpy, scipy, scikit-image and Pillow:
#   python -m pip install --user numpy scipy scikit-image pillow
import json, numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt, gaussian_filter
from skimage.measure import find_contours, approximate_polygon
from skimage.morphology import dilation, disk

PX = 30.0                      # px per metre (Field Asset Spec)
ELEV_MAX = 1.8                 # metres at elevation value 1.0 (region1_floor3.tres elevation_max_height)
BASE_WALK = 0.4                # walkable floor height above the outer ground (m)
CREST_RISE = 1.2               # ridge crest above the walkable floor (m)
FACE_W = 2.0                   # inner face width (m) -> ~31 deg mean slope, under the 45 deg limit
CREST_W = 1.0                  # flat-ish crest width (m)
OUTER_FALL = 4.0               # outer slope down to the outer ground (m)
BARRIER_IN = 0.4               # ledge barrier sits this far up the inner face (m)
OUTER_EDGE_AT = FACE_W + 0.5 * CREST_W   # outer ground starts at the crest centreline (m past the walkable edge)
OUTER_EDGE_WIDTH = 0.3         # the whole outer-ground transition (m)

src = np.array(Image.open("floor3_walkable_sample.png").convert("RGB")).astype(int)
H, W, _ = src.shape
r, g, b = src[...,0], src[...,1], src[...,2]
def dot(mask):
    ys, xs = np.nonzero(mask); return (float(xs.mean()), float(ys.mean()))
spawn = dot((r > 200) & (g < 80) & (b < 80))
exit_ = dot((g > 200) & (r < 80) & (b < 80))
elite = dot((r > 200) & (g > 200) & (b < 80))
walk = (src.sum(-1) > 3*127)            # white or any coloured dot = walkable

# signed distance in metres: >0 outside the walkable area
d_out = distance_transform_edt(~walk) / PX
d_in = distance_transform_edt(walk) / PX

h = np.full((H, W), BASE_WALK, np.float32)          # walkable floor
o = d_out
face = np.clip(o / FACE_W, 0, 1)
h = np.where(o > 0, BASE_WALK + CREST_RISE * face, h)
fall_t = np.clip((o - FACE_W - CREST_W) / OUTER_FALL, 0, 1)
crest_h = BASE_WALK + CREST_RISE
h = np.where(o > FACE_W + CREST_W, crest_h - crest_h * fall_t, h)
h = gaussian_filter(h, sigma=0.3 * PX)               # round the ends of the linear faces
# ridge shrinks where two faces meet in a narrow wedge: nothing to do, max() of distance handles it

elev = np.clip(h / ELEV_MAX, 0, 1)
Image.fromarray((elev * 255 + 0.5).astype(np.uint8), "L").save("../../region1_floor3_elev.png")

# rock mask: the inner face, grown ~1 m (the shader's slope test finds the real edge)
rock = (o > 0) & (o < FACE_W + 1.0)
rock = gaussian_filter(rock.astype(np.float32), 2.0)
Image.fromarray((np.clip(rock, 0, 1) * 255).astype(np.uint8), "L").save("../../region1_floor3_rock.png")

# outer ground: 0 on the walkable area, the inner face and the crest's inner
# half, 1 past the crest centreline - a smoothstep OUTER_EDGE_WIDTH wide, no
# blur after it. 1 along every canvas edge, which the shader extends past it.
t = np.clip((o - OUTER_EDGE_AT) / OUTER_EDGE_WIDTH + 0.5, 0, 1)
outer_ground = t * t * (3 - 2 * t)
Image.fromarray((outer_ground * 255 + 0.5).astype(np.uint8), "L").save("../../region1_floor3_outer.png")

# landmass: all land (dry floor, no water)
Image.fromarray(np.full((H, W), 255, np.uint8), "L").save("../../region1_floor3_landmass.png")

# damp patches in the outer zone (optional: not read by the engine yet)
rng = np.random.default_rng(11)
n = gaussian_filter(rng.standard_normal((H, W)).astype(np.float32), 1.4 * PX)
n = (n - n.min()) / (n.max() - n.min())
outer = np.clip((o - (FACE_W + CREST_W + 2.0)) / 3.0, 0, 1)
damp = gaussian_filter(((n > 0.6).astype(np.float32)) * outer, 0.6 * PX)
Image.fromarray((np.clip(damp, 0, 1) * 255).astype(np.uint8), "L").save("./floor3_damp.png")

# ledge barrier: walkable area grown BARRIER_IN metres up the face, traced and simplified
barrier = dilation(walk, disk(int(BARRIER_IN * PX)))
cs = find_contours(barrier.astype(float), 0.5)
c = max(cs, key=len)
poly = approximate_polygon(c, tolerance=0.08 * PX)    # ~25 cm accuracy
def to_world(py, px_):
    return [round((px_ - spawn[0]) / PX, 3), round((py - spawn[1]) / PX, 3)]   # x right, z down-image (+Z = south)
ledge = [to_world(p[0], p[1]) for p in poly]

layout = {
    "canvas_px": [W, H], "px_per_m": PX,
    "landmass_mask_origin_uv": [round(spawn[0] / W, 5), round(spawn[1] / H, 5)],
    "spawn_px": [round(spawn[0], 1), round(spawn[1], 1)],
    "exit_world_xz": to_world(exit_[1], exit_[0]),
    "elite_world_xz": to_world(elite[1], elite[0]),
    "assumed_elevation_max_height_m": ELEV_MAX,
    "heights_m": {"outer_ground": 0.0, "walkable_floor": BASE_WALK, "ridge_crest": BASE_WALK + CREST_RISE},
    "ridge": {"inner_face_width_m": FACE_W, "crest_width_m": CREST_W, "outer_falloff_m": OUTER_FALL},
    "outer_ground": {"edge_at_m": OUTER_EDGE_AT, "edge_width_m": OUTER_EDGE_WIDTH},
    "ledge_barrier_world_xz": ledge,
    "note": "World XZ in metres relative to spawn; +X right, +Z toward the bottom of the image (south). Forward/exit is toward -Z.",
}
json.dump(layout, open("./floor3_layout.json", "w"), indent=1)

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
outside = (o > FACE_W + CREST_W)
col = col * np.where(outside, 0.88, 1.0)[...,None]
img = (np.clip(col, 0, 1) * 255).astype(np.uint8)
im = Image.fromarray(img, "RGB")
from PIL import ImageDraw
dr = ImageDraw.Draw(im)
for c_, colr in [(spawn,(200,40,40)),(exit_,(40,160,60)),(elite,(210,170,0))]:
    dr.ellipse([c_[0]-10,c_[1]-10,c_[0]+10,c_[1]+10], fill=colr)
pts = [(p[1], p[0]) for p in poly]
dr.line(pts + [pts[0]], fill=(30,60,140), width=2)
im.save("./floor3_ground_preview.png")

slope_face = np.degrees(np.arctan(CREST_RISE / FACE_W))
print("spawn", spawn, "exit", exit_, "elite", elite)
print("ledge points", len(ledge), " face mean slope", round(slope_face,1), "deg")
print("max slope on faces", round(float(slope[(o>0)&(o<FACE_W)].max()),1), "deg")
print("elev values: walk", round(BASE_WALK/ELEV_MAX,3), "crest", round((BASE_WALK+CREST_RISE)/ELEV_MAX,3))
