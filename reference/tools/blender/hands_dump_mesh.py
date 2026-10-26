# Headless: the deformed hand meshes' world vertices at chosen frames, straight from Blender.
#   blender --background --factory-startup --python hands_dump_mesh.py -- <in.fbx> <out.json> <f,f,...>
# Hand A is the FBX's own binding. Hand B is built as hands_export_both.py builds it.
import bpy, sys, json, os, importlib.util
argv = sys.argv[sys.argv.index("--") + 1:]
src, out, frames = argv[0], argv[1], [int(x) for x in argv[2].split(",")]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=src, automatic_bone_orientation=False, use_anim=True)
scene = bpy.context.scene
A = bpy.data.objects["Hand_Low"]; Bs = bpy.data.objects["Hand_Low1"]; Ba = bpy.data.objects["Armature.001"]
data = A.data.copy(); B = bpy.data.objects.new("Hand_B", data); scene.collection.objects.link(B)
for g in list(B.vertex_groups): B.vertex_groups.remove(g)
names = [g.name for g in Bs.vertex_groups]; groups = {n: B.vertex_groups.new(name=n) for n in names}
for v in Bs.data.vertices:
    for g in v.groups:
        if g.weight > 0: groups[names[g.group]].add([v.index], g.weight, 'REPLACE')
B.parent = Ba; B.matrix_parent_inverse = A.matrix_parent_inverse.copy()
B.location, B.rotation_euler, B.scale = A.location.copy(), A.rotation_euler.copy(), A.scale.copy()
B.modifiers.new("Armature", 'ARMATURE').object = Ba
res = {"frames": {}}
for fr in frames:
    scene.frame_set(fr)
    dg = bpy.context.evaluated_depsgraph_get()
    res["frames"][fr] = {}
    for tag, ob in (("A", A), ("B", B)):
        e = ob.evaluated_get(dg); me = e.to_mesh()
        res["frames"][fr][tag] = [[round(c, 7) for c in (e.matrix_world @ v.co)] for v in me.vertices]
        e.to_mesh_clear()
with open(out, "w") as f: json.dump(res, f)
print("MESHDUMP_OK", frames)
