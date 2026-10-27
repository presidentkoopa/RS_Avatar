"""mkfbxposes.py -- hand poses for the avatars, from the FBX hands (models/hands/hand_final.fbx).

THE SOURCE IS THE FBX AND NOTHING ELSE. Both hands, each from its OWN skeleton: hand A (the
unmirrored controls) and hand B (the controls with a -1 scale). Armature space is below those
controls, so both read as the same-handed skeleton there; hand B is mirrored in X here to make
it the other side, and each hand's side is DETECTED (the side whose palm formula makes the
fingers fold into the palm), never assumed.

WHAT IS WRITTEN: `rot <pose> <R|L> <finger> <joint> <x> <y> <z> <w>`, the joint's FULL rotation
away from the open hand, in the joint's canonical bone frame -- the frame measure_avatar.py builds
on every avatar from its own rest pose:
    +X along the bone toward its child, +Z = X x palm (the fold axis), +Y = Z x X (palmward)
The engine applies it in the avatar's own measured frame, so a pose bends any body's fingers the
way the FBX hand bends, spread, twist and full depth included. Nothing is clamped.

The open hand is the FBX's frame 1 (all fingers straight); every pose is measured against it.
FBX joints BASE/MID/TOP are the engine's joints 1/2/3; UP_TOP is a tip with no counterpart.

usage: python mkfbxposes.py <fbx_pose_mats.json> <poses.json> <out VRHANDPOSE text>
       poses.json: {"<pose name>": [<FBX frame>, "<A|B|both>"], ...}
         or, composed: {"<pose name>": {"fingers": {"thumb": "<earlier pose>", ... all five},
                                       "why": "<one line>"}}
         a key starting with // is a comment and is skipped
"""
import sys, json, math

FINGERS = [("thumb", "THUMB"), ("index", "INDEX"), ("middle", "MIDDLE_F"), ("ring", "RING"), ("pinky", "PINK")]
SEGS = {1: "BASE", 2: "MID", 3: "TOP"}

def mat3(m): return [[m[i][j] for j in range(3)] for i in range(3)]
def pos(m): return [m[0][3], m[1][3], m[2][3]]
def T(a): return [[a[j][i] for j in range(3)] for i in range(3)]
def mm(a, b): return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
def mv(a, v): return [sum(a[i][k] * v[k] for k in range(3)) for i in range(3)]
def sub(a, b): return [a[i] - b[i] for i in range(3)]
def dot(a, b): return sum(a[i] * b[i] for i in range(3))
def cross(a, b): return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]
def unit(a):
    l = math.sqrt(dot(a, a)); return [x / l for x in a] if l > 1e-12 else None
def ortho(m):
    # nearest rotation (removes scale; the FBX controls carry a 0.01 scale)
    c = [unit([m[0][j], m[1][j], m[2][j]]) for j in range(3)]
    c[2] = unit(cross(c[0], c[1])); c[1] = cross(c[2], c[0])
    return [[c[j][i] for j in range(3)] for i in range(3)]
def det(m): return dot([m[0][0], m[1][0], m[2][0]], cross([m[0][1], m[1][1], m[2][1]], [m[0][2], m[1][2], m[2][2]]))
def quat(r):
    t = r[0][0] + r[1][1] + r[2][2]
    if t > 0:
        s = math.sqrt(t + 1.0) * 2; w = 0.25 * s
        x = (r[2][1] - r[1][2]) / s; y = (r[0][2] - r[2][0]) / s; z = (r[1][0] - r[0][1]) / s
    elif r[0][0] > r[1][1] and r[0][0] > r[2][2]:
        s = math.sqrt(1.0 + r[0][0] - r[1][1] - r[2][2]) * 2; w = (r[2][1] - r[1][2]) / s
        x = 0.25 * s; y = (r[0][1] + r[1][0]) / s; z = (r[0][2] + r[2][0]) / s
    elif r[1][1] > r[2][2]:
        s = math.sqrt(1.0 + r[1][1] - r[0][0] - r[2][2]) * 2; w = (r[0][2] - r[2][0]) / s
        x = (r[0][1] + r[1][0]) / s; y = 0.25 * s; z = (r[1][2] + r[2][1]) / s
    else:
        s = math.sqrt(1.0 + r[2][2] - r[0][0] - r[1][1]) * 2; w = (r[1][0] - r[0][1]) / s
        x = (r[0][2] + r[2][0]) / s; y = (r[1][2] + r[2][1]) / s; z = 0.25 * s
    if w < 0: x, y, z, w = -x, -y, -z, -w
    return [x, y, z, w]

MIRROR = [[-1, 0, 0], [0, 1, 0], [0, 0, 1]]

def hand_globals(H, frame, mirror):
    """per bone: (rotation, position) in armature space; rest when frame is None"""
    mats = H["rest"] if frame is None else H["frames"][str(frame)]
    out = {}
    for name, m in zip(H["bones"], mats):
        r = ortho(mat3(m)); p = pos(m)
        if mirror:
            r = mm(mm(MIRROR, r), MIRROR); p = mv(MIRROR, p)
        out[name] = (r, p)
    return out

def frames_for(H, rest, side_right):
    """canonical bone frame of every finger joint, in the joint's own rest frame (measure_avatar.py)"""
    f = unit(sub(rest["MIDDLE_F_BASE_joint"][1], rest["Root_joint"][1]))
    kr = sub(rest["INDEX_BASE_joint"][1], rest["PINK_BASE_joint"][1])
    k = unit(sub(kr, [f[i] * dot(kr, f) for i in range(3)]))
    palm = unit(cross(k, f) if side_right else cross(f, k))
    child = {}
    for n, p in zip(H["bones"], H["parent"]):
        if p: child.setdefault(p, []).append(n)
    F = {}; folds = []
    for fn, fb in FINGERS:
        prevX = None
        for j in (1, 2, 3):
            name = "%s_%s_joint" % (fb, SEGS[j])
            R, P = rest[name]
            kids = child.get(name, [])
            if kids:
                best = max(kids, key=lambda c: math.dist(rest[c][1], P))
                X = unit(mv(T(R), sub(rest[best][1], P)))
            else:
                X = prevX
            palm_l = unit(mv(T(R), palm))
            Z = unit(cross(X, palm_l))
            X = unit(cross(Z, unit(cross(X, Z))))
            Y = cross(Z, X)
            folds.append(dot(Y, palm_l))
            F[(fn, j)] = [[X[i], Y[i], Z[i]] for i in range(3)]   # columns X, Y, Z
            prevX = X
    return F, folds

def local(g, name, parent):
    R = g[name][0]
    return R if parent is None else mm(T(g[parent][0]), R)

def main():
    data = json.load(open(sys.argv[1]))["hands"]
    poses = json.load(open(sys.argv[2]))
    out_lines = []
    report = []
    # Each hand, read both as stored and mirrored: each reading is one side, detected.
    readings = {}
    for tag in ("A", "B"):
        H = data[tag]
        for mirror in (False, True):
            # The OPEN HAND (frame 1) is the reference everything is measured against, so the bone
            # frames are built on it too, not on the FBX's bind pose.
            rest = hand_globals(H, 1, mirror)
            # WHICH SIDE, FROM THE HAND'S OWN MOTION. In the fist (frame 319) the fingertips travel
            # toward the palm. measure_avatar.py's palm for a RIGHT hand is knuckles x fingers; if
            # the tips travel along it this is a right hand, else a left one.
            fist = hand_globals(H, 319, mirror)
            f = unit(sub(rest["MIDDLE_F_BASE_joint"][1], rest["Root_joint"][1]))
            kr = sub(rest["INDEX_BASE_joint"][1], rest["PINK_BASE_joint"][1])
            k = unit(sub(kr, [f[i] * dot(kr, f) for i in range(3)]))
            palmR = unit(cross(k, f))
            travel = [0.0, 0.0, 0.0]
            for tip in ("INDEX_TOP_joint", "MIDDLE_F_TOP_joint", "RING_TOP_joint", "PINK_TOP_joint"):
                mv_ = sub(sub(fist[tip][1], fist["Root_joint"][1]), sub(rest[tip][1], rest["Root_joint"][1]))
                travel = [travel[i] + mv_[i] for i in range(3)]
            along = dot(unit(travel), palmR)
            right = along > 0
            side = "R" if right else "L"
            F, folds = frames_for(H, rest, right)
            if (tag, side) in readings: raise SystemExit("hand %s reads as %s both as stored and mirrored" % (tag, side))
            readings[(tag, side)] = (mirror, F)
            report.append("hand %s %s is a %s hand (fist travel along the right-hand palm %+.2f)"
                          % (tag, "mirrored" if mirror else "as stored", "RIGHT" if right else "LEFT", along))
    # The hand's OWN side: B is the mirrored one in the FBX, so B as stored is A's side and B
    # mirrored is its own; A as stored is its own.
    native = {"A": [s for (t, s), (m, _) in readings.items() if t == "A" and not m][0],
              "B": [s for (t, s), (m, _) in readings.items() if t == "B" and m][0]}
    report.append("own sides: hand A = %s, hand B = %s" % (native["A"], native["B"]))
    # Every pose: the FBX frame it is, or -- a COMPOSED pose -- each finger taken whole from a pose
    # named earlier in the spec. A finger is never assembled from two frames; a hand may be.
    done = {}      # (pose, side) -> {(finger, joint): (q, comment)}
    for pname, spec in poses.items():
        if pname.startswith("//"): continue
        for side in ("R", "L"):
            if isinstance(spec, dict):
                src = spec["fingers"]
                got = {}
                parts = []
                for fn, _ in FINGERS:
                    base = src[fn]
                    if (base, side) not in done: raise SystemExit("%s: %s comes from %s, which is not defined before it" % (pname, fn, base))
                    for j in (1, 2, 3): got[(fn, j)] = done[(base, side)][(fn, j)]
                    parts.append("%s from %s" % (fn, base))
                done[(pname, side)] = got
                out_lines.append("// %s %s: COMPOSED -- %s" % (pname, side, "; ".join(parts)))
                if spec.get("why"): out_lines.append("//   " + spec["why"])
            else:
                frame, src = spec[0], spec[1]
                # Use the hand that authored this side when both did; otherwise the one hand, and say so.
                if src == "both":
                    tag = "A" if native["A"] == side else "B"; how = "own"
                else:
                    tag = src; how = "own" if native[src] == side else "MIRRORED from hand %s" % src
                mirror, F = readings[(tag, side)]
                H = data[tag]; par = dict(zip(H["bones"], H["parent"]))
                open_g = hand_globals(H, 1, mirror); g = hand_globals(H, frame, mirror)
                got = {}
                for fn, fb in FINGERS:
                    for j in (1, 2, 3):
                        name = "%s_%s_joint" % (fb, SEGS[j]); p = par[name]
                        D = mm(T(local(open_g, name, p)), local(g, name, p))
                        Fc = F[(fn, j)]
                        got[(fn, j)] = quat(mm(mm(T(Fc), D), Fc))
                done[(pname, side)] = got
                out_lines.append("// %s %s: FBX frame %d, hand %s (%s)" % (pname, side, frame, tag, how))
            for fn, _ in FINGERS:
                for j in (1, 2, 3):
                    q = done[(pname, side)][(fn, j)]
                    ang = 2 * math.degrees(math.acos(min(1.0, abs(q[3]))))
                    out_lines.append("rot  %-22s %s  %-6s %d  %+.6f %+.6f %+.6f %+.6f   // %5.1f deg"
                                     % (pname, side, fn, j, q[0], q[1], q[2], q[3], ang))
    hdr = ["// GENERATED BY mkfbxposes.py FROM models/hands/hand_final.fbx -- DO NOT EDIT BY HAND.",
           "// Both FBX hands, each from its own skeleton. Full joint rotations against the FBX open hand",
           "// (frame 1), in the canonical bone frame (+X along the bone, +Z the fold axis, +Y palmward).",
           "// A pose only one hand authored is also written for the other side, mirrored, and says so.",
           "// A COMPOSED pose takes each finger whole from an FBX pose above it; it says which.",
           "//"] + ["// " + r for r in report] + [
           "//", "// rot <pose> <R|L> <finger> <joint 1-3> <x> <y> <z> <w>", ""]
    open(sys.argv[3], "w").write("\n".join(hdr + out_lines) + "\n")
    print("\n".join(report)); print("wrote", len(out_lines), "lines for", len([k for k in poses if not k.startswith("//")]), "poses")

if __name__ == "__main__":
    main()
