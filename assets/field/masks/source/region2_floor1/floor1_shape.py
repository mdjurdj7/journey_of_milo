# Region 2 floor 1's walkable sample, drawn from parameters: a drained lakebed
# below an old shoreline (a raised strip along the south and up the west side),
# a main lane winding north through reed walls to a clearing that is the only
# way on, an open patch where the pier comes into view, a low point up onto the
# shoreline, and the steps lane where the pier's boat steps come down.
# World metres from spawn: +X right (east), +Z down (south); forward is -Z.
# Writes floor1_walkable_sample.png:
#   white      = walkable lakebed (lanes, patch, clearing)
#   light grey = walkable old shoreline (raised)
#   black      = not walkable (reeds, the shoreline's face, beyond the floor)
#   dots: spawn (red), exit (green), required fight (yellow)
# The pier is a prop (walk surface), not ground; it is described in PLAN and
# drawn by make_pier.py. floor1_mask_gen.py imports PLAN from this file.
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter

PX = 30.0
X0, Z0 = -24.0, -58.0                        # world metres at the canvas's top-left
W, H = 1140, 2010                            # 38 x 67 m
SPAWN, EXIT, SLOT = (0.0, 0.0), (4.0, -53.0), (4.0, -41.5)

PLAN = {
    # the old shoreline: walkable, raised SHORE_RISE above the lakebed at spawn
    "shore_rects": [((-21.0, -16.0), (-50.0, 8.0)),      # west strip: x range, z range
                    ((-21.0, 12.0), (4.0, 8.0))],         # south rim behind spawn
    "shore_rise_m": 1.2,
    "face_w_m": 2.0,                                      # shoreline face, ~31 deg
    # behind the shoreline the old dry land rises again as a bank (the floor's edge, like floor 4's ridges)
    "landward": {"west_of_x": -21.0, "south_of_z": 8.0, "north_end": {"west_of_x": -16.0, "north_of_z": -50.0}},
    "bank_rise_m": 1.2,
    # ramps between lakebed (first point) and shoreline (last point)
    "ramps": [{"name": "step you came down", "path": [(0.0, 0.5), (0.0, 4.5)], "width": 4.0},
              {"name": "low point", "path": [(-9.5, -10.5), (-16.5, -10.5)], "width": 2.5}],
    # lakebed lanes: (points, widths) capsules, as floor 4's shape script draws them
    "main_lane": ([(0, 0), (2, -6), (-1, -12), (1, -19), (5, -26), (5, -35), (4, -41), (4, -46), (4, -51), (4, -55)],
                  [3.0, 2.6, 2.6, 2.4, 2.4, 2.4, 2.6, 2.4, 2.4, 2.4]),
    "patch_link": ([(-1.5, -12.0), (-5.0, -11.2)], [2.2, 2.2]),
    "steps_lane": ([(1.5, -32.0), (4.0, -33.0)], [1.8, 1.8]),
    "open_patch": ((-6.0, -11.0), (4.0, 3.0)),            # centre, radii (x, z)
    "clearing": ((4.0, -41.0), (5.0, 4.5)),
    # the lakebed falls gently along the walk, and away under the pier
    "lake_fall_per_m_north": 0.02,
    "bowl": {"centre": (-6.0, -33.0), "radius_m": 9.0, "depth_m": 1.2},
    "exit_drop": {"z_from": -49.0, "z_to_lane": -53.0, "z_to_elsewhere": -51.0, "lane_x": 4.0, "drop_m": 1.2},
    # the pier: a prop the Wanderer walks on (deck level with the shoreline)
    "pier": {"root": (-18.0, -16.0), "end": (-5.0, -32.0), "width": 2.0,
             "platform": ((-7.0, -3.0), (-34.0, -30.0)),
             "mooring_posts": [(-7.0, -34.0), (-3.0, -34.0)],
             "steps": {"from": (-3.0, -32.0), "to": (1.5, -32.0), "width": 1.4}},
    "short_reed_corridor_m": 3.5,                         # either side of the pier line
    # the creature's trail: a narrow run out of the clearing toward the tower, not walkable
    "trail": ([(0.5, -43.0), (-4.0, -47.0), (-9.0, -50.5)], 0.7),
    "slot_faces_toward": (-9.0, -50.5),
    "wear": {"main": 1.0, "side": 0.6, "trail": 0.2},
}
EDGE_WOBBLE_M = 0.35

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


def ellipse(c, r):
    k = np.sqrt(((XX - c[0]) / r[0]) ** 2 + ((ZZ - c[1]) / r[1]) ** 2)
    return (k - 1) * min(r)


def rect(xr, zr):
    return np.maximum.reduce([xr[0] - XX, XX - xr[1], zr[0] - ZZ, ZZ - zr[1]])


def wobble(scale_m, amp_m, seed):
    n = gaussian_filter(np.random.default_rng(seed).standard_normal(XX.shape), scale_m * PX)
    return n / np.abs(n).max() * amp_m


def build():
    P = PLAN
    lake = np.minimum.reduce([
        capsules(*P["main_lane"]), capsules(*P["patch_link"]), capsules(*P["steps_lane"]),
        ellipse(*P["open_patch"]), ellipse(*P["clearing"]),
        *[capsules(r["path"], [r["width"]] * len(r["path"])) for r in P["ramps"]]])
    lake_walk = gaussian_filter(((lake + wobble(2.0, EDGE_WOBBLE_M, 21)) < 0).astype(float), 0.4 * PX) > 0.5
    shore = np.minimum.reduce([rect(*r) for r in P["shore_rects"]])
    shore_walk = gaussian_filter(((shore + wobble(3.0, 0.25, 22)) < 0).astype(float), 0.4 * PX) > 0.5
    return lake_walk, shore_walk & ~lake_walk


if __name__ == "__main__":
    lake_walk, shore_walk = build()
    a = np.zeros((H, W), np.uint8)
    a[shore_walk] = 190
    a[lake_walk] = 255
    img = Image.fromarray(a, "L").convert("RGB")
    dr = ImageDraw.Draw(img)
    for (x, z), col in [(SPAWN, (255, 0, 0)), (EXIT, (0, 255, 0)), (SLOT, (255, 255, 0))]:
        cx, cy = px(x, z); dr.ellipse([cx - 7, cy - 7, cx + 7, cy + 7], fill=col)
    img.save("floor1_walkable_sample.png")
    walk = lake_walk | shore_walk
    print("walkable extent m:", round(np.ptp(walk.any(0).nonzero()[0]) / PX, 1), "x",
          round(np.ptp(walk.any(1).nonzero()[0]) / PX, 1))
