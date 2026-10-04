# Builds floor4_walkable_sample.png: white = walkable, black = not, coloured dots = markers.
# The loop at 0.75 of its first size round spawn, the dune sized for a ring ~7-9 m wide,
# so the field camera's frame holds a wall on either hand: a south entry neck, the loop
# round the central dune, the collector's bay in its east flank, the rejoin, the exit
# neck west.
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter

PX = 30
S = 0.75                                             # the first layout's scale
X0, X1, Z0, Z1 = -38.0, 29.0, -46.0, 12.0           # world extent in metres (z north = negative)
W, H = int((X1 - X0) * PX), int((Z1 - Z0) * PX)
def px(x, z): return ((x - X0) * PX, (z - Z0) * PX)
yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
def ellipse(c, rx, ry):
    cx, cy = px(*c); return ((xx - cx) / (rx * PX)) ** 2 + ((yy - cy) / (ry * PX)) ** 2 <= 1
def capsule(a, b, r):
    (ax, ay), (bx, by) = px(*a), px(*b); dx, dy = bx - ax, by - ay
    t = np.clip(((xx - ax) * dx + (yy - ay) * dy) / (dx * dx + dy * dy), 0, 1)
    return np.hypot(xx - (ax + t * dx), yy - (ay + t * dy)) <= r * PX
def s(p): return (p[0] * S, p[1] * S)

walk = ellipse(s((0, -28)), 29 * S, 23 * S)          # the loop's outer edge
walk |= capsule(s((0, -8)), s((0, 3.5)), 4.5 * S)    # south entry neck, closed behind spawn
walk |= capsule(s((-22, -46)), s((-37, -50)), 4.2 * S)   # exit neck heading west
walk |= ellipse(s((-38, -50)), 5.0 * S, 4.6 * S)     # exit lobe beyond the gate line
walk &= ~ellipse((0.6, -21.0), 14.0, 9.6)            # the central dune (impassable), for a ~8 m ring
walk |= ellipse((11.0, -22.5), 2.7, 3.2)             # collector's bay tucked into the dune's east flank
walk &= ~ellipse(s((32, -19)), 4.5 * S, 4.0 * S)     # ridge bump: the east side winds and narrows
walk &= ~ellipse(s((-31.5, -36)), 3.0 * S, 4.0 * S)  # small west bump so the west edge isn't a perfect arc

rng = np.random.default_rng(4)
noise = gaussian_filter(rng.standard_normal((H, W)).astype(np.float32), 40); noise /= np.abs(noise).max()
soft = gaussian_filter(walk.astype(np.float32), 18) + noise * 0.10
walk = soft > 0.5

img = Image.fromarray((walk * 255).astype(np.uint8), "L").convert("RGB")
d = ImageDraw.Draw(img)
markers = {  # world xz -> colour (read back by the generator)
    "spawn": ((0, 0), (255, 0, 0)),
    "exit": (s((-37, -50)), (0, 255, 0)),
    "required_fight": (s((-18, -43)), (0, 0, 255)),
    "collector": ((11.0, -22.5), (255, 255, 0)),
    "optional_fight": (s((-23, -24)), (255, 0, 255)),
    "dig_site": (s((21, -42)), (0, 255, 255)),
}
for name, (w, col) in markers.items():
    cx, cy = px(*w); assert walk[int(cy), int(cx)], name
    d.ellipse([cx - 8, cy - 8, cx + 8, cy + 8], fill=col)
img.save("floor4_walkable_sample.png")
print("canvas", W, H, "spawn px", px(0, 0))
