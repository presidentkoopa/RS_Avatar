# Headless: render chosen frames of the FBX hands, both hands, to PNGs for a contact sheet.
#   blender --background --factory-startup --python fbx_contact.py -- <in.fbx> <out_dir> <frame,frame,...>
# The second mesh (Hand_Low1) ships unbound; it is bound to Armature.001 by its vertex groups here.
import bpy, sys, os, math
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
src, outdir, frames = argv[0], argv[1], [int(x) for x in argv[2].split(",")]
os.makedirs(outdir, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=src, automatic_bone_orientation=False, use_anim=True)
scene = bpy.context.scene

meshes = {ob.name: ob for ob in bpy.data.objects if ob.type == 'MESH'}
arms = {ob.name: ob for ob in bpy.data.objects if ob.type == 'ARMATURE'}
# THE LEFT HAND IS THE SAME MESH ON THE MIRRORED SKELETON. The FBX carries one skinned hand
# (Hand_Low on Armature) and a second skeleton under a -1 scaled control (Armature.001); its own
# mesh (Hand_Low1) is an unbound copy. So the left is Hand_Low duplicated onto Armature.001 with
# the same local placement, and Hand_Low1 is dropped.
h1 = meshes.get("Hand_Low"); a2 = arms.get("Armature.001")
if "Hand_Low1" in meshes:
    bpy.data.objects.remove(meshes.pop("Hand_Low1"), do_unlink=True)
if h1 and a2:
    h2 = h1.copy(); h2.data = h1.data; h2.name = "Hand_Left"
    scene.collection.objects.link(h2)
    h2.parent = a2
    h2.matrix_parent_inverse = h1.matrix_parent_inverse.copy()
    h2.location, h2.rotation_euler, h2.scale = h1.location.copy(), h1.rotation_euler.copy(), h1.scale.copy()
    for m in h2.modifiers:
        if m.type == 'ARMATURE': m.object = a2
    meshes["Hand_Left"] = h2
    print("LEFT HAND = Hand_Low on Armature.001")

scene.render.engine = 'BLENDER_WORKBENCH'
scene.display.shading.light = 'STUDIO'
scene.display.shading.color_type = 'SINGLE'
scene.render.resolution_x = 512; scene.render.resolution_y = 384
scene.render.film_transparent = False
cam_data = bpy.data.cameras.new("cam"); cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam); scene.camera = cam
cam_data.type = 'ORTHO'

def frame_bounds():
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for ob in meshes.values():
        e = ob.evaluated_get(dg); me = e.to_mesh()
        pts += [e.matrix_world @ v.co for v in me.vertices]
        e.to_mesh_clear()
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi

for fr in frames:
    scene.frame_set(fr)
    lo, hi = frame_bounds(); c = (lo + hi) / 2; size = max(max(hi - lo), 1e-4)
    cam_data.clip_start = size * 0.01; cam_data.clip_end = size * 10.0
    print("FRAME", fr, "size", round(size, 4), "centre", [round(x, 3) for x in c])
    for view, d in (("side", Vector((0, -1, 0))), ("top", Vector((0, 0, 1)))):
        cam.location = c + d * size * 3
        cam.rotation_euler = (d * -1).to_track_quat('-Z', 'Y').to_euler()
        cam_data.ortho_scale = size * 1.15
        scene.render.filepath = os.path.join(outdir, "f%04d_%s.png" % (fr, view))
        bpy.ops.render.render(write_still=True)
print("CONTACT_OK", len(frames))
