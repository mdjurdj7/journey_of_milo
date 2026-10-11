"""Usage: blender -b --factory-startup --python tools/bake_ao_blender.py -- <model.glb> <out.npy> [samples] [distance_m]  (run by paint_texture.py --blender)

Bakes Cycles ambient occlusion onto the mesh's vertices in its bind pose
(armature modifiers dropped) and saves one float32 row per vertex:
x, y, z (glTF axes, Y up) and the AO, averaged over the vertex's corners.
paint_texture.py matches the rows to the glb's own vertices by position.
"""
import sys

import bpy
import numpy as np

args = sys.argv[sys.argv.index("--") + 1:]
model, out = args[0], args[1]
samples = int(args[2]) if len(args) > 2 else 64
distance = float(args[3]) if len(args) > 3 else 0.08

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=model)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = samples
scene.world = bpy.data.worlds.new("AO")
scene.world.light_settings.distance = distance

rows = []
# The glTF importer parks non-exported helpers in an excluded collection;
# baking needs every selected object to be visible.
for obj in [o for o in scene.objects if o.type == "MESH" and o.visible_get()]:
    for modifier in list(obj.modifiers):
        obj.modifiers.remove(modifier)
    mesh = obj.data
    attribute = mesh.color_attributes.new("AO", "FLOAT_COLOR", "CORNER")
    mesh.color_attributes.active_color = attribute
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.bake(type="AO", target="VERTEX_COLORS")

    corner_ao = np.zeros(len(mesh.loops) * 4, np.float32)
    attribute.data.foreach_get("color", corner_ao)
    corner_ao = corner_ao.reshape(-1, 4)[:, 0]
    corner_vertex = np.zeros(len(mesh.loops), np.int64)
    mesh.loops.foreach_get("vertex_index", corner_vertex)
    co = np.zeros(len(mesh.vertices) * 3, np.float32)
    mesh.vertices.foreach_get("co", co)
    world = np.array(obj.matrix_world)
    co = co.reshape(-1, 3) @ world[:3, :3].T + world[:3, 3]
    total = np.bincount(corner_vertex, corner_ao, len(co))
    count = np.bincount(corner_vertex, minlength=len(co))
    ao = total / np.maximum(count, 1)
    # Blender is Z up: back to glTF's (x, z, -y).
    rows.append(np.column_stack([co[:, 0], co[:, 2], -co[:, 1], ao]))

np.save(out, np.concatenate(rows).astype(np.float32))
print("bake_ao_blender: %d vertices baked" % sum(len(r) for r in rows))
