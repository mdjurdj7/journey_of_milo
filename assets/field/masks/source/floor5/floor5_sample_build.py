"""Builds floor5_walkable_sample.png: white = walkable, coloured dots = markers.
Floor 5 (Region 1's last floor): one broad slope climbing north from the dunes to a rocky crest.
World metres around spawn; +X east, +Z south (north is negative Z)."""
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter

PX = 30
X0, X1, Z0, Z1 = -46.0, 46.0, -70.0, 14.0   # 92 m wide: past the sides the ground is height 0, so the rising outer ground needs room
NOISE_X0, NOISE_X1 = -26.0, 26.0             # the edge noise keeps the original 52 m grid, so widening never moves the walkable edge
W, H = int((X1 - X0) * PX), int((Z1 - Z0) * PX)
def px(x, z): return ((x - X0) * PX, (z - Z0) * PX)
yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
wx = xx / PX + X0
wz = yy / PX + Z0

# half-width of the climb along its length (z -> half width in m)
ZS = np.array([6.0, 2.0, -8.0, -16.0, -22.0, -28.0, -34.0, -40.0, -47.0, -50.0, -53.0, -60.0, -63.5])
HW = np.array([5.0, 9.0, 9.0, 7.0, 5.0, 6.5, 8.5, 9.5, 9.0, 4.5, 3.6, 3.6, 0.0])
half = np.interp(-wz, -ZS, HW)            # interp needs increasing x
def centre_x(z): return 3.5 * np.sin(-np.asarray(z) * np.pi / 40.0)   # a gentle S-bend so the climb isn't a straight corridor
walk = (np.abs(wx - centre_x(wz)) <= half) & (wz <= 6.0) & (wz >= -63.5)
def ellipse(c, rx, ry):
    cx, cy = px(*c); return ((xx - cx) / (rx * PX)) ** 2 + ((yy - cy) / (ry * PX)) ** 2 <= 1
walk |= ellipse((0, 3.0), 5.5, 3.5)                  # round closed foot behind spawn
POCKET_Z = -15.5
POCKET_X = float(centre_x(POCKET_Z) - np.interp(-POCKET_Z, -ZS, HW) - 2.7)
walk |= ellipse((POCKET_X, POCKET_Z), 3.4, 3.0)          # the one side pocket (west), for a small finding
walk |= ellipse((float(centre_x(-61.0)), -61.0), 4.4, 3.4)   # exit lobe beyond the gate line

rng = np.random.default_rng(5)
noise_w = int((NOISE_X1 - NOISE_X0) * PX)
noise_core = gaussian_filter(rng.standard_normal((H, noise_w)).astype(np.float32), 35); noise_core /= np.abs(noise_core).max()
noise = np.zeros((H, W), np.float32)
noise[:, int((NOISE_X0 - X0) * PX):int((NOISE_X0 - X0) * PX) + noise_w] = noise_core
walk = (gaussian_filter(walk.astype(np.float32), 15) + noise * 0.16) > 0.5

img = Image.fromarray((walk * 255).astype(np.uint8), "L").convert("RGB")
d = ImageDraw.Draw(img)
markers = {
    "spawn": ((0, 0), (255, 0, 0)),
    "exit": ((float(centre_x(-60)), -60), (0, 255, 0)),
    "region_end_fight": ((float(centre_x(-42)), -42), (255, 255, 0)),
    "finding": ((POCKET_X - 0.6, POCKET_Z - 0.4), (0, 255, 255)),
}
for name, (w, col) in markers.items():
    cx, cy = px(*w); assert walk[int(cy), int(cx)], name
    d.ellipse([cx - 8, cy - 8, cx + 8, cy + 8], fill=col)
img.save("floor5_walkable_sample.png")
print("canvas", W, H, "spawn px", px(0, 0), "pocket", round(POCKET_X,2), POCKET_Z)
import json; json.dump({"pocket": [POCKET_X, POCKET_Z], "centre_x_amp": 3.5, "centre_x_period_m": 80}, open("floor5_sample_params.json","w"))
