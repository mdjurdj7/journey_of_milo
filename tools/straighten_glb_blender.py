"""Usage: blender -b --factory-startup --python tools/straighten_glb_blender.py -- <in.glb> <out.glb> [shaft_from] [shaft_to]

Straightens a long prop modelled at a slant (the Gaff Hook): fits a line
through the centres of its cross-sections between shaft_from and shaft_to
(fractions of its height, glTF Y; defaults 0.1 and 0.7 - clear of a loop
at one end and a head at the other), turns the whole mesh so that line
runs up +Y, then moves it so the line passes through X = Z = 0 and its
lowest point sits at Y = 0. Materials and their images go out as they came
in (embedded, unconverted, under their own names). Prints the bounds
before and after, in glTF axes (Y up).
"""
import sys

import bpy
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1:]
source, target = args[0], args[1]
shaft_from = float(args[2]) if len(args) > 2 else 0.1
shaft_to = float(args[3]) if len(args) > 3 else 0.7

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=source)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]


def world_vertices():
    points = []
    for obj in meshes:
        points.extend(obj.matrix_world @ v.co for v in obj.data.vertices)
    return points


def gltf_bounds(points):
    # Blender is Z up: glTF's (x, y, z) is Blender's (x, z, -y).
    lo = Vector((min(p.x for p in points), min(p.z for p in points), min(-p.y for p in points)))
    hi = Vector((max(p.x for p in points), max(p.z for p in points), max(-p.y for p in points)))
    return lo, hi


points = world_vertices()
lo, hi = gltf_bounds(points)
print("straighten: before %s .. %s size %s" % (tuple(round(c, 4) for c in lo), tuple(round(c, 4) for c in hi), tuple(round(c, 4) for c in hi - lo)))

# Cross-section centres along Blender Z (glTF Y), every 2 cm of the shaft.
z_lo = min(p.z for p in points)
z_hi = max(p.z for p in points)
height = z_hi - z_lo
centres = []
z = z_lo + height * shaft_from
step = height * 0.02
while z < z_lo + height * shaft_to:
    band = [p for p in points if z <= p.z < z + step]
    if band:
        cx = (min(p.x for p in band) + max(p.x for p in band)) / 2.0
        cy = (min(p.y for p in band) + max(p.y for p in band)) / 2.0
        centres.append(Vector((cx, cy, z + step / 2.0)))
    z += step

# Least squares x(z), y(z).
n = len(centres)
mz = sum(c.z for c in centres) / n
mx = sum(c.x for c in centres) / n
my = sum(c.y for c in centres) / n
szz = sum((c.z - mz) ** 2 for c in centres)
ax = sum((c.z - mz) * (c.x - mx) for c in centres) / szz
ay = sum((c.z - mz) * (c.y - my) for c in centres) / szz
direction = Vector((ax, ay, 1.0)).normalized()
tilt = direction.angle(Vector((0.0, 0.0, 1.0)))
print("straighten: shaft line through %d sections, %.2f deg off upright" % (n, tilt * 57.29578))

# Turn about a point on the line, then put the line on X = Z = 0 (glTF)
# and the lowest point on the floor.
pivot = Vector((mx, my, mz))
turn = direction.rotation_difference(Vector((0.0, 0.0, 1.0))).to_matrix().to_4x4()
move = Matrix.Translation(pivot) @ turn @ Matrix.Translation(-pivot)
for obj in meshes:
    obj.data.transform(move @ obj.matrix_world)
    obj.matrix_world = Matrix.Identity(4)
    obj.parent = None
turned = world_vertices()
floor = min(p.z for p in turned)
shift = Matrix.Translation(Vector((-pivot.x, -pivot.y, -floor)))
for obj in meshes:
    obj.data.transform(shift)
    obj.data.update()

lo, hi = gltf_bounds(world_vertices())
print("straighten: after %s .. %s size %s" % (tuple(round(c, 4) for c in lo), tuple(round(c, 4) for c in hi), tuple(round(c, 4) for c in hi - lo)))

# The importer names a glb's unnamed images Image_<n>; back to <n>, so
# Godot's extraction lands on the files it made of the original
# (<model>_<n>.jpg) rather than beside them.
for image in bpy.data.images:
    if image.name.startswith("Image_") and image.name[6:].isdigit():
        image.name = image.name[6:]

# Only the meshes go out - the importer's empties and helpers stay behind.
for obj in list(bpy.context.scene.objects):
    if obj.type != "MESH":
        bpy.data.objects.remove(obj)
bpy.ops.export_scene.gltf(filepath=target, export_format="GLB", export_image_format="AUTO", export_yup=True)
print("straighten: wrote %s" % target)
