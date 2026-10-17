# The Greyshelf's colour map, painted on his body - the worked example of
# editing a fragmented (Meshy) colour map by region in 3D.
#
#   blender -b --python tools/texel_bake_blender.py -- assets/models/enemies/Greyshelf/Greyshelf.glb 2048 <bake_dir>
#   blender -b --python tools/greyshelf_paint_blender.py -- assets/models/enemies/Greyshelf/Greyshelf_colour_v1.png <out.png> <bake_dir>
#   python -c "from PIL import Image; Image.open('<out.png>').save('<out.png>', optimize=True)"
#
# (blender = "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe")
#
# Reads the first-pass map (Greyshelf_colour_v1.png - flat painted masses,
# never written) and the texel bake, and paints, per covered texel:
#   1. countershading - down-facing and low surfaces (belly, under the
#      jaw, inner limbs) paler toward BELLY, by value only, hue kept;
#   2. the old soft blue blob taken out, and a shaped throat patch put
#      in: the head's underside from the chin to the fold behind the jaw
#      (FOLD_Y, sweeping back up the neck), its sides where the surface
#      turns from facing down, a few faint transverse folds in it; its
#      colour the first pass's blue at THROAT_DESATURATE toward grey;
#   3. scale breakup - jittered 3D cells, larger on the back, smaller on
#      limbs and neck, a few percent of value, off the scutes;
#   4. eyes - a dark iris, a dark lid and brow shadow over its top third
#      and up above it, a thin pale edge on the lower lid only;
#   5. any warm cast neutralised toward cool slate.
# Each change is carried a few texels into the islands' padding, so
# mipmaps don't bleed the old values at the seams. Positions are Blender
# object space (Z up, the head toward -Y), metres before model_scale.
#
# For another model, keep the frame (load, masks on P/N/C, padding, save)
# and replace the region steps; find features such as eyes in the source
# map (git history is LFS: git show <rev>:<path> | git lfs smudge > f).
import os
import sys

import bpy
import numpy as np

src, dst, bake = (os.path.abspath(a) for a in sys.argv[-3:])

BELLY = 0.40               # the paler underside's value (the sand is ~0.70)
THROAT_DESATURATE = 0.35   # the throat's blue, this far toward its grey
CHIN_Y = -1.80             # the throat patch, from the chin...
FOLD_Y = -1.32             # ...to the fold behind the jaw, at its lowest
FOLD_SWEEP = 0.45          # metres back per metre up the neck's side
FOLD_SOFT = 0.008          # its end's soft edge, metres
FOLD_CREASE = 0.12         # the fold's crease just behind it, this much darker
# The jaw line the patch stays under: the head's underside rises from
# JAW_LOW (z at the fold) to JAW_CHIN (at the chin), and the patch runs
# at most JAW_REACH over it - never up the jaw's side to the eye.
JAW_LOW, JAW_CHIN, JAW_REACH = 0.40, 0.68, 0.11
EYES = [                   # centre, outward facing (from the source map)
    (np.array([0.108, -1.527, 0.816]), np.array([0.93, -0.28, -0.23])),
    (np.array([-0.17, -1.48, 0.824]), np.array([-0.93, -0.29, -0.23])),
]
IRIS_R = 0.030
IRIS = np.array([0.065, 0.07, 0.075], np.float32)
LID = np.array([0.10, 0.105, 0.11], np.float32)
LOWER_LID = np.array([0.42, 0.425, 0.43], np.float32)
LOWER_LID_W = 0.007

pos = np.load(os.path.join(bake, "pos.npy"))
nrm = np.load(os.path.join(bake, "nrm.npy"))
cov = np.load(os.path.join(bake, "cov.npy")) > 0
img = bpy.data.images.load(src)
img.colorspace_settings.name = 'Non-Color'
W, H = img.size
orig = np.array(img.pixels[:], dtype=np.float32).reshape(H, W, 4)[::-1][..., :3].copy()
LUMA = np.array([0.299, 0.587, 0.114], np.float32)


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def luma(c):
    return c @ LUMA


P = pos[cov]
N = nrm[cov]
C = orig[cov].copy()
lum = luma(C)
zn = P[:, 2] / 1.2
old_blue = smoothstep(0.03, 0.09, C[:, 2] - 0.5 * (C[:, 0] + C[:, 1]))
scute = smoothstep(0.30, 0.38, lum) * smoothstep(0.2, 0.5, N[:, 2]) * (1.0 - old_blue)

# The throat's colour: the first pass's blue, quieted.
strong = old_blue > 0.9
blue_rgb = C[strong].mean(axis=0)
blue_rgb = blue_rgb + (luma(blue_rgb) - blue_rgb) * THROAT_DESATURATE
blue_ratio = blue_rgb / luma(blue_rgb)

# 2a. The old blob out, its faint airbrushed tail too: every texel bluer
# than grey back to its own grey.
blue_tail = smoothstep(0.004, 0.035, C[:, 2] - 0.5 * (C[:, 0] + C[:, 1]))
C = C + (lum[:, None] - C) * blue_tail[:, None]

# 1. Countershading, value only.
down = smoothstep(0.15, -0.7, N[:, 2])
low = smoothstep(0.50, 0.12, zn) * (1.0 - smoothstep(0.1, 0.6, N[:, 2]))
shade_t = np.maximum(down, 0.75 * low) * (1.0 - scute)
lum = luma(C)
new_lum = lum + np.clip(BELLY - lum, 0.0, None) * shade_t * 0.85
C = C * (new_lum / np.maximum(lum, 1e-4))[:, None]

# 2b. The throat patch: the head's underside, chin to fold.
fold_y = FOLD_Y - FOLD_SWEEP * np.clip(P[:, 2] - 0.38, 0.0, None)
along = smoothstep(CHIN_Y - 0.03, CHIN_Y + 0.02, P[:, 1]) * (1.0 - smoothstep(fold_y - FOLD_SOFT, fold_y, P[:, 1]))
facing = smoothstep(-0.33, -0.39, N[:, 2])
jaw_z = JAW_LOW + (JAW_CHIN - JAW_LOW) * np.clip((FOLD_Y - P[:, 1]) / (FOLD_Y - CHIN_Y), 0.0, 1.0)
under_jaw = 1.0 - smoothstep(jaw_z + JAW_REACH - 0.02, jaw_z + JAW_REACH, P[:, 2])
throat = along * facing * under_jaw * smoothstep(0.33, 0.36, P[:, 2]) * (np.abs(P[:, 0]) < 0.32)
# A few transverse folds, faint, following the patch.
folds = 1.0 - 0.07 * (0.5 + 0.5 * np.cos((P[:, 1] - CHIN_Y) / 0.07 * 2.0 * np.pi + 0.8 * np.sin(P[:, 0] * 18.0)))
lum = luma(C)
C = C + ((lum * folds)[:, None] * blue_ratio - C) * throat[:, None]
# The fold itself: a thin crease just behind the patch's end, a touch
# darker, so the patch reads as ending at it.
behind = P[:, 1] - fold_y
crease = smoothstep(0.0, 0.006, behind) * (1.0 - smoothstep(0.012, 0.028, behind))
crease *= facing * under_jaw * smoothstep(0.33, 0.36, P[:, 2]) * (np.abs(P[:, 0]) < 0.32)
C = C * (1.0 - FOLD_CREASE * crease)[:, None]
print("THROAT texels %d (old blob %d)" % (int((throat > 0.5).sum()), int((old_blue > 0.5).sum())))


# 3. Scale breakup.
def cells(points, size, seed):
    q = points / size
    base = np.floor(q).astype(np.int64)
    f1 = np.full(len(q), 9.0)
    f2 = np.full(len(q), 9.0)
    cell_id = np.zeros(len(q))
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            for dz in (-1, 0, 1):
                c = base + np.array([dx, dy, dz])
                h = (c[:, 0] * 73856093) ^ (c[:, 1] * 19349663) ^ (c[:, 2] * 83492791) ^ seed
                h = (h * 2654435761) & 0xFFFFFFFF
                jitter = np.stack([((h >> s) & 1023) / 1023.0 for s in (0, 10, 20)], axis=-1)
                d = np.linalg.norm(q - (c + 0.15 + 0.7 * jitter), axis=-1)
                closer = d < f1
                f2 = np.where(closer, f1, np.minimum(f2, d))
                cell_id = np.where(closer, ((h >> 7) & 255) / 255.0, cell_id)
                f1 = np.where(closer, d, f1)
    return f2 - f1, cell_id


back = smoothstep(0.45, 0.85, zn) * smoothstep(-0.1, 0.5, N[:, 2])
neck = smoothstep(-1.0, -1.35, P[:, 1])
big = back * (1.0 - neck)
edge_s, id_s = cells(P, 0.032, 11)
edge_b, id_b = cells(P, 0.085, 23)
edge = big * edge_b + (1.0 - big) * edge_s
cell_id = big * id_b + (1.0 - big) * id_s
breakup = 1.0 - 0.07 * (1.0 - smoothstep(0.0, 0.18, edge)) + 0.035 * (cell_id - 0.5)
C = C * (1.0 + (breakup - 1.0) * (1.0 - scute))[:, None]

# 4. Eyes: iris, a heavy lid over its top third, a pale lower-lid edge.
up = np.array([0.0, 0.0, 1.0])
for centre, out_dir in EYES:
    f = out_dir / np.linalg.norm(out_dir)
    u = up - f * (up @ f)
    u /= np.linalg.norm(u)
    s = np.cross(f, u)
    side = (N @ f) > 0.2
    o = P - centre
    r = np.linalg.norm(o, axis=-1)
    v = (o @ u) / IRIS_R          # up the eye, in iris radii
    w = (o @ s) / IRIS_R          # across it
    soft = 0.004
    iris = (1.0 - smoothstep(IRIS_R - soft, IRIS_R, r)) * side
    # The lid and brow: from a third down the iris, up and over it, fading
    # above and to the sides.
    lid = smoothstep(0.2, 0.42, v) * (1.0 - smoothstep(1.6, 2.6, v)) * (1.0 - smoothstep(1.3, 1.9, np.abs(w))) * side
    lid_core = lid * (1.0 - smoothstep(1.0, 1.6, v))
    lower = (smoothstep(IRIS_R - soft, IRIS_R, r) * (1.0 - smoothstep(IRIS_R + LOWER_LID_W - 0.003, IRIS_R + LOWER_LID_W, r))
             * smoothstep(-0.15, -0.55, v) * side)
    C = C + (IRIS - C) * iris[:, None]
    C = C + (LOWER_LID - C) * lower[:, None]
    C = C + (LID - C) * lid_core[:, None]
    C = C * (1.0 - 0.45 * (lid - lid_core))[:, None]
    print("EYE iris %d lid %d lower lid %d texels" % (int((iris > 0.5).sum()), int((lid_core > 0.5).sum()), int((lower > 0.5).sum())))

# 5. Nothing warm.
chroma = C - luma(C)[:, None]
warm = np.clip(chroma[:, 0] - chroma[:, 2], 0.0, None)
C[:, 0] -= warm * 0.6
C[:, 2] += warm * 0.4
C = np.clip(C, 0.0, 1.0)

out = orig.copy()
out[cov] = C
delta = np.zeros_like(out)
delta[cov] = out[cov] - orig[cov]
have = cov.copy()
for i in range(6):
    acc = np.zeros_like(delta)
    cnt = np.zeros(have.shape, np.float32)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        acc += np.roll(np.roll(delta, dy, 0), dx, 1) * np.roll(np.roll(have, dy, 0), dx, 1)[..., None]
        cnt += np.roll(np.roll(have, dy, 0), dx, 1)
    grow = (~have) & (cnt > 0)
    delta[grow] = acc[grow] / cnt[grow][:, None]
    have |= grow
pad = have & ~cov
out[pad] = np.clip(orig[pad] + delta[pad], 0.0, 1.0)

res = np.concatenate([out, np.ones((H, W, 1), np.float32)], axis=-1)[::-1]
image = bpy.data.images.new("out", W, H, alpha=False, float_buffer=False)
image.colorspace_settings.name = 'Non-Color'
image.pixels.foreach_set(res.astype(np.float32).ravel())
image.filepath_raw = dst
image.file_format = 'PNG'
image.save()
final = luma(out[cov])
print("greyshelf_paint: value mean %.3f, p10 %.3f, p90 %.3f -> %s" % (final.mean(), np.percentile(final, 10), np.percentile(final, 90), dst))
