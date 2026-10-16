# Placeholder basking slab for floor 4's Adder: a low, irregular, weathered
# stone slab. glb, metres, Y up, origin at the centre of its base (y = 0).
import numpy as np, trimesh
from PIL import Image
from scipy.ndimage import gaussian_filter

rng = np.random.default_rng(7)
LEN, WID, THICK = 1.75, 1.15, 0.24       # metres
N_ANG, N_RING = 96, 14

# irregular outline: an ellipse-ish shape with soft lumps, slightly flattened on one side
ang = np.linspace(0, 2 * np.pi, N_ANG, endpoint=False)
lumps = sum(rng.uniform(0.02, 0.06) * np.cos(k * ang + rng.uniform(0, 2 * np.pi)) for k in (2, 3, 5))
rad_x = 0.5 * LEN * (1 + lumps)
rad_z = 0.5 * WID * (1 + lumps) * (1 - 0.08 * np.clip(np.sin(ang), 0, 1))   # one flatter edge
verts, uvs = [], []
def add(x, y, z):
    verts.append((x, y, z)); uvs.append((0.5 + x / LEN, 0.5 + z / WID)); return len(verts) - 1
# top: rings from the centre out; gently domed, tilted a few degrees, rounded edge
tilt = np.array([0.03, 0.0])
top = [[add(0.0, THICK, 0.0)]]
for j in range(1, N_RING + 1):
    t = j / N_RING
    ring = []
    for i, a in enumerate(ang):
        x, z = t * rad_x[i] * np.cos(a), t * rad_z[i] * np.sin(a)
        edge_t = np.clip((t - 0.72) / 0.28, 0, 1)
        shoulder = 1 - edge_t * edge_t * (3 - 2 * edge_t)          # flat top, rounded edge
        undulate = 0.012 * np.sin(1.7 * x + 0.6) * np.cos(2.3 * z - 0.4) + 0.008 * np.sin(4.1 * x + 3.1 * z)
        y = max(0.015, THICK * (0.06 + 0.94 * shoulder) * (0.97 + 0.03 * (1 - t * t)) + undulate * shoulder + tilt[0] * x)
        ring.append(add(x, y, z))
    top.append(ring)
# bottom ring and centre, flat at y = 0
bot_ring = [add(rad_x[i] * np.cos(a) * 1.02, 0.0, rad_z[i] * np.sin(a) * 1.02) for i, a in enumerate(ang)]
bot_c = add(0.0, 0.0, 0.0)
faces = []
for i in range(N_ANG):                                   # top fan
    faces.append((top[0][0], top[1][(i + 1) % N_ANG], top[1][i]))
for j in range(1, N_RING):                               # top rings
    for i in range(N_ANG):
        a, b = top[j][i], top[j][(i + 1) % N_ANG]
        c, d = top[j + 1][i], top[j + 1][(i + 1) % N_ANG]
        faces += [(a, b, d), (a, d, c)]
for i in range(N_ANG):                                   # sides
    a, b = top[N_RING][i], top[N_RING][(i + 1) % N_ANG]
    c, d = bot_ring[i], bot_ring[(i + 1) % N_ANG]
    faces += [(a, b, d), (a, d, c)]
for i in range(N_ANG):                                   # bottom fan
    faces.append((bot_c, bot_ring[i], bot_ring[(i + 1) % N_ANG]))

# painted texture: the ground's exposed-rock colour, low-frequency mottling, a few soft seams
S = 256
base = np.array([0.56, 0.59, 0.50])
m = gaussian_filter(rng.standard_normal((S, S)), 18); m = m / np.abs(m).max()
f = gaussian_filter(rng.standard_normal((S, S)), 4);  f = f / np.abs(f).max()
yy, xx = np.mgrid[0:S, 0:S] / S
seam = np.exp(-((yy - 0.42 - 0.08 * np.sin(xx * 7)) ** 2) / 0.0006) * 0.5 + \
       np.exp(-((xx - 0.63 - 0.05 * np.sin(yy * 9)) ** 2) / 0.0004) * 0.35
val = 1 + 0.07 * m + 0.025 * f - 0.10 * seam
tex = np.clip(base[None, None, :] * val[..., None], 0, 1)
img = Image.fromarray((tex * 255 + 0.5).astype(np.uint8), "RGB")
img.save("basking_slab_albedo.png")

mesh = trimesh.Trimesh(vertices=np.array(verts), faces=np.array(faces), process=False)
mesh.fix_normals()
mat = trimesh.visual.material.PBRMaterial(baseColorTexture=img, metallicFactor=0.0, roughnessFactor=1.0)
mesh.visual = trimesh.visual.TextureVisuals(uv=np.array(uvs), material=mat)
mesh.export("basking_slab.glb")
b = mesh.bounds
print("bounds (m): x", np.round(b[:, 0], 3), " y", np.round(b[:, 1], 3), " z", np.round(b[:, 2], 3), " tris", len(faces), " watertight", mesh.is_watertight)
