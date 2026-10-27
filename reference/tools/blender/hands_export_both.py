# Headless: export ONE hand of the FBX to IQM, with its OWN skeleton, its OWN weights and its OWN
# animation, every frame. Run once per hand.
#   blender --background --factory-startup --python hands_export_both.py -- <in.fbx> <out.iqm> <A|B>
#
#   A = Hand_Low on Armature (the unmirrored controls).
#   B = the second hand: Armature.001 under the -1 scaled controls, with Hand_Low1's own skin
#       weights. Blender's FBX import leaves Hand_Low1 unbound (its vertices are identical to
#       Hand_Low's, index for index; its weights and face order are its own). So B is built from
#       Hand_Low's vertex positions and faces with Hand_Low1's weights, placed under Armature.001
#       the way Hand_Low sits under Armature. NOTHING of A's animation is used for B.
#       B is written UNMIRRORED (iqm_export_rs.WORLD_FIX = mirror in X), so its data are proper
#       rotations; draw it with a negative X scale in MODELDEF to put the mirror back.
import bpy, sys, os, importlib.util
from mathutils import Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
src, out, which = argv[0], argv[1], argv[2].upper()
here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("iqm_export_rs", os.path.join(here, "iqm_export_rs.py"))
iqm = importlib.util.module_from_spec(spec); spec.loader.exec_module(iqm)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=src, automatic_bone_orientation=False, use_anim=True)
scene = bpy.context.scene
A_arm = bpy.data.objects["Armature"]; B_arm = bpy.data.objects["Armature.001"]
A_mesh = bpy.data.objects["Hand_Low"]; B_src = bpy.data.objects["Hand_Low1"]

# Full take: the scene's frames are 1..1279; the armature actions stop at 1278.
last = 1
for a in bpy.data.actions: last = max(last, int(round(a.frame_range[1])))
iqm.FRAME_RANGE = (1, last)
print("FRAMES", 1, last)

if which == "A":
    arm, mesh = A_arm, A_mesh
    for ob in (B_src, B_arm): bpy.data.objects.remove(ob, do_unlink=True)
    iqm.WORLD_FIX = Matrix.Identity(4)
elif which == "B":
    data = A_mesh.data.copy(); data.name = "Hand_B_mesh"
    mesh = bpy.data.objects.new("Hand_B", data)
    scene.collection.objects.link(mesh)
    # B's own weights, by vertex index (positions are identical index for index; checked).
    for g in list(mesh.vertex_groups): mesh.vertex_groups.remove(g)
    names = [g.name for g in B_src.vertex_groups]
    groups = {n: mesh.vertex_groups.new(name=n) for n in names}
    nset = 0
    for v in B_src.data.vertices:
        for g in v.groups:
            if g.weight > 0.0:
                groups[names[g.group]].add([v.index], g.weight, 'REPLACE'); nset += 1
    print("B WEIGHTS copied", nset, "entries over", len(names), "groups")
    # Weights differ from A? Report, so the owner can see B is not A.
    diff = 0.0
    for v in B_src.data.vertices:
        wb = {names[g.group]: g.weight for g in v.groups}
        wa = {A_mesh.vertex_groups[g.group].name: g.weight for g in A_mesh.data.vertices[v.index].groups}
        for k in set(wa) | set(wb): diff = max(diff, abs(wa.get(k, 0.0) - wb.get(k, 0.0)))
    print("B vs A max weight difference", round(diff, 6))
    mesh.parent = B_arm
    mesh.matrix_parent_inverse = A_mesh.matrix_parent_inverse.copy()
    mesh.location, mesh.rotation_euler, mesh.scale = A_mesh.location.copy(), A_mesh.rotation_euler.copy(), A_mesh.scale.copy()
    mod = mesh.modifiers.new("Armature", 'ARMATURE'); mod.object = B_arm
    for m in A_mesh.data.materials: pass
    arm = B_arm
    for ob in (A_mesh, B_src, A_arm): bpy.data.objects.remove(ob, do_unlink=True)
    iqm.WORLD_FIX = Matrix.Scale(-1.0, 4, (1.0, 0.0, 0.0))
else:
    raise SystemExit("which must be A or B")

for ob in bpy.context.view_layer.objects: ob.select_set(False)
arm.select_set(True); mesh.select_set(True)
bpy.context.view_layer.objects.active = arm
print("HAND", which, "armature", arm.name, "action", arm.animation_data.action.name if arm.animation_data and arm.animation_data.action else None,
      "mesh", mesh.name, len(mesh.data.vertices), "verts", len(mesh.data.polygons), "polys")
iqm.exportIQM(bpy.context, out, "IQM", usemesh=True, usemods=False, usebbox=True, usecol=False, scale=1.0)
print("EXPORT_OK", which, out, os.path.getsize(out) if os.path.exists(out) else -1)
