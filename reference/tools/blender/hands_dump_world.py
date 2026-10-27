# Headless: every joint's WORLD position, every frame, for both FBX hands, straight from the FBX.
# The reference the exported IQMs are checked against.
#   blender --background --factory-startup --python hands_dump_world.py -- <in.fbx> <out.json>
import bpy, sys, json
argv = sys.argv[sys.argv.index("--") + 1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=argv[0], automatic_bone_orientation=False, use_anim=True)
scene = bpy.context.scene
last = 1
for a in bpy.data.actions: last = max(last, int(round(a.frame_range[1])))
out = {"first": 1, "last": last, "hands": {}}
for tag, name in (("A", "Armature"), ("B", "Armature.001")):
    arm = bpy.data.objects[name]
    out["hands"][tag] = {"bones": [pb.name for pb in arm.pose.bones], "frames": []}
for fr in range(1, last + 1):
    scene.frame_set(fr)
    for tag, name in (("A", "Armature"), ("B", "Armature.001")):
        arm = bpy.data.objects[name]
        row = []
        for pb in arm.pose.bones:
            p = arm.matrix_world @ pb.head
            row.append([round(p.x, 7), round(p.y, 7), round(p.z, 7)])
        out["hands"][tag]["frames"].append(row)
with open(argv[1], "w") as f: json.dump(out, f)
print("DUMP_OK", last)
