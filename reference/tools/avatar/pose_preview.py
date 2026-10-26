"""pose_preview.py -- the FBX hand poses (vrhandpose.txt rot lines) on real avatars, offline.

Does what vr_avatar_pose.cpp [POSEROT] does to a body's finger joints, at the bind pose:
    D = F . R(q) . F^T  (F: the .avatar's measured canonical frame of the joint, in joint space)
    G_joint <- G_joint . D, and the rest of that finger is carried with it.
then linear-blend skins the avatar's own mesh (.mdl/.vvd/.dx90.vtx) and draws the hand.

usage: pose_preview.py <vrhandpose.txt> <out.png> <pose,pose,...> <model.mdl>...
       (each .mdl needs its .vvd, .dx90.vtx and the .avatar beside it)
       env REFDIR=<FBX renders dir> POSEJSON=<fbx_poses.json> adds the FBX source frame as a first column

This is the engine's arithmetic run offline at the BIND pose, to see a pose on a body before
it goes in game. It is not the engine: arm IK, smoothing and the index fire blend are not here.
"""
import sys, os, struct, re, glob, json
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from studio import Studio
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection

VIEWS = [(1.0, 0.15), (0.25, 1.0)]     # thumb side; palm (palmnormal points out of the palm)
VNAMES = ["thumb side", "palm"]
FINGERS = ["thumb", "index", "middle", "ring", "pinky"]

# ------------------------------------------------------------------ files
def load_poses(path):
    P = {}
    for line in open(path):
        m = re.match(r"\s*rot\s+(\S+)\s+([RL])\s+(\w+)\s+(\d)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)", line)
        if m:
            P.setdefault(m.group(1), {})[(m.group(2), m.group(3), int(m.group(4)))] = \
                np.array([float(m.group(k)) for k in (5, 6, 7, 8)])
    return P

def load_avatar(path):
    sides = {}; cur = None; joints = {}
    sect = None
    for line in open(path):
        t = line.split("//")[0].split()
        if not t: continue
        if t[0] == "side": cur = sides.setdefault(t[1], {"bones": {}}); sect = "side"; continue
        if t[0] == "joints": sect = "joints"; continue
        if t[0] == "end": cur = None; sect = None; continue
        if sect == "side":
            if t[0] == "bone":
                fr = [float(x) for x in t[4:13]]
                cur["bones"][(t[1], int(t[2]))] = (int(t[3]), np.array(fr).reshape(3, 3).T)  # columns X,Y,Z
            elif t[0] in ("fingeraxis", "knuckleaxis", "palmnormal"):
                cur[t[0]] = np.array([float(x) for x in t[1:4]])
        elif sect == "joints":
            joints[t[0]] = int(t[1])
    return sides, joints

def qmat(q):
    x, y, z, w = q
    return np.array([[1-2*(y*y+z*z), 2*(x*y-w*z), 2*(x*z+w*y)],
                     [2*(x*y+w*z), 1-2*(x*x+z*z), 2*(y*z-w*x)],
                     [2*(x*z-w*y), 2*(y*z+w*x), 1-2*(x*x+y*y)]])

def bind_globals(st):
    G = []
    for j in st.joints:
        L = np.eye(4); L[:3, :3] = qmat(j.r); L[:3, 3] = j.t
        G.append(L if j.parent < 0 else G[j.parent] @ L)
    return G

def vtx_triangles(mdl_path, nverts_lod0):
    """LOD-0 triangles as indices into the fixed-up VVD vertex list."""
    d = open(mdl_path, "rb").read()
    v = open(os.path.splitext(mdl_path)[0] + ".dx90.vtx", "rb").read()
    I = lambda b, o: struct.unpack_from("<i", b, o)[0]
    nbp, bpo = I(d, 232), I(d, 236)
    vnbp, vbpo = I(v, 28), I(v, 32)
    assert nbp == vnbp, "mdl/vtx body part counts differ"
    # strip group header size: 25 in older vtx, 33 when topology fields are present
    tris = []
    for sg_size in (25, 33):
        tris = []; ok = True
        try:
            for b in range(nbp):
                mb = bpo + b * 16; nmod, modi = I(d, mb + 4), I(d, mb + 12)
                vb = vbpo + b * 8; vnmod, vmodo = I(v, vb), I(v, vb + 4)
                for m in range(nmod):
                    mm = mb + modi + m * 148
                    nmesh, meshi, vindex = I(d, mm + 72), I(d, mm + 76), I(d, mm + 84)
                    vbase = vindex // 48
                    vm = vb + vmodo + m * 8
                    nlod, lodo = I(v, vm), I(v, vm + 4)
                    lod = vm + lodo               # LOD 0
                    vnmesh, vmesho = I(v, lod), I(v, lod + 4)
                    for k in range(nmesh):
                        me = mm + meshi + k * 116
                        moff = I(d, me + 12)
                        vme = lod + vmesho + k * 9
                        nsg, sgo = I(v, vme), I(v, vme + 4)
                        for g in range(nsg):
                            sg = vme + sgo + g * sg_size
                            nv, vo, ni, io = I(v, sg), I(v, sg + 4), I(v, sg + 8), I(v, sg + 12)
                            orig = [struct.unpack_from("<H", v, sg + vo + q * 9 + 4)[0] for q in range(nv)]
                            idx = struct.unpack_from("<%dH" % ni, v, sg + io)
                            for t in range(0, ni - 2, 3):
                                tri = [vbase + moff + orig[idx[t + c]] for c in range(3)]
                                if max(tri) >= nverts_lod0: raise ValueError
                                tris.append(tri)
        except (ValueError, IndexError, struct.error):
            ok = False
        if ok and tris: return np.array(tris)
    raise SystemExit("could not read triangles from the vtx")

# ------------------------------------------------------------------ posing
def posed_globals(G0, side, pose, sd):
    G = [g.copy() for g in G0]
    for f in FINGERS:
        for j in (1, 2, 3):
            key = (sd, f, j)
            if key not in pose or (f, j) not in side["bones"]: continue
            q = pose[key]
            if abs(q[3]) > 0.999999: continue
            ji, F = side["bones"][(f, j)]
            D = np.eye(4); D[:3, :3] = F @ qmat(q) @ F.T
            before = G[ji]; after = before @ D; G[ji] = after
            carry = after @ np.linalg.inv(before)
            for k in range(j + 1, 4):
                if (f, k) in side["bones"]:
                    ck = side["bones"][(f, k)][0]; G[ck] = carry @ G[ck]
    return G

def skin(P, W, G0, G):
    S = [G[b] @ np.linalg.inv(G0[b]) for b in range(len(G))]
    out = np.zeros_like(P)
    for i, (p, (w, b, nb)) in enumerate(zip(P, W)):
        acc = np.zeros(3); tot = 0
        for k in range(min(nb, 3)):
            M = S[b[k]]; acc += w[k] * (M[:3, :3] @ p + M[:3, 3]); tot += w[k]
        out[i] = acc / tot if tot > 0 else p
    return out

# ------------------------------------------------------------------ drawing
def draw(ax, V, T, view, up, light):
    z = view / np.linalg.norm(view)
    x = np.cross(up, z); x /= np.linalg.norm(x); y = np.cross(z, x)
    P2 = np.stack([V @ x, V @ y], 1); depth = V @ z
    tv = V[T]
    n = np.cross(tv[:, 1] - tv[:, 0], tv[:, 2] - tv[:, 0])
    nl = np.linalg.norm(n, axis=1); nl[nl == 0] = 1; n /= nl[:, None]
    shade = np.abs(n @ light) * 0.75 + 0.2
    order = np.argsort(depth[T].mean(1))          # far first (camera at +z looking toward -z)
    polys = P2[T][order]
    cols = np.clip(np.stack([shade * 0.86, shade * 0.80, shade * 0.74], 1), 0, 1)[order]
    ax.add_collection(PolyCollection(polys, facecolors=cols, edgecolors="none", antialiased=False))
    lo, hi = P2.min(0), P2.max(0); c = (lo + hi) / 2; r = (hi - lo).max() / 2 * 1.08
    ax.set_xlim(c[0] - r, c[0] + r); ax.set_ylim(c[1] - r, c[1] + r)
    ax.set_aspect("equal"); ax.axis("off")

def hand_mesh(st, T, sides, joints, sd):
    """The hand's own vertices: carried mostly by the hand bone or ANY bone under it, plus the wrist.

    Not just the finger bones the .avatar names: a rig can skin its palm to metacarpal or helper
    bones under the hand (slayer_praetor's *_part01) and to a wrist-twist bone, and leaving those
    out draws fingers floating over a missing palm.
    """
    hand = joints["hand_" + sd]
    kids = {}
    for j in st.joints: kids.setdefault(j.parent, []).append(j.index)
    want = set(); stack = [hand]
    while stack:
        x = stack.pop(); want.add(x); stack += kids.get(x, [])
    hp = np.array(st_globals(st)[hand][:3, 3])
    tips = [np.array(st_globals(st)[sides[sd]["bones"][(f, 3)][0]][:3, 3]) for f in ("index", "middle", "ring", "pinky") if (f, 3) in sides[sd]["bones"]]
    reach = max(np.linalg.norm(t - hp) for t in tips) if tips else 6.0
    P = np.array(st.positions)
    keep = np.zeros(len(P), bool)
    for i, (w, b, nb) in enumerate(st.weights):
        mine = sum(w[k] for k in range(min(nb, 3)) if b[k] in want)
        keep[i] = mine >= 0.5 or (mine > 0.0 and np.linalg.norm(P[i] - hp) < reach)
    # the heel of the palm on a wrist bone: close to the hand joint, on the finger side of it
    fax = sides[sd]["fingeraxis"]
    near = np.linalg.norm(P - hp, axis=1) < 0.45 * reach
    keep |= near & ((P - hp) @ fax > -0.15 * reach)
    tk = T[keep[T].all(1)]
    used = np.unique(tk)
    return used, tk

_GL = {}
def st_globals(st):
    if id(st) not in _GL: _GL[id(st)] = bind_globals(st)
    return _GL[id(st)]

def main():
    poses = load_poses(sys.argv[1]); out = sys.argv[2]; names = sys.argv[3].split(",")
    models = sys.argv[4:]
    cols = []
    for mdl in models:
        st = Studio(mdl)
        avatar = glob.glob(os.path.join(os.path.dirname(mdl), "*.avatar"))[0]
        sides, joints = load_avatar(avatar)
        P = np.array(st.positions); T = vtx_triangles(mdl, len(P)); G0 = bind_globals(st)
        # sanity: the measured finger joints sit inside their own weighted vertices
        for sd in ("R", "L"):
            used, tk = hand_mesh(st, T, sides, joints, sd)
            cols.append((os.path.splitext(os.path.basename(mdl))[0], sd, st, P, G0, sides, joints, used, tk))
            print(os.path.basename(mdl), sd, "hand verts", len(used), "tris", len(tk))
    REF = os.environ.get("REFDIR"); frames = json.load(open(os.environ["POSEJSON"])) if REF else {}
    off = 1 if REF else 0
    fig, axs = plt.subplots(len(names), 2 * len(cols) + off, figsize=(1.9 * (2 * len(cols) + 1.6 * off), 1.9 * len(names)),
                            gridspec_kw={"width_ratios": ([1.6] if REF else []) + [1] * (2 * len(cols))})
    axs = np.atleast_2d(axs)
    if REF:
        for r, pname in enumerate(names):
            ax = axs[r, 0]; ax.axis("off")
            fp = os.path.join(REF, "f%04d_side.png" % frames[pname][0])
            if os.path.exists(fp): ax.imshow(plt.imread(fp))
            ax.text(0.5, -0.02, "FBX frame %d, hand %s" % tuple(frames[pname]), transform=ax.transAxes, ha="center", va="top", fontsize=6)
            if r == 0: ax.set_title("the FBX hands\n(source)", fontsize=7)
        axs = axs[:, 1:]
    for r, pname in enumerate(names):
        pose = poses[pname]
        for c, (mname, sd, st, P, G0, sides, joints, used, tk) in enumerate(cols):
            G = posed_globals(G0, sides[sd], pose, sd)
            sub_idx = {u: i for i, u in enumerate(used)}
            Psub = P[used]; Wsub = [st.weights[u] for u in used]
            V = skin(Psub, Wsub, G0, G)
            Tl = np.vectorize(sub_idx.get)(tk)
            s = sides[sd]
            k = s["knuckleaxis"]; p = s["palmnormal"]; f = s["fingeraxis"]
            for vi, (a, b) in enumerate(VIEWS):
                view = a * k + b * p
                ax = axs[r, 2 * c + vi]
                draw(ax, V, Tl, view, f, (view + f * 0.5) / np.linalg.norm(view + f * 0.5))
                if r == 0: ax.set_title("%s %s\n%s" % (mname, "right" if sd == "R" else "left", VNAMES[vi]), fontsize=7)
            if c == 0: axs[r, 0].text(-0.08, 0.5, pname, transform=axs[r, 0].transAxes, rotation=90,
                                      ha="right", va="center", fontsize=8)
    plt.tight_layout(); plt.savefig(out, dpi=110, facecolor="white"); print("wrote", out)

if __name__ == "__main__":
    main()
