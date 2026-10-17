# Texel bake: where on the model each texel of its colour map lies.
#
#   "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --python tools/texel_bake_blender.py -- <model.glb> <size> <out_dir>
#
# Imports the glb, rasterises every UV triangle of its (first) mesh at
# <size> x <size> and writes, in <out_dir>:
#   pos.npy  (size, size, 3) float32 - each texel's object-space position
#   nrm.npy  (size, size, 3) float32 - its smooth normal, unit length
#   cov.npy  (size, size)    uint8   - 1 where a triangle covers it
# Row 0 is the image's top (v = 1). Blender object space: Z up; check
# which end the head is at (a glb's forward lands on Blender's -Y or +Y).
#
# For colour maps whose UVs are thousands of small islands (Meshy
# models): an image-space blur or mask mixes unrelated islands, so edits
# by body region - countershading, eyes, a throat patch, scale cells -
# are made per texel in 3D from these arrays instead (see
# tools/greyshelf_paint_blender.py). Runs in Blender's bundled Python,
# which has numpy; the system Python here has Pillow only. 11k faces at
# 2048 take a few seconds.
import os
import sys

import bpy
import numpy as np

glb, size, out = sys.argv[-3], int(sys.argv[-2]), sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
ob = [o for o in bpy.data.objects if o.type == 'MESH'][0]
me = ob.data
me.calc_loop_triangles()
uv = me.uv_layers.active.data
co = np.array([v.co[:] for v in me.vertices], dtype=np.float32)
vn = np.array([v.normal[:] for v in me.vertices], dtype=np.float32)

pos = np.zeros((size, size, 3), np.float32)
nrm = np.zeros((size, size, 3), np.float32)
cov = np.zeros((size, size), np.uint8)
for tri in me.loop_triangles:
    vids = list(tri.vertices)
    uvs = np.array([uv[l].uv[:] for l in tri.loops], dtype=np.float64)
    # Pixel space: x right, y down (row 0 = v 1), texel centres at +0.5.
    px = uvs[:, 0] * size - 0.5
    py = (1.0 - uvs[:, 1]) * size - 0.5
    x0, x1 = max(int(np.floor(px.min())) - 1, 0), min(int(np.ceil(px.max())) + 1, size - 1)
    y0, y1 = max(int(np.floor(py.min())) - 1, 0), min(int(np.ceil(py.max())) + 1, size - 1)
    if x1 < x0 or y1 < y0:
        continue
    gx, gy = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
    d = (py[1] - py[2]) * (px[0] - px[2]) + (px[2] - px[1]) * (py[0] - py[2])
    if abs(d) < 1e-12:
        continue
    l0 = ((py[1] - py[2]) * (gx - px[2]) + (px[2] - px[1]) * (gy - py[2])) / d
    l1 = ((py[2] - py[0]) * (gx - px[2]) + (px[0] - px[2]) * (gy - py[2])) / d
    l2 = 1.0 - l0 - l1
    # A hair outside each edge too, so islands' rims are covered.
    eps = 0.02
    inside = (l0 >= -eps) & (l1 >= -eps) & (l2 >= -eps)
    if not inside.any():
        continue
    w = np.clip(np.stack([l0[inside], l1[inside], l2[inside]], axis=-1), 0.0, 1.0)
    w /= w.sum(axis=-1, keepdims=True)
    ys, xs = gy[inside], gx[inside]
    pos[ys, xs] = w @ co[vids]
    nrm[ys, xs] = w @ vn[vids]
    cov[ys, xs] = 1
length = np.linalg.norm(nrm, axis=-1, keepdims=True)
nrm = np.where(length > 1e-6, nrm / np.maximum(length, 1e-6), 0.0).astype(np.float32)
os.makedirs(out, exist_ok=True)
np.save(os.path.join(out, "pos.npy"), pos)
np.save(os.path.join(out, "nrm.npy"), nrm)
np.save(os.path.join(out, "cov.npy"), cov)
print("texel_bake: %d x %d, %d texels covered, into %s" % (size, size, int(cov.sum()), out))
