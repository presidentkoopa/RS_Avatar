# Headless: armature-space rest and posed matrices of every bone, both FBX hands, at chosen frames.
#   blender --background --factory-startup --python hands_dump_pose_mats.py -- <in.fbx> <out.json> <f,f,...>
# Armature space is below the (possibly mirrored) controls, so both hands are the same-handed skeleton
# here; the tool that reads this mirrors hand B itself to make it the other side.
import bpy, sys, json
argv = sys.argv[sys.argv.index("--") + 1:]
src, out, frames = argv[0], argv[1], [int(x) for x in argv[2].split(",")]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=src, automatic_bone_orientation=False, use_anim=True)
scene = bpy.context.scene
M = lambda m: [[round(m[i][j], 8) for j in range(4)] for i in range(4)]
res = {"hands": {}}
for tag, name in (("A", "Armature"), ("B", "Armature.001")):
    arm = bpy.data.objects[name]
    res["hands"][tag] = {"bones": [b.name for b in arm.data.bones],
                         "parent": [b.parent.name if b.parent else None for b in arm.data.bones],
                         "rest": [M(b.matrix_local) for b in arm.data.bones],
                         "world_det": arm.matrix_world.to_3x3().determinant(),
                         "frames": {}}
for fr in frames:
    scene.frame_set(fr)
    for tag, name in (("A", "Armature"), ("B", "Armature.001")):
        arm = bpy.data.objects[name]
        res["hands"][tag]["frames"][fr] = [M(arm.pose.bones[b.name].matrix) for b in arm.data.bones]
with open(out, "w") as f: json.dump(res, f)
print("POSEMATS_OK", len(frames))
