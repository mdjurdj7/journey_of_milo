# Repaints floor 3's north-east corridor on the walkable sample: narrower, and
# arcing right (it leaves the hub heading north, then turns east to the exit).
# Spawn, hub, west (wagon) lobe, the Wardling's neck and lobe, and every dot
# stay where they are. Reads floor3_walkable_sample_orig.png, writes
# floor3_walkable_sample.png. Run floor3_mask_gen.py after it.
import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter, binary_closing
from skimage.morphology import disk

PX = 30.0
# Corridor centreline: quadratic Bezier, image px (x right, y down).
P0 = (700, 700)     # inside the hub
P1 = (740, 280)     # pulls the corridor north before it turns
P2 = (1300, 370)    # into the exit bulb
# Walkable width (m) along the curve: joins the hub, pinches, opens to the exit.
WIDTH_KEYS = [(0.0, 7.5), (0.3, 6.5), (0.55, 6.0), (0.8, 6.8), (1.0, 8.0)]
EXIT_BULB = ((1318, 362), 3.9)   # centre px, radius m (the exit dot sits inside it)
SMOOTH_M = 0.8                   # rounds the new joins (blur + threshold, local only)
CLOSE_M = 1.5                    # fills any crack narrower than 2x this between new and old shapes

src = np.array(Image.open("floor3_walkable_sample_orig.png").convert("RGB"))
H, W, _ = src.shape
walk = src.astype(int).sum(-1) > 3 * 127
yy, xx = np.mgrid[0:H, 0:W]

# Remove the old corridor: north of the hub, and its lower half down to the
# notch above the Wardling's neck.
old = (walk & (yy < 640) & (xx > 600)) | (walk & (xx > 760) & (yy < 860))
new_walk = walk & ~old

# Paint the new corridor as discs along the curve.
def bez(t):
    a, b, c = np.array(P0, float), np.array(P1, float), np.array(P2, float)
    return (1 - t) ** 2 * a + 2 * t * (1 - t) * b + t ** 2 * c
ts, ws = zip(*WIDTH_KEYS)
corr = np.zeros_like(walk)
for t in np.linspace(0, 1, 400):
    x, y = bez(t)
    r = 0.5 * np.interp(t, ts, ws) * PX
    corr |= (xx - x) ** 2 + (yy - y) ** 2 <= r * r
(bx, by), br = EXIT_BULB
corr |= (xx - bx) ** 2 + (yy - by) ** 2 <= (br * PX) ** 2
new_walk |= corr

# Round the new joins, only near what changed.
changed = gaussian_filter((new_walk != walk).astype(float), 2 * PX) > 0.01
closed = binary_closing(new_walk, structure=disk(int(CLOSE_M * PX)))
smooth = gaussian_filter(closed.astype(float), SMOOTH_M * PX) > 0.5
new_walk = np.where(changed, smooth, new_walk)

out = np.zeros((H, W, 3), np.uint8)
out[new_walk] = 255
# Carry the original dots over unchanged.
s = src.astype(int)
dots = (np.abs(s[..., 0] - s[..., 1]) > 60) | (np.abs(s[..., 1] - s[..., 2]) > 60) | (np.abs(s[..., 0] - s[..., 2]) > 60)
out[dots] = src[dots]
Image.fromarray(out, "RGB").save("floor3_walkable_sample.png")
print("dots carried:", int(dots.sum()), "px")
