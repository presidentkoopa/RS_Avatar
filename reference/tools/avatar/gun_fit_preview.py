"""gun_fit_preview.py -- a body's own hand, in the FBX grip pose for the gun's type, on the gun mesh.

What the engine will draw when a gun is anchored in the hand (vr_gun_anchor_hand), offline:

  * THE GUN: its md3 at the card's drawn frame, scaled by its MODELDEF Scale (mirror included)
    into map units -- every number from tools/avatar_grip's guns.json, which reads them off the
    live cards and MODELDEFs.
  * THE GRIP FRAME: vr_rig.cpp VRRig_GripFrame, rake on: the handle from the card's `rake`
    (-sin, 0, -cos in the gun's XZ plane), the bore from `barrel`, both mapped through the scale;
    N = H x B, B squared to the handle (B = N x H), N negated for a left hand, Z = B x N.
  * THE HAND ON IT: the body's canonical hand frame (fingeraxis, -palmnormal, their cross) laid
    onto (B, N, Z), the body's `gripsocket` on the card's `palm` -- the rule tools/avatar_grip
    (seatsheet.place_hand) states, with vr_gun_anchor_q* at identity.
  * THE FINGERS: grip_<class> from vrhandpose.txt, the [POSEROT] arithmetic (pose_preview.py),
    skinned on the body's own mesh.

usage: gun_fit_preview.py <guns.json> <mesh root> <vrhandpose.txt> <body.mdl> <out.png> <Gun,Gun,...> [bodyscale]
       bodyscale: map units per body unit (c_doom_marine 0.655, RS_AVATAR.md 3)
"""
import sys, os, json, struct, math
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pose_preview as PP
from studio import Studio
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.collections import PolyCollection

# card.zs DefaultGripClass: the weapon type's grip class
CLASS = {"pistol": "pistol", "revolver": "pistol", "pump": "shotgun", "shotgun": "shotgun",
         "breakaction": "ssg", "rifle": "rifle", "smg": "rifle", "chaingun": "rifle",
         "launcher": "rocket", "plasma": "plasma", "railgun": "plasma", "flamethrower": "plasma",
         "bfg": "bfg", "chainsaw": "saw", "melee": "melee", "grenade": "melee"}

def md3_load(path, frame=0, hide=()):
    d = open(path, "rb").read()
    nfr, ntag, nsurf, nskin, ofr, otag, osurf, oeof = struct.unpack_from("<8i", d, 76)
    hide = [h.lower() for h in hide if h]
    T = []; V = []; base = 0; off = osurf
    for s in range(nsurf):
        name = d[off + 4:off + 68].split(b"\0")[0].decode("latin1")
        flags, nf, nsh, nv, nt, otri, osh, ost, oxyz, oend = struct.unpack_from("<10i", d, off + 68)
        if not any(name.lower() == h or name.lower().startswith(h) for h in hide):
            tris = np.frombuffer(d, "<i4", nt * 3, off + otri).reshape(nt, 3)
            f = min(frame, nf - 1)
            raw = np.frombuffer(d, "<i2", nv * 4, off + oxyz + f * nv * 8).reshape(nv, 4)
            T.append(tris + base); V.append(raw[:, :3].astype(float) / 64.0); base += nv
        off += oend
    return np.concatenate(T), np.concatenate(V)

def vec(s): return np.array([float(x) for x in s.replace(",", " ").split()])

def unit(v): return v / np.linalg.norm(v)

def grip_frame(bore_m, rake_deg, scale, right, roll_deg=0.0):
    s = np.array(scale, float)
    rk = math.radians(rake_deg)
    B = unit(s * bore_m)
    H = unit(s * np.array([-math.sin(rk), 0.0, -math.cos(rk)]))
    N = unit(np.cross(H, B))
    B = np.cross(N, H)                      # [GRIPRAKE] the bore squared against the handle
    if not right: N = -N
    Z = unit(np.cross(B, N))
    if roll_deg:
        # [ROLL] a hand turned about the handle: the palm off the gun's side and under it (positive)
        a = math.radians(roll_deg) * (1 if right else -1)
        c, s_ = math.cos(a), math.sin(a)
        K = np.array([[0, -Z[2], Z[1]], [Z[2], 0, -Z[0]], [-Z[1], Z[0], 0]])
        Rz = np.eye(3) + s_ * K + (1 - c) * (K @ K)
        B, N = Rz @ B, Rz @ N
    return np.stack([B, N, Z], 1)

def hand_on(world_palm, RA, side_data, hand_joint_pos, socket, bs):
    X = unit(side_data["fingeraxis"])
    Y = -side_data["palmnormal"]; Y = unit(Y - X * (Y @ X))
    RC = np.stack([X, Y, np.cross(X, Y)], 1)
    M = RA @ RC.T
    return lambda P: world_palm + ((P - hand_joint_pos) @ M.T - RA @ socket) * bs

def socket_of(avatar_path, sd):
    blk = open(avatar_path).read().split("side ")
    for b in blk:
        if b.startswith(sd):
            for l in b.split("\n"):
                q = l.split()
                if q and q[0] == "gripsocket": return np.array([float(x) for x in q[1:4]])
    raise SystemExit("no gripsocket for side %s" % sd)

def draw(ax, layers, U, Vv, W):
    """layers: [(verts (n,3), tris, rgb)]; view: screen x = U, y = Vv, depth along W (toward camera)."""
    polys = []; cols = []; deps = []
    light = unit(W + 0.4 * Vv)
    for V, T, rgb in layers:
        tv = V[T]
        n = np.cross(tv[:, 1] - tv[:, 0], tv[:, 2] - tv[:, 0])
        nl = np.linalg.norm(n, axis=1); nl[nl == 0] = 1; n /= nl[:, None]
        sh = np.abs(n @ light) * 0.7 + 0.3
        polys.append(np.stack([tv @ U, tv @ Vv], 2)); deps.append((tv @ W).mean(1))
        cols.append(np.clip(np.outer(sh, rgb), 0, 1))
    P = np.concatenate(polys); C = np.concatenate(cols); D = np.concatenate(deps)
    o = np.argsort(D)
    ax.add_collection(PolyCollection(P[o], facecolors=C[o], edgecolors="none", antialiased=False))
    return P.reshape(-1, 2)

def main():
    guns = {g["cls"]: g for g in json.load(open(sys.argv[1]))}
    root, posef, mdl, out = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
    names = sys.argv[6].split(",")
    bs = float(sys.argv[7]) if len(sys.argv) > 7 else 0.655
    poses = PP.load_poses(posef)
    st = Studio(mdl)
    avatar = [os.path.join(os.path.dirname(mdl), f) for f in os.listdir(os.path.dirname(mdl)) if f.endswith(".avatar")][0]
    sides, joints = PP.load_avatar(avatar)
    P = np.array(st.positions); T = PP.vtx_triangles(mdl, len(P)); G0 = PP.bind_globals(st)
    meshes = {sd: PP.hand_mesh(st, T, sides, joints, sd) for sd in ("R", "L")}
    fig, axs = plt.subplots(len(names), 3, figsize=(12, 3.6 * len(names)))
    axs = np.atleast_2d(axs)
    report = []
    for r, gname in enumerate(names):
        g = guns[gname]
        right = g.get("hand", "main") == "main"
        sd = "R" if right else "L"
        cls = CLASS.get(g.get("type", ""), "")
        pname = "grip_" + cls if ("grip_" + cls) in poses else "gun_grip"
        gp = g["grip"]
        palm_m = vec(gp["palm"]); rake = float(gp.get("rake", 15))
        bore_m = vec(g.get("barrel", "1 0 0")) if g.get("barrel") else np.array([1.0, 0, 0])
        # THE GUN'S OWN FILE SPACE, size only. The cards' points, `rake` and the hand rule are all
        # stated there (+X muzzle, +Y left, +Z up, every mesh in every set). A negative MODELDEF
        # scale is a mirror the follow-hand path undoes on the way to the screen; carried into the
        # grip frame here it turns the palm normal over and puts the hand on the gun inside out.
        scale = np.abs(np.array(g["scale"], float))
        GT, GV = md3_load(os.path.join(root, g["mesh"].replace("\\", "/")), int(g.get("frame") or 0), g.get("hidden") or [])
        GVw = GV * scale
        palm_w = palm_m * scale
        roll = float(os.environ.get("ROLL_" + gname, os.environ.get("ROLL", "0")))
        RA = grip_frame(bore_m, rake, scale, right, roll)
        used, tk = meshes[sd]
        Gp = PP.posed_globals(G0, sides[sd], poses.get(pname, {}), sd)
        HV = PP.skin(P[used], [st.weights[u] for u in used], G0, Gp)
        idx = {u: i for i, u in enumerate(used)}; HT = np.vectorize(idx.get)(tk)
        hj = G0[joints["hand_" + sd]][:3, 3]
        place = hand_on(palm_w, RA, sides[sd], hj, socket_of(avatar, sd), bs)
        HVw = place(HV)
        # how far into the gun the hand goes, and how close it comes: nearest gun vertex to each hand vertex
        from scipy.spatial import cKDTree
        dgun, _ = cKDTree(GVw).query(HVw)
        report.append("%-20s %-6s %-12s %-14s hand verts within 0.15 mu of the gun: %4d of %d" % (gname, sd, g.get("type"), pname, int((dgun < 0.15).sum()), len(HVw)))
        layers = [(GVw, GT, np.array([0.62, 0.64, 0.68])), (HVw, HT, np.array([0.93, 0.78, 0.62]))]
        X, Y, Z = np.eye(3)
        views = [("side", X * np.sign(scale[0]) * -1 if False else X, Z, -Y if right else Y),
                 ("top", X, Y, Z), ("along the bore", Y, Z, X)]
        span = 0.0
        for c, (vn, U, Vv, W) in enumerate(views):
            ax = axs[r, c]
            pts = draw(ax, layers, U, Vv, W)
            hp = HVw @ np.stack([U, Vv], 1)
            ctr = hp.mean(0); rad = max(np.ptp(hp, 0).max() * 1.4, 1e-3)
            ax.set_xlim(ctr[0] - rad, ctr[0] + rad); ax.set_ylim(ctr[1] - rad, ctr[1] + rad)
            ax.set_aspect("equal"); ax.axis("off")
            ax.set_title("%s -- %s" % (gname, vn) if c == 0 else vn, fontsize=8)
        axs[r, 0].text(0.0, -0.02, "%s, %s hand, %s, rake %.1f, roll %.0f" % (g.get("type"), "right" if right else "left", pname, rake, roll),
                       transform=axs[r, 0].transAxes, fontsize=7, va="top")
    plt.tight_layout(); plt.savefig(out, dpi=90, facecolor="white")
    print("\n".join(report)); print("wrote", out)

if __name__ == "__main__":
    main()
