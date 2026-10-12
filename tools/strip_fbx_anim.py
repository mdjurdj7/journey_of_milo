"""Usage: blender -b --factory-startup --python tools/strip_fbx_anim.py -- <in.fbx> <out.fbx>  (an animation clip down to its skeleton and keys)

Re-exports a clip FBX that ships with its skin (Meshy's *_withSkin.fbx:
~27 MB each) as the armature and its one action alone - no mesh, no
materials, no textures, so Godot extracts nothing beside it on import.
The export bakes the action's own frame range, not the scene's default
1-250, so the clip keeps its length. The Wanderer's Idle, Walk and Run
(assets/models/wanderer/wanderer_v3_*.fbx) are made with it.
"""
import sys

import bpy

source, out = sys.argv[sys.argv.index("--") + 1:][:2]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=source)
for obj in list(bpy.context.scene.objects):
    if obj.type != "ARMATURE":
        bpy.data.objects.remove(obj, do_unlink=True)
for blocks in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.textures):
    for block in list(blocks):
        blocks.remove(block)
armature = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"][0]
action = armature.animation_data.action if armature.animation_data else None
if action is not None:
    bpy.context.scene.frame_start, bpy.context.scene.frame_end = int(action.frame_range[0]), int(action.frame_range[1])
print("armature %s: %d bones, action %s, frames %s at %d fps" % (
    armature.name, len(armature.data.bones), action.name if action else None,
    tuple(action.frame_range) if action else None, bpy.context.scene.render.fps))
bpy.ops.export_scene.fbx(filepath=out, object_types={"ARMATURE"}, use_selection=False, add_leaf_bones=False,
                         bake_anim=True, bake_anim_use_all_actions=False, bake_anim_use_nla_strips=False,
                         bake_anim_simplify_factor=0.0, path_mode="STRIP", embed_textures=False)
