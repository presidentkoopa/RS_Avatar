"""part_fit_preview.py -- the avatar's hand ON a slide, charging handle, pump or foregrip, offline.

The reload hand as RS_VR_Reload's WM_System.AnchorHeldParts places it, through the engine's
anchor (VRRig_GripFrame, the body's gripsocket on the point):

  * WHERE: the part's `handseat`, or its `grab` when the card states none.
  * HOW, by the part's `subject`:
      slide (slide, charging handle, bolt): knuckles ACROSS the part, the index-to-little line
        along the bore toward the muzzle -- over the top, the back of the hand up.
      forend, foregrip: knuckles across, the line along the bore toward the shooter -- round
        it, under it, palm up.
      `handaxis` stated: the line the hand closes round, index to little finger; the knuckles
        across when that line runs along the bore, forward along the bore when it does not.
  * ACROSS is away from the hand's own side of the gun: the working hand is the OTHER hand.
  * FINGERS: hold_<subject>_<class>, else hold_<subject> (vrhandpose.txt, FBX only).

All in the gun's own file space (+X muzzle, +Y left, +Z up), sized by |MODELDEF scale|.

usage: part_fit_preview.py <cards dir> <guns.json> <mesh root> <vrhandpose.txt> <body.mdl> <out.png> <card file,...> [bodyscale]
       guns.json (tools/avatar_grip table.py) gives each mesh's drawn frame, scale and hidden parts,
       matched to the card by the mesh's file name.
"""
import sys, os, re, json, math
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pose_preview as PP
import gun_fit_preview as GF
from studio import Studio
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

HELD = ("slide", "forend", "foregrip")

def vec(s): return np.array([float(x) for x in s.split("#")[0].replace(",", " ").split()])

def parse_cards(path):
    out = []; gun = None; part = None; depth = 0
    for raw in open(path, encoding="utf-8", errors="replace"):
        l = raw.split("#")[0].strip()
        if not l: continue
        m = re.match(r'^weapon\s+"([^"]+)"', l)
        if m: gun = {"name": m.group(1), "file": os.path.basename(path)}; part = None; continue
        if gun is None: continue
        if part is None:
            m = re.match(r'^model\s*=\s*"([^"]*)"\s*"([^"]*)"', l)
            if m and "model" not in gun: gun["model"] = m.group(2)
            for k in ("type", "hand", "class"):
                m = re.match(r"^%s\s*=\s*(\S+)" % k, l)
                if m: gun[k] = m.group(1)
            m = re.match(r"^barrel\s*=\s*(.+)$", l)
            if m: gun["barrel"] = vec(m.group(1))
            m = re.match(r"^part\s+(\S+)", l)
            if m: part = {"id": m.group(1)}; depth = 1; continue
        else:
            if l in ("dof", "dof2", "index"): depth += 1; continue
            if l == "end":
                depth -= 1
                if depth == 0:
                    if part.get("subject") in HELD: out.append((dict(gun), part))
                    part = None
                continue
            if depth > 1: continue
            m = re.match(r"^(\w+)\s*=\s*(.+)$", l)
            if m:
                k, v = m.group(1), m.group(2).strip()
                if k in ("grab", "handseat", "handaxis"): part[k] = vec(v)
                elif k in ("subject", "role"): part[k] = v
    return out

def part_frame(seat, bore, subject, axis, hand_right):
    """(B = knuckles, H = index to little finger) in the gun's space, as AnchorHeldParts makes them."""
    bore = GF.unit(bore)
    up = np.array([0, 0, 1.0]) - bore * bore[2]; up = GF.unit(up)
    left = np.cross(up, bore)                      # +Y for a level gun
    handside = -left if hand_right else left       # the right hand works the gun from its right side
    across = -handside
    if axis is not None:
        ax = GF.unit(axis)
        k = across if abs(ax @ bore) > 0.7 else bore
        return GF.unit(k - ax * (k @ ax)), ax
    if subject == "slide": return across, bore
    return across, -bore

def grip_frame_from(B, H, right):
    """VRRig_GripFrame with the rake squared: N = H x B, B = N x H, N negated for a left hand, Z = B x N."""
    B = GF.unit(B); H = GF.unit(H)
    N = GF.unit(np.cross(H, B)); B = np.cross(N, H)
    if not right: N = -N
    return np.stack([B, N, GF.unit(np.cross(B, N))], 1)

def main():
    cards_dir, gunsj, root, posef, mdl, out = sys.argv[1:7]
    files = sys.argv[7].split(",")
    bs = float(sys.argv[8]) if len(sys.argv) > 8 else 0.655
    bymesh = {}
    for g in json.load(open(gunsj)):
        bymesh.setdefault(os.path.basename(g["mesh"].replace("\\", "/")).lower(), g)
    poses = PP.load_poses(posef)
    st = Studio(mdl)
    avatar = [os.path.join(os.path.dirname(mdl), f) for f in os.listdir(os.path.dirname(mdl)) if f.endswith(".avatar")][0]
    sides, joints = PP.load_avatar(avatar)
    P = np.array(st.positions); T = PP.vtx_triangles(mdl, len(P)); G0 = PP.bind_globals(st)
    meshes = {sd: PP.hand_mesh(st, T, sides, joints, sd) for sd in ("R", "L")}
    rows = []
    for f in files:
        for gun, part in parse_cards(os.path.join(cards_dir, f)):
            g = bymesh.get((gun.get("model") or "").lower())
            if g is None: print("no mesh entry for", gun["name"], gun.get("model")); continue
            if not os.path.exists(os.path.join(root, g["mesh"].replace("\\", "/"))):
                print("mesh not here, skipped:", gun["name"], g["mesh"]); continue
            rows.append((gun, part, g))
    seen = set(); keep = []
    for gun, part, g in rows:                        # one row per mesh and part: shared meshes draw once
        key = (g["mesh"], part["id"])
        if key in seen: continue
        seen.add(key); keep.append((gun, part, g))
    fig, axs = plt.subplots(len(keep), 3, figsize=(12, 3.4 * len(keep)))
    axs = np.atleast_2d(axs)
    for r, (gun, part, g) in enumerate(keep):
        main_right = (gun.get("hand", "main") == "main")
        right = not main_right                       # the working hand is the other hand
        sd = "R" if right else "L"
        cls = GF.CLASS.get(gun.get("type") or g.get("type", ""), "")
        subj = part["subject"]
        pname = next((n for n in ("hold_%s_%s" % (subj, cls), "hold_" + subj) if n in poses), None)
        seat_from = "handseat" if "handseat" in part else "grab"
        seat_m = part.get("handseat", part.get("grab"))
        if seat_m is None: continue
        scale = np.abs(np.array(g["scale"], float))
        bore = gun.get("barrel", np.array([1.0, 0, 0]))
        Bm, Hm = part_frame(seat_m, bore * scale, subj, part.get("handaxis") * scale if "handaxis" in part else None, right)
        RA = grip_frame_from(Bm, Hm, right)
        GT, GV = GF.gun_load(os.path.join(root, g["mesh"].replace("\\", "/")), int(g.get("frame") or 0), g.get("hidden") or [])
        GVw = GV * scale
        used, tk = meshes[sd]
        Gp = PP.posed_globals(G0, sides[sd], poses.get(pname, {}), sd)
        HV = PP.skin(P[used], [st.weights[u] for u in used], G0, Gp)
        idx = {u: i for i, u in enumerate(used)}; HT = np.vectorize(idx.get)(tk)
        hj = G0[joints["hand_" + sd]][:3, 3]
        place = GF.hand_on(seat_m * scale, RA, sides[sd], hj, GF.socket_of(avatar, sd), bs)
        HVw = place(HV)
        layers = [(GVw, GT, np.array([0.62, 0.64, 0.68])), (HVw, HT, np.array([0.93, 0.78, 0.62]))]
        X, Y, Z = np.eye(3)
        views = [("side", X, Z, -Y if right else Y), ("top", X, Y, Z), ("along the bore", Y, Z, X)]
        for c, (vn, U, Vv, W) in enumerate(views):
            ax = axs[r, c]
            GF.draw(ax, layers, U, Vv, W)
            hp = HVw @ np.stack([U, Vv], 1)
            ctr = hp.mean(0); rad = max(np.ptp(hp, 0).max() * 1.5, 1e-3)
            ax.set_xlim(ctr[0] - rad, ctr[0] + rad); ax.set_ylim(ctr[1] - rad, ctr[1] + rad)
            ax.set_aspect("equal"); ax.axis("off")
            ax.set_title("%s %s -- %s" % (gun["name"], part["id"], vn) if c == 0 else vn, fontsize=8)
        axs[r, 0].text(0.0, -0.02, "%s, %s on the %s, %s hand, %s%s" % (gun.get("type"), subj, seat_from, "right" if right else "left",
                       pname, ", handaxis" if "handaxis" in part else ""), transform=axs[r, 0].transAxes, fontsize=7, va="top")
        print("%-24s %-16s %-9s %-9s %-6s %s" % (gun["name"], part["id"], subj, seat_from, sd, pname))
    plt.tight_layout(); plt.savefig(out, dpi=85, facecolor="white"); print("wrote", out)

if __name__ == "__main__":
    main()
