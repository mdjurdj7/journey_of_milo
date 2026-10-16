# Floor 4's walkable sample, drawn from parameters: a ring around a central dune
# (worn west side wider than the faint east/north side), the tail behind spawn,
# the exit arm heading west, the collector's lee hollow off the road side, and
# the Adder's hooked curl ending in a pocket wide enough to stage a fight.
# World metres from spawn: +X right (east), +Z down (south). Writes
# floor4_walkable_sample.png with spawn (red), exit (green), elite (yellow) dots.
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter, distance_transform_edt

PX = 30.0
X0, Z0 = -36.0, -36.0                       # world metres at the canvas's top-left
W, H = 2010, 1590                           # 67 x 53 m
SPAWN, EXIT, ELITE = (0.0, 0.0), (-23.8, -22.2), (15.0, -9.4)

DUNE_C, DUNE_R = (-3.0, -13.0), (8.5, 5.2)  # central dune, irregular edge
RING_W_WORN, RING_W_FAINT = 7.0, 5.5        # south-west (road) side, north-east (faint) side
EDGE_WOBBLE_M = 0.55

xs = X0 + (np.arange(W) + 0.5) / PX
zs = Z0 + (np.arange(H) + 0.5) / PX
XX, ZZ = np.meshgrid(xs, zs)
def px(x, z): return ((x - X0) * PX, (z - Z0) * PX)
def capsules(pts, widths):
    d = np.full(XX.shape, 1e9)
    for a, b, wa, wb in zip(pts[:-1], pts[1:], widths[:-1], widths[1:]):
        vx, vz = b[0] - a[0], b[1] - a[1]; L2 = vx * vx + vz * vz
        t = np.clip(((XX - a[0]) * vx + (ZZ - a[1]) * vz) / L2, 0, 1)
        d = np.minimum(d, np.hypot(XX - (a[0] + t * vx), ZZ - (a[1] + t * vz)) - 0.5 * (wa + (wb - wa) * t))
    return d
def circle(c, r): return np.hypot(XX - c[0], ZZ - c[1]) - r

rng = np.random.default_rng(9)
def wobble(scale_m, amp_m, seed):
    n = gaussian_filter(np.random.default_rng(seed).standard_normal(XX.shape), scale_m * PX)
    return n / np.abs(n).max() * amp_m

# central dune
k = np.sqrt(((XX - DUNE_C[0]) / DUNE_R[0]) ** 2 + ((ZZ - DUNE_C[1]) / DUNE_R[1]) ** 2)
dune = ((k - 1) * min(DUNE_R) + wobble(2.5, 0.8, 9)) < 0
d_dune = distance_transform_edt(~dune) / PX
# ring width by direction: widest toward the south-west (road), narrowest north-east (faint)
ux, uz = XX - DUNE_C[0], ZZ - DUNE_C[1]
n = np.hypot(ux, uz) + 1e-6
sw = (-ux / n + uz / n) / np.sqrt(2)                       # +1 south-west, -1 north-east
ring_w = 0.5 * (RING_W_WORN + RING_W_FAINT) + 0.5 * (RING_W_WORN - RING_W_FAINT) * sw
ring = d_dune - ring_w

tail = capsules([(0.6, 5.5), (0.0, 0.0), (-0.6, -3.5)], [5.5, 6.0, 6.5])
exit_arm = capsules([(-13.5, -21.0), (-19.0, -22.5), (-25.5, -22.0)], [8.0, 6.5, 6.0])
collector = np.minimum(capsules([(-15.5, -11.5), (-19.0, -12.8), (-21.6, -12.2)], [5.0, 4.6, 3.4]),
                       circle((-20.4, -10.6), 1.6))
curl = capsules([(8.0, -15.5), (13.5, -18.5), (18.3, -16.0), (19.0, -11.4), (17.0, -8.6)],
                [6.0, 5.4, 5.0, 4.8, 4.8])
pocket = capsules([(17.0, -8.6), (14.4, -9.4)], [5.0, 4.6])   # wide enough to stage a fight

field = np.minimum.reduce([ring, tail, exit_arm, collector, curl, pocket])
field = np.where(dune, 1.0, field)
walk = gaussian_filter(((field + wobble(2.2, EDGE_WOBBLE_M, 4)) < 0).astype(float), 0.6 * PX) > 0.5

img = Image.fromarray(np.where(walk, 255, 0).astype(np.uint8), "L").convert("RGB")
dr = ImageDraw.Draw(img)
for (x, z), col in [(SPAWN, (255, 0, 0)), (EXIT, (0, 255, 0)), (ELITE, (255, 255, 0))]:
    cx, cy = px(x, z); dr.ellipse([cx - 7, cy - 7, cx + 7, cy + 7], fill=col)
img.save("floor4_walkable_sample.png")
print("walkable extent m:", round((np.ptp(walk.any(0).nonzero()[0])) / PX, 1), "x", round((np.ptp(walk.any(1).nonzero()[0])) / PX, 1))
