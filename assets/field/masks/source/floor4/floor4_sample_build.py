# Builds floor4_walkable_sample.png: white = walkable, black = not, coloured dots = markers.
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter

PX = 30
X0, X1, Z0, Z1 = -50.0, 38.0, -60.0, 16.0          # world extent in metres (z north = negative)
W, H = int((X1 - X0) * PX), int((Z1 - Z0) * PX)
def px(x, z): return ((x - X0) * PX, (z - Z0) * PX)
yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
def ellipse(c, rx, ry):
    cx, cy = px(*c); return ((xx - cx) / (rx * PX)) ** 2 + ((yy - cy) / (ry * PX)) ** 2 <= 1
def capsule(a, b, r):
    (ax, ay), (bx, by) = px(*a), px(*b); dx, dy = bx - ax, by - ay
    t = np.clip(((xx - ax) * dx + (yy - ay) * dy) / (dx * dx + dy * dy), 0, 1)
    return np.hypot(xx - (ax + t * dx), yy - (ay + t * dy)) <= r * PX

walk = ellipse((0, -28), 29, 23)                    # the loop's outer edge
walk |= capsule((0, -8), (0, 3.5), 4.5)             # south entry neck, closed behind spawn
walk |= capsule((-22, -46), (-37, -50), 4.2)        # exit neck heading west
walk |= ellipse((-38, -50), 5.0, 4.6)               # exit lobe beyond the gate line
walk &= ~ellipse((2, -28), 17, 13)                  # the central dune (impassable)
walk |= ellipse((15.5, -30), 3.6, 4.2)              # collector's bay tucked into the dune's east flank
walk &= ~ellipse((32, -19), 4.5, 4.0)               # ridge bump: the east side winds and narrows
walk &= ~ellipse((-31.5, -36), 3.0, 4.0)            # small west bump so the west edge isn't a perfect arc

rng = np.random.default_rng(4)
noise = gaussian_filter(rng.standard_normal((H, W)).astype(np.float32), 40); noise /= np.abs(noise).max()
soft = gaussian_filter(walk.astype(np.float32), 18) + noise * 0.10
walk = soft > 0.5

img = Image.fromarray((walk * 255).astype(np.uint8), "L").convert("RGB")
d = ImageDraw.Draw(img)
markers = {  # world xz -> colour (read back by the generator)
    "spawn": ((0, 0), (255, 0, 0)),
    "exit": ((-37, -50), (0, 255, 0)),
    "required_fight": ((-18, -43), (0, 0, 255)),
    "collector": ((14.5, -30), (255, 255, 0)),
    "optional_fight": ((-23, -24), (255, 0, 255)),
    "dig_site": ((21, -42), (0, 255, 255)),
}
for name, (w, col) in markers.items():
    cx, cy = px(*w); assert walk[int(cy), int(cx)], name
    d.ellipse([cx - 8, cy - 8, cx + 8, cy + 8], fill=col)
img.save("floor4_walkable_sample.png")
print("canvas", W, H, "spawn px", px(0, 0))
