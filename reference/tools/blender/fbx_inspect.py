# Headless: import an FBX, report what is in it, and dump every bone's local rotation for every frame.
#   blender --background --factory-startup --python fbx_inspect.py -- <in.fbx> <out_dir>
# Writes <out_dir>/inspect.json (structure) and <out_dir>/frames.json (per-frame local pose per armature).
import bpy, sys, json, os, math

argv = sys.argv[sys.argv.index("--") + 1:]
src, outdir = argv[0], argv[1]
os.makedirs(outdir, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=src, automatic_bone_orientation=False, use_anim=True)

scene = bpy.context.scene
info = {"file": src, "fps": scene.render.fps / scene.render.fps_base,
        "frame_start": scene.frame_start, "frame_end": scene.frame_end,
        "objects": [], "actions": []}
for ob in bpy.data.objects:
    e = {"name": ob.name, "type": ob.type, "parent": ob.parent.name if ob.parent else None,
         "location": list(ob.location), "rotation_euler": list(ob.rotation_euler), "scale": list(ob.scale)}
    if ob.type == 'MESH':
        me = ob.data
        e["verts"] = len(me.vertices); e["polys"] = len(me.polygons)
        e["vgroups"] = [g.name for g in ob.vertex_groups]
        e["materials"] = [m.name for m in me.materials if m]
        e["armature_mod"] = [m.object.name for m in ob.modifiers if m.type == 'ARMATURE' and m.object]
        e["shape_keys"] = [k.name for k in me.shape_keys.key_blocks] if me.shape_keys else []
    if ob.type == 'ARMATURE':
        e["bones"] = [{"name": b.name, "parent": b.parent.name if b.parent else None,
                       "head": list(b.head_local), "tail": list(b.tail_local)} for b in ob.data.bones]
        ad = ob.animation_data
        e["action"] = ad.action.name if ad and ad.action else None
    info["objects"].append(e)
for a in bpy.data.actions:
    rng = list(a.frame_range)
    info["actions"].append({"name": a.name, "range": rng})
with open(os.path.join(outdir, "inspect.json"), "w") as f:
    json.dump(info, f, indent=1)

# Per-frame local pose: for each armature, every pose bone's local rotation (quaternion w,x,y,z)
# relative to its rest, and location, for every frame of the scene.
arms = [ob for ob in bpy.data.objects if ob.type == 'ARMATURE']
s0, s1 = scene.frame_start, scene.frame_end
for a in bpy.data.actions:
    s0 = min(s0, int(math.floor(a.frame_range[0]))); s1 = max(s1, int(math.ceil(a.frame_range[1])))
frames = {"start": s0, "end": s1, "armatures": {}}
for ob in arms:
    frames["armatures"][ob.name] = {"bones": [pb.name for pb in ob.pose.bones], "frames": []}
for fr in range(s0, s1 + 1):
    scene.frame_set(fr)
    for ob in arms:
        row = []
        for pb in ob.pose.bones:
            q = pb.matrix_basis.to_quaternion(); t = pb.matrix_basis.to_translation()
            row.append([round(q.w, 6), round(q.x, 6), round(q.y, 6), round(q.z, 6),
                        round(t.x, 5), round(t.y, 5), round(t.z, 5)])
        frames["armatures"][ob.name]["frames"].append(row)
with open(os.path.join(outdir, "frames.json"), "w") as f:
    json.dump(frames, f)
print("INSPECT_OK", len(arms), "armatures", s0, s1)
